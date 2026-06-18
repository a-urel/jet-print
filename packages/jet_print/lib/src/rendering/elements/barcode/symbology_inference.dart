/// Pure symbology inference for [BarcodeSymbology.auto] and 1D/2D classification
/// (spec 036, FR-004). No Flutter, no third-party dependency.
library;

import '../../../domain/elements/barcode_element.dart';

/// The longest value still inferred as a 1D code; longer → QR.
const int _maxLinearLength = 40;

/// Infers a concrete symbology from [value] by the documented priority
/// (FR-004). Never returns [BarcodeSymbology.auto].
BarcodeSymbology inferSymbology(String value) {
  final String v = value.trim();
  // URL / multiline / non-ASCII / over-length → 2D QR.
  final bool nonAscii = v.runes.any((int r) => r < 0x20 || r > 0x7e);
  final bool looksUrl =
      v.startsWith('http://') || v.startsWith('https://') || v.contains('://');
  if (looksUrl || nonAscii || v.length > _maxLinearLength) {
    return BarcodeSymbology.qrCode;
  }
  final bool allDigits = v.isNotEmpty && RegExp(r'^\d+$').hasMatch(v);
  if (allDigits) {
    switch (v.length) {
      case 13:
        return BarcodeSymbology.ean13;
      case 12:
        return BarcodeSymbology.upcA;
      case 8:
        return BarcodeSymbology.ean8;
      case 14:
        return BarcodeSymbology.itf14;
      default:
        return BarcodeSymbology.code128;
    }
  }
  // Any remaining (alphanumeric or empty) → Code 128.
  return BarcodeSymbology.code128;
}

/// Resolves [symbology] to a concrete value: [inferSymbology] for `auto`, the
/// value itself otherwise. An empty value with `auto` previews as QR (FR-004).
BarcodeSymbology resolveConcreteSymbology(
    BarcodeSymbology symbology, String value) {
  if (symbology != BarcodeSymbology.auto) return symbology;
  if (value.trim().isEmpty) return BarcodeSymbology.qrCode;
  return inferSymbology(value);
}

/// Whether [s] is a 2D matrix symbology (square modules, no HRI text).
bool isTwoDSymbology(BarcodeSymbology s) =>
    s == BarcodeSymbology.qrCode ||
    s == BarcodeSymbology.dataMatrix ||
    s == BarcodeSymbology.pdf417 ||
    s == BarcodeSymbology.aztec;
