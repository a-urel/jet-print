/// The first-party barcode encoder seam (spec 036, FR-011). Implementations map
/// a symbology + value to [BarcodeSymbol] geometry or a [BarcodeInvalid] reason;
/// only the package adapter imports the third-party encoder.
library;

import '../../../domain/elements/barcode_element.dart';
import 'barcode_symbol.dart';

/// The outcome of an encode attempt.
sealed class BarcodeEncodeResult {
  /// Const base constructor.
  const BarcodeEncodeResult();
}

/// A successful encode: the [symbol] geometry and the [resolvedSymbology]
/// (the concrete symbology used, after `auto` inference).
final class BarcodeEncoded extends BarcodeEncodeResult {
  /// Creates a success result.
  const BarcodeEncoded(this.symbol, this.resolvedSymbology);

  /// The positioned geometry.
  final BarcodeSymbol symbol;

  /// The concrete symbology actually encoded.
  final BarcodeSymbology resolvedSymbology;
}

/// A failed encode (invalid data for the symbology, after auto-fix).
final class BarcodeInvalid extends BarcodeEncodeResult {
  /// Creates an invalid result with a human-readable [reason].
  const BarcodeInvalid(this.reason);

  /// Why the value could not be encoded.
  final String reason;
}

/// Encodes a barcode value into [BarcodeSymbol] geometry within a [width] x
/// [height] coordinate space.
abstract interface class BarcodeEncoder {
  /// Encodes [value] as [symbology] (resolving `auto`), laying out into a
  /// [width] x [height] space. Draws HRI text when [showText] and the symbology
  /// is 1D. [eccLevel] applies only to QR.
  BarcodeEncodeResult encode(
    BarcodeSymbology symbology,
    String value, {
    required double width,
    required double height,
    bool showText = true,
    QrErrorCorrectionLevel eccLevel = QrErrorCorrectionLevel.m,
  });
}
