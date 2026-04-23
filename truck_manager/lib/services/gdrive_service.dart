import 'dart:io' as io;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/oauth2/v2.dart' as oauth2;
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/strage.dart';
import 'package:http/http.dart' as http;

class GDriveService implements StorageService {
  final drive.DriveApi _api;
  final String? _uploadFolderId;

  // Private constructor
  GDriveService._(this._api, this._uploadFolderId);

  // Static factory method for asynchronous initialization
  static Future<GDriveService> create() async {
    final String clientIdStr = await AssetLoader.readAsset("OAUTH_ID");
    final String clientSecretStr = await AssetLoader.readAsset("OAUTH_SECRET");
    final String refreshTokenStr = await AssetLoader.readAsset("G_REFRESH_TOKEN");
    final uploadFolderId = await AssetLoader.readAsset("GDRIVE_UPLOAD_FOLDER_ID");

    final id = ClientId(clientIdStr, clientSecretStr);
    // Add userinfo.email scope to retrieve user email
    final scopes = [
      drive.DriveApi.driveFileScope,
      'https://www.googleapis.com/auth/userinfo.email',
    ];

    final credentials = AccessCredentials(
      AccessToken(
        'Bearer',
        '',
        DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      ),
      refreshTokenStr,
      scopes,
    );

    final authClient = autoRefreshingClient(id, credentials, http.Client());
    final api = drive.DriveApi(authClient);

    // Retrieve and print logged-in user information for debugging
    try {
      final oauth2Api = oauth2.Oauth2Api(authClient);
      final userinfo = await oauth2Api.userinfo.get();
      print('Google Drive Service ログインユーザー: ${userinfo.email}');
    } catch (e) {
      print('ユーザー情報の取得に失敗しました (デバッグ用): $e');
    }

    return GDriveService._(api, uploadFolderId);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<String> uploadFile(
      {required String name, required io.File file}) async {
    print('GDriveService: アップロード処理を開始します。ファイル名: $name');
    final driveFile = drive.File()..name = name;
    if (_uploadFolderId != null && _uploadFolderId!.isNotEmpty) {
      driveFile.parents = [_uploadFolderId!];
      print('GDriveService: アップロードフォルダID: $_uploadFolderId に設定します。');
    } else {
      print('GDriveService: アップロードフォルダIDが設定されていないため、ルートにアップロードされます。');
    }

    final media = drive.Media(file.openRead(), await file.length());
    print('GDriveService: ファイルサイズ: ${await file.length()} bytes');

    try {
      final response = await _api.files.create(
        driveFile,
        uploadMedia: media,
      );
      print('GDriveService: ファイルがアップロードされました。ファイルID: ${response.id}');

      // Make the file publicly readable
      await _api.permissions.create(
        drive.Permission()
          ..role = 'reader'
          ..type = 'anyone',
        response.id!,
      );
      print('GDriveService: ファイルの公開設定が完了しました。');

      // Get the web link for the file
      final uploadedFile = await _api.files.get(response.id!, $fields: 'webViewLink') as drive.File;
      print('GDriveService: Web表示リンクを取得しました: ${uploadedFile.webViewLink}');
      return uploadedFile.webViewLink!;
    } catch (e, stackTrace) {
      print('GDriveService: ファイルアップロード中にエラーが発生しました: $e');
      print('GDriveService: スタックトレース: $stackTrace');
      rethrow; // AppServiceでエラーを捕捉できるように再スロー
    }
  }
}
