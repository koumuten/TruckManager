
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/capsules.dart';
import 'package:path/path.dart' as path;

class PdfService {
  PdfService._();

  static Future<PdfService> create() async {
    return PdfService._();
  }

  Future<InvoiceCapsule> processToJpgWithWatermark(
      File sourcePdf, ShiftCapsule shift) async {

    // 1. まず pdftotext でテキストを抽出
    String text = await _extractTextWithPdfToText(sourcePdf);

    // 2. 抽出結果から InvoiceCapsule を生成
    InvoiceCapsule invoice = InvoiceCapsule.fromPdfText(text);

    // 3. 抽出が失敗していたら（金額が0円なら）、Geminiで再挑戦
    if (invoice.isExtractionInvalid) {
      print("pdftotext failed. Retrying with Gemini...");
      text = await _extractTextWithGemini(sourcePdf);
      invoice = InvoiceCapsule.fromPdfText(text);
    }

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
        await _addWatermarkToJpg(File(outputJpgPath), shift);
    await File(outputJpgPath).writeAsBytes(watermarkedJpgBytes);

    invoice.invoiceImgPath = outputJpgPath;
    return invoice;
  }

  Future<Uint8List> _addWatermarkToJpg(File jpgFile, ShiftCapsule shift) async {
    final imageBytes = await jpgFile.readAsBytes();
    final image = img.decodeImage(imageBytes);

    if (image == null) {
      throw Exception("Could not decode JPG image.");
    }

    final watermark =
        'Assigned: ${shift.assignment} Reserver: ${shift.reserver} Event: ${shift.eventName}';

    img.drawString(
      image,
      watermark,
      font: img.arial24,
      x: (image.width - (watermark.length * 12)) - 20,
      y: image.height - 40,
      color: img.ColorRgb8(0, 0, 0),
    );

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
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$apiKey');

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
        headers: {'Content-Type': 'application/json'},
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
