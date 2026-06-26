/// Human-readable display names for [BarcodeSymbology] values, used by the
/// designer's Symbology dropdown so the picker reads "GS1-128 (EAN-128)" rather
/// than the raw enum name `gs128`.
///
/// The switch is exhaustive (no `default`): adding a new symbology to the enum
/// is a compile error here until its label is declared — so the picker can
/// never silently fall back to a raw enum name.
library;

import '../../../domain/elements/barcode_element.dart';

/// The friendly label for [symbology]. [BarcodeSymbology.auto] returns a plain
/// 'Automatic'; the panel overrides it with the localized string, but a label
/// is provided here so every enum value is covered.
String barcodeSymbologyLabel(BarcodeSymbology symbology) {
  switch (symbology) {
    case BarcodeSymbology.auto:
      return 'Automatic';
    case BarcodeSymbology.qrCode:
      return 'QR Code';
    case BarcodeSymbology.code128:
      return 'Code 128';
    case BarcodeSymbology.ean13:
      return 'EAN-13';
    case BarcodeSymbology.ean8:
      return 'EAN-8';
    case BarcodeSymbology.upcA:
      return 'UPC-A';
    case BarcodeSymbology.code39:
      return 'Code 39';
    case BarcodeSymbology.itf14:
      return 'ITF-14';
    case BarcodeSymbology.code93:
      return 'Code 93';
    case BarcodeSymbology.codabar:
      return 'Codabar';
    case BarcodeSymbology.itf:
      return 'Interleaved 2 of 5';
    case BarcodeSymbology.gs128:
      return 'GS1-128 (EAN-128)';
    case BarcodeSymbology.upcE:
      return 'UPC-E';
    case BarcodeSymbology.ean2:
      return 'EAN-2 (supplement)';
    case BarcodeSymbology.ean5:
      return 'EAN-5 (supplement)';
    case BarcodeSymbology.postnet:
      return 'POSTNET';
    case BarcodeSymbology.itf16:
      return 'ITF-16';
    case BarcodeSymbology.isbn:
      return 'ISBN';
    case BarcodeSymbology.telepen:
      return 'Telepen';
    case BarcodeSymbology.rm4scc:
      return 'RM4SCC (Royal Mail)';
    case BarcodeSymbology.dataMatrix:
      return 'Data Matrix';
    case BarcodeSymbology.pdf417:
      return 'PDF417';
    case BarcodeSymbology.aztec:
      return 'Aztec';
  }
}
