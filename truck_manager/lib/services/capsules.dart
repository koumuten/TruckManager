
import 'package:intl/intl.dart';

class OrderCapsule {
  final String state;
  final String percentage;
  final String date;
  final String price;
  final String objectName;
  final String lastUpdated;
  final String url;
  final String id;

  OrderCapsule({
    this.state = '',
    this.percentage = '',
    this.date = '',
    this.price = '',
    this.objectName = '',
    this.lastUpdated = '',
    this.url = '',
    this.id = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'state': state,
      'percentage': percentage,
      'date': date,
      'price': price,
      'objectName': objectName,
      'lastUpdated': lastUpdated,
      'url': url,
      'id': id,
    };
  }
}

class InvoiceCapsule {
  String clientName;
  String myCompany;
  String invoiceDate;
  int totalAmount;
  String invoiceNumber;
  String invoiceImgPath;

  InvoiceCapsule({
    this.clientName = '',
    this.myCompany = '',
    this.invoiceDate = '',
    this.totalAmount = 0,
    this.invoiceNumber = '',
    this.invoiceImgPath = '',
  });

  /// 抽出結果が無効（例：金額が0）かどうかを判定する
  bool get isExtractionInvalid => totalAmount == 0;

  factory InvoiceCapsule.fromPdfText(String text) {
    final capsule = InvoiceCapsule();
    final lines = text.split('\n');

    // 正規表現のパターン
    final amountPattern = RegExp(r'(?:¥|\|￥|\s)((?:[0-9]{1,3},)*[0-9]{1,3})');
    final datePattern = RegExp(r'(\d{4})[年|\/|\.](\d{1,2})[月|\/|\.](\d{1,2})日?');
    final invoiceNumPattern = RegExp(r'No\.\s*([A-Z0-9\-]+)');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.contains('請求書')) {
        // 「御中」が含まれる行をクライアント名として扱う
        if (i > 0 && lines[i - 1].contains('御中')) {
          capsule.clientName = lines[i - 1].replaceAll('御中', '').trim();
        }
      }

      // 金額の抽出
      final amountMatch = amountPattern.firstMatch(line);
      if (amountMatch != null) {
        final amountStr = amountMatch.group(1)!.replaceAll(',', '');
        final amount = int.tryParse(amountStr);
        if (amount != null && amount > capsule.totalAmount) {
          capsule.totalAmount = amount;
        }
      }

      // 日付の抽出
      final dateMatch = datePattern.firstMatch(line);
      if (dateMatch != null) {
        final year = int.parse(dateMatch.group(1)!);
        final month = int.parse(dateMatch.group(2)!);
        final day = int.parse(dateMatch.group(3)!);
        capsule.invoiceDate = DateFormat('yyyy-MM-dd').format(DateTime(year, month, day));
      }

      // 請求書番号の抽出
      final invoiceNumMatch = invoiceNumPattern.firstMatch(line);
      if (invoiceNumMatch != null) {
        capsule.invoiceNumber = invoiceNumMatch.group(1)!;
      }
    }

    return capsule;
  }
}

class ShiftCapsule {
  final String client;
  final String date;
  final String eventName;
  final String assignment;
  final String reserver;
  final String id;

  ShiftCapsule({
    this.client = '',
    this.date = '',
    this.eventName = '',
    this.assignment = '',
    this.reserver = '',
    this.id = '',
  });

  factory ShiftCapsule.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'] as Map<String, dynamic>;
    final clientRelation = properties['Client']?['relation'] as List<dynamic>?;
    final eventNameTitle = properties['案件名']?['title'] as List<dynamic>?;
    final dateData = properties['Date']?['date'] as Map<String, dynamic>?;
    final assignmentSelect = properties['Assignment']?['select'] as Map<String, dynamic>?;
    final reserverPeople = properties['確保']?['people'] as List<dynamic>?;

    return ShiftCapsule(
      client: clientRelation?.isNotEmpty == true ? clientRelation![0]['id'] : '',
      eventName: eventNameTitle?.isNotEmpty == true ? eventNameTitle![0]['plain_text'] : '',
      date: dateData?['start'] ?? '',
      assignment: assignmentSelect?['name'] ?? '',
      reserver: reserverPeople?.isNotEmpty == true ? reserverPeople![0]['id'] : '',
      id: json['id'],
    );
  }
}
