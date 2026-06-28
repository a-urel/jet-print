// Band structure commands.
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlBands on JetReportDesignerController {
  /// Sets band [bandId]'s height to [height] (floor-clamped) as one undoable
  /// step — the committed form used by numeric editing and tests. An unknown id
  /// is ignored.
  void setBandHeight(String bandId, double height) {
    if (findBand(_document.definition, bandId) == null) return;
    _applyBandHeight(bandId, height);
  }

  /// Sets band [bandId]'s multi-column label [layout] as one undoable step
  /// (spec 035). An unknown id is ignored; a value-equal layout records no
  /// history (routed through `_commit`).
  void setColumnLayout(String bandId, ColumnLayout layout) {
    if (findBand(_document.definition, bandId) == null) return;
    _commit(SetColumnLayoutCommand(bandId: bandId, layout: layout));
  }

  /// Clears band [bandId]'s column layout as one undoable step (spec 035). An
  /// unknown id — or a band that already has no layout — is ignored.
  void removeColumnLayout(String bandId) {
    final Band? band = findBand(_document.definition, bandId);
    if (band == null || band.columnLayout == null) return;
    _commit(RemoveColumnLayoutCommand(bandId: bandId));
  }

  /// Sets the display [name] of the band [bandId] as one undoable step; blank
  /// normalizes to `null` (falling back to the band-type label). No-op when
  /// unchanged.
  void renameBand(String bandId, String? name) =>
      _commit(RenameBandCommand(bandId: bandId, name: _normalizeName(name)));

  /// Sets the [visible] property of band [bandId] (undoable). No-op when equal.
  void setBandVisible(String bandId, BoolProperty visible) =>
      _commit(SetBandVisibleCommand(bandId: bandId, visible: visible));

  /// Adds a band to the singleton slot for [type] (a furniture slot, or a body
  /// title/summary/no-data band) and selects it, as one undoable step. A no-op
  /// for a non-singleton [type] or an already-occupied slot.
  void addBand(BandType type) {
    if (!isSingletonSlotType(type)) return;
    if (bandInSlot(_document.definition, type) != null) return;
    final Band band = Band(
        id: _ids.next('band'), type: type, height: _defaultBandHeight(type));
    _commit(DefinitionEditCommand(
      label: 'Add band',
      transform: (ReportDefinition d) => setSlotBand(d, type, band),
      selection: Selection.band(band.id),
    ));
  }

  /// Appends a per-row detail band to scope [scopeId] and selects it, as one
  /// undoable step. A no-op for an unknown scope.
  void addDetailBand(String scopeId) {
    if (findScope(_document.definition, scopeId) == null) return;
    final Band band = Band(
        id: _ids.next('band'),
        type: BandType.detail,
        height: _defaultBandHeight(BandType.detail));
    _commit(DefinitionEditCommand(
      label: 'Add band',
      transform: (ReportDefinition d) =>
          addScopeChild(d, scopeId, BandNode(band)),
      selection: Selection.band(band.id),
    ));
  }

  /// Adds group [groupId]'s [header] (or footer, when false) band and selects
  /// it, as one undoable step. A no-op for an unknown group or an occupied slot.
  void addGroupBand(String groupId, {required bool header}) {
    final GroupLevel? group = findGroup(_document.definition, groupId);
    if (group == null) return;
    if ((header ? group.header : group.footer) != null) return;
    final BandType type = header ? BandType.groupHeader : BandType.groupFooter;
    final Band band = Band(
        id: _ids.next('band'), type: type, height: _defaultBandHeight(type));
    _commit(DefinitionEditCommand(
      label: 'Add band',
      transform: (ReportDefinition d) =>
          setGroupBand(d, groupId, header: header, band: band),
      selection: Selection.band(band.id),
    ));
  }

  /// Removes the band [bandId] wherever it lives (a furniture slot, a body
  /// once-band, a group header/footer, or a scope per-row band) as one undoable
  /// step, clearing the selection. A no-op for an unknown id.
  void removeBand(String bandId) {
    if (findBand(_document.definition, bandId) == null) return;
    _commit(DefinitionEditCommand(
      label: 'Remove band',
      transform: (ReportDefinition d) => removeBandFromTree(d, bandId),
      selection: Selection.empty,
    ));
  }

  /// Moves the per-row band [bandId] by [delta] positions within its scope's
  /// ordered children (negative = toward the front), as one undoable step,
  /// keeping it selected. A no-op when the band is not a scope per-row band or
  /// the move clamps to its current position.
  void moveBand(String bandId, int delta) {
    final DetailScope? scope = findScopeOfBand(_document.definition, bandId);
    if (scope == null) return;
    // Selection is preserved (not forced), so a clamped move — which leaves the
    // definition value-equal — records no history.
    _commit(DefinitionEditCommand(
      label: 'Reorder band',
      transform: (ReportDefinition d) =>
          reorderScopeChild(d, scope.id, bandId, delta),
    ));
  }

  /// Retypes band [bandId] to [newType], relocating it to that type's slot and
  /// updating its [Band.type] (FR-012 / FR-001a) — id, height, and elements are
  /// preserved. Supported for the singleton-slot types (furniture + body
  /// once-bands); a no-op for a non-singleton target, an occupied target slot,
  /// an unknown id, or an unchanged type. One undoable step; the band stays
  /// selected.
  void retypeBand(String bandId, BandType newType) {
    final Band? band = findBand(_document.definition, bandId);
    if (band == null || band.type == newType) return;
    if (!isSingletonSlotType(newType)) return;
    if (bandInSlot(_document.definition, newType) != null) return;
    final Band relocated = band.copyWith(type: newType);
    _commit(DefinitionEditCommand(
      label: 'Change band type',
      transform: (ReportDefinition d) =>
          setSlotBand(removeBandFromTree(d, bandId), newType, relocated),
      selection: Selection.band(bandId),
    ));
  }
}
