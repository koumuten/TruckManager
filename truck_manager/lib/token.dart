import 'dart:io';
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/asset_loader.dart';

void main() async {
  final clientId = await AssetLoader.readAsset("OAUTH_ID");
  final clientSecret = await AssetLoader.readAsset("OAUTH_SECRET");

  final id = ClientId(clientId, clientSecret);

  // 必要な権限 (Gmailの読み書き)
  final scopes = ['https://www.googleapis.com/auth/gmail.modify'];

  try {
    final client = await clientViaUserConsentManual(id, scopes, (url) async {
      print('\n1. 以下の URL をブラウザで開いて認証してください:');
      print('------------------------------------------------------------');
      print(url);
      print('------------------------------------------------------------\n');

      print('2. 認証後、画面に表示された「認証コード」をコピーしてください。');
      stdout.write('3. ここにコードを貼り付けて Enter を押してください: ');

      // --- ここを修正 ---
      // ユーザーの入力を一行読み取り、その結果を返す
      final input = stdin.readLineSync();
      if (input == null || input.isEmpty) {
        throw Exception("認証コードが入力されませんでした。");
      }
      return input.trim();
    });

    // 取得したリフレッシュトークンを表示
    print('\n============================================================');
    print('【成功】リフレッシュトークンを取得しました！');
    print('これを GitHub Secrets (G_REFRESH_TOKEN) に保存してください:');
    print('');
    print(client.credentials.refreshToken);
    print('============================================================');

    exit(0);
  } catch (e) {
    print('\nエラーが発生しました: $e');
    exit(1);
  }
}
