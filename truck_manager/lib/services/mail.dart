import 'dart:convert';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis_auth/auth_io.dart';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:http/http.dart' as http;

/// Gmail API との通信を抽象化するインターフェース
abstract class GmailService {
  Future<void> initialize();
  Future<List<gmail.Message>> fetchMessageList(String query);
  Future<gmail.Message> getMessageDetails(String id);
  Future<List<int>> fetchAttachment(String messageId, String attachmentId);
  Future<void> markAsRead(String id);
  Future<String?> GetOriginalSender(String id);
}

/// Gmail API との実際の通信を担うクラス
class GmailServiceImpl implements GmailService {
  gmail.GmailApi? _api;

  @override
  Future<void> initialize() async {
    final String clientId = await AssetLoader.readAsset("OAUTH_ID");
    final String clientSecret = await AssetLoader.readAsset("OAUTH_SECRET");
    final String refreshToken = await AssetLoader.readAsset("G_REFRESH_TOKEN");

    await init(
      clientId: clientId,
      clientSecret: clientSecret,
      refreshToken: refreshToken,
    );
  }

  Future<String> init({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    final id = ClientId(clientId, clientSecret);
    final scopes = [gmail.GmailApi.gmailModifyScope];

    // 修正ポイント: AccessToken の第1引数(type)を "Bearer" に、第2引数(data)を空文字にする
    final credentials = AccessCredentials(
      AccessToken(
        'Bearer', // ← ここを "Bearer" に変更
        '', // アクセストークン自体は空でOK（後でリフレッシュされるため）
        DateTime.now().toUtc().subtract(const Duration(hours: 1)), // 期限切れの状態にする
      ),
      refreshToken,
      scopes,
    );

    final authClient = autoRefreshingClient(id, credentials, http.Client());

    _api = gmail.GmailApi(authClient);
    print(authClient.runtimeType.toString());
    return authClient.runtimeType.toString();
  }

  @override
  Future<List<gmail.Message>> fetchMessageList(String query) async {
    if (_api == null) throw StateError("GmailApi is not initialized");
    final response = await _api!.users.messages.list('me', q: query);
    return response.messages ?? [];
  }

  @override
  Future<gmail.Message> getMessageDetails(String id) async {
    if (_api == null) throw StateError("GmailApi is not initialized");
    return await _api!.users.messages.get('me', id);
  }

  @override
  Future<List<int>> fetchAttachment(
      String messageId, String attachmentId) async {
    if (_api == null) throw StateError("GmailApi is not initialized");
    final attachment = await _api!.users.messages.attachments
        .get('me', messageId, attachmentId);
    if (attachment.data == null) {
      throw Exception("Attachment data is null");
    }
    return base64Url.decode(attachment.data!);
  }

  @override
  Future<void> markAsRead(String id) async {
    if (_api == null) throw StateError("GmailApi is not initialized");
    final request = gmail.ModifyMessageRequest(removeLabelIds: ['UNREAD']);
    await _api!.users.messages.modify(request, 'me', id);
  }

  /// メッセージのヘッダーから指定した名前の値を抽出する
  String? GetHeader(gmail.Message message, String name) {
    // 引用元：https://pub.dev/documentation/googleapis/latest/gmail/v1/MessagePart-class.html (公式)
    final headers = message.payload?.headers;
    if (headers == null) return null;

    final header = headers.firstWhere(
      (h) => h.name?.toLowerCase() == name.toLowerCase(),
      orElse: () => gmail.MessagePartHeader(),
    );
    return header.value;
  }

  /// 転送元（Original Sender）を推定するメソッド
  @override
  Future<String?> GetOriginalSender(String id) async {
    final message = await getMessageDetails(id);

    // 1. X-Forwarded-For ヘッダーを確認
    final forwardedFor = GetHeader(message, 'X-Forwarded-For');
    if (forwardedFor != null) return forwardedFor;

    // 2. 本文が 'Fwd:' の場合、Return-Path などを確認（憶測：環境により異なる）
    // 通常の From は転送した人のアドレスになっているため、
    // 転送設定による転送なら 'X-Forwarded-From' が存在する場合もあります。
    final forwardedFrom = GetHeader(message, 'X-Forwarded-From');
    if (forwardedFrom != null) return forwardedFrom;

    // 3. 見つからない場合は通常の From を返すか、null を返す
    return GetHeader(message, 'From');
  }
}
