/// Crosstab lifecycle + property commands (spec B).
///
/// A crosstab is a [ScopeNode] sibling of bands, not an element, so its
/// lifecycle mirrors [CreateScopeCommand] / [DeleteScopeCommand]. Every
/// property edit — name, binding, style, visibility, and each axis-level or
/// measure list change — goes through the single [UpdateCrosstabCommand],
/// which takes the rewrite as a thunk (the shape `UpdateGroupCommand` and
/// `ElementEditCommand` already use) rather than growing one command class per
/// field.
library;

import '../../../domain/crosstab/crosstab.dart';
import '../../../domain/detail_scope.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Appends [crosstab] to scope [parentScopeId]'s children and selects it.
class CreateCrosstabCommand extends EditCommand {
  /// Creates an add of [crosstab] under [parentScopeId].
  const CreateCrosstabCommand(
      {required this.parentScopeId, required this.crosstab});

  /// The stable id of the scope receiving the crosstab.
  final String parentScopeId;

  /// The new crosstab (ids, axes and measures already assigned).
  final Crosstab crosstab;

  @override
  String get label => 'Add crosstab';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        addScopeChild(before.definition, parentScopeId, CrosstabNode(crosstab)),
        selection: Selection.crosstab(crosstab.id),
      );
}

/// Removes the crosstab [crosstabId] and clears the selection.
class DeleteCrosstabCommand extends EditCommand {
  /// Creates a delete of crosstab [crosstabId].
  const DeleteCrosstabCommand(this.crosstabId);

  /// The stable id of the crosstab to remove.
  final String crosstabId;

  @override
  String get label => 'Delete crosstab';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        removeCrosstab(before.definition, crosstabId),
        selection: Selection.empty,
      );
}

/// Rewrites crosstab [crosstabId] through [update], under the history entry
/// [label]. The selection is preserved, so an edit made from the Properties
/// panel leaves the crosstab selected.
///
/// An [update] that returns its argument unchanged leaves the whole definition
/// value-equal, which the controller's commit guard turns into "no history
/// entry" — that is how the axis/measure removal guards refuse without
/// recording a step.
class UpdateCrosstabCommand extends EditCommand {
  /// Creates an update of crosstab [crosstabId].
  const UpdateCrosstabCommand({
    required this.crosstabId,
    required this.label,
    required this.update,
  });

  /// The stable id of the target crosstab.
  final String crosstabId;

  @override
  final String label;

  /// The rewrite applied to the matching crosstab.
  final Crosstab Function(Crosstab) update;

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        mapCrosstabs(before.definition,
            (Crosstab c) => c.id == crosstabId ? update(c) : c),
      );
}
