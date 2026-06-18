/// Command: toggle a barcode element's rendering options (spec 036).
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Updates any of [showText]/[quietZone]/[eccLevel] (omitted = unchanged).
class SetBarcodeOptionsCommand extends EditCommand {
  /// Creates the command.
  const SetBarcodeOptionsCommand({
    required this.id,
    this.showText,
    this.quietZone,
    this.eccLevel,
  });

  /// Target element id.
  final String id;

  /// New HRI-text flag, or null.
  final bool? showText;

  /// New quiet-zone flag, or null.
  final bool? quietZone;

  /// New QR ECC level, or null.
  final QrErrorCorrectionLevel? eccLevel;

  @override
  String get label => 'Edit barcode options';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
            before.definition,
            id,
            (ReportElement e) => e is BarcodeElement
                ? e.copyWith(
                    showText: showText,
                    quietZone: quietZone,
                    eccLevel: eccLevel)
                : e),
      );
}
