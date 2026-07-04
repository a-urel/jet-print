/// The command that recolors a barcode element (021 / US3 / FR-011).
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/styles/color.dart';
import '../element_edit_command.dart';

/// Replaces the [BarcodeElement] [id]'s foreground [color] in one undoable
/// step, preserving its symbology, data, and bounds.
///
/// **No-op** when the element already carries an equal color (value-equal
/// definition → no history, FR-013). Also a no-op for a non-barcode or
/// absent [id].
class SetBarcodeColorCommand extends ElementEditCommand<BarcodeElement> {
  /// Creates a recolor of the barcode element [id] to [color].
  const SetBarcodeColorCommand({required String id, required this.color})
      : super(id);

  /// The foreground (bar) color to apply.
  final JetColor color;

  @override
  String get label => 'Edit barcode color';

  @override
  BarcodeElement edit(BarcodeElement element) => element.copyWith(color: color);
}
