import 'dart:io';
import 'dart:convert';
import 'package:dotenv/dotenv.dart' as dotenv;

class AssetLoader {
  /// テスト環境で実行されているかをチェックする
  static Future<bool> isDebug() async {
    final envJudge = Platform.environment.containsKey('IS_TEST_ENVIRONMENT');
    final fileJudge = await File('.env').exists();
    return envJudge || fileJudge;
  }

  /// パスが ./ か / で始まる場合はファイルとして読み込み、
  /// それ以外の場合は環境変数から取得する。
  static Future<String> readAsset(String keyOrPath) async {
    if (keyOrPath.startsWith('.') || keyOrPath.startsWith('/')) {
      final file = File(keyOrPath);
      if (!await file.exists()) {
        throw Exception('File not found: $keyOrPath');
      }
      return await file.readAsString();
    } else {
      final List<String> envfiles = [];
      if (await File('.env').exists()) {
        envfiles.add('.env');
      }
      for (var element in envfiles) {
        dotenv.load(element);
      }
      final value = dotenv.env[keyOrPath];
      if (value == null || value.isEmpty) {
        throw Exception('Environment variable NOT FOUND: $keyOrPath');
      }
      return value;
    }
  }
}
