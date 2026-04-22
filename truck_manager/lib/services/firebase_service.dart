import 'dart:convert';
import 'dart:io' as io;
import 'package:googleapis/storage/v1.dart' as storage; // firebasestorage ではなく storage
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/notify.dart';

class FirebaseService {
  final FirestoreApi? api;
  final storage.StorageApi? storageApi;
  final String? rootPath;
  final String? projectId;

  // コンストラクタを private にして、中途半端な状態での生成を防ぐ
  FirebaseService._(this.api, this.storageApi, this.rootPath,this.projectId);

  // 静的ファクトリメソッド（初期化子代わり）
  static Future<FirebaseService> create(String jsonKey) async {
    // サービスアカウントJSONで認証
    final credentials = ServiceAccountCredentials.fromJson(jsonKey);
    final client = await clientViaServiceAccount(
      credentials, 
      [FirestoreApi.datastoreScope,storage.StorageApi.cloudPlatformScope]
    );
    
    final fireStoreApi = FirestoreApi(client);
    final storageApiTmp = storage.StorageApi(client);
    // プロジェクトIDをJSONから取得し、Firestoreのパスを組み立て
    final jsonDict = jsonDecode(jsonKey);
    final projectIdTmp = jsonDict["project_id"];
    if (projectIdTmp == null) {
      throw Exception("Project ID not found in JSON key");
    }
    final rootPath = 'projects/$projectIdTmp/databases/(default)/documents';

    // 準備が整った状態でインスタンスを返す
    return FirebaseService._(fireStoreApi,storageApiTmp, rootPath,projectIdTmp);
  }

  Future<String> uploadFile({
    required String storagePath,
    required io.File file,
  }) async {
    try {
      // バケット名：FirebaseコンソールのStorageタブにある「gs://」以降の名前
      // 通常は [プロジェクトID].appspot.com か [プロジェクトID].firebasestorage.app
      final bucketName = '$projectId.firebasestorage.app';

      final media = storage.Media(
        file.openRead(),
        await file.length(),
        contentType: 'image/jpeg',
      );

      print('Storageへアップロード中: $storagePath ...');

    if (storageApi == null) {
        throw Exception("StorageApi (objects) is not initialized");
      }

      print('Storageへアップロード中: $storagePath ...');

      final response = await storageApi!.objects.insert(
        storage.Object(name: storagePath),
        bucketName,
        uploadMedia: media,
      );

      // 公開URLの構築（Firebaseの標準的な形式）
      // セキュリティルールが「allow read;」になっていればこのURLで閲覧可能
      final encodedPath = Uri.encodeComponent(response.name!);
      final downloadUrl = 'https://firebasestorage.googleapis.com/v0/b/$bucketName/o/$encodedPath?alt=media';
      
      print('アップロード成功: $downloadUrl');
      return downloadUrl;
    } catch (e,stackTrace) {
      print('Firebase Storage Upload Error: $e');
      await GASNotifyService.notifyErrorToGas(
          "Faital Error in AppService: \n $e \n Stack: $stackTrace");
      rethrow;
    }
  }

  /// 指定したコレクションにドキュメントを保存する
  Future<String> saveDocument({
    required String collectionPath,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    if (api == null) throw Exception("FirebaseService is not initialized");

    final doc = Document()..fields = _toFirestoreMap(data);
    await api!.projects.databases.documents
        .patch(doc, '$rootPath/$collectionPath/$docId');
    return '$rootPath/$collectionPath/$docId';
  }

  /// DartのMapをFirestoreのDocument.fields形式 (Map<String, Value>) に変換する
  Map<String, Value> _toFirestoreMap(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, _toFirestoreValue(value)));
  }

  /// 個別の値を Firestore の Value オブジェクトに変換する
  Value _toFirestoreValue(dynamic value) {
    final firestoreValue = Value();

    if (value == null) {
      firestoreValue.nullValue = 'NULL_VALUE';
    } else if (value is bool) {
      firestoreValue.booleanValue = value;
    } else if (value is int) {
      firestoreValue.integerValue = value.toString();
    } else if (value is double) {
      firestoreValue.doubleValue = value;
    } else if (value is DateTime) {
      firestoreValue.timestampValue = value.toUtc().toIso8601String();
    } else if (value is List) {
      firestoreValue.arrayValue = ArrayValue()
        ..values = value.map((item) => _toFirestoreValue(item)).toList();
    } else if (value is Map<String, dynamic>) {
      firestoreValue.mapValue = MapValue()..fields = _toFirestoreMap(value);
    } else {
      firestoreValue.stringValue = value.toString();
    }

    return firestoreValue;
  }
}
