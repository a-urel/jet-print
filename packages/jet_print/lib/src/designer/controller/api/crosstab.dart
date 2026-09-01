// Crosstab authoring commands (spec B).
//
// A part of `jet_report_designer_controller.dart`:
// command family split out as an extension so it keeps full private
// access to the controller's state with no API change.
part of '../jet_report_designer_controller.dart';

extension CtrlCrosstab on JetReportDesignerController {
  /// Adds a crosstab to scope [scopeId] and selects it, as one undoable step.
  ///
  /// The crosstab is born **valid and bound** (`validate()` requires at least
  /// one row group, one column group and one measure), seeded from [fields] —
  /// the fields of its data source, which the caller resolves from the schema:
  /// the scope's in-scope fields when [collectionField] is null, else that
  /// collection's own child fields. The controller is schema-less by design, so
  /// the resolution happens at the UI seam and only the rule lives here.
  ///
  /// The rule: the first scalar field keys the row axis; the second (or the
  /// first again, when there is only one) keys the column axis; the first
  /// numeric field becomes a `sum` measure, or — when the source has none —
  /// the first scalar becomes a `count` measure, which needs no numeric input.
  /// A no-op for an unknown scope, or a source with no scalar field at all:
  /// there would be nothing to bucket rows by.
  void createCrosstab(
    String scopeId, {
    required List<FieldDef> fields,
    String? collectionField,
  }) {
    if (findScope(_document.definition, scopeId) == null) return;
    final List<FieldDef> scalars = <FieldDef>[
      for (final FieldDef f in fields)
        if (f.type != JetFieldType.collection) f,
    ];
    if (scalars.isEmpty) return;
    final FieldDef rowField = scalars.first;
    final FieldDef columnField =
        scalars.length > 1 ? scalars[1] : scalars.first;
    final FieldDef? numeric = scalars
        .where((FieldDef f) =>
            f.type == JetFieldType.integer || f.type == JetFieldType.double)
        .firstOrNull;
    _commit(CreateCrosstabCommand(
      parentScopeId: scopeId,
      crosstab: Crosstab(
        id: _ids.next('crosstab'),
        collectionField: collectionField,
        rowGroups: <CrosstabGroup>[_seedGroup(rowField)],
        columnGroups: <CrosstabGroup>[_seedGroup(columnField)],
        measures: <CrosstabMeasure>[
          CrosstabMeasure(
            id: _ids.next('ctmeasure'),
            name: (numeric ?? rowField).name,
            expression: '\$F{${(numeric ?? rowField).name}}',
            aggregate:
                numeric == null ? JetCalculation.count : JetCalculation.sum,
          ),
        ],
      ),
    ));
  }

  /// An axis level keyed by [field], named after it — the shape both seeded and
  /// author-added levels share.
  CrosstabGroup _seedGroup(FieldDef field) => CrosstabGroup(
        id: _ids.next('ctgroup'),
        name: field.name,
        expression: '\$F{${field.name}}',
      );

  /// Removes crosstab [crosstabId] as one undoable step, clearing the
  /// selection.
  void deleteCrosstab(String crosstabId) =>
      _commit(DeleteCrosstabCommand(crosstabId));

  /// Moves crosstab [crosstabId] by [delta] positions among its siblings.
  ///
  /// The position is semantic (spec A decision 7): above the first
  /// row-producing sibling the crosstab prints once **before** the row loop,
  /// below it once **after**. Selection is preserved, so a clamped move —
  /// which leaves the definition value-equal — records no history.
  void moveCrosstab(String crosstabId, int delta) {
    final DetailScope? scope =
        findScopeOfCrosstab(_document.definition, crosstabId);
    if (scope == null) return;
    _commit(DefinitionEditCommand(
      label: 'Reorder crosstab',
      transform: (ReportDefinition d) =>
          reorderScopeNode(d, scope.id, crosstabId, delta),
    ));
  }

  /// Renames crosstab [crosstabId] (a display label only; a blank name clears
  /// back to the localized fallback) as one undoable step.
  void renameCrosstab(String crosstabId, String? name) => _updateCrosstab(
      crosstabId,
      'Rename crosstab',
      (Crosstab c) => c.copyWith(name: () => _normalizeName(name)));

  /// Sets (or, when null, clears) the nested collection crosstab [crosstabId]
  /// pools across the scope's rows. Null means "fold the scope's own rows".
  void setCrosstabCollection(String crosstabId, String? collectionField) =>
      _updateCrosstab(crosstabId, 'Bind crosstab',
          (Crosstab c) => c.copyWith(collectionField: () => collectionField));

  /// Sets the [visible] property of crosstab [crosstabId] (undoable).
  void setCrosstabVisible(String crosstabId, BoolProperty visible) =>
      _updateCrosstab(crosstabId, 'Set crosstab visibility',
          (Crosstab c) => c.copyWith(visible: visible));

  /// Replaces crosstab [crosstabId]'s appearance and metrics (undoable).
  void setCrosstabStyle(String crosstabId, CrosstabStyle style) =>
      _updateCrosstab(crosstabId, 'Set crosstab style',
          (Crosstab c) => c.copyWith(style: style));

  /// Commits [update] against crosstab [id] under the history entry [label].
  void _updateCrosstab(
          String id, String label, Crosstab Function(Crosstab) update) =>
      _commit(
          UpdateCrosstabCommand(crosstabId: id, label: label, update: update));
}
