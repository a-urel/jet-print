/// The command that changes a band's designed height (vertical band resize).
library;

import '../../../domain/band.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Sets the (already floor-clamped) [height] of the band with stable id
/// [bandId].
///
/// A band only has a height in the model (its width/position are derived by the
/// design/layout from the page format), so a band resize is a single-field
/// change. The controller computes the final height up front and bakes it in, so
/// redo reproduces it exactly. The resized band is left selected. A no-op for an
/// unknown [bandId].
class SetBandHeightCommand extends EditCommand {
  /// Creates a height change of band [bandId] to [height] points.
  const SetBandHeightCommand({required this.bandId, required this.height});

  /// The stable id of the band being resized.
  final String bandId;

  /// The target height, in points.
  final double height;

  @override
  String get label => 'Resize band';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateBand(
            before.definition, bandId, (Band b) => b.copyWith(height: height)),
        selection: Selection.band(bandId),
      );
}
