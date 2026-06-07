/// A 1D/2D barcode element.
library;

import '../report_element.dart';
import '../styles/color.dart';

/// The barcode symbology (encoding) to render.
enum BarcodeSymbology {
  /// 2D QR code.
  qrCode,

  /// 1D Code 128 (alphanumeric).
  code128,

  /// 1D EAN-13 / UPC retail code.
  ean13,

  /// 2D Data Matrix.
  dataMatrix,
}

/// Encodes [data] as a [symbology] barcode drawn in [color] within [bounds].
/// For this iteration [data] is a literal string; expression binding arrives
/// with the expression engine (spec 005).
class BarcodeElement extends ReportElement {
  /// Creates a barcode element.
  const BarcodeElement({
    required super.id,
    required super.bounds,
    required this.symbology,
    required this.data,
    this.color = JetColor.black,
  });

  /// The barcode encoding.
  final BarcodeSymbology symbology;

  /// The literal data to encode.
  final String data;

  /// Foreground (bar) color.
  final JetColor color;

  @override
  String get typeKey => 'barcode';

  @override
  bool operator ==(Object other) =>
      other is BarcodeElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.symbology == symbology &&
      other.data == data &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, bounds, symbology, data, color);

  @override
  String toString() => 'BarcodeElement($id, ${symbology.name})';
}
