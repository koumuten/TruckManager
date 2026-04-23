import 'package:truck_manager/truck_manager.dart';
import 'package:truck_manager/services/firestore_service.dart';
import 'package:truck_manager/services/gdrive_service.dart';
import 'package:truck_manager/services/line.dart';
import 'package:truck_manager/services/pdf_service.dart';
import 'package:truck_manager/services/mail.dart';
import 'package:truck_manager/services/spread_sheet.dart';

Future<void> main(List<String> arguments) async {
  final pdfService = await PdfService.create();
  final gdriveService = await GDriveService.create();
  final firestoreService = await FirestoreService.create();
  final lineNotifyService = await LineNotifyService.create();
  final gmailService = GmailServiceImpl(); // GmailServiceImplのインスタンスを作成
  await gmailService.initialize(); // initializeを呼び出す
  final spreadSheetService =
      await SpreadSheetService.create(); // SpreadSheetServiceのインスタンスを作成

  final app = AppService(pdfService, gdriveService, firestoreService,
      lineNotifyService, gmailService, spreadSheetService);
  await app.runInvoiceSyncWorkflow();
  //await app.runConsolidateInvoicesForLine();
}
