import 'package:json_annotation/json_annotation.dart';

part 'capsules.g.dart';

/// 運搬日程1日分を表すためのカプセル
@JsonSerializable()
class ShiftCapsule {
    DateTime date;

    String assignment; //運転手:8 
    String reserver;   //予約者:7
    String eventName;  //練習目的:2

    // date はなければ現在時刻を入力。→一度宣言後、改めて代入
    ShiftCapsule({
        DateTime? date,
        this.assignment = "",
        this.reserver = "",
        this.eventName = "",
    }): date = date ?? DateTime.now();

    // json deserializer
    factory ShiftCapsule.fromJson(Map<String, dynamic> json) => _$ShiftCapsuleFromJson(json);

    // json serializer
    Map<String, dynamic> toJson() => _$ShiftCapsuleToJson(this);
}

/// LINEの振り込みタスク通知（Flex Message）用のカプセル
@JsonSerializable()
class OrderCapsule {
  String state;       // {{State}} に対応（例: "未振り込み"）
  String percentage;  // {{percentage}} に対応（例: "0%"）
  String date;        // {{date}} に対応（例: "2026-03-20"）
  String price;       // {{price}} に対応（例: "¥10,000"）
  String objectName;  // {{Object}} に対応（例: "週末の練習試合"）
  String lastUpdated; // {{Last}} に対応（例: "今日"）

  OrderCapsule({
    this.state = "未振り込み",
    this.percentage = "0%",
    required this.date,
    this.price = "¥0",
    required this.objectName,
    this.lastUpdated = "未更新",
  });

  // json deserializer
  factory OrderCapsule.fromJson(Map<String, dynamic> json) => _$OrderCapsuleFromJson(json);

  // json serializer
  Map<String, dynamic> toJson() => _$OrderCapsuleToJson(this);

  // =================================================================
  // ▼ 明示的なキャスト（ShiftCapsule と InvoiceCapsule から生成） ▼
  // =================================================================
  factory OrderCapsule.fromAggregatedData({
    required ShiftCapsule shift,
    required InvoiceCapsule invoice,
    required String statusState, // 例: 'unpaid'
  }) {
    // 英語のステータス文字列を、LINEで表示するための日本語に変換
    String displayState = statusState == 'unpaid' ? '未振り込み' : statusState;

    return OrderCapsule(
      state: displayState,        // 変換したステータス
      percentage: "0%",           // 未払いなので固定で0%
      date: invoice.date,         // 請求書側の発行日を採用
      price: invoice.price,       // 請求書側の抽出金額を採用
      objectName: shift.eventName,// 運搬タスク側の「練習目的」を採用
      lastUpdated: "今日",
    );
  }
}

/// PDF（領収書/請求書）から抽出したデータを入れるカプセル
@JsonSerializable()
class InvoiceCapsule {
  String date;  // 例: "2026-03-18"
  String price; // 例: "¥20,460"
  String? invoiceImgPath; 

  InvoiceCapsule({
    required this.date,
    required this.price,
    this.invoiceImgPath,
  });

  factory InvoiceCapsule.fromJson(Map<String, dynamic> json) => _$InvoiceCapsuleFromJson(json);
  Map<String, dynamic> toJson() => _$InvoiceCapsuleToJson(this);

  factory InvoiceCapsule.fromPdfText(String pdfText) {
    // 1. 日付の抽出
    final dateMatch = RegExp(r'発行日[\s\S]*?(\d{4}/\d{2}/\d{2})').firstMatch(pdfText);
    String extractedDate = dateMatch != null ? dateMatch.group(1)! : "不明な日付";
    extractedDate = extractedDate.replaceAll('/', '-'); 

    // 2. 金額の抽出
    final priceMatch = RegExp(r'お支払い総合計[\s\S]*?([\d,]+)円').firstMatch(pdfText);
    String extractedPrice = priceMatch != null ? "¥${priceMatch.group(1)}" : "¥0";

    return InvoiceCapsule(
      date: extractedDate,
      price: extractedPrice,
    );
  }
}