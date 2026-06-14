/// The command that removes the selected elements (FR-014).
library;

import '../../../domain/band.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Removes every element whose id is in [ids] from its band, clearing the
/// selection. Bands that lose nothing are value-equal (so the whole definition
/// is unchanged when [ids] matches nothing — no history entry).
class DeleteCommand extends EditCommand {
  /// Creates a delete of [ids].
  const DeleteCommand(this.ids);

  /// The element ids to remove.
  final Set<String> ids;

  @override
  String get label => 'Delete';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        mapBands(
          before.definition,
          (Band band) =>
              band.elements.any((ReportElement e) => ids.contains(e.id))
                  ? band.copyWith(elements: <ReportElement>[
                      for (final ReportElement e in band.elements)
                        if (!ids.contains(e.id)) e,
                    ])
                  : band,
        ),
        selection: Selection.empty,
      );
}
