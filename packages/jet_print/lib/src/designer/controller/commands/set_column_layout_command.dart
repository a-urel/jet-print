/// The command that sets (or replaces) a band's multi-column label layout
/// (spec 035).
library;

import '../../../domain/band.dart';
import '../../../domain/column_layout.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Sets the [ColumnLayout] of the band with stable id [bandId].
///
/// A single-field change on the band, mirroring `SetBandHeightCommand`: the
/// controller bakes in the exact layout so redo reproduces it, and leaves the
/// band selected. A no-op for an unknown [bandId] (the band-walker transform
/// matches nothing) or a value-equal layout (the controller's commit treats an
/// unchanged definition as a no-op).
class SetColumnLayoutCommand extends EditCommand {
  /// Creates a command setting band [bandId]'s [layout].
  const SetColumnLayoutCommand({required this.bandId, required this.layout});

  /// The stable id of the band carrying the label grid.
  final String bandId;

  /// The new column layout.
  final ColumnLayout layout;

  @override
  String get label => 'Set column layout';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateBand(before.definition, bandId,
            (Band b) => b.copyWith(columnLayout: layout)),
        selection: Selection.band(bandId),
      );
}
