/// The command that inserts pasted/duplicated element copies (FR-015).
library;

import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../clipboard.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Inserts pre-built copies (fresh ids + paste offset already applied by the
/// controller) into their bands and selects them. Used by paste and duplicate.
class ClipboardCommand extends EditCommand {
  /// Creates an insert of [copies] (each carrying its target band index).
  const ClipboardCommand(this.copies);

  /// The copies to insert, each with its destination band index.
  final List<ClipboardEntry> copies;

  @override
  String get label => 'Paste';

  @override
  DesignerDocument apply(DesignerDocument before) {
    if (copies.isEmpty) return before;
    final List<ReportBand> bands = List<ReportBand>.of(before.template.bands);
    for (final ClipboardEntry copy in copies) {
      if (copy.bandIndex < 0 || copy.bandIndex >= bands.length) continue;
      final ReportBand band = bands[copy.bandIndex];
      bands[copy.bandIndex] = band.copyWith(
        elements: <ReportElement>[...band.elements, copy.element],
      );
    }
    return DesignerDocument(
      template: before.template.copyWith(bands: bands),
      selection: Selection.of(<String>[
        for (final ClipboardEntry c in copies) c.element.id,
      ]),
    );
  }
}
