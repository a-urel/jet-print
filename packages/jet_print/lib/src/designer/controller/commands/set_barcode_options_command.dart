/// Command: toggle a barcode element's rendering options (spec 036).
library;

import '../../../domain/elements/barcode_element.dart';
import '../element_edit_command.dart';

/// Updates any of [showText]/[quietZone]/[eccLevel] (omitted = unchanged).
class SetBarcodeOptionsCommand extends ElementEditCommand<BarcodeElement> {
  /// Creates the command.
  const SetBarcodeOptionsCommand({
    required String id,
    this.showText,
    this.quietZone,
    this.eccLevel,
  }) : super(id);

  /// New HRI-text flag, or null.
  final bool? showText;

  /// New quiet-zone flag, or null.
  final bool? quietZone;

  /// New QR ECC level, or null.
  final QrErrorCorrectionLevel? eccLevel;

  @override
  String get label => 'Edit barcode options';

  @override
  BarcodeElement edit(BarcodeElement element) => element.copyWith(
      showText: showText, quietZone: quietZone, eccLevel: eccLevel);
}
