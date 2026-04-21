
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:truck_manager/app.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/capsules.dart';
import 'package:truck_manager/services/line.dart';

// app_test.dartで生成されたモッククラスを再利用します。
import 'app_test.mocks.dart';

void main() {
  late AppService appService;
  late MockFirebaseService mockFirebaseService;
  late MockGmailService mockGmailService;
  late MockGoogleSheetsService mockGoogleSheetsService;
  late MockPdfService mockPdfService;
  late LineNotifyService lineNotifyService; // Mockではなく本物を使用

  setUp(() async {
    mockFirebaseService = MockFirebaseService();
    mockGmailService = MockGmailService();
    mockGoogleSheetsService = MockGoogleSheetsService();
    mockPdfService = MockPdfService();
    lineNotifyService = await LineNotifyService.create();

    appService = AppService(
      firebase: mockFirebaseService,
      gmail: mockGmailService,
      sheets: mockGoogleSheetsService,
      pdf: mockPdfService,
      line: lineNotifyService, // 本物のインスタンスを渡す
      tmpDir: '/tmp',
    );
  });

  group('Integration Test with Mock Data', () {
    test('should generate correct JSON for LINE notification', () async {
      print("Start Test");
      
      await AssetLoader.ReadAllVal();
      // 1. 静的ファイルからGmail APIのモックデータを作成
      // メッセージ一覧の読み込み
      final messageListFile = File('test/static_files/emai_list.json');
      final messageListJson = jsonDecode(await messageListFile.readAsString()) as Map<String, dynamic>;
      final messages = (messageListJson['messages'] as List).map((m) {
        final msg = gmail.Message();
        msg.id = (m as Map<String, dynamic>)['id'];
        msg.threadId = (m)['threadId'];
        return msg;
      }).toList();

      // メッセージ詳細の読み込み
      final messageId = messages.first.id!;
      final messageDetailFile = File('test/static_files/email_get_$messageId.json');
      final messageDetailJson = jsonDecode(await messageDetailFile.readAsString()) as Map<String, dynamic>;

      // JSONからgmail.Messageオブジェクトを手動で構築
      final messageDetail = gmail.Message()
        ..id = messageDetailJson['id']
        ..payload = (gmail.MessagePart()
          ..parts = ((messageDetailJson['payload'] as Map<String, dynamic>)['parts'] as List).map((part) {
            final partJson = part as Map<String, dynamic>;
            return gmail.MessagePart()
              ..mimeType = partJson['mimeType']
              ..filename = partJson['filename']
              ..body = (gmail.MessagePartBody()
                ..attachmentId = (partJson['body'] as Map<String, dynamic>)['attachmentId']);
          }).toList());

      // 2番目のメールのモック
      final messageId2 = messages[1].id!;
      final messageDetailFile2 = File('test/static_files/email_get_$messageId2.json');
      final messageDetailJson2 = jsonDecode(await messageDetailFile2.readAsString()) as Map<String, dynamic>;
      final messageDetail2 = gmail.Message()
        ..id = messageDetailJson2['id']
        ..payload = (gmail.MessagePart()
          ..parts = ((messageDetailJson2['payload'] as Map<String, dynamic>)['parts'] as List).map((part) {
            final partJson = part as Map<String, dynamic>;
            return gmail.MessagePart()
              ..mimeType = partJson['mimeType']
              ..filename = partJson['filename']
              ..body = (gmail.MessagePartBody()
                ..attachmentId = (partJson['body'] as Map<String, dynamic>)['attachmentId']);
          }).toList());

      // 2. モックの設定
      // Gmailサービスからのレスポンスを静的ファイルの内容でモック
      when(mockGmailService.fetchMessageList(any)).thenAnswer((_) async => messages);
      when(mockGmailService.getMessageDetails(messageId)).thenAnswer((_) async => messageDetail);
      when(mockGmailService.fetchAttachment(messageId, any)).thenAnswer((_) async => [1, 2, 3]); // ダミーのPDFバイト
      when(mockGmailService.markAsRead(messageId)).thenAnswer((_) async => Future.value());

      when(mockGmailService.getMessageDetails(messageId2)).thenAnswer((_) async => messageDetail2);
      when(mockGmailService.fetchAttachment(messageId2, any)).thenAnswer((_) async => [1, 2, 3]); // ダミーのPDFバイト
      when(mockGmailService.markAsRead(messageId2)).thenAnswer((_) async => Future.value());


      // PDFから抽出されるテキストをモック
      final pdfText = '発行日: 2024/05/20\nお支払い総合計: 50,000円';
      when(mockPdfService.extractTextFromPdf(any)).thenAnswer((_) async => pdfText);
      
      // スプレッドシートからのデータをモック
      final shiftCapsule = ShiftCapsule(date: DateTime(2024, 5, 20), assignment: 'Truck-X', eventName: 'テスト運搬');
      when(mockGoogleSheetsService.retriveTruckData(any)).thenAnswer((_) async => shiftCapsule);

      // PDFからJPGへの変換処理をモック
      final invoiceCapsule = InvoiceCapsule(date: '2024-05-20', price: '¥50,000', invoiceImgPath: '/tmp/invoice.jpg');
      when(mockPdfService.processToJpgWithWatermark(any, any)).thenAnswer((_) async => invoiceCapsule);
      
      // Firebaseへのアップロード処理をモック
      final downloadUrl = 'http://example.com/invoice.jpg';
      when(mockFirebaseService.uploadFile(storagePath: anyNamed('storagePath'), file: anyNamed('file'))).thenAnswer((_) async => downloadUrl);
      when(mockFirebaseService.saveDocument(collectionPath: anyNamed('collectionPath'), docId: anyNamed('docId'), data: anyNamed('data'))).thenAnswer((_) async => 'success_doc_id');
      
      // 3. ワークフローの実行
      final results = await appService.runInvoiceSyncWorkflow(targetSubject: 'test', isDebug: true);

      // 4. 結果のJSONを解析
      final decodedBody = jsonDecode(results);
      final carouselMessages = decodedBody['messages'][0]['contents']['contents'];
      expect(carouselMessages.length, 2);
      
      print('--- Generated LINE JSON Data ---');
      print(results);
      print('------------------------------');

      // 5. 生成されたJSONの内容を検証
      final contents = carouselMessages[0];
      final headerText = contents['header']['contents'][0]['text'];
      final bodyContents = contents['body']['contents'];

      // headerの検証
      expect(headerText, '未振り込み');
      
      // bodyの各項目を検証
      expect(bodyContents[0]['contents'][1]['text'], '2024-05-20');
      expect(bodyContents[1]['contents'][1]['text'], '¥50,000');
      expect(bodyContents[2]['contents'][1]['text'], 'テスト運搬');
      
      expect(headerText, isNot('unpaid')); 
    });
  });
}
