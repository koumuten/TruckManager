
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:truck_manager/services/capsules.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/notify.dart';

class LineNotifyService {
  final String channelAccessToken;
  final String targetUserId;

  LineNotifyService._(this.channelAccessToken, this.targetUserId);

  static Future<LineNotifyService> create() async {
    final String channelAccessTokenTmp =
        await AssetLoader.readAsset('LINE_NOTIFY_TOKEN');
    final String targetUserIdTmp =
        await AssetLoader.readAsset('LINE_TARGET_USER_ID');

    return LineNotifyService._(channelAccessTokenTmp, targetUserIdTmp);
  }

  /// OrderCapsuleのリストを受け取って、LINEへカルーセル形式で送信する
  Future<String> sendOrderNotifications(List<OrderCapsule> orders, {bool isDebug = false}) async {
    if (channelAccessToken.isEmpty || targetUserId.isEmpty) {
      throw Exception('LINEの認証情報（環境変数）が不足しています。');
    }

    try {
      // 1. JSONテンプレートの読み込みと「バブル部分」の抽出
      final file = File('assets/template.json');
      final templateString = await file.readAsString();
      final Map<String, dynamic> fullTemplate = jsonDecode(templateString);

      // JSONの "contents" 配列の最初の要素（バブル1個分）を文字列として抽出
      final String bubbleBaseStr = jsonEncode(fullTemplate['contents'][0]);

      // 2. 各オーダーデータをテンプレートに流し込む（マッピング）
      List<Map<String, dynamic>> carouselContents = orders.map((order) {
        String replaced = bubbleBaseStr;

        // OrderCapsule のプロパティを使って、テンプレートの {{変数}} を置換
        replaced = replaced.replaceAll('{{State}}', order.state);
        replaced = replaced.replaceAll('{{percentage}}', order.percentage);
        replaced = replaced.replaceAll('{{date}}', order.date);
        replaced = replaced.replaceAll('{{price}}', order.price);
        replaced = replaced.replaceAll('{{Object}}', order.objectName);
        replaced = replaced.replaceAll('{{Last}}', order.lastUpdated);

        return jsonDecode(replaced) as Map<String, dynamic>;
      }).toList();

      // 3. LINE Messaging API 用のペイロード組み立て
      final body = {
        "to": targetUserId,
        "messages": [
          {
            "type": "flex",
            "altText": "振り込みタスクのお知らせ",
            "contents": {
              "type": "carousel",
              "contents": carouselContents // 生成したバブルのリストをここに流し込む
            }
          }
        ]
      };

      // 4. 送信実行
      if (!isDebug) {
        final response = await http.post(
          Uri.parse('https://api.line.me/v2/bot/message/push'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $channelAccessToken',
          },
          body: jsonEncode(body),
        );

        if (response.statusCode == 200) {
          print('LINE通知が正常に送信されました。');
        } else {
          print('LINE送信エラー: ${response.statusCode} - ${response.body}');
          await GASNotifyService.notifyErrorToGas(
          "Faital Error in LineNotifyService : \n${response.statusCode}\n${response.body}");
        }
        return response.statusCode.toString();
      }else{
        return jsonEncode(body);
      }
    } catch (e,stackTrace) {
      print('LINEサービス内でエラーが発生しました: $e');
      await GASNotifyService.notifyErrorToGas(
          "Faital Error in AppService: \n $e \n Stack: $stackTrace");
    }
    return "";
  }
}
