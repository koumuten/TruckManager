import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:dart_pdf_reader/dart_pdf_reader.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/capsules.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

class PdfService {
  final Uint8List japaneseFont; // TTFの生データ

  PdfService._(this.japaneseFont);

  /// 外部から呼ぶ初期化メソッド
  static Future<PdfService> create() async {
    final fontData = await _fetchFontData();
    return PdfService._(fontData);
  }

  /// メイン処理：PDF解析 → 文字追記 → JPG変換 → テキストデータと JPG アップロード
  Future<InvoiceCapsule> processToJpgWithWatermark(File sourcePdf, ShiftCapsule shift) async {
    // 1. テキストを抽出
    final text = await extractTextFromPdf(sourcePdf);
    InvoiceCapsule invoice = InvoiceCapsule.fromPdfText(text);

    // 2. PDFに文字を焼き付ける (imageパッケージではなくpdfパッケージを使用)
    final watermarkedPdfBytes = await _addTextToPdf(sourcePdf, shift);
    
    final tmpDir = await AssetLoader.readAsset("TMP_DIR");
    final tempPdfPath = '$tmpDir/temp_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await File(tempPdfPath).writeAsBytes(watermarkedPdfBytes);

    // 3. 外部コマンド pdftoppm でJPGに変換
    final outputJpgBase = '$tmpDir/edited_${DateTime.now().millisecondsSinceEpoch}';
    final result = await Process.run('pdftoppm', [
      '-jpeg',
      '-singlefile',
      '-r', '150', // 解像度設定
      tempPdfPath,
      outputJpgBase,
    ]);

    if (result.exitCode != 0) {
      throw Exception("PDFの画像変換に失敗しました: ${result.stderr}");
    }

    invoice.invoiceImgPath = '$outputJpgBase.jpg';
    
    // 一時PDFは削除
    await File(tempPdfPath).delete();
    
    return invoice;
  }

  /// PDFの上にShiftcapsuleの情報を記載する
  Future<List<int>> _addTextToPdf(File sourcePdf, ShiftCapsule shift) async {
    final pdf = pw.Document();
    final ttf = pw.Font.ttf(japaneseFont.buffer.asByteData());
    final watermark = '担当: ${shift.assignment}\n予約: ${shift.reserver}\n${shift.eventName}';
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Stack(
          children: [
            pw.Align(
              alignment: pw.Alignment.bottomRight,
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Text(
                  watermark,
                  style: pw.TextStyle(font: ttf, fontSize: 20, color: PdfColor.fromHex("#000000")),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  /// PDFからテキスト抽出 (dart_pdf_reader)
  Future<String> extractTextFromPdf(File pdfFile) async {
    final bytes = await pdfFile.readAsBytes();
    final parser = PDFParser(ByteStream(bytes));
    final document = await parser.parse();
    final catalog = await document.catalog;
    final pages = await catalog.getPages();
    final page = pages.getPageAtIndex(0);
    
    return page.toString(); 
  }

  /// フォントデータの取得ロジック
  static Future<Uint8List> _fetchFontData() async {
    final fontDir = Directory(await AssetLoader.readAsset("FONT_DIR"));
    if (!await fontDir.exists()) await fontDir.create(recursive: true);

    final String fontPath = path.join(fontDir.path, 'font.ttf');
    final file = File(fontPath);

    if (await file.exists()) {
      return await file.readAsBytes();
    }

    const fontUrl = "https://github.com/google/fonts/raw/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf";
    final response = await http.get(Uri.parse(fontUrl));
    
    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);
      return response.bodyBytes;
    } else {
      throw Exception('Font download failed');
    }
  }
}