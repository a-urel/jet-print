/// The command that restyles a shape element.
library;

import '../../../domain/elements/shape_element.dart';
import '../../../domain/styles/box_style.dart';
import '../element_edit_command.dart';

/// Replaces the [ShapeElement] [id]'s whole style with [style] in one
/// undoable step, preserving its kind, bounds, and flip state.
///
/// **No-op** when the element already carries an equal style (value-equal
/// definition → no history). Also a no-op for a non-shape or absent
/// [id].
class SetShapeStyleCommand extends ElementEditCommand<ShapeElement> {
  /// Creates a restyle of the shape element [id] to [style].
  const SetShapeStyleCommand({required String id, required this.style})
      : super(id);

  /// The style to apply (whole-value replacement; editors build it with
  /// [JetBoxStyle.copyWith], whose explicit-null fill/stroke expresses the
  /// None states).
  final JetBoxStyle style;

  @override
  String get label => 'Edit shape style';

  @override
  ShapeElement edit(ShapeElement element) => element.copyWith(style: style);
}
