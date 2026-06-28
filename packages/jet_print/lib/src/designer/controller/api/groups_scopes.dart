// Group and detail-scope commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlGroupsScopes on JetReportDesignerController {
  /// Adds a new group level (named [name], keyed by [key]) to scope [scopeId] and
  /// selects it, as one undoable step. The new group gets a fresh unique id.
  void createGroup(String scopeId,
      {required String name, required String key}) {
    _commit(CreateGroupCommand(
      scopeId: scopeId,
      group: GroupLevel(id: _ids.next('group'), name: name, key: key),
    ));
  }

  /// Creates a group level on scope [scopeId] keyed to scalar field [fieldName]
  /// (`$F{fieldName}`) and named after it, together with its header band, and
  /// selects the header band — as ONE undoable step. The data-bound creation
  /// path: every authored group is born resolvable against the data source
  /// (spec 026), replacing the placeholder-key path. A no-op for an unknown
  /// scope or a blank [fieldName].
  void createGroupBoundToField(String scopeId, String fieldName) {
    if (fieldName.trim().isEmpty) return;
    if (findScope(_document.definition, scopeId) == null) return;
    final String groupId = _ids.next('group');
    final Band header = Band(
        id: _ids.next('band'),
        type: BandType.groupHeader,
        height: _defaultBandHeight(BandType.groupHeader));
    final GroupLevel group = GroupLevel(
      id: groupId,
      name: fieldName,
      key: '\$F{$fieldName}',
      header: header,
    );
    _commit(DefinitionEditCommand(
      label: 'Add group',
      transform: (ReportDefinition d) => addGroup(d, scopeId, group),
      selection: Selection.band(header.id),
    ));
  }

  /// Removes the group [groupId] (and its header/footer bands) as one undoable
  /// step, clearing the selection.
  void deleteGroup(String groupId) => _commit(DeleteGroupCommand(groupId));

  /// Sets group [groupId]'s grouping [key] expression as one undoable step.
  void setGroupKey(String groupId, String key) => _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set group key',
        update: (GroupLevel g) => g.copyWith(key: key),
      ));

  /// Renames group [groupId] (a display label only; groups are referenced by
  /// id, not name) as one undoable step. A no-op for an unknown group or an
  /// unchanged name.
  void setGroupName(String groupId, String name) => _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set group name',
        update: (GroupLevel g) => g.copyWith(name: name),
      ));

  /// Sets group [groupId]'s `keepTogether` flag as one undoable step.
  void setGroupKeepTogether(String groupId, bool value) =>
      _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set keep together',
        update: (GroupLevel g) => g.copyWith(keepTogether: value),
      ));

  /// Sets group [groupId]'s `reprintHeaderOnEachPage` flag as one undoable step.
  void setGroupReprintHeader(String groupId, bool value) =>
      _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set reprint header',
        update: (GroupLevel g) => g.copyWith(reprintHeaderOnEachPage: value),
      ));

  /// Sets group [groupId]'s `startNewPage` flag — start each instance after the
  /// first on a fresh page — as one undoable step (the 023 feature, now owned by
  /// the group). A no-op (no history) for an unknown group or an unchanged value.
  void setGroupStartNewPage(String groupId, bool value) =>
      _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set group page break',
        update: (GroupLevel g) => g.copyWith(startNewPage: value),
      ));

  /// Adds a nested detail scope iterating [collectionField] under parent scope
  /// [parentScopeId] and selects it, as one undoable step. The new scope gets a
  /// fresh unique id.
  void createScope(String parentScopeId, {String? collectionField}) {
    _commit(CreateScopeCommand(
      parentScopeId: parentScopeId,
      scope:
          DetailScope(id: _ids.next('scope'), collectionField: collectionField),
    ));
  }

  /// Creates a nested list (scope) iterating [collectionField] under
  /// [parentScopeId], pre-populated with one empty detail band, and selects that
  /// band — as ONE undoable step. The data-first entry point used by a Data
  /// Source collection drop/＋ and the Outline "Add list" action to build a
  /// master/detail. A no-op for an unknown parent scope.
  void createListWithBand(String parentScopeId, {String? collectionField}) {
    if (findScope(_document.definition, parentScopeId) == null) return;
    final Band band = Band(
        id: _ids.next('band'),
        type: BandType.detail,
        height: _defaultBandHeight(BandType.detail));
    final DetailScope scope = DetailScope(
      id: _ids.next('scope'),
      collectionField: collectionField,
      children: <ScopeNode>[BandNode(band)],
    );
    _commit(DefinitionEditCommand(
      label: 'Add list',
      transform: (ReportDefinition d) =>
          addScopeChild(d, parentScopeId, NestedScope(scope)),
      selection: Selection.band(band.id),
    ));
  }

  /// Removes the nested scope [scopeId] (and everything it contains) as one
  /// undoable step, clearing the selection.
  void deleteScope(String scopeId) => _commit(DeleteScopeCommand(scopeId));

  /// Sets (or clears, when null) the nested [collectionField] scope [scopeId]
  /// iterates, as one undoable step (US3 / FR-015, FR-015a).
  void setScopeCollection(String scopeId, String? collectionField) => _commit(
        SetScopeCollectionCommand(
            scopeId: scopeId, collectionField: collectionField),
      );

  // --- Band lifecycle (add / remove / reorder / retype — spec 024 / US3) ------
}
