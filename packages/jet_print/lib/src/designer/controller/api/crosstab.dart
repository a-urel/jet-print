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

  // --- Axis levels -----------------------------------------------------------

  /// Appends an axis level to crosstab [crosstabId], keyed by [fieldName] and
  /// named after it — the row axis when [row] is true, else the column axis.
  /// A no-op for a blank [fieldName].
  void addCrosstabGroup(String crosstabId,
      {required bool row, required String fieldName}) {
    if (fieldName.trim().isEmpty) return;
    final CrosstabGroup g = _seedGroup(FieldDef(fieldName.trim()));
    _updateCrosstab(
        crosstabId,
        'Add crosstab level',
        (Crosstab c) => row
            ? c.copyWith(rowGroups: <CrosstabGroup>[...c.rowGroups, g])
            : c.copyWith(columnGroups: <CrosstabGroup>[...c.columnGroups, g]));
  }

  /// Removes axis level [groupId] from whichever axis holds it.
  ///
  /// Refuses to remove the last level of an axis: `validate()` requires at
  /// least one row group and one column group, so the invariant is enforced
  /// here and not only by a disabled button. A refusal is a no-op edit, so it
  /// records no history.
  void removeCrosstabGroup(String crosstabId, String groupId) =>
      _updateCrosstab(crosstabId, 'Remove crosstab level', (Crosstab c) {
        if (c.rowGroups.any((CrosstabGroup g) => g.id == groupId)) {
          return c.rowGroups.length == 1
              ? c
              : c.copyWith(rowGroups: _without(c.rowGroups, groupId));
        }
        if (!c.columnGroups.any((CrosstabGroup g) => g.id == groupId)) return c;
        return c.columnGroups.length == 1
            ? c
            : c.copyWith(columnGroups: _without(c.columnGroups, groupId));
      });

  /// Moves axis level [groupId] by [delta] positions on its own axis, clamped
  /// to the axis bounds. Outermost is first.
  void moveCrosstabGroup(String crosstabId, String groupId, int delta) =>
      _updateCrosstab(crosstabId, 'Reorder crosstab level', (Crosstab c) {
        if (c.rowGroups.any((CrosstabGroup g) => g.id == groupId)) {
          return c.copyWith(rowGroups: _moved(c.rowGroups, groupId, delta));
        }
        return c.copyWith(columnGroups: _moved(c.columnGroups, groupId, delta));
      });

  /// Rewrites axis level [groupId] through [update] as one undoable step.
  void updateCrosstabGroup(String crosstabId, String groupId,
          CrosstabGroup Function(CrosstabGroup) update) =>
      _updateCrosstab(
          crosstabId,
          'Edit crosstab level',
          (Crosstab c) => c.copyWith(
                rowGroups: _mapped(c.rowGroups, groupId, update),
                columnGroups: _mapped(c.columnGroups, groupId, update),
              ));

  // --- Measures --------------------------------------------------------------

  /// Appends a `sum` measure over [fieldName] to crosstab [crosstabId], named
  /// after the field. A no-op for a blank [fieldName]; the aggregate and format
  /// are then edited in place through [updateCrosstabMeasure].
  void addCrosstabMeasure(String crosstabId, {required String fieldName}) {
    final String name = fieldName.trim();
    if (name.isEmpty) return;
    final CrosstabMeasure m = CrosstabMeasure(
      id: _ids.next('ctmeasure'),
      name: name,
      expression: '\$F{$name}',
      aggregate: JetCalculation.sum,
    );
    _updateCrosstab(
        crosstabId,
        'Add crosstab measure',
        (Crosstab c) =>
            c.copyWith(measures: <CrosstabMeasure>[...c.measures, m]));
  }

  /// Removes measure [measureId], refusing the last one — `validate()` requires
  /// at least one measure, so a refusal is a no-op edit that records no
  /// history.
  void removeCrosstabMeasure(String crosstabId, String measureId) =>
      _updateCrosstab(
          crosstabId,
          'Remove crosstab measure',
          (Crosstab c) => c.measures.length == 1
              ? c
              : c.copyWith(measures: _without(c.measures, measureId)));

  /// Moves measure [measureId] by [delta] positions in column order, clamped.
  void moveCrosstabMeasure(String crosstabId, String measureId, int delta) =>
      _updateCrosstab(
          crosstabId,
          'Reorder crosstab measure',
          (Crosstab c) =>
              c.copyWith(measures: _moved(c.measures, measureId, delta)));

  /// Rewrites measure [measureId] through [update] as one undoable step.
  void updateCrosstabMeasure(String crosstabId, String measureId,
          CrosstabMeasure Function(CrosstabMeasure) update) =>
      _updateCrosstab(
          crosstabId,
          'Edit crosstab measure',
          (Crosstab c) =>
              c.copyWith(measures: _mapped(c.measures, measureId, update)));

  /// Commits [update] against crosstab [id] under the history entry [label].
  void _updateCrosstab(
          String id, String label, Crosstab Function(Crosstab) update) =>
      _commit(
          UpdateCrosstabCommand(crosstabId: id, label: label, update: update));
}

/// The list-shape helpers the axis and measure families share. `T` is a
/// [CrosstabGroup] or a [CrosstabMeasure]; both are identified by a string id,
/// so one set of helpers serves both axes and the measure list. Each returns
/// the list unchanged when the id is absent (or the move clamps to a no-op), so
/// the enclosing command sees a value-equal crosstab and records no history.
List<T> _without<T extends Object>(List<T> items, String id) => <T>[
      for (final T i in items)
        if (_idOf(i) != id) i
    ];

List<T> _mapped<T extends Object>(
        List<T> items, String id, T Function(T) update) =>
    <T>[
      for (final T i in items)
        if (_idOf(i) == id) update(i) else i
    ];

List<T> _moved<T extends Object>(List<T> items, String id, int delta) {
  final int idx = items.indexWhere((T i) => _idOf(i) == id);
  if (idx < 0) return items;
  final int target = (idx + delta).clamp(0, items.length - 1);
  if (target == idx) return items;
  final List<T> out = <T>[...items];
  out.insert(target, out.removeAt(idx));
  return out;
}

String? _idOf(Object item) => switch (item) {
      CrosstabGroup(id: final String id) => id,
      CrosstabMeasure(id: final String id) => id,
      _ => null,
    };
