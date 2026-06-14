/// The command that inserts pasted/duplicated element copies (FR-015).
library;

import '../../../domain/band.dart';
import '../../../domain/report_definition.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../clipboard.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Inserts pre-built copies (fresh ids + paste offset already applied by the
/// controller) into their bands (by stable id) and selects them. Used by paste
/// and duplicate. A copy whose band no longer exists is skipped.
class ClipboardCommand extends EditCommand {
  /// Creates an insert of [copies] (each carrying its target band id).
  const ClipboardCommand(this.copies);

  /// The copies to insert, each with its destination band id.
  final List<ClipboardEntry> copies;

  @override
  String get label => 'Paste';

  @override
  DesignerDocument apply(DesignerDocument before) {
    if (copies.isEmpty) return before;
    ReportDefinition def = before.definition;
    for (final ClipboardEntry copy in copies) {
      def = updateBand(
        def,
        copy.bandId,
        (Band b) =>
            b.copyWith(elements: <ReportElement>[...b.elements, copy.element]),
      );
    }
    return before.withDefinition(
      def,
      selection: Selection.of(<String>[
        for (final ClipboardEntry c in copies) c.element.id,
      ]),
    );
  }
}
