/// Command: change a barcode element's symbology.
library;

import '../../../domain/elements/barcode_element.dart';
import '../element_edit_command.dart';

/// Replaces the [BarcodeElement] [id]'s [symbology] in one undoable step.
class SetBarcodeSymbologyCommand extends ElementEditCommand<BarcodeElement> {
  /// Creates the command.
  const SetBarcodeSymbologyCommand(
      {required String id, required this.symbology})
      : super(id);

  /// New symbology.
  final BarcodeSymbology symbology;

  @override
  String get label => 'Edit barcode symbology';

  @override
  BarcodeElement edit(BarcodeElement element) =>
      element.copyWith(symbology: symbology);
}
