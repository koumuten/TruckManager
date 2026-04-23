import 'package:truck_manager/services/pdf_service.dart';
import 'package:truck_manager/services/firestore_service.dart';
import 'package:truck_manager/services/line.dart';
import 'package:truck_manager/services/notify.dart';
import 'package:truck_manager/services/capsules.dart';
import 'package:truck_manager/services/gdrive_service.dart';
import 'package:truck_manager/services/mail.dart';
import 'package:truck_manager/services/spread_sheet.dart';
import 'package:truck_manager/truck_manager.dart';

class App {
  final AppService _appService;

  App(this._appService);

  static Future<App> create() async {
    // 各サービスを非同期で初期化
    final pdf = await PdfService.create();
    final drive = await GDriveService.create();
    final firestore = await FirestoreService.create();
    final line = await LineNotifyService.create();
    final gmail = GmailServiceImpl();
    final spreadsheet = await SpreadSheetService.create();
    await gmail.initialize();

    // AppServiceにすべてのサービスを渡して初期化
    final appService =
        AppService(pdf, drive, firestore, line, gmail, spreadsheet);

    return App(appService);
  }

  // AppServiceのメソッドを呼び出す
  Future<void> runInvoiceSyncWorkflow() => _appService.runInvoiceSyncWorkflow();
}

Future<void> main() async {
  final app = await App.create();
  await app.runInvoiceSyncWorkflow();
}
