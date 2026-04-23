import 'dart:convert';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/capsules.dart';

class SpreadSheetService {
  SheetsApi? sheetsApi;

  String spreadsheetId;

  SpreadSheetService._(this.sheetsApi, this.spreadsheetId);

  static Future<SpreadSheetService> create() async {
    final spreadsheetIdTmp = await AssetLoader.readAsset("SHIFT_SHEET_ID");
    String serviceAccountJson;
    if (await AssetLoader.isDebug()) {
      serviceAccountJson =
          await AssetLoader.readAsset('./test/test_env/cnfg/g_cred.json');
    } else {
      serviceAccountJson = await AssetLoader.readAsset('GOOGLE_SERVICE_CRED');
    }
    final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);

    // スプレッドシート読み書き用のスコープを指定
    final scopes = [SheetsApi.spreadsheetsScope];
    final authClient = await clientViaServiceAccount(credentials, scopes);

    final sheetsApiTmp = SheetsApi(authClient);

    return SpreadSheetService._(sheetsApiTmp, spreadsheetIdTmp);
  }

  Future<ShiftCapsule?> retriveTruckData(DateTime date) async {
    if (sheetsApi == null) throw Exception('APIが初期化されていません。');

    ShiftCapsule? shift;

    //日調君の範囲指定 (シート名がyyyymmの0埋めなし)
    final range = '${date.year}${date.month}!A:I';

    final targetDateStr = '${date.year}/${date.month}/${date.day}';
    try {
      final response =
          await sheetsApi!.spreadsheets.values.get(spreadsheetId, range);
      final rows = response.values;

      if (rows == null || rows.isEmpty) {
        print('シート"${date.year}${date.month}"がありません。');
        return ShiftCapsule();
      }

      // 3. ループで探索

      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;

        // A列(インデックス0)に日付が入っていると仮定
        final cellDateStr = row[0].toString();

        if (cellDateStr == targetDateStr) {
          shift = ShiftCapsule();
          shift.date = "${date.year}/${date.month}/${date.day}";
          shift.assignment = row.length > 8 ? row[8].toString() : '';
          shift.reserver = row.length > 7 ? row[7].toString() : '';
          shift.eventName = row.length > 2 ? row[2].toString() : '';
        }
      }

      if (shift == null) {
        print('$targetDateStr のデータは存在しませんでした。');
      }
    } catch (e) {
      print('エラーが発生しました: $e');
    }

    return shift;
  }
}
