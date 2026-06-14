/// The command that restyles a shape element (021 / US2 / FR-007, FR-008).
library;

import '../../../domain/elements/shape_element.dart';
import '../../../domain/report_element.dart';
import '../../../domain/styles/box_style.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Replaces the [ShapeElement] [id]'s whole style with [style] in one
/// undoable step, preserving its kind, bounds, and flip state.
///
/// **No-op** when the element already carries an equal style (value-equal
/// definition → no history, FR-013). Also a no-op for a non-shape or absent
/// [id].
class SetShapeStyleCommand extends EditCommand {
  /// Creates a restyle of the shape element [id] to [style].
  const SetShapeStyleCommand({required this.id, required this.style});

  /// The target shape element.
  final String id;

  /// The style to apply (whole-value replacement; editors build it with
  /// [JetBoxStyle.copyWith], whose explicit-null fill/stroke expresses the
  /// None states).
  final JetBoxStyle style;

  @override
  String get label => 'Edit shape style';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
          before.definition,
          id,
          (ReportElement e) => e is ShapeElement ? e.copyWith(style: style) : e,
        ),
      );
}
