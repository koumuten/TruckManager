import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared/capsules.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/notify.dart';

class LineNotifyService {
  final String channelAccessToken;
  final String targetUserId;

  LineNotifyService._(this.channelAccessToken, this.targetUserId);

  static Future<LineNotifyService> create({String targetId = ''}) async {
    final String channelAccessTokenTmp =
        await AssetLoader.readAsset('LINE_NOTIFY_TOKEN');
    final String targetUserIdTmp = targetId.isEmpty 
    ? await AssetLoader.readAsset('LINE_TARGET_USER_ID') 
    : targetId;


    return LineNotifyService._(channelAccessTokenTmp, targetUserIdTmp);
  }

  /// 値が空またはnullの場合に半角スペースを返すヘルパー関数
  String _safeValue(String? value) =>
      (value == null || value.isEmpty) ? ' ' : value;

  /// 汎用的なFlex Message送信メソッド
  Future<String> sendFlexMessage({
    required String to,
    required String altText,
    required Map<String, dynamic> contents,
  }) async {
    if (channelAccessToken.isEmpty) {
      throw Exception('LINEの認証情報（環境変数）が不足しています。');
    }

    final body = {
      "to": to,
      "messages": [
        {
          "type": "flex",
          "altText": altText,
          "contents": contents,
        }
      ]
    };

    try {
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
    } catch (e, stackTrace) {
      print('LINEサービス内でエラーが発生しました: $e');
      await GASNotifyService.notifyErrorToGas(
          "Faital Error in sendFlexMessage: \n $e \n Stack: $stackTrace");
      return "";
    }
  }

    /// OrderCapsuleのリストを受け取って、LINEへカルーセル形式で送信する
  Future<String> sendOrderNotifications(List<OrderCapsule> orders, String altText) async {
    if (targetUserId.isEmpty) {
      throw Exception('LINEのターゲットユーザーIDが設定されていません。');
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

        order.lastUpdated ??= DateTime.now();

        try {
          DateTime created = DateTime.parse(order.date);
          order.date = "${created.month} / ${created.day}";
        } catch (e, stackTrace) {
          print(e);
          GASNotifyService.notifyErrorToGas("faital error : $e \n $stackTrace");
        }

        replaced = replaced.replaceAll('{{State}}', _safeValue(StateJp[order.state]));
        replaced = replaced.replaceAll('{{percentage}}', _safeValue(order.percentage));
        replaced = replaced.replaceAll('{{date}}', _safeValue(order.date));
        replaced = replaced.replaceAll('{{price}}', _safeValue(order.price));
        replaced = replaced.replaceAll('{{Object}}', _safeValue(order.objectName));
        replaced = replaced.replaceAll(
            '{{Last}}', _safeValue("${order.lastUpdated!.month}/${order.lastUpdated!.day}"));
        replaced = replaced.replaceAll('{{url}}', _safeValue(order.url));
        replaced = replaced.replaceAll('{{reserver}}', _safeValue(order.reserver));
        replaced = replaced.replaceAll('{{bgColor}}', "#${_safeValue(order.BGColor)}");

        Map<String, dynamic> bubble = jsonDecode(replaced) as Map<String, dynamic>;

        if (order.url == null || order.url!.trim().isEmpty) {
          List<dynamic> bodyContents = bubble['body']['contents'];
          bodyContents.removeWhere((item) => 
            item['type'] == 'button' || item['type'] == 'separator'
          );
        }

        return bubble;
      }).toList();

      // 3. APIの制限（最大12個）を回避するため、リストを分割して送信
      const int maxBubblesPerCarousel = 10; // 安全マージンを取って10個ずつ（最大12個まで可）
      String lastStatusCode = "200";

      for (int i = 0; i < carouselContents.length; i += maxBubblesPerCarousel) {
        // 部分リスト（チャンク）の終了インデックスを計算
        final end = (i + maxBubblesPerCarousel < carouselContents.length)
            ? i + maxBubblesPerCarousel
            : carouselContents.length;
        
        final chunk = carouselContents.sublist(i, end);

        // 複数回送信される場合、altTextにページ数をつけてあげると親切です
        final int currentPage = (i ~/ maxBubblesPerCarousel) + 1;
        final int totalPages = (carouselContents.length / maxBubblesPerCarousel).ceil();
        final displayAltText = totalPages > 1 ? "$altText ($currentPage/$totalPages)" : altText;

        lastStatusCode = await sendFlexMessage(
          to: targetUserId,
          altText: displayAltText,
          contents: {
            "type": "carousel",
            "contents": chunk
          },
        );
      }

      return lastStatusCode;

    } catch (e, stackTrace) {
      print('LINEサービス内でエラーが発生しました: $e');
      await GASNotifyService.notifyErrorToGas(
          "Faital Error in AppService: \n $e \n Stack: $stackTrace");
      return "";
    }
  }
}
