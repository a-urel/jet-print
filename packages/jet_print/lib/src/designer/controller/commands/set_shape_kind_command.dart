/// The command that changes a shape element's form.
library;

import '../../../domain/elements/shape_element.dart';
import '../element_edit_command.dart';

/// Sets the [ShapeElement] [id]'s form to [kind] in one undoable step,
/// preserving its bounds and style.
///
/// * **No-op** when the element is already that form *and* carries no preserved
///   [ShapeElement.unknownForm]: the rebuilt element is value-equal, so the
///   controller's commit records no history and notifies no listener. A
///   shape rendered as a rectangle only because its serialized form was
///   unrecognized is therefore *not* a no-op when rectangle is picked — the pick
///   clears the preserved form, changing the element.
/// * Switching **away from** [ShapeKind.line] resets the line-only
///   [ShapeElement.flipDiagonal] to false; staying on/returning to a line keeps it.
/// * Any deliberate pick clears [ShapeElement.unknownForm].
///
/// A no-op for a non-shape or absent [id].
class SetShapeKindCommand extends ElementEditCommand<ShapeElement> {
  /// Creates a pick of [kind] for the shape [id].
  const SetShapeKindCommand({required String id, required this.kind})
      : super(id);

  /// The form to switch to.
  final ShapeKind kind;

  @override
  String get label => 'Set shape';

  @override
  ShapeElement edit(ShapeElement element) => element.copyWith(
        kind: kind,
        flipDiagonal: kind == ShapeKind.line ? element.flipDiagonal : false,
        clearUnknownForm: true,
      );
}
