// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'capsules.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrderCapsule _$OrderCapsuleFromJson(Map<String, dynamic> json) => OrderCapsule(
      state: json['state'] as String? ?? '',
      percentage: json['percentage'] as String? ?? '',
      date: json['date'] as String? ?? '',
      price: json['price'] as String? ?? '',
      objectName: json['objectName'] as String? ?? '',
      lastUpdated: json['lastUpdated'] as String? ?? '',
      url: json['url'] as String? ?? '',
      id: json['id'] as String? ?? '',
    );

Map<String, dynamic> _$OrderCapsuleToJson(OrderCapsule instance) =>
    <String, dynamic>{
      'state': instance.state,
      'percentage': instance.percentage,
      'date': instance.date,
      'price': instance.price,
      'objectName': instance.objectName,
      'lastUpdated': instance.lastUpdated,
      'url': instance.url,
      'id': instance.id,
    };

InvoiceCapsule _$InvoiceCapsuleFromJson(Map<String, dynamic> json) =>
    InvoiceCapsule(
      clientName: json['clientName'] as String? ?? '',
      myCompany: json['myCompany'] as String? ?? '',
      invoiceDate: json['invoiceDate'] as String? ?? '',
      totalAmount: (json['totalAmount'] as num?)?.toInt() ?? 0,
      invoiceNumber: json['invoiceNumber'] as String? ?? '',
      invoiceImgPath: json['invoiceImgPath'] as String? ?? '',
    );

Map<String, dynamic> _$InvoiceCapsuleToJson(InvoiceCapsule instance) =>
    <String, dynamic>{
      'clientName': instance.clientName,
      'myCompany': instance.myCompany,
      'invoiceDate': instance.invoiceDate,
      'totalAmount': instance.totalAmount,
      'invoiceNumber': instance.invoiceNumber,
      'invoiceImgPath': instance.invoiceImgPath,
    };

ShiftCapsule _$ShiftCapsuleFromJson(Map<String, dynamic> json) => ShiftCapsule(
      client: json['client'] as String? ?? '',
      date: json['date'] as String? ?? '',
      eventName: json['eventName'] as String? ?? '',
      assignment: json['assignment'] as String? ?? '',
      reserver: json['reserver'] as String? ?? '',
      id: json['id'] as String? ?? '',
    );

Map<String, dynamic> _$ShiftCapsuleToJson(ShiftCapsule instance) =>
    <String, dynamic>{
      'client': instance.client,
      'date': instance.date,
      'eventName': instance.eventName,
      'assignment': instance.assignment,
      'reserver': instance.reserver,
      'id': instance.id,
    };
