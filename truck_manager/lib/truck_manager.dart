
import 'dart:async';
import 'dart:io';

import 'package:truck_manager/services/pdf_service.dart';
import 'package:truck_manager/services/firestore_service.dart';
import 'package:truck_manager/services/line.dart';
import 'package:truck_manager/services/notify.dart';
import 'package:truck_manager/services/capsules.dart';
import 'package:truck_manager/services/gdrive_service.dart';

class AppService {
  final PdfService _pdf;
  final GDriveService _drive;
  final FirestoreService _firestore;
  final LineNotifyService _line;

  AppService(this._pdf, this._drive, this._firestore, this._line);

  Future<void> runInvoiceSyncWorkflow() async {
    // Notionへの依存を削除したため、このワークフローは現在機能しません。
    // 請求書データ取得の新しい起点を定義する必要があります。
    print("Invoice sync workflow is currently disabled due to NotionService removal.");
    
    // TODO: 新しいデータソースから請求書情報を取得する処理を実装する

    // ダミーの実行例（削除予定）
    // await runConsolidateInvoicesForLine();
  }

  Future<void> runConsolidateInvoicesForLine() async {
    // Notionへの依存を削除したため、このワークフローは現在機能しません。
    print("Consolidate invoices for LINE is currently disabled due to NotionService removal.");

    // TODO: 新しいデータソースから未払い注文を取得する処理を実装する
    final List<OrderCapsule> lineNotifications = [];

    if (lineNotifications.isNotEmpty) {
      await _line.sendOrderNotifications(lineNotifications);
    }
  }
}
