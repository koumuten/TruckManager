import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'dart:convert';

class FirestoreService {
  final FirestoreApi _api;
  final String _project;
  final String _collection;

  FirestoreService(this._api, this._project, this._collection);

  static Future<FirestoreService> create(String _collection) async {
    String credentialsJson;
    if (await AssetLoader.isDebug()) {
      credentialsJson =
          await AssetLoader.readAsset('./test/test_env/cnfg/g_cred.json');
    } else {
      credentialsJson = await AssetLoader.readAsset('GOOGLE_SERVICE_CRED');
    }
    final credentials =
        ServiceAccountCredentials.fromJson(jsonDecode(credentialsJson));
    final client = await clientViaServiceAccount(
        credentials, [FirestoreApi.datastoreScope]);
    final project =
        (jsonDecode(credentialsJson) as Map<String, dynamic>)['project_id'];
    return FirestoreService(FirestoreApi(client), project, _collection);
  }

  Future<void> saveDocument({
    required String collectionId,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final parent = 'projects/$_project/databases/$_collection/documents';
    final safeDocId = docId.replaceAll('/', '-');
    final documentPath = '$collectionId/$safeDocId';

    // 1. メインドキュメントの更新
    // 引用元：https://pub.dev/documentation/googleapis/latest/firestore/v1/ProjectsDatabasesDocumentsResource/patch.html (公式)
    final document = _createDocumentFromMap(data);
    await _api.projects.databases.documents.patch(
      document,
      '$parent/$documentPath',
      updateMask_fieldPaths: data.keys.toList(), // 指定したフィールドのみ更新
    );

    // 2. 更新履歴の作成
    final historyData = Map<String, dynamic>.from(data);
    historyData['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    final historyDocument = _createDocumentFromMap(historyData);

    // 履歴を保存するサブコレクションの「親」となるパスを指定
    // 構造: projects/.../documents/コレクション/ドキュメントID
    final historyParentPath = '$parent/$collectionId/$safeDocId';

    await _api.projects.databases.documents.createDocument(
      historyDocument,
      historyParentPath,
      'history',
    );
  }

  Future<List<Map<String, dynamic>>> getAllInvoices() async {
    final parent = 'projects/$_project/databases/$_collection/documents';
    final response =
        await _api.projects.databases.documents.list(parent, 'invoices');

    final List<Map<String, dynamic>> invoices = [];
    if (response.documents != null) {
      for (var doc in response.documents!) {
        invoices.add(_convertDocumentToMap(doc));
      }
    }
    return invoices;
  }

  Document _createDocumentFromMap(Map<String, dynamic> data) {
    final fields = <String, Value>{};
    for (var key in data.keys) {
      if (data[key] is String) {
        fields[key] = Value(stringValue: data[key]);
      } else if (data[key] is int) {
        fields[key] = Value(integerValue: data[key].toString());
      } // 他のデータ型も必要に応じて追加
    }
    return Document(fields: fields);
  }

  Map<String, dynamic> _convertDocumentToMap(Document document) {
    final map = <String, dynamic>{};
    if (document.fields != null) {
      for (var key in document.fields!.keys) {
        final value = document.fields![key];
        if (value!.stringValue != null) {
          map[key] = value.stringValue!;
        } else if (value.integerValue != null) {
          map[key] = int.tryParse(value.integerValue!) ?? 0;
        } // 他のデータ型も必要に応じて追加
      }
    }
    return map;
  }

  Future<Map<String, dynamic>?> getDocument({
    required String collectionId,
    required String docId,
  }) async {
    final name =
        'projects/$_project/databases/$_collection/documents/$collectionId/${docId.replaceAll('/', '-')}';

    try {
      final document = await _api.projects.databases.documents.get(name);
      return _convertDocumentToMap(document);
    } catch (e) {
      // ドキュメントが見つからない等のエラーハンドリング
      print('Error getting document: $e');
      return null;
    }
  }

  /// 任意のフィルタを受け取ってクエリを実行する
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collectionId,
    required Filter filter,
    int? limit,
  }) async {
    final parent = 'projects/$_project/databases/$_collection/documents';

    final query = RunQueryRequest(
      structuredQuery: StructuredQuery(
        from: [CollectionSelector(collectionId: collectionId)],
        where: filter,
        limit: limit,
      ),
    );

    final List<Map<String, dynamic>> results = [];
    try {
      // 引用元：https://pub.dev/documentation/googleapis/latest/firestore/v1/ProjectsDatabasesDocumentsResource/runQuery.html (公式)
      final List<RunQueryResponseElement> response =
          await _api.projects.databases.documents.runQuery(query, parent);

      for (var element in response) {
        if (element.document != null) {
          results.add(_convertDocumentToMap(element.document!));
        }
      }
    } catch (e) {
      print('Query execution error: $e');
    }
    return results;
  }
}
