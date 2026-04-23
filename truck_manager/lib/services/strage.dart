import 'dart:io' as io;

abstract class StorageService {
  /// 認証情報の初期化
  Future<void> initialize();

  /// ファイルをアップロードして公開（またはアクセス可能）URLを返す
  Future<String> uploadFile({
    required String name,
    required io.File file,
  });
}
