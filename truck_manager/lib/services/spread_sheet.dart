import 'dart:convert';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/capsules.dart';

class SpreadSheetService {
  final SheetsApi _sheetsApi;
  final String _spreadsheetId;

  SpreadSheetService(this._sheetsApi, this._spreadsheetId);

  static Future<SpreadSheetService> create() async {
    final credentialsJson = await AssetLoader.readAsset('GCP_SA_KEY');
    final credentials =
        ServiceAccountCredentials.fromJson(jsonDecode(credentialsJson));
    final client = await clientViaServiceAccount(
        credentials, [SheetsApi.spreadsheetsScope]);
    final sheetsApi = SheetsApi(client);
    final spreadsheetId = await AssetLoader.readAsset('SPREAD_SHEET_ID');
    return SpreadSheetService(sheetsApi, spreadsheetId);
  }

  Future<ShiftCapsule?> getShiftByInvoiceId(String invoiceId) async {
    try {
      final range = 'A2:I'; // 検索範囲
      final result =
          await _sheetsApi.spreadsheets.values.get(_spreadsheetId, range);
      final rows = result.values;

      if (rows != null) {
        for (final row in rows) {
          if (row.length > 8 && row[8] == invoiceId) {
            String date = '';
            if (row.isNotEmpty && row[0] is String) {
              final dateParts = "${row[0]}".split('/');
              if (dateParts?.length == 3) {
                final year = int.parse(dateParts![0]);
                final month =
                    int.parse(dateParts[1]).toString().padLeft(2, '0');
                final day = int.parse(dateParts[2]).toString().padLeft(2, '0');
                date = '$year-$month-$day';
              }
            }

            return ShiftCapsule(
              date: date,
              assignment: row.length > 8 ? row[8].toString() : '',
              reserver: row.length > 7 ? row[7].toString() : '',
              eventName: row.length > 2 ? row[2].toString() : '',
            );
          }
        }
      }
      return null;
    } catch (e) {
      print('Error getting shift by invoice ID: $e');
      return null;
    }
  }
}
