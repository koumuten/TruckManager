import 'package:http/http.dart' as http;
import 'package:truck_manager/services/asset_loader.dart';

class GASNotifyService {
  static Future<void> notifyErrorToGas(String message) async {
    print(message);
    try {
      // GASのデプロイURL (GETパラメータとしてメッセージを送信)
      final url = Uri.parse(await AssetLoader.readAsset("GAS_WEB_HOOK"))
          .replace(queryParameters: {'message': message});

      await http.get(url);
    } catch (e) {
      print("GASへの通知自体に失敗しました: $e");
    }
  }
}
