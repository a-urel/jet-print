// Barcode element property commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlBarcode on JetReportDesignerController {
  /// Replaces the barcode element [id]'s foreground color with [color] as
  /// one undoable step (021 / FR-011), preserving its symbology, data, and
  /// bounds.
  void setBarcodeColor(String id, JetColor color) =>
      _commit(SetBarcodeColorCommand(id: id, color: color));
  /// Changes the barcode [id]'s symbology.
  void setBarcodeSymbology(String id, BarcodeSymbology symbology) =>
      _commit(SetBarcodeSymbologyCommand(id: id, symbology: symbology));
  /// Sets the barcode [id]'s literal data (clears any bound field).
  void setBarcodeData(String id, String data) =>
      _commit(SetBarcodeDataCommand(id: id, data: data));
  /// Binds the barcode [id]'s value to [field] (null clears the binding).
  void setBarcodeDataField(String id, String? field) =>
      _commit(SetBarcodeDataFieldCommand(id: id, field: field));
  /// Sets the barcode [id]'s data from a value-field [raw] string: a bare
  /// `[field]` token binds the value to that field (keeping the prior literal as
  /// a fallback); any other text is a literal (and clears the binding). Mirrors
  /// [setValue]'s single-input UX, but barcode is field-or-literal — no
  /// expressions (spec 036). One undoable step.
  void setBarcodeValue(String id, String raw) {
    final String? field = parseFieldToken(raw);
    if (field != null) {
      _commit(SetBarcodeDataFieldCommand(id: id, field: field));
    } else {
      _commit(SetBarcodeDataCommand(id: id, data: raw));
    }
  }
  /// Toggles HRI text under the barcode [id].
  void setBarcodeShowText(String id, bool value) =>
      _commit(SetBarcodeOptionsCommand(id: id, showText: value));
  /// Toggles the quiet zone of the barcode [id].
  void setBarcodeQuietZone(String id, bool value) =>
      _commit(SetBarcodeOptionsCommand(id: id, quietZone: value));
  /// Sets the QR error-correction level of the barcode [id].
  void setBarcodeEccLevel(String id, QrErrorCorrectionLevel level) =>
      _commit(SetBarcodeOptionsCommand(id: id, eccLevel: level));
}
