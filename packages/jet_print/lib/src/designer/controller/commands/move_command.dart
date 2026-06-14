/// The command that repositions one or more elements (FR-008/010).
library;

import '../../../domain/geometry.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../element_bounds.dart';

/// Sets the (already band-clamped) bounds of the elements named in [newBounds].
///
/// The controller computes the clamped target bounds for the whole selection up
/// front and bakes them into the command, so redo reproduces the exact same
/// positions. Multi-element by construction — moving a selection is one command,
/// hence one undo step (FR-017).
class MoveCommand extends EditCommand {
  /// Creates a move to the band-relative, clamped [newBounds] (keyed by id).
  const MoveCommand(this.newBounds);

  /// Target band-relative bounds per element id.
  final Map<String, JetRect> newBounds;

  @override
  String get label => 'Move';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        replaceElementBoundsInDef(before.definition, newBounds),
      );
}
