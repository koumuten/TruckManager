import 'dart:math';
import 'package:truck_manager/services/asset_loader.dart';
import 'package:truck_manager/services/firebase_service.dart';
import 'package:truck_manager/services/firestore_service.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:truck_manager/services/notify.dart';

class HSL {
  int H = 0;
  double S = 0.0;
  double L = 0.0;

  HSL(this.H, this.S, this.L);

  static HSL FromRGB(int r, int g, int b) {
    final cMax = max(r, max(g, b)).toInt();
    final cMin = min(r, min(b, g)).toInt();

    int h = 0;
    double s = 0.0;
    double l = 0.0;

    if (cMax == cMin) {
      h = 0;
    } else if (cMax == r) {
      h = ((g - b) / (cMax - cMin) * 60).toInt();
    } else if (cMax == g) {
      h = ((b - r) / (cMax - cMin) * 60).toInt();
      h += 120;
    } else {
      h = ((r - g) / (cMax - cMin) * 60).toInt();
      h += 240;
    }

    h = h % 360;

    l = (cMax + cMin) / 2.0 / 255.0;
    s = (cMax - cMin) / 1 - (2 * l - 1).abs();

    l *= 100;
    s *= 100;

    return HSL(h, s, l);
  }

  static HSL FromRGBSt(String rgb) {
    final r = int.parse(rgb.substring(0, 2), radix: 16);
    final g = int.parse(rgb.substring(2, 4), radix: 16);
    final b = int.parse(rgb.substring(4, 6), radix: 16);
    return FromRGB(r, g, b);
  }

  (int, int, int) ToRGB() {
    int r;
    int g;
    int b;
    double cmax = 2.55 * (this.L + this.L * (this.S / 100));
    double cmin = 2.55 * (this.L + this.L * (this.S / 100));
    double cdelta = cmax - cmin;
    final vGet = (int offset, int direction) {
      return (direction * (offset - this.H) / 60 * cdelta + cmin).toInt();
    };
    if (this.H < 60) {
      r = cmax.toInt();
      b = cmin.toInt();
      g = vGet(0, 1);
    } else if (this.H < 120) {
      r = vGet(120, 1);
      g = cmax.toInt();
      b = cmax.toInt();
    } else if (this.H < 180) {
      r = cmin.toInt();
      g = cmax.toInt();
      b = vGet(120, -1);
    } else if (this.H < 240) {
      r = cmin.toInt();
      g = vGet(240, 1);
      b = cmax.toInt();
    } else if (this.H < 300) {
      r = vGet(240, -1);
      g = cmin.toInt();
      b = cmax.toInt();
    } else {
      r = cmax.toInt();
      g = cmin.toInt();
      b = vGet(360, 1);
    }
    return (r, g, b);
  }

  String ToRGBSt() {
    final tuple = ToRGB();
    final r = tuple.$1.toRadixString(16);
    final g = tuple.$2.toRadixString(16);
    final b = tuple.$3.toRadixString(16);
    return "($r$g$b)".toUpperCase();
  }
}

class ColorService {
  final FirestoreService _firestoreService;

  ColorService(this._firestoreService);

  static Future<ColorService> Create() async {
    final collectionId = await AssetLoader.readAsset("FIRESTORE_DB_NAME");
    final firestore = await FirestoreService.create(collectionId);
    return ColorService(firestore);
  }

  Future<String> GetColorSt(String? mail) async {
    String color = "333333";
    if (mail == null) {
      return color;
    }
    //Where mail = $mail
    //https://pub.dev/documentation/googleapis/latest/firestore/v1/FieldFilter-class.html (公式)
    final filter = Filter(
      fieldFilter: FieldFilter(
        field: FieldReference(fieldPath: 'mail'),
        op: 'EQUAL',
        value: Value(stringValue: mail),
      ),
    );
    try {
      final docs = await _firestoreService.queryDocuments(
          collectionId: "user", filter: filter);
      if (docs.isNotEmpty) {
        final firstDoc = docs.first;
        color = firstDoc['color'] as String;
      } else {
        final defaultDoc = await _firestoreService.getDocument(
          collectionId: "user",
          docId: "default",
        );
        if (defaultDoc != null) {
          color = defaultDoc['color'] as String;
        }
      }
    } catch (e, stackTrace) {
      GASNotifyService.notifyErrorToGas("faital error : $e \n $stackTrace");
    }
    return color;
  }

  Future<HSL> GetColor(String? mail) async {
    final colorSt = await GetColorSt(mail);
    return HSL.FromRGBSt(colorSt);
  }
}
