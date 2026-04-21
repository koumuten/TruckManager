
import 'package:test/test.dart';
import 'package:truck_manager/services/capsules.dart';

void main() {
  group('InvoiceCapsule', () {
    const pdfText = '''
      これはテスト用のPDFテキストです。
      発行日 : 2024/07/26
      いろいろな情報がここにあります。
      お支払い総合計
      ここに合計金額が記載されています。
      12,345円
      ありがとうございました。
    ''';

    test('fromPdfText should correctly parse date and price', () {
      final invoice = InvoiceCapsule.fromPdfText(pdfText);

      expect(invoice.date, '2024-07-26');
      expect(invoice.price, '¥12,345');
      expect(invoice.invoiceImgPath, isNull);
    });

    test('toJson should correctly serialize the object', () {
      final invoice = InvoiceCapsule.fromPdfText(pdfText);
      final json = invoice.toJson();

      final expectedJson = {
        'date': '2024-07-26',
        'price': '¥12,345',
        'invoiceImgPath': null,
      };

      expect(json, expectedJson);
    });

    test('fromJson should correctly deserialize the object', () {
       final sourceJson = {
        'date': '2025-01-01',
        'price': '¥9,876',
        'invoiceImgPath': '/path/to/image.jpg',
      };

      final invoice = InvoiceCapsule.fromJson(sourceJson);

      expect(invoice.date, '2025-01-01');
      expect(invoice.price, '¥9,876');
      expect(invoice.invoiceImgPath, '/path/to/image.jpg');
    });

    test('JSON serialization and deserialization should be consistent', () {
      final originalInvoice = InvoiceCapsule(
        date: '2023-12-25',
        price: '¥5,000',
        invoiceImgPath: 'test/path.png'
      );

      final json = originalInvoice.toJson();
      final deserializedInvoice = InvoiceCapsule.fromJson(json);

      expect(deserializedInvoice.date, originalInvoice.date);
      expect(deserializedInvoice.price, originalInvoice.price);
      expect(deserializedInvoice.invoiceImgPath, originalInvoice.invoiceImgPath);
    });
  });
}
