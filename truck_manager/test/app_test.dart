
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:test/test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:truck_manager/services/firebase_service.dart';
import 'package:truck_manager/services/mail.dart';
import 'package:truck_manager/services/spread_sheet.dart';
import 'package:truck_manager/services/pdf_service.dart';
import 'package:truck_manager/services/line.dart';
import 'package:truck_manager/app.dart';
import 'package:truck_manager/services/capsules.dart';

import 'app_test.mocks.dart';

// モックを生成するクラスを指定
@GenerateMocks([
  FirebaseService,
  GmailService,
  GoogleSheetsService,
  PdfService,
  LineNotifyService
])
void main() {
  
  late MockFirebaseService mockFirebaseService;
  late MockGmailService mockGmailService;
  late MockGoogleSheetsService mockGoogleSheetsService;
  late MockPdfService mockPdfService;
  late MockLineNotifyService mockLineNotifyService;
  late AppService appService;

  setUp(() {
    mockFirebaseService = MockFirebaseService();
    mockGmailService = MockGmailService();
    mockGoogleSheetsService = MockGoogleSheetsService();
    mockPdfService = MockPdfService();
    mockLineNotifyService = MockLineNotifyService();

    appService = AppService(
      firebase: mockFirebaseService,
      gmail: mockGmailService,
      sheets: mockGoogleSheetsService,
      pdf: mockPdfService,
      line: mockLineNotifyService,
      tmpDir: "/test/test_env/tmp"
    );
  });

  group('AppService', () {
    test('runInvoiceSyncWorkflow should complete without errors when no new emails', () async {
      when(mockGmailService.fetchMessageList(any)).thenAnswer((_) async => []);

      await appService.runInvoiceSyncWorkflow(targetSubject: 'test');

      verify(mockGmailService.fetchMessageList(any)).called(1);
      verifyNever(mockGmailService.getMessageDetails(any));
    });

    test('should process email with PDF attachment correctly', () async {
      // 1. Setup Mocks
      final message = gmail.Message()..id = 'test_msg_id';
      final messageDetail = gmail.Message()
        ..payload = (gmail.MessagePart()
          ..parts = [
            gmail.MessagePart()
              ..mimeType = 'application/pdf'
              ..filename = 'invoice.pdf'
              ..body = (gmail.MessagePartBody()..attachmentId = 'test_attachment_id')
          ]);

      when(mockGmailService.fetchMessageList(any)).thenAnswer((_) async => [message]);
      when(mockGmailService.getMessageDetails(message.id!)).thenAnswer((_) async => messageDetail);
      when(mockGmailService.fetchAttachment(message.id!, 'test_attachment_id')).thenAnswer((_) async => [1, 2, 3]);
      when(mockGmailService.markAsRead(message.id!)).thenAnswer((_) async => Future.value());

      final pdfText = '発行日: 2023/01/15\nお支払い総合計: 10,000円'; // Regexにマッチするテキスト
      when(mockPdfService.extractTextFromPdf(any)).thenAnswer((_) async => pdfText);
      
      final shiftCapsule = ShiftCapsule(date: DateTime(2023, 1, 15), assignment: 'Truck A', eventName: 'Test Event');
      when(mockGoogleSheetsService.retriveTruckData(any)).thenAnswer((_) async => shiftCapsule);

      final invoiceCapsule = InvoiceCapsule(date: '2023-01-15', price: '¥10,000', invoiceImgPath: '/tmp/invoice.jpg'); // totalAmount -> price
      when(mockPdfService.processToJpgWithWatermark(any, any)).thenAnswer((_) async => invoiceCapsule);
      
      final downloadUrl = 'http://example.com/invoice.jpg';
      when(mockFirebaseService.uploadFile(storagePath: anyNamed('storagePath'), file: anyNamed('file'))).thenAnswer((_) async => downloadUrl);
      when(mockFirebaseService.saveDocument(collectionPath: anyNamed('collectionPath'), docId: anyNamed('docId'), data: anyNamed('data'))).thenAnswer((_) async => 'success_id');
      
      when(mockLineNotifyService.sendOrderNotifications(any)).thenAnswer((_) async => Future.value());

      // 2. Run workflow
      await appService.runInvoiceSyncWorkflow(targetSubject: 'test');

      // 3. Verify
      verify(mockGmailService.fetchMessageList(any)).called(1);
      verify(mockGmailService.getMessageDetails(message.id!)).called(1);
      verify(mockGmailService.fetchAttachment(message.id!, 'test_attachment_id')).called(1);
      verify(mockPdfService.extractTextFromPdf(any)).called(1);
      verify(mockGoogleSheetsService.retriveTruckData(any)).called(1);
      verify(mockPdfService.processToJpgWithWatermark(any, any)).called(1);
      verify(mockFirebaseService.uploadFile(storagePath: anyNamed('storagePath'), file: anyNamed('file'))).called(1);
      final captured = verify(mockFirebaseService.saveDocument(collectionPath: 'orders', docId: anyNamed('docId'), data: captureAnyNamed('data'))).captured;
      expect(captured.first['eventName'], 'Test Event'); // Verify data passed to firestore
      verify(mockGmailService.markAsRead(message.id!)).called(1);
      verify(mockLineNotifyService.sendOrderNotifications(any)).called(1);
    });
  });
}
