import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/capsules.dart';
import 'package:truck_manager/services/notify.dart';

class GoogleSheetsService {
  sheets.SheetsApi? sheetsApi;

  String spreadsheetId;

  GoogleSheetsService._(this.sheetsApi, this.spreadsheetId);

  static Future<GoogleSheetsService> create() async {
    final spreadsheetIdTmp = await AssetLoader.readAsset("SHIFT_SHEET_ID");
    final serviceAccountJson =
        await AssetLoader.readAsset('FIREBASE_SERVICE_ACCOUNT_JSON');

    final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);

    // スプレッドシート読み書き用のスコープを指定
    final scopes = [sheets.SheetsApi.spreadsheetsScope];
    final authClient = await clientViaServiceAccount(credentials, scopes);

    final sheetsApiTmp = sheets.SheetsApi(authClient);

    return GoogleSheetsService._(sheetsApiTmp, spreadsheetIdTmp);
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
        return null;
      }

      // 3. ループで探索

      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;

        // A列(インデックス0)に日付が入っていると仮定
        final cellDateStr = row[0].toString();

        if (cellDateStr == targetDateStr) {
          shift = ShiftCapsule();
          shift.date = date;
          shift.assignment = row.length > 8 ? row[8].toString() : '';
          shift.reserver = row.length > 7 ? row[7].toString() : '';
          shift.eventName = row.length > 2 ? row[2].toString() : '';
        }
      }

      if (shift == null) {
        print('$targetDateStr のデータは存在しませんでした。');
      }
    } catch (e, stackTrace) {
      print('エラーが発生しました: $e');
      await GASNotifyService.notifyErrorToGas(
          "Faital Error in AppService: \n $e \n Stack: $stackTrace");
    }

    return shift;
  }
}
