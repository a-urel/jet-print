/// Command: change a barcode element's symbology (spec 036).
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Replaces the [BarcodeElement] [id]'s [symbology] in one undoable step.
class SetBarcodeSymbologyCommand extends EditCommand {
  /// Creates the command.
  const SetBarcodeSymbologyCommand({required this.id, required this.symbology});

  /// Target element id.
  final String id;

  /// New symbology.
  final BarcodeSymbology symbology;

  @override
  String get label => 'Edit barcode symbology';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
            before.definition,
            id,
            (ReportElement e) =>
                e is BarcodeElement ? e.copyWith(symbology: symbology) : e),
      );
}
