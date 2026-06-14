/// The command that resizes a single element (FR-009).
library;

import '../../../domain/geometry.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../element_bounds.dart';

/// Sets the (already clamped, min-size-enforced) [bounds] of element [id].
///
/// Like [MoveCommand], the controller computes the final clamped bounds up front
/// and bakes them in, so redo reproduces the exact size/position.
class ResizeCommand extends EditCommand {
  /// Creates a resize of [id] to band-relative [bounds].
  const ResizeCommand({required this.id, required this.bounds});

  /// The element being resized.
  final String id;

  /// The target band-relative bounds.
  final JetRect bounds;

  @override
  String get label => 'Resize';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        replaceElementBoundsInDef(
            before.definition, <String, JetRect>{id: bounds}),
      );
}
