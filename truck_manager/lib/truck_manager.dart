import 'dart:async';
import 'dart:io';
import 'package:truck_manager/services/color.dart';
import 'package:uuid/uuid.dart';
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
import 'package:googleapis/firestore/v1.dart';

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
      final tmpDir = await AssetLoader.readAsset('TMP_DIR');
      final tmp = Directory(tmpDir);
      if (!(await tmp.exists())) {
        await tmp.create();
      }

      final collectionId = await AssetLoader.readAsset("FIRESTORE_COLLECTION");

      //メールの検索
      final target = await AssetLoader.readAsset("TARGET");
      final messages =
          await _gmail.fetchMessageList('is:unread subject:($target)');
      if (messages.isEmpty) {
        print('No new invoice emails to process.');
        return;
      }

      //メール毎に対処
      print('Found ${messages.length} new invoice emails.');
      final orders = <OrderCapsule>[];
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

            var uuid = Uuid();
            final pdfFile = File(path.join(tmpDir, "${uuid.v4()}.pdf"));

            try {
              // 添付ファイルを取得して保存
              final attachment =
                  await _gmail.fetchAttachment(message.id!, attachmentId);
              await pdfFile.writeAsBytes(attachment);
              print('Attachment saved to ${pdfFile.path}');

              InvoiceCapsule invoice =
                  await _pdf.ExtractInvoiceCapsule(pdfFile);

              OrderCapsule order = OrderCapsule(id: uuid.v4());
              try {
                print("${invoice.invoiceDate}に対応するドキュメントを取得中...");
                // PDFから抽出した日付で検索
                final filter = Filter(
                  fieldFilter: FieldFilter(
                    field: FieldReference(fieldPath: 'date'),
                    op: 'EQUAL',
                    value: Value(stringValue: invoice.invoiceDate),
                  ),
                );

                final existingDocs = await _firestore.queryDocuments(
                  collectionId: collectionId,
                  filter: filter,
                );

                if (existingDocs.isNotEmpty) {
                  print("既存のOrderCapsuleが見つかりました。復元します。");
                  // 既存データから復元
                  order = OrderCapsule.fromJson(existingDocs.first);
                }
              } catch (e, stackTrace) {
                GASNotifyService.notifyErrorToGas(
                    "faital error in retriving order: $e \n $stackTrace");
              }

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

              order.AggregatedData(
                  shift: shift, invoice: invoice, status: State.unpaid);

              await _firestore.saveDocument(
                collectionId: collectionId,
                docId: '${order.id}',
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

              ColorService colService = await ColorService.Create();
              String? eMail = await _gmail.GetOriginalSender(message.id!);
              HSL color = await colService.GetColor(eMail);
              color.L = 0.4;
              order.BGColor = color.ToRGBSt();

              orders.add(order);
            } catch (e, stackTrace) {
              print('Error processing attachment for email ${message.id}: $e');
              print(stackTrace);
              await GASNotifyService.notifyErrorToGas(
                  'Failed to process invoice from email ${message.id}: $e');
            }
          }
        }
      }
      await _line.sendOrderNotifications(orders);
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
        print('Cleaned up temporary directory: ${tmp.path}');
      }
    } catch (e, stackTrace) {
      print('An error occurred during the invoice sync workflow: $e');
      print(stackTrace);
      await GASNotifyService.notifyErrorToGas(
          'Critical error in invoice sync workflow: $e');
    }
  }
}
