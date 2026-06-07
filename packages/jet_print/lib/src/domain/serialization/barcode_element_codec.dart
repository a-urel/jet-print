/// JSON codec for [BarcodeElement].
library;

import '../elements/barcode_element.dart';
import '../geometry.dart';
import '../styles/color.dart';
import 'element_codec.dart';

/// Serializes [BarcodeElement] to/from its field map.
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
        color: json['color'] is String
            ? JetColor.fromJson(json['color']! as String)
            : JetColor.black,
      );

  @override
  Map<String, Object?> toJson(BarcodeElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'symbology': element.symbology.name,
        'data': element.data,
        if (element.color != JetColor.black) 'color': element.color.toJson(),
      };
}
