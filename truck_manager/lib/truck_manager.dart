import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/pdf_service.dart';
import 'package:truck_manager/services/firestore_service.dart';
import 'package:truck_manager/services/line.dart';
import 'package:truck_manager/services/notify.dart';
import 'package:truck_manager/services/capsules.dart';
import 'package:truck_manager/services/gdrive_service.dart';
import 'package:truck_manager/services/mail.dart';
import 'package:truck_manager/services/spread_sheet.dart';
import 'package:intl/intl.dart';

class AppService {
  final PdfService _pdf;
  final GDriveService _drive;
  final FirestoreService _firestore;
  final LineNotifyService _line;
  final GmailService _gmail;
  final SpreadSheetService _spreadsheet;

  AppService(this._pdf, this._drive, this._firestore, this._line, this._gmail,
      this._spreadsheet);

  Future<void> runInvoiceSyncWorkflow() async {
    print('Invoice processing workflow started.');
    try {
      final target = await AssetLoader.readAsset("TARGET");
      final messages =
          await _gmail.fetchMessageList('is:unread subject:($target)');
      if (messages.isEmpty) {
        print('No new invoice emails to process.');
        return;
      }

      print('Found ${messages.length} new invoice emails.');

      for (final messageMeta in messages) {
        final message = await _gmail.getMessageDetails(messageMeta.id!);
        final payload = message.payload;
        if (payload == null || payload.parts == null) continue;

        for (final part in payload.parts!) {
          if (part.filename != null &&
              part.filename!.toLowerCase().endsWith('.pdf')) {
            print(
                'Found PDF attachment: ${part.filename} in email ${message.id}');
            final attachmentId = part.body!.attachmentId;
            if (attachmentId == null) continue;

            // 一時ディレクトリを取得
            final tmpDir = Directory.systemTemp.createTempSync('invoice_pdf_');
            final pdfFile = File(path.join(tmpDir.path, part.filename!));

            try {
              // 添付ファイルを取得して保存
              final attachment =
                  await _gmail.fetchAttachment(message.id!, attachmentId);
              await pdfFile.writeAsBytes(attachment);
              print('Attachment saved to ${pdfFile.path}');

              InvoiceCapsule invoice =
                  await _pdf.ExtractInvoiceCapsule(pdfFile);
              ShiftCapsule shift;

              try {
                print("${invoice.invoiceDate}に対応するシフトを取得中...");
                DateTime date = DateTime.parse(invoice.invoiceDate);
                ShiftCapsule? shiftNullable =
                    await _spreadsheet.retriveTruckData(date);
                if (shiftNullable == null) {
                  print("シフトを取得できませんでした。一日前で検索します。");
                  date = date.subtract(const Duration(days: 1));
                  ShiftCapsule? shiftNullable =
                      await _spreadsheet.retriveTruckData(date);
                  if (shiftNullable == null) {
                    GASNotifyService.notifyErrorToGas("""
                      Non Faital Error From SpreadSheetService via App Service: 
                      対応するシフトが得られませんでした。
                      日付: ${invoice.invoiceDate}
                      やったこと : 発行日当日及び前日のシフト確認
                      打開策 :
                      """
                        .trim());
                    shiftNullable = ShiftCapsule(
                      client: '',
                      date: DateTime.now().toIso8601String(),
                      eventName: '対応した行事がわかりません',
                      assignment: '担当ドライバーが不明です',
                      reserver: '予約者が不明です',
                      id: '404',
                    );
                  }
                }
                shift = shiftNullable!;
              } catch (e, t) {
                GASNotifyService.notifyErrorToGas("faital error : $e \n $t");
                shift = ShiftCapsule(
                  client: '',
                  date: DateTime.now().toIso8601String(),
                  eventName: '対応した行事がわかりません',
                  assignment: '担当ドライバーが不明です',
                  reserver: '予約者が不明です',
                  id: '404',
                );
              }

              invoice =
                  await _pdf.processToJpgWithWatermark(pdfFile, shift, invoice);

              print("出来上がったファイルをGoogle Drive に上げていきます");

              final pdfUrl = await _drive.uploadFile(
                  name: "Invoice_${shift.date}.pdf", file: pdfFile);

              final imgUrl = await _drive.uploadFile(
                  name: "Invoice_${shift.date}.jpg",
                  file: File(invoice.invoiceImgPath));

              invoice.invoiceImgPath = imgUrl;

              OrderCapsule order = OrderCapsule.fromAggregatedData(
                  shift: shift, invoice: invoice, statusState: "unpaid");

              await _firestore.saveDocument(
                collectionPath: 'orders',
                docId: '${shift.date}',
                data: {
                  ...order.toJson(),
                  'imageUrl': imgUrl,
                  'pdfUrl': pdfUrl,
                  'createdAt': DateTime.now().toUtc().toIso8601String(),
                },
              );

              // 処理が成功したらメールを既読にする
              if (!(await AssetLoader.isDebug())) {
                await _gmail.markAsRead(message.id!);
                print('Marked email ${message.id} as read.');
              }
              order.url = imgUrl;
              await _line.sendOrderNotifications([order]);

            } catch (e, stackTrace) {
              print('Error processing attachment for email ${message.id}: $e');
              print(stackTrace);
              await GASNotifyService.notifyErrorToGas(
                  'Failed to process invoice from email ${message.id}: $e');
            } finally {
              // 一時ファイルをクリーンアップ
              if (await tmpDir.exists()) {
                await tmpDir.delete(recursive: true);
                print('Cleaned up temporary directory: ${tmpDir.path}');
              }
            }
          }
        }
      }
    } catch (e, stackTrace) {
      print('An error occurred during the invoice sync workflow: $e');
      print(stackTrace);
      await GASNotifyService.notifyErrorToGas(
          'Critical error in invoice sync workflow: $e');
    }
  }

  Future<void> runConsolidateInvoicesForLine() async {
    // Firestoreから未払いの請求書を取得し、LINE通知用のデータに変換します。
    print("Checking for unpaid invoices to notify on LINE...");

    try {
      final allInvoices = await _firestore.getAllInvoices();
      final currencyFormatter = NumberFormat('¥#,##0', 'ja_JP');
      final List<OrderCapsule> lineNotifications = [];

      print(allInvoices);

      for (final invoiceData in allInvoices) {
        // Firestoreに 'paymentState' フィールドがあり、その値が 'unpaid' のものを対象とします。
        if (invoiceData['paymentState'] == 'unpaid') {
          final amount = invoiceData['price'] as int? ?? 0;

          final notification = OrderCapsule(
            state: '未振り込み', // LINEテンプレート用の状態
            date: invoiceData['date'] as String? ?? '日付不明',
            price: currencyFormatter.format(amount),
            objectName: invoiceData['objectName'] as String? ?? '案件名不明',
            url: invoiceData['imageUrl'] as String? ?? '',
            id: invoiceData['id'] as String? ?? '',
            percentage: invoiceData['percentage'] as String? ?? '',
            lastUpdated: '',
          );
          lineNotifications.add(notification);
        }
      }

      if (lineNotifications.isNotEmpty) {
        print('${lineNotifications.length}件の未払い請求書についてLINE通知を送信します。');
        await _line.sendOrderNotifications(lineNotifications);
      } else {
        print("通知対象の未払い請求書はありませんでした。");
      }
    } catch (e, stackTrace) {
      print('LINE通知処理中にエラーが発生しました: $e');
      print(stackTrace);
      // エラーを外部に通知する
      await GASNotifyService.notifyErrorToGas(
          'runConsolidateInvoicesForLine failed: $e');
    }
  }
}
