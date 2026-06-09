/// The command that removes the selected elements (FR-014).
library;

import '../../../domain/report_band.dart';
import '../../../domain/report_element.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Removes every element whose id is in [ids] from its band, clearing the
/// selection. Bands that lose nothing are reused referentially (FR-025).
class DeleteCommand extends EditCommand {
  /// Creates a delete of [ids].
  const DeleteCommand(this.ids);

  /// The element ids to remove.
  final Set<String> ids;

  @override
  String get label => 'Delete';

  @override
  DesignerDocument apply(DesignerDocument before) {
    bool changed = false;
    final List<ReportBand> bands = <ReportBand>[
      for (final ReportBand band in before.template.bands)
        if (band.elements.any((ReportElement e) => ids.contains(e.id)))
          () {
            changed = true;
            return band.copyWith(elements: <ReportElement>[
              for (final ReportElement e in band.elements)
                if (!ids.contains(e.id)) e,
            ]);
          }()
        else
          band,
    ];
    if (!changed) return before;
    return DesignerDocument(
      template: before.template.copyWith(bands: bands),
      selection: Selection.empty,
    );
  }
}
