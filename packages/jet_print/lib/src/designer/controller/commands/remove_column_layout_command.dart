/// The command that clears a band's multi-column label layout.
library;

import '../../../domain/band.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Clears the column layout of band [bandId], turning a label sheet back into a
/// plain detail band. Every other field is carried by [Band.copyWith]. A no-op
/// for an unknown [bandId] or a band that already has no layout (the copy is
/// value-equal, so commit no-ops).
class RemoveColumnLayoutCommand extends EditCommand {
  /// Creates a command clearing band [bandId]'s column layout.
  const RemoveColumnLayoutCommand({required this.bandId});

  /// The stable id of the band whose layout is cleared.
  final String bandId;

  @override
  String get label => 'Remove column layout';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateBand(
          before.definition,
          bandId,
          (Band b) => b.copyWith(columnLayout: () => null),
        ),
        selection: Selection.band(bandId),
      );
}
