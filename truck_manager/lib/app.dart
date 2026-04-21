
import 'dart:io';
import 'package:truck_manager/services/firebase_service.dart';
import 'package:truck_manager/services/mail.dart';
import 'package:truck_manager/services/spread_sheet.dart';
import 'package:truck_manager/services/pdf_service.dart';
import 'package:truck_manager/services/line.dart';
import 'package:truck_manager/services/capsules.dart';

class AppService {
  final FirebaseService _firebase;
  final GmailService _gmail;
  final GoogleSheetsService _sheets;
  final PdfService _pdf;
  final LineNotifyService _line;
  final String tmpDir;

  // コンストラクタで依存性を注入
  AppService({
    required FirebaseService firebase,
    required GmailService gmail,
    required GoogleSheetsService sheets,
    required PdfService pdf,
    required LineNotifyService line,
    required this.tmpDir,
  })  : _firebase = firebase,
        _gmail = gmail,
        _sheets = sheets,
        _pdf = pdf,
        _line = line;

  Future<String> runInvoiceSyncWorkflow({
    required String targetSubject,
    bool isDebug = false,
  }) async {
    try {
      print('=== 請求書同期ワークフローを開始します ===');

      // サービスの初期化はコンストラクタで行われるため、ここでは不要

      final query = 'subject:"$targetSubject"';
      final messages = await _gmail.fetchMessageList(query);

      if (messages.isEmpty) {
        print('処理対象の新着メールはありません。');
        return "";
      }

      List<OrderCapsule> processedOrders = [];

      for (var msg in messages) {
        final detail = await _gmail.getMessageDetails(msg.id!);
        final parts = detail.payload?.parts ?? [];

        for (var part in parts) {
          if (part.mimeType == 'application/pdf' && part.body?.attachmentId != null) {
            final bytes = await _gmail.fetchAttachment(msg.id!, part.body!.attachmentId!);
            
            final tempDir = await Directory(tmpDir).createTemp('invoice_');
            final pdfFile = await File('${tempDir.path}/${part.filename}').writeAsBytes(bytes);

            final String pdfText = await _pdf.extractTextFromPdf(pdfFile);
            final InvoiceCapsule tempInvoice = InvoiceCapsule.fromPdfText(pdfText);

            DateTime targetDate;
            try {
              targetDate = DateTime.parse(tempInvoice.date);
            } catch (e) {
              print('日付のパース失敗: ${tempInvoice.date} -> 現在時刻を使用');
              targetDate = DateTime.now();
            }

            final ShiftCapsule shiftData = await _sheets.retriveTruckData(targetDate) 
                ?? ShiftCapsule(date: targetDate, assignment: "未割り当て");

            final InvoiceCapsule finalInvoice = await _pdf.processToJpgWithWatermark(pdfFile, shiftData);

            if (finalInvoice.invoiceImgPath == null) throw Exception('画像の生成に失敗しました。');
            final File imgFile = File(finalInvoice.invoiceImgPath!);
            
            final storagePath = 'invoices/${finalInvoice.date}_${DateTime.now().millisecondsSinceEpoch}.jpg';
            
            final String downloadUrl = await _firebase.uploadFile(
              storagePath: storagePath,
              file: imgFile,
            );

            final order = OrderCapsule.fromAggregatedData(
              shift: shiftData,
              invoice: finalInvoice,
              statusState: '未振り込み',
            );

            await _firebase.saveDocument(
              collectionPath: 'orders',
              docId: '${finalInvoice.date}_${msg.id}',
              data: {
                ...order.toJson(),
                'imageUrl': downloadUrl,
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              },
            );

            processedOrders.add(order);
            await tempDir.delete(recursive: true);
          }
        }

        if (!isDebug) {
          await _gmail.markAsRead(msg.id!);
          print('メール(ID: msg.id) を既読にしました。');
        }
      }

      if (processedOrders.isNotEmpty) {
        return await _line.sendOrderNotifications(processedOrders, isDebug: isDebug);
      }

      print('=== ワークフローが正常に完了しました ({processedOrders.length}件) ===');

    } catch (e) {
      print('AppService エラー: $e');
      rethrow;
    }
    return "";
  }
}
