/// JSON codec for [BarcodeElement].
library;

import '../elements/barcode_element.dart';
import '../geometry.dart';
import '../styles/color.dart';
import 'element_codec.dart';

/// Serializes [BarcodeElement] to/from its field map. New fields (036) are
/// additive: written only when non-default, defaulted when absent, so legacy
/// documents round-trip byte-identically.
class BarcodeElementCodec extends ElementCodec<BarcodeElement> {
  /// Const constructor (the codec is stateless).
  const BarcodeElementCodec();

  @override
  BarcodeElement fromJson(Map<String, Object?> json) => BarcodeElement(
        id: json['id']! as String,
        bounds:
            JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        symbology: BarcodeSymbology.values.byName(json['symbology']! as String),
        data: json['data']! as String,
        dataField: json['dataField'] as String?,
        color: json['color'] is String
            ? JetColor.fromJson(json['color']! as String)
            : JetColor.black,
        showText: json['showText'] as bool? ?? true,
        quietZone: json['quietZone'] as bool? ?? true,
        eccLevel: json['ecc'] is String
            ? QrErrorCorrectionLevel.values.byName(json['ecc']! as String)
            : QrErrorCorrectionLevel.m,
        name: json['name'] as String?,
      );

  @override
  Map<String, Object?> toJson(BarcodeElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'symbology': element.symbology.name,
        'data': element.data,
        if (element.dataField != null) 'dataField': element.dataField,
        if (element.color != JetColor.black) 'color': element.color.toJson(),
        if (!element.showText) 'showText': false,
        if (!element.quietZone) 'quietZone': false,
        if (element.eccLevel != QrErrorCorrectionLevel.m)
          'ecc': element.eccLevel.name,
        if (element.name != null) 'name': element.name,
      };
}
