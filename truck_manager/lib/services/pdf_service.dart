import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/capsules.dart';
import 'package:truck_manager/services/download.dart';
import 'package:path/path.dart' as path;

class PdfService {
  PdfService._();

  static Future<PdfService> create() async {
    return PdfService._();
  }

  Future<InvoiceCapsule> ExtractInvoiceCapsule(File sourcePdf) async {
    // 1. まず pdftotext でテキストを抽出
    String text = await _extractTextWithPdfToText(sourcePdf);

    // 2. 抽出結果から InvoiceCapsule を生成
    InvoiceCapsule invoice = InvoiceCapsule.fromPdfText(text);

    print("price : ${invoice.totalAmount}");

    // 3. 抽出が失敗していたら（金額が0円なら）、Geminiで再挑戦
    if (invoice.isExtractionInvalid || invoice.totalAmount < 1000) {
      print("pdftotext failed. Retrying with Gemini...");
      text = await _extractTextWithGemini(sourcePdf);
      invoice = InvoiceCapsule.fromPdfText(text);
    }

    return invoice;
  }

  Future<InvoiceCapsule> processToJpgWithWatermark(
      File sourcePdf, ShiftCapsule shift, InvoiceCapsule invoice) async {
    // 4. 外部コマンド pdftoppm でJPGに変換
    final tmpDir = await AssetLoader.readAsset("TMP_DIR");
    final outputJpgBase =
        path.join(tmpDir, 'edited_${DateTime.now().millisecondsSinceEpoch}');
    final outputJpgPath = '$outputJpgBase.jpg';

    final result = await Process.run('pdftoppm', [
      '-jpeg',
      '-singlefile',
      '-r',
      '150',
      sourcePdf.path,
      outputJpgBase,
    ]);

    if (result.exitCode != 0) {
      print('pdftoppm stdout: ${result.stdout}');
      print('pdftoppm stderr: ${result.stderr}');
      throw Exception("PDF to JPG conversion failed: ${result.stderr}");
    }

    // 5. JPGにウォーターマークを追加
    final watermarkedJpgBytes =
        await _addWatermarkToJpg(File(outputJpgPath), shift, invoice);
    await File(outputJpgPath).writeAsBytes(watermarkedJpgBytes);

    invoice.invoiceImgPath = outputJpgPath;
    return invoice;
  }

  Future<Uint8List> _addWatermarkToJpg(
      File jpgFile, ShiftCapsule shift, InvoiceCapsule invoice) async {
    final fontDir = await AssetLoader.readAsset("FONT_DIR");
    final ttfPath = '${fontDir}/font.ttf';
    if (await File(ttfPath).exists() != true) {
      final fontUrl = await AssetLoader.readAsset("FONT_URL");
      RetriveService.downloadFile(fontUrl, ttfPath);
    }
    final rawText =
        '${shift.assignment}${shift.reserver}${shift.eventName}${invoice.totalAmount}担当予約イベント金額¥: ';
    final uniqueChars = rawText.split('').toSet().join(''); // 重複削除

    final charsetFile = await File('${fontDir}/charset.txt').create();
    await charsetFile.writeAsString(uniqueChars);
    ProcessResult? result;
    // 2. シェルスクリプトを実行してフォント生成
    for (var i = 0; i < 2; i++) {
      try {
        result = await Process.run('msdf-bmfont', [
          "-f", "xml",
          '-i', charsetFile.path,
          '-s', '32', // 文字サイズ
          '-t', 'sdf',
          ttfPath, // 元となるTTFのパス
          '-o', '${fontDir}/font.fnt'
        ]);
      } catch (e) {
        if (i == 1) {
          rethrow;
        }
        print("installing msdf-bmfont-xml...");
        await Process.run("npm", ["install", "msdf-bmfont-xml"]);
        result = await Process.run("which", ["msdf-bmfont"]);
        print("msdf-bmfont-xml : ${result.stdout}");
        print("font.ttf : ${await File('${fontDir}/font.ttf').exists()}");
        print("charset : ${await File(charsetFile.path).exists()}");
      }
    }

    if (result == null || result.exitCode != 0) {
      throw Exception(
          "Font generation failed: ${result?.stderr ?? "result is null"}");
    }

    await Process.run('zip', [
      '-j',
      '${fontDir}/font.zip',
      '${fontDir}/font.fnt',
      '${fontDir}/font.png'
    ]);

    // ビットマップフォントとして読み込み

    final zip = await File("${fontDir}/font.zip").readAsBytes();
    final font = img.BitmapFont.fromZip(zip);
    // 5. 画像描画処理
    final imageBytes = await jpgFile.readAsBytes();
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception("Decode failed");

    final watermark = [
      '担当: ${shift.assignment}',
      '予約: ${shift.reserver}',
      'イベント: ${shift.eventName}',
      '金額: ¥${invoice.totalAmount}'
    ];

    for (var i = 0; i < watermark.length; i++) {
      img.drawString(
        image,
        watermark[i],
        font: font,
        x: (image.width / 2).toInt(),
        y: image.height - 150 + (i * 40),
        color: img.ColorRgb8(255, 255, 255),
      );
    }

    await File('${fontDir}/font.zip').delete();

    return Uint8List.fromList(img.encodeJpg(image));
  }

  Future<String> _extractTextWithPdfToText(File pdfFile) async {
    final result = await Process.run('pdftotext', [pdfFile.path, '-']);
    if (result.exitCode != 0) {
      print("pdftotext stderr: ${result.stderr}");
      return "";
    }
    return result.stdout as String;
  }

  Future<String> _extractTextWithGemini(File pdfFile) async {
    try {
      final apiKey = await AssetLoader.readAsset('GEMINI_API_KEY');
      if (apiKey.isEmpty) throw Exception("GEMINI_API_KEY is not set.");

      final pdfBytes = await pdfFile.readAsBytes();
      final pdfBase64 = base64Encode(pdfBytes);

      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent');

      final requestBody = {
        "contents": [
          {
            "parts": [
              {"text": "このPDFファイルから日本語のテキストをすべて抽出して、プレーンテキスト形式で返してください。"},
              {
                "inline_data": {
                  "mime_type": "application/pdf",
                  "data": pdfBase64
                }
              }
            ]
          }
        ]
      };

      final response = await http.post(
        url,
        headers: {
          "x-goog-api-key": "$apiKey",
          'Content-Type': 'application/json'
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        final extractedText =
            responseBody['candidates'][0]['content']['parts'][0]['text'];
        return extractedText as String;
      } else {
        print("Gemini API error: ${response.statusCode} - ${response.body}");
        return "";
      }
    } catch (e) {
      print("Error calling Gemini API: $e");
      return "";
    }
  }
}
