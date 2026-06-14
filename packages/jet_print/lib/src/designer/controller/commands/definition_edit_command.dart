/// A generic, pure definition transform as one undoable edit (spec 024 / US3).
///
/// The band/group/scope lifecycle operations (add / remove / reorder / retype)
/// are each a single `ReportDefinition → ReportDefinition` transform plus a
/// resulting selection. Rather than a near-identical command class per op, they
/// share this one: the controller supplies the [transform] (built from the
/// `band_walker` tree helpers) and the [selection] to leave active. A transform
/// that leaves the definition value-equal records no history (the controller's
/// value-equality commit guard), so an out-of-range or rejected edit is a clean
/// no-op.
library;

import '../../../domain/report_definition.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Applies [transform] to the document's definition as one undoable step,
/// leaving [selection] active (null keeps the current selection).
class DefinitionEditCommand extends EditCommand {
  /// Creates a definition edit labelled [label] applying [transform], optionally
  /// setting [selection] (null preserves the current selection).
  DefinitionEditCommand({
    required this.label,
    required this.transform,
    this.selection,
  });

  @override
  final String label;

  /// The pure definition transform.
  final ReportDefinition Function(ReportDefinition) transform;

  /// The selection to leave active, or null to keep the current one.
  final Selection? selection;

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        transform(before.definition),
        selection: selection,
      );
}
