/// Pure check-digit / length auto-fix for retail symbologies (spec 036, FR-005).
/// Repairs what the spec allows; the encoder still validates the result.
library;

import '../../../domain/elements/barcode_element.dart';

bool _isDigits(String s) => s.isNotEmpty && RegExp(r'^\d+$').hasMatch(s);

/// The UPC/EAN mod-10 check digit for the [digits] *without* its check digit.
/// Weights alternate 3,1 starting from the rightmost given digit.
int mod10CheckDigit(String digits) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    final int d = digits.codeUnitAt(digits.length - 1 - i) - 0x30;
    sum += (i.isEven) ? d * 3 : d;
  }
  return (10 - (sum % 10)) % 10;
}

String _appendCheck(String digits) => '$digits${mod10CheckDigit(digits)}';

/// Repairs [value] for [concrete] where the symbology spec allows; otherwise
/// returns [value] unchanged.
String barcodeAutoFix(BarcodeSymbology concrete, String value) {
  switch (concrete) {
    case BarcodeSymbology.ean13:
      return (_isDigits(value) && value.length == 12)
          ? _appendCheck(value)
          : value;
    case BarcodeSymbology.ean8:
      return (_isDigits(value) && value.length == 7)
          ? _appendCheck(value)
          : value;
    case BarcodeSymbology.upcA:
      return (_isDigits(value) && value.length == 11)
          ? _appendCheck(value)
          : value;
    case BarcodeSymbology.itf14:
      var v = value;
      if (_isDigits(v) && v.length == 13) v = _appendCheck(v);
      // ITF requires an even number of digits; single left-pad is intentional —
      // a still-odd result (e.g. raw odd input) is left to the encoder to reject.
      if (_isDigits(v) && v.length.isOdd) v = '0$v';
      return v;
    case BarcodeSymbology.auto:
    case BarcodeSymbology.qrCode:
    case BarcodeSymbology.code128:
    case BarcodeSymbology.code39:
    case BarcodeSymbology.code93:
    case BarcodeSymbology.codabar:
    case BarcodeSymbology.itf:
    case BarcodeSymbology.gs128:
    case BarcodeSymbology.upcE:
    case BarcodeSymbology.ean2:
    case BarcodeSymbology.ean5:
    case BarcodeSymbology.postnet:
    case BarcodeSymbology.itf16:
    case BarcodeSymbology.isbn:
    case BarcodeSymbology.telepen:
    case BarcodeSymbology.rm4scc:
    case BarcodeSymbology.dataMatrix:
    case BarcodeSymbology.pdf417:
    case BarcodeSymbology.aztec:
      return value;
  }
}
