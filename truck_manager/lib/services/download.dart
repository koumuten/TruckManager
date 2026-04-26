import 'dart:io';

class RetriveService {
  static Future<void> downloadFile(String url, String savePath) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));

      final response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        final file = File(savePath);
        await response.pipe(file.openWrite());
        print('complete download: $savePath');
      } else {
        throw Exception('faital error in dowloading.. ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    } finally {
      client.close();
    }
  }
}
