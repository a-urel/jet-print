/// The command that clears a band's multi-column label layout (spec 035).
library;

import '../../../domain/band.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Clears the column layout of band [bandId], turning a label sheet back into a
/// plain detail band.
///
/// `Band.copyWith` cannot null a field (`columnLayout ?? this.columnLayout`), so
/// removal rebuilds the band through its constructor, explicitly carrying every
/// OTHER field (id, type, height, elements, name) and omitting `columnLayout` —
/// the spec-031 silent-drop guard (also applies to `name`, per the same class of
/// latent silent-drop bug). A no-op for an unknown [bandId] or a band that
/// already has no layout (the rebuilt band is value-equal, so commit no-ops).
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
          (Band b) => Band(
            id: b.id,
            type: b.type,
            height: b.height,
            elements: b.elements,
            name: b.name,
          ),
        ),
        selection: Selection.band(bandId),
      );
}
