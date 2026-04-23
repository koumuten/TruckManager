import 'dart:io' as io;
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/strage.dart';

class FirebaseStorageService implements StorageService {
  storage.StorageApi? _api;
  String? _bucketName;

  @override
  Future<void> initialize() async {
    final String clientId = await AssetLoader.readAsset("OAUTH_ID");
    final String clientSecret = await AssetLoader.readAsset("OAUTH_SECRET");
    final String refreshToken = await AssetLoader.readAsset("G_REFRESH_TOKEN");
    // Firebaseのバケット名をアセットから取得するようにします
    final String projectId = await AssetLoader.readAsset("TARGET");

    final id = ClientId(clientId, clientSecret);
    final scopes = [storage.StorageApi.cloudPlatformScope];

    final credentials = AccessCredentials(
      AccessToken('Bearer', '',
          DateTime.now().toUtc().subtract(const Duration(hours: 1))),
      refreshToken,
      scopes,
    );

    final authClient = autoRefreshingClient(id, credentials, http.Client());
    _api = storage.StorageApi(authClient);
    _bucketName = '$projectId.firebasestorage.app';
  }

  @override
  Future<String> uploadFile(
      {required String name, required io.File file}) async {
    if (_api == null) throw StateError("StorageApi is not initialized");

    final media = storage.Media(file.openRead(), await file.length(),
        contentType: 'image/jpeg');
    final response = await _api!.objects.insert(
      storage.Object(name: name),
      _bucketName!,
      uploadMedia: media,
    );

    final encodedPath = Uri.encodeComponent(response.name!);
    return 'https://firebasestorage.googleapis.com/v0/b/$_bucketName/o/$encodedPath?alt=media';
  }
}
