
import 'dart:convert';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/asset_loader.dart';

/// Gmail API との通信を抽象化するインターフェース
abstract class GmailService {
  Future<void> initialize();
  Future<List<gmail.Message>> fetchMessageList(String query);
  Future<gmail.Message> getMessageDetails(String id);
  Future<List<int>> fetchAttachment(String messageId, String attachmentId);
  Future<void> markAsRead(String id);
}

/// Gmail API との実際の通信を担うクラス
class GmailServiceImpl implements GmailService {
  gmail.GmailApi? _api;

  @override
  Future<void> initialize() async {
    final json = await AssetLoader.readAsset('FIREBASE_SERVICE_ACCOUNT_JSON');
    final credentials = ServiceAccountCredentials.fromJson(json);
    final authClient = await clientViaServiceAccount(credentials, [gmail.GmailApi.gmailModifyScope]);
    _api = gmail.GmailApi(authClient);
  }

  @override
  Future<List<gmail.Message>> fetchMessageList(String query) async {
    final response = await _api!.users.messages.list('me', q: query);
    return response.messages ?? [];
  }

  @override
  Future<gmail.Message> getMessageDetails(String id) async {
    return await _api!.users.messages.get('me', id);
  }

  @override
  Future<List<int>> fetchAttachment(String messageId, String attachmentId) async {
    final attachment = await _api!.users.messages.attachments.get('me', messageId, attachmentId);
    if (attachment.data == null) {
      throw Exception("Attachment data is null");
    }
    return base64Url.decode(attachment.data!);
  }

  @override
  Future<void> markAsRead(String id) async {
    final request = gmail.ModifyMessageRequest(removeLabelIds: ['UNREAD']);
    await _api!.users.messages.modify(request, 'me', id);
  }
}
