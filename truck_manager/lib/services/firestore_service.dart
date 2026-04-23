import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'dart:convert';

class FirestoreService {
  final FirestoreApi _api;
  final String _project;

  FirestoreService(this._api, this._project);

  static Future<FirestoreService> create() async {
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
    return FirestoreService(FirestoreApi(client), project);
  }

  Future<void> saveDocument({
    required String collectionPath,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final document = _createDocumentFromMap(data);
    final parent = 'projects/$_project/databases/truck/documents';
    final path = '$parent/$collectionPath';

    await _api.projects.databases.documents.createDocument(
      document,
      parent,
      collectionPath,
      documentId: docId.replaceAll('/', '-'),
    );
  }

  Future<List<Map<String, dynamic>>> getAllInvoices() async {
    final parent = 'projects/$_project/databases/(default)/documents';
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
}
