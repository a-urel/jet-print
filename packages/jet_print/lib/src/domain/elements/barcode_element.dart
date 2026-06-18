/// A 1D/2D barcode element.
library;

import '../geometry.dart';
import '../report_element.dart';
import '../styles/color.dart';

/// The barcode symbology (encoding) to render. [auto] infers the concrete
/// symbology from the encoded value at fill time (see `symbology_inference`).
enum BarcodeSymbology {
  /// Infer the concrete symbology from the value (default for new elements).
  auto,

  /// 2D QR code.
  qrCode,

  /// 1D Code 128 (alphanumeric).
  code128,

  /// 1D EAN-13 / UPC retail code.
  ean13,

  /// 1D EAN-8 retail code.
  ean8,

  /// 1D UPC-A retail code.
  upcA,

  /// 1D Code 39.
  code39,

  /// 1D ITF-14 (interleaved 2-of-5, shipping containers).
  itf14,

  /// 2D Data Matrix.
  dataMatrix,

  /// 2D PDF417 (stacked linear).
  pdf417,

  /// 2D Aztec.
  aztec,
}

/// QR error-correction level (higher survives more damage, holds less data).
enum QrErrorCorrectionLevel { l, m, q, h }

/// Encodes [data] (or, when [dataField] is set, the value of that data-source
/// field resolved at fill time) as a [symbology] barcode drawn in [color]
/// within [bounds].
class BarcodeElement extends ReportElement {
  /// Creates a barcode element.
  const BarcodeElement({
    required super.id,
    required super.bounds,
    required this.symbology,
    required this.data,
    this.dataField,
    this.color = JetColor.black,
    this.showText = true,
    this.quietZone = true,
    this.eccLevel = QrErrorCorrectionLevel.m,
  });

  /// The barcode encoding (or [BarcodeSymbology.auto]).
  final BarcodeSymbology symbology;

  /// The literal data to encode when [dataField] is null.
  final String data;

  /// When non-null, the encoded value comes from this data-source field at
  /// fill time (and wins over [data]); otherwise [data] is used.
  final String? dataField;

  /// Foreground (bar/module) color.
  final JetColor color;

  /// Whether to draw human-readable text under 1D symbols (ignored by 2D).
  final bool showText;

  /// Whether to reserve the mandatory quiet-zone margin inside [bounds].
  final bool quietZone;

  /// QR error-correction level (ignored by non-QR symbologies).
  final QrErrorCorrectionLevel eccLevel;

  @override
  String get typeKey => 'barcode';

  /// Returns a copy with the named fields replaced and the rest preserved.
  ///
  /// [dataField] uses a wrapped callback so callers can clear it to null
  /// (`dataField: () => null`) distinctly from leaving it unchanged (omit).
  BarcodeElement copyWith({
    JetRect? bounds,
    BarcodeSymbology? symbology,
    String? data,
    String? Function()? dataField,
    JetColor? color,
    bool? showText,
    bool? quietZone,
    QrErrorCorrectionLevel? eccLevel,
  }) =>
      BarcodeElement(
        id: id,
        bounds: bounds ?? this.bounds,
        symbology: symbology ?? this.symbology,
        data: data ?? this.data,
        dataField: dataField != null ? dataField() : this.dataField,
        color: color ?? this.color,
        showText: showText ?? this.showText,
        quietZone: quietZone ?? this.quietZone,
        eccLevel: eccLevel ?? this.eccLevel,
      );

  @override
  BarcodeElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  bool operator ==(Object other) =>
      other is BarcodeElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.symbology == symbology &&
      other.data == data &&
      other.dataField == dataField &&
      other.color == color &&
      other.showText == showText &&
      other.quietZone == quietZone &&
      other.eccLevel == eccLevel;

  @override
  int get hashCode => Object.hash(id, bounds, symbology, data, dataField, color,
      showText, quietZone, eccLevel);

  @override
  String toString() => 'BarcodeElement($id, ${symbology.name})';
}
