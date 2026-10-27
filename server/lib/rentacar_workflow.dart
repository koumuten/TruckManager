import 'package:truck_manager/services/line.dart';
import 'package:truck_manager/services/mail.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/notify.dart';
import 'package:truck_manager/services/firestore_service.dart';
import 'package:shared/capsules.dart';
import 'package:truck_manager/services/color.dart';
import 'package:truck_manager/services/spread_sheet.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:truck_manager/services/user.dart';

class RentACarWorkflow {
  final GmailService _gmail;
  final LineNotifyService _line;
  final FirestoreService _firestore;
  final SpreadSheetService _spreadsheet;

  RentACarWorkflow(this._gmail, this._line, this._firestore, this._spreadsheet);

  Future<void> run() async {
    print('Rent-a-car workflow started.');
    final baseUrl = await AssetLoader.readAsset("BASE_URL");
    final collectionId = await AssetLoader.readAsset("FIRESTORE_COLLECTION");
    try {
      final messages =
          await _gmail.fetchMessageList('is:unread subject:("【ニッポンレンタカー】ご予約")');
      if (messages.isEmpty) {
        print('No new rent-a-car emails to process.');
        return;
      }

      print('Found ${messages.length} rent-a-car emails.');
      var orders = <OrderCapsule>[];
      for (final messageMeta in messages) {
        final message = await _gmail.getMessageDetails(messageMeta.id!);
        final body = _gmail.getPlainTextBody(message);

        // 中身が読み取れないならスキップ
        if (body == null) {
          print('No plain text body found for email ${message.id}.');
          continue;
        }

        final parsedData = await _parseEmailBody(body);
        DateTime date = DateTime.now();
        OrderCapsule order = OrderCapsule();
        // 予約番号が不明の場合はUUIDを生成して設定
        if (parsedData['予約番号'] == '不明') {
          var uuid = Uuid();
          parsedData['予約番号'] = uuid.v4().toString();
        }

        // 出発日時が不明の場合はスキップ
        if (parsedData['出発日時'] == '不明' || parsedData["出発日時"] == null) {
          print('出発日時が不明のため、メール ${message.id} をスキップします。');
          continue;
        }else{
          date = DateFormat('yyyy/MM/dd HH:mm').parse(parsedData['出発日時']!);
        }
      
        try {
            // 検索対象の値をわかりやすく変数に格納（※任意です）
            final targetDate = DateFormat('yyyy-MM-dd').format(date);
            
            print("$targetDate に対応するドキュメントを取得中...");
            
            // 日時と予約番号（id）のAND条件で検索
            var filter = 
                  Filter(
                    fieldFilter: FieldFilter(
                      field: FieldReference(fieldPath: 'date'),
                      op: 'EQUAL',
                      value: Value(stringValue: targetDate), 
                    ),
                  );

            // Firestoreからクエリを実行
            var existingDocs = await _firestore.queryDocuments(
              collectionId: collectionId,
              filter: filter,
            );

            if(existingDocs.length > 1){
              print("複数のOrderCapsuleが見つかりました。予約番号 ${parsedData['予約番号']} で絞り込みます。");
              filter = Filter(
                compositeFilter: CompositeFilter(
                  op: 'AND',
                  filters: [
                    // 1つ目の条件: 日時 (date) が一致
                    Filter(
                      fieldFilter: FieldFilter(
                        field: FieldReference(fieldPath: 'date'),
                        op: 'EQUAL',
                        value: Value(stringValue: targetDate), 
                      ),
                    ),
                    // 2つ目の条件: id が一致
                    Filter(
                      fieldFilter: FieldFilter(
                        field: FieldReference(fieldPath: 'id'), 
                        op: 'EQUAL',
                        value: Value(stringValue: parsedData['予約番号']), 
                      ),
                    ),
                  ],
                ),
              );
              existingDocs = await _firestore.queryDocuments(
                collectionId: collectionId,
                filter: filter,
              );
            }

            if (existingDocs.isNotEmpty) {
              print("既存のOrderCapsuleが見つかりました。復元します。");
              order = OrderCapsule.fromJson(existingDocs.first);
            } else {
              print("該当するOrderCapsuleは見つかりませんでした。");
            }
          } catch (e, stackTrace) {
            GASNotifyService.notifyErrorToGas(
                "faital error in retriving order: $e \n $stackTrace");
          }

         order = OrderCapsule(
          state : State.reserved,
          date :   DateFormat('yyyy-MM-dd').format(date),
          reserver: parsedData['お名前'] ?? '',
          lastUpdated : DateTime.now(),
          price : '不明',
          url : "$baseUrl/order/${parsedData['予約番号'] }",
          id : parsedData['予約番号'] ?? '',
        );
        order.percentage = "${order.getPercentageValue()}%";

        // shiftの取得とorderへの練習内容の反映
        ShiftCapsule shift;
        try {
          print("${order.date}に対応するシフトを取得中...");
          DateTime date = DateTime.parse(order.date);
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
                日付: ${order.date}
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

        order.objectName = shift.eventName;

        //予約者の取得と日調君への反映
        String? eMail = await _gmail.GetOriginalSender(message.id!);
        UserService userService = await UserService.Create();
        UserCapsule user = await userService.GetUser(eMail);
        _spreadsheet.updateTruckDataByHeader(DateTime.parse(order.date), "予約者", user.name);

        if (eMail != null) {
          eMail = eMail.split(" ")[0];
        }
        HSL color = HSL.FromRGBSt(user.color);
        color.L = order.getIdealLightness();
        order.BGColor = color.ToRGBSt();

        // Save to Firestore
        String docId = parsedData['予約番号'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        if (docId == '不明') docId = DateTime.now().millisecondsSinceEpoch.toString();
        await _firestore.saveDocument(
          collectionId: collectionId,
          docId: docId,
          data: {
            ...order.toJson(),
            "carType": parsedData['クラス'] ?? '',
            "pickupLocation": parsedData['出発店舗'] ?? '',
            "returnDate": parsedData['返却日時'] ?? '',
            "departureDate": parsedData['出発日時'] ?? '',  
            'state': State.reserved.name,
          },
        );

        // Mark as read if not in debug mode
        if (!(await AssetLoader.isDebug())) {
          await _gmail.markAsRead(message.id!);
          print('Marked email ${message.id} as read.');
        }
        
        orders.add(order);
        if(shift.id == '404'){
          print("対応するシフトが見つからなかったため、LINE通知を送信します。");        
          order = OrderCapsule(
            state : State.unknown,
            date :   DateFormat('yyyy-MM-dd').format(date),
            reserver: parsedData['お名前'] ?? '',
            lastUpdated : DateTime.now(),
            price : '不明',
            url : "$baseUrl/order/${order.id}",
            id : parsedData['予約番号'] ?? '',
          );
          await _line.sendOrderNotifications([order], "不正な予約プロセス ${parsedData['予約番号']} について");
        }

      }
      if (orders.isNotEmpty) {
        print('Sending LINE notifications for ${orders.length} orders.');
        await _line.sendOrderNotifications(orders, "レンタカー予約のお知らせ");
      } else {
        print('No valid orders to send notifications for.');
      }

    } catch (e, stackTrace) {
      print('An error occurred during the rent-a-car workflow: $e');
      print(stackTrace);
      await GASNotifyService.notifyErrorToGas(
          'Critical error in rent-a-car workflow: $e');
    }
  }

  Future<Map<String, String>> _parseEmailBody(String body) async{
    final Map<String, String> result = {};

    // Determine status based on subject or body contents
    String status = "予約完了";
    if (body.contains("変更いたしました")) {
      status = "予約変更";
    }

    body = body.replaceAll("\r\n", "\n"); // Normalize line endings
    if (await AssetLoader.isDebug()) {
      print(body);
    }

    result['ステータス'] = status;
    result['予約番号'] = _extractMatch(body, RegExp(r'予約番号：(.*?)\n'));
    result['お名前'] = _extractMatch(body, RegExp(r'お名前：(.*?)\n'));
    result['出発日時'] = _extractMatch(body, RegExp(r'出発日時：(.*?)\n'));
    result['返却日時'] = _extractMatch(body, RegExp(r'返却日時：(.*?)\n'));
    result['出発店舗'] = _extractMatch(body, RegExp(r'出発店舗\(TEL\)：(.*?)\n'));
    result['クラス'] = _extractMatch(body, RegExp(r'クラス：(.*?)\n'));
    print("${result['予約番号']} に対応するデータを抽出しました。");
    return result;
  }

  String _extractMatch(String text, RegExp regex) {
    final match = regex.firstMatch(text);
    return match?.group(1)?.trim() ?? '不明';
  }
}
