import 'truck_manager.dart';
import 'package:truck_manager/services/firebase_service.dart';
import 'package:truck_manager/services/mail.dart';
import 'package:truck_manager/services/spread_sheet.dart';
import 'package:truck_manager/services/pdf_service.dart';
import 'package:truck_manager/services/line.dart';
import 'package:truck_manager/services/asset_loader.dart';

void main() async {
  print('Hello, World!');
  GmailServiceImpl gmail = GmailServiceImpl();
  List<Future<Object>> tasks = [
    AssetLoader.readAsset("TMP_DIR"),
    PdfService.create(),
    LineNotifyService.create(),
    AssetLoader.readAsset("TARGET")
  ];
  if (await AssetLoader.isDebug()) {
    tasks.add(AssetLoader.readAsset("./test/test_env/cnfg/g_cred.json"));
  } else {
    tasks.add(AssetLoader.readAsset("GOOGLE_SERVICE_CRED"));
  }

  List<Object> results = await Future.wait(tasks);

  String jsonKey = results[4] as String;
  String tmpDir = results[0] as String;
  PdfService pdf = results[1] as PdfService;
  LineNotifyService line = results[2] as LineNotifyService;
  String targetSubject = results[3] as String;

  tasks = [
    FirebaseService.create(jsonKey),
    GoogleSheetsService.create(jsonKey)
  ];
  results = await Future.wait(tasks);

  await gmail.initialize();

  AppService appService = AppService(
      firebase: results[0] as FirebaseService,
      gmail: gmail,
      sheets: results[1] as GoogleSheetsService,
      pdf: pdf,
      line: line,
      tmpDir: tmpDir);
  try {
    String result = await appService.runInvoiceSyncWorkflow(
      targetSubject: targetSubject,
      isDebug: false,
    );
    print("結果: $result");
  } catch (e) {
    print("エラーが発生しました: $e");
  }
}
