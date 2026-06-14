/// Group-level lifecycle + property commands (spec 024 / T031 / FR-015).
///
/// A [GroupLevel] is now a first-class, addressable entity that *owns* its key,
/// header/footer bands, and pagination flags — so creating, deleting, or editing
/// a group is a single undoable step, and a flag has exactly one home (the 023
/// "same flag on both header and footer band" smell is gone).
library;

import '../../../domain/group_level.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Appends [group] to scope [scopeId]'s group levels and selects it.
class CreateGroupCommand extends EditCommand {
  /// Creates an add of [group] to scope [scopeId].
  const CreateGroupCommand({required this.scopeId, required this.group});

  /// The stable id of the scope receiving the group.
  final String scopeId;

  /// The new group level (id, name, key already assigned by the controller).
  final GroupLevel group;

  @override
  String get label => 'Add group';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        addGroup(before.definition, scopeId, group),
        selection: Selection.group(group.id),
      );
}

/// Removes the group level [groupId] and clears the selection.
class DeleteGroupCommand extends EditCommand {
  /// Creates a delete of group [groupId].
  const DeleteGroupCommand(this.groupId);

  /// The stable id of the group to remove.
  final String groupId;

  @override
  String get label => 'Delete group';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        removeGroup(before.definition, groupId),
        selection: Selection.empty,
      );
}

/// Edits group [groupId]'s key or one flag via [update] as one undoable step —
/// the single command behind every per-group inspector edit (key +
/// keepTogether + reprintHeaderOnEachPage + startNewPage), so each is exactly
/// one history entry (FR-015). A no-op for an unknown group, or when [update]
/// leaves the group value-equal. The selection is left as-is (the group is
/// already selected when its inspector is shown).
class UpdateGroupCommand extends EditCommand {
  /// Creates a group edit labelled [label] applying [update] to [groupId].
  UpdateGroupCommand({
    required this.groupId,
    required this.label,
    required this.update,
  });

  /// The stable id of the group to edit.
  final String groupId;

  @override
  final String label;

  /// The pure transform applied to the matched group.
  final GroupLevel Function(GroupLevel) update;

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateGroup(before.definition, groupId, update),
      );
}
