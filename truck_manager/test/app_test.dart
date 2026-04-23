import 'dart:io';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:truck_manager/app.dart';
import 'package:truck_manager/services/capsules.dart';
import 'package:truck_manager/services/firestore_service.dart';
import 'package:truck_manager/services/gdrive_service.dart';
import 'package:truck_manager/services/notify.dart';
import 'package:truck_manager/services/pdf_service.dart';
import 'package:truck_manager/services/strage.dart';

class MockFirestoreService extends Mock implements FirestoreService {}
class MockGDriveService extends Mock implements GDriveService {}
class MockStorageService extends Mock implements StorageService {}
class MockPdfService extends Mock implements PdfService {}
class MockFile extends Mock implements File {}

void main() {
  group('App', () {
    late App app;
    late MockFirestoreService mockFirestoreService;
    late MockGDriveService mockGDriveService;
    late MockStorageService mockStorageService;
    late MockPdfService mockPdfService;
    late MockNotifyService mockNotifyService;

    setUp(() {
      mockFirestoreService = MockFirestoreService();
      mockGDriveService = MockGDriveService();
      mockStorageService = MockStorageService();
      mockPdfService = MockPdfService();
      mockNotifyService = MockNotifyService();

      app = App(
        db: mockFirestoreService,
        drive: mockGDriveService,
        storage: mockStorageService,
        pdf: mockPdfService,
        notify: mockNotifyService,
      );
    });

    test('run should execute without errors', () async {
      // Setup mocks
      final user = User(id: 'testId', name: 'Test User', email: 'test@example.com');
      when(mockFirestoreService.getUsers()).thenAnswer((_) async => [user]);
      when(mockGDriveService.checkNewFiles(any)).thenAnswer((_) async => []);

      // Execute
      await app.run(null);

      // Verify interactions
      verify(mockFirestoreService.getUsers()).called(1);
      verify(mockGDriveService.checkNewFiles(any)).called(1);
    });

    test('run should handle new files and process them', () async {
      final user = User(id: 'testId', name: 'Test User', email: 'test@example.com');
      final mockPdfFile = MockFile();
      final invoiceCapsule = InvoiceCapsule(invoiceId: 'inv1');

      when(mockFirestoreService.getUsers()).thenAnswer((_) async => [user]);
      when(mockGDriveService.checkNewFiles(any)).thenAnswer((_) async => [mockPdfFile]);
      when(mockPdfFile.path).thenReturn('dummy.pdf');
      when(mockStorageService.uploadFile(
        localPath: anyNamed('localPath'),
        remotePath: anyNamed('remotePath'),
      )).thenAnswer((_) async => 'http://dummy.url/invoice.jpg');
      
      when(mockPdfService.processToJpgWithWatermark(any, any))
          .thenAnswer((_) async => invoiceCapsule);

      // Execute
      await app.run(null);

      // Verify
      verify(mockPdfService.processToJpgWithWatermark(any, any)).called(1);
      verify(mockStorageService.uploadFile(
        localPath: anyNamed('localPath'),
        remotePath: anyNamed('remotePath'),
      )).called(1);
      verify(mockFirestoreService.saveInvoice(any)).called(1);
      verify(mockNotifyService.sendNotify(any, any)).called(1);
    });

  });
}
