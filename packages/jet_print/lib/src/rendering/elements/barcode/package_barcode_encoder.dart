/// The sole adapter onto the third-party `barcode` package (spec 036, FR-011).
/// THIS IS THE ONLY FILE IN THE LIBRARY THAT MAY IMPORT `package:barcode`.
/// `BarcodeException` is caught here and never escapes the seam.
library;

import 'package:barcode/barcode.dart' as bc;

import '../../../domain/elements/barcode_element.dart';
import 'barcode_autofix.dart';
import 'barcode_encoder.dart';
import 'barcode_symbol.dart';
import 'symbology_inference.dart';

/// Encodes barcodes via the `barcode` package, translating its positioned
/// elements into first-party [BarcodeSymbol] geometry.
class PackageBarcodeEncoder implements BarcodeEncoder {
  /// Const constructor (stateless).
  const PackageBarcodeEncoder();

  @override
  BarcodeEncodeResult encode(
    BarcodeSymbology symbology,
    String value, {
    required double width,
    required double height,
    bool showText = true,
    QrErrorCorrectionLevel eccLevel = QrErrorCorrectionLevel.m,
  }) {
    final BarcodeSymbology concrete =
        resolveConcreteSymbology(symbology, value);
    final bool twoD = isTwoDSymbology(concrete);
    final String fixed = barcodeAutoFix(concrete, value);
    final bc.Barcode encoder = _encoderFor(concrete, eccLevel);

    if (!encoder.isValid(fixed)) {
      return BarcodeInvalid('Value "$value" is not valid for ${concrete.name}');
    }

    // 2D codes are laid out in a square so modules stay square; 1D uses the
    // full space and draws HRI text when requested.
    final double w = twoD ? (width < height ? width : height) : width;
    final double h = twoD ? w : height;
    final bool drawText = showText && !twoD;

    // When drawing text on 1D codes, the barcode package requires a non-null
    // fontHeight (assertion in Barcode1D.makeBytes). Use the same 20%-of-height
    // default that the package's own toSvg() uses.
    final double? fontHeight = drawText ? h * 0.2 : null;

    final List<BarcodeModule> modules = <BarcodeModule>[];
    final List<BarcodeHriText> texts = <BarcodeHriText>[];
    try {
      for (final bc.BarcodeElement e in encoder.make(
        fixed,
        width: w,
        height: h,
        drawText: drawText,
        fontHeight: fontHeight,
      )) {
        if (e is bc.BarcodeBar) {
          if (e.black) {
            // Emit each bar as a single rectangle — for both 1D and 2D.
            // 2D bars are run-length-encoded horizontal spans (consecutive
            // same-row black modules merged by the package); emitting them raw
            // is lossless because the renderer fills rectangles. Grid squareness
            // for 2D comes from the square coordinate space (w == h above), not
            // from subdividing spans. Splitting spans was wrong for PDF417,
            // whose modules are non-square (pixelH ≈ 2×pixelW), causing module
            // widths ~2× too large and an unscannable pattern.
            modules.add(BarcodeModule(e.left, e.top, e.width, e.height));
          }
        } else if (e is bc.BarcodeText) {
          texts.add(BarcodeHriText(
            left: e.left,
            top: e.top,
            width: e.width,
            height: e.height,
            text: e.text,
            align: _align(e.align),
          ));
        }
      }
    } on bc.BarcodeException catch (ex) {
      return BarcodeInvalid('${concrete.name}: ${ex.message}');
    }

    return BarcodeEncoded(
      BarcodeSymbol(
        modules: modules,
        texts: texts,
        spaceWidth: w,
        spaceHeight: h,
        isTwoD: twoD,
      ),
      concrete,
    );
  }

  bc.Barcode _encoderFor(BarcodeSymbology s, QrErrorCorrectionLevel ecc) {
    switch (s) {
      case BarcodeSymbology.qrCode:
        return bc.Barcode.qrCode(errorCorrectLevel: _ecc(ecc));
      case BarcodeSymbology.code128:
        return bc.Barcode.code128();
      case BarcodeSymbology.code39:
        return bc.Barcode.code39();
      case BarcodeSymbology.ean13:
        return bc.Barcode.ean13();
      case BarcodeSymbology.ean8:
        return bc.Barcode.ean8();
      case BarcodeSymbology.upcA:
        return bc.Barcode.upcA();
      case BarcodeSymbology.itf14:
        return bc.Barcode.itf14();
      case BarcodeSymbology.code93:
        return bc.Barcode.code93();
      case BarcodeSymbology.codabar:
        return bc.Barcode.codabar();
      case BarcodeSymbology.itf:
        return bc.Barcode.itf();
      case BarcodeSymbology.gs128:
        return bc.Barcode.gs128();
      case BarcodeSymbology.upcE:
        return bc.Barcode.upcE();
      case BarcodeSymbology.ean2:
        return bc.Barcode.ean2();
      case BarcodeSymbology.ean5:
        return bc.Barcode.ean5();
      case BarcodeSymbology.postnet:
        return bc.Barcode.postnet();
      case BarcodeSymbology.itf16:
        return bc.Barcode.itf16();
      case BarcodeSymbology.isbn:
        return bc.Barcode.isbn();
      case BarcodeSymbology.telepen:
        return bc.Barcode.telepen();
      case BarcodeSymbology.rm4scc:
        return bc.Barcode.rm4scc();
      case BarcodeSymbology.dataMatrix:
        return bc.Barcode.dataMatrix();
      case BarcodeSymbology.pdf417:
        return bc.Barcode.pdf417();
      case BarcodeSymbology.aztec:
        return bc.Barcode.aztec();
      case BarcodeSymbology.auto:
        // resolveConcreteSymbology never returns auto; defensive fallback.
        return bc.Barcode.qrCode(errorCorrectLevel: _ecc(ecc));
    }
  }

  bc.BarcodeQRCorrectionLevel _ecc(QrErrorCorrectionLevel l) {
    switch (l) {
      case QrErrorCorrectionLevel.l:
        return bc.BarcodeQRCorrectionLevel.low;
      case QrErrorCorrectionLevel.m:
        return bc.BarcodeQRCorrectionLevel.medium;
      case QrErrorCorrectionLevel.q:
        return bc.BarcodeQRCorrectionLevel.quartile;
      case QrErrorCorrectionLevel.h:
        return bc.BarcodeQRCorrectionLevel.high;
    }
  }

  BarcodeHriAlign _align(bc.BarcodeTextAlign a) {
    switch (a) {
      case bc.BarcodeTextAlign.left:
        return BarcodeHriAlign.left;
      case bc.BarcodeTextAlign.center:
        return BarcodeHriAlign.center;
      case bc.BarcodeTextAlign.right:
        return BarcodeHriAlign.right;
    }
  }
}
