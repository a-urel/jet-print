/// A 1D/2D barcode element.
library;

import '../bool_property.dart';
import '../geometry.dart';
import '../report_element.dart';
import '../styles/color.dart';

/// The barcode symbology (encoding) to render. [auto] infers the concrete
/// symbology from the encoded value at fill time (see `symbology_inference`).
enum BarcodeSymbology {
  /// Infer the concrete symbology from the value (default for new elements).
  ///
  /// Inference resolves only to the common retail/QR set (EAN-13, UPC-A, EAN-8,
  /// ITF-14, Code 128, QR); every other symbology below is explicit-select,
  /// since it overlaps those on length/charset (see `symbology_inference`).
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

  /// 1D Code 93 (alphanumeric, denser than Code 39).
  code93,

  /// 1D Codabar (numeric + a few symbols; pass digits, start/stop added).
  codabar,

  /// 1D Interleaved 2-of-5 (generic; requires an even digit count).
  itf,

  /// 1D GS1-128 / EAN-128 (Code 128 with GS1 Application Identifiers).
  gs128,

  /// 1D UPC-E (compressed UPC; covers UPC-E0 and UPC-E1).
  upcE,

  /// 1D EAN/UPC 2-digit supplemental add-on.
  ean2,

  /// 1D EAN/UPC 5-digit supplemental add-on.
  ean5,

  /// 1D POSTNET (USPS postal routing).
  postnet,

  /// 1D ITF-16 (interleaved 2-of-5, 16-digit logistics variant).
  itf16,

  /// 1D ISBN (bookland EAN-13 with ISBN human-readable text).
  isbn,

  /// 1D Telepen (full-ASCII, common in UK libraries).
  telepen,

  /// 1D RM4SCC (Royal Mail 4-state customer code).
  rm4scc,

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
    this.symbology = BarcodeSymbology.auto,
    required this.data,
    this.dataField,
    this.color = JetColor.black,
    this.showText = true,
    this.quietZone = true,
    this.eccLevel = QrErrorCorrectionLevel.m,
    super.name,
    super.visible,
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
    String? name,
    BoolProperty? visible,
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
        name: name ?? this.name,
        visible: visible ?? this.visible,
      );

  @override
  BarcodeElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  BarcodeElement withName(String? name) => BarcodeElement(
        id: id,
        bounds: bounds,
        symbology: symbology,
        data: data,
        dataField: dataField,
        color: color,
        showText: showText,
        quietZone: quietZone,
        eccLevel: eccLevel,
        name: name,
        visible: visible,
      );

  @override
  BarcodeElement withVisible(BoolProperty visible) => BarcodeElement(
        id: id,
        bounds: bounds,
        symbology: symbology,
        data: data,
        dataField: dataField,
        color: color,
        showText: showText,
        quietZone: quietZone,
        eccLevel: eccLevel,
        name: name,
        visible: visible,
      );

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
      other.eccLevel == eccLevel &&
      other.name == name &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(id, bounds, symbology, data, dataField, color,
      showText, quietZone, eccLevel, name, visible);

  @override
  String toString() => 'BarcodeElement($id, ${symbology.name})';
}
