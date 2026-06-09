/// The command that changes a band's designed height (vertical band resize).
library;

import '../../../domain/report_band.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Sets the (already floor-clamped) [height] of the band at [bandIndex].
///
/// A band only has a height in the model (its width/position are derived by the
/// design/layout from the page format), so a band resize is a single-field
/// change. The controller computes the final height up front and bakes it in, so
/// redo reproduces it exactly. The resized band is left selected.
class SetBandHeightCommand extends EditCommand {
  /// Creates a height change of the band at [bandIndex] to [height] points.
  const SetBandHeightCommand({required this.bandIndex, required this.height});

  /// The band being resized.
  final int bandIndex;

  /// The target height, in points.
  final double height;

  @override
  String get label => 'Resize band';

  @override
  DesignerDocument apply(DesignerDocument before) {
    if (bandIndex < 0 || bandIndex >= before.template.bands.length) {
      return before;
    }
    final List<ReportBand> bands = List<ReportBand>.of(before.template.bands);
    bands[bandIndex] = bands[bandIndex].copyWith(height: height);
    return before.withTemplate(
      before.template.copyWith(bands: bands),
      selection: Selection.band(bandIndex),
    );
  }
}
