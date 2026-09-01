// The crosstab inspector (spec B).
//
// A part of `properties_panel.dart`: the panel is split one `part` file per
// inspector, and this follows that structure.
//
// Selection granularity is the whole crosstab, so its axis levels and measures
// are edited here as ordered lists — each a card with its own fields and its
// own add / remove / reorder actions — rather than as separately selectable
// objects. Every edit commits through the controller as one undoable step.
part of '../../properties_panel.dart';

extension _CrosstabInspector on _PropertiesPanelState {
  /// The inspector for the selected crosstab: identity, data source, both axes,
  /// the measures, the layout metrics and visibility.
  List<Widget> _crosstabInspector(
    JetReportDesignerController controller,
    String crosstabId,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
    JetDataSchema? schema,
  ) {
    final Crosstab? ct = findCrosstab(controller.definition, crosstabId);
    if (ct == null) return const <Widget>[];
    final DetailScope? scope =
        findScopeOfCrosstab(controller.definition, crosstabId);
    final String scopeId = scope?.id ?? controller.definition.body.root.id;
    final List<FieldDef> sourceFields = crosstabSourceFields(
        schema, controller.definition, scopeId, ct.collectionField);

    return <Widget>[
      _Header(
        icon: LucideIcons.table2,
        title: crosstabDisplayLabel(ct, l10n),
        rawName: ct.name,
        fallback: l10n.crosstabLabel,
        editing: _editingHeader,
        onEditingStart: () => _rebuild(() => _editingHeader = true),
        onEditingEnd: () => _rebuild(() => _editingHeader = false),
        onCommit: (String? name) {
          controller.renameCrosstab(crosstabId, name);
          _rebuild(() => _editingHeader = false);
        },
        theme: theme,
      ),
      const SizedBox(height: 14),
      SectionLabel(l10n.propertiesName),
      _TextInput(
        fieldKey: const ValueKey<String>('$_p.field.crosstabName'),
        value: ct.name ?? '',
        placeholder: l10n.crosstabLabel,
        onCommit: (String v) => controller.renameCrosstab(crosstabId, v),
      ),
      const SizedBox(height: 12),
      SectionLabel(l10n.propertiesBinding),
      // Cleared means "fold the enclosing scope's own rows"; a bound collection
      // is pooled across every row, which is what pivoting a nested list means.
      _BindingField(
        fieldKey: const ValueKey<String>('$_p.field.crosstabCollection'),
        value: ct.collectionField ?? '',
        placeholder: l10n.crosstabScopeRows,
        clearTooltip: l10n.bindingClearTooltip,
        fields:
            crosstabCollectionChoices(schema, controller.definition, scopeId),
        pickerTooltip: l10n.bindingFieldPickerTooltip,
        pickerKeyPrefix: '$_p.field.crosstabCollection.pick',
        onSet: (String v) => controller.setCrosstabCollection(crosstabId, v),
        onClear: () => controller.setCrosstabCollection(crosstabId, null),
      ),
      const SizedBox(height: 18),
      ..._crosstabAxisSection(controller, ct,
          row: true, fields: sourceFields, theme: theme, l10n: l10n),
      const SizedBox(height: 18),
      ..._crosstabAxisSection(controller, ct,
          row: false, fields: sourceFields, theme: theme, l10n: l10n),
      const SizedBox(height: 18),
      ..._crosstabMeasureSection(controller, ct,
          fields: sourceFields, theme: theme, l10n: l10n),
      const SizedBox(height: 18),
      ..._crosstabLayoutSection(controller, ct, theme, l10n),
      const SizedBox(height: 18),
      // Appearance: three flat sections — Header, Cells, Totals — matching
      // every other panel; the designer has no disclosure primitive and one
      // slot's null-means-inherited behaviour is documented on
      // _crosstabRoleSection. Keyed by crosstab id so selecting a different
      // crosstab discards any uncommitted input the composed editors hold.
      KeyedSubtree(
        key: ValueKey<String>('$_p.crosstab.style.$crosstabId'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ..._crosstabRoleSection(
              label: l10n.crosstabStyleHeader,
              keyBase: '$_p.crosstab.header',
              text: ct.style.headerText,
              box: ct.style.headerBox,
              effectiveText: _kCrosstabHeaderDefault,
              effectiveBox: JetBoxStyle.none,
              onText: (JetTextStyle s) => controller.setCrosstabStyle(
                  crosstabId, ct.style.copyWith(headerText: () => s)),
              onBox: (JetBoxStyle s) => controller.setCrosstabStyle(
                  crosstabId, ct.style.copyWith(headerBox: () => s)),
              onReset: () => controller.setCrosstabStyle(
                  crosstabId,
                  ct.style
                      .copyWith(headerText: () => null, headerBox: () => null)),
              l10n: l10n,
              theme: theme,
            ),
            ..._crosstabRoleSection(
              label: l10n.crosstabStyleCells,
              keyBase: '$_p.crosstab.cells',
              text: ct.style.cellText,
              box: ct.style.cellBox,
              effectiveText: _kCrosstabCellDefault,
              effectiveBox: JetBoxStyle.none,
              onText: (JetTextStyle s) => controller.setCrosstabStyle(
                  crosstabId, ct.style.copyWith(cellText: () => s)),
              onBox: (JetBoxStyle s) => controller.setCrosstabStyle(
                  crosstabId, ct.style.copyWith(cellBox: () => s)),
              onReset: () => controller.setCrosstabStyle(crosstabId,
                  ct.style.copyWith(cellText: () => null, cellBox: () => null)),
              l10n: l10n,
              theme: theme,
            ),
            ..._crosstabRoleSection(
              label: l10n.crosstabStyleTotals,
              keyBase: '$_p.crosstab.totals',
              text: ct.style.totalText,
              box: ct.style.totalBox,
              // Totals cascades through Cells before the bare default
              // (`_totalCellText`/`_cellBoxStyle` in crosstab_planner.dart):
              // an unset totalText/totalBox falls to cellText/cellBox first,
              // and only then to _kCrosstabCellDefault/JetBoxStyle.none. The
              // effective value shown here must be what the planner will
              // actually resolve, not the bare default one hop early.
              effectiveText: ct.style.cellText ?? _kCrosstabCellDefault,
              effectiveBox: ct.style.cellBox ?? JetBoxStyle.none,
              onText: (JetTextStyle s) => controller.setCrosstabStyle(
                  crosstabId, ct.style.copyWith(totalText: () => s)),
              onBox: (JetBoxStyle s) => controller.setCrosstabStyle(
                  crosstabId, ct.style.copyWith(totalBox: () => s)),
              onReset: () => controller.setCrosstabStyle(
                  crosstabId,
                  ct.style
                      .copyWith(totalText: () => null, totalBox: () => null)),
              l10n: l10n,
              theme: theme,
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      SectionLabel(l10n.propertiesVisible),
      _visibleSection(
        visible: ct.visible,
        onChanged: (BoolProperty v) =>
            controller.setCrosstabVisible(crosstabId, v),
        l10n: l10n,
      ),
    ];
  }

  /// One axis's ordered levels (outermost first), each a card, plus the menu
  /// that appends a level bound to a schema field.
  List<Widget> _crosstabAxisSection(
    JetReportDesignerController controller,
    Crosstab ct, {
    required bool row,
    required List<FieldDef> fields,
    required ShadThemeData theme,
    required JetPrintLocalizations l10n,
  }) {
    final List<CrosstabGroup> levels = row ? ct.rowGroups : ct.columnGroups;
    final String axis = row ? 'rowGroups' : 'columnGroups';
    return <Widget>[
      SectionLabel(row ? l10n.crosstabRowGroups : l10n.crosstabColumnGroups),
      for (int i = 0; i < levels.length; i++)
        _crosstabGroupCard(controller, ct, levels[i],
            index: i,
            axisLength: levels.length,
            fields: fields,
            theme: theme,
            l10n: l10n),
      const SizedBox(height: 8),
      _addFieldMenu(
        keyPrefix: '$_p.crosstab.$axis.add',
        label: l10n.crosstabAddLevel,
        fields: fields,
        onPick: (String name) =>
            controller.addCrosstabGroup(ct.id, row: row, fieldName: name),
      ),
    ];
  }

  /// One axis level: name, key expression, sort, subtotal — plus reorder and
  /// remove. Remove is omitted on the last level of an axis, which `validate()`
  /// requires to stay non-empty (the controller refuses it too).
  Widget _crosstabGroupCard(
    JetReportDesignerController controller,
    Crosstab ct,
    CrosstabGroup group, {
    required int index,
    required int axisLength,
    required List<FieldDef> fields,
    required ShadThemeData theme,
    required JetPrintLocalizations l10n,
  }) {
    final String base = '$_p.crosstab.group.${group.id}';
    return _CrosstabCard(
      theme: theme,
      children: <Widget>[
        _crosstabCardHeader(
          base: base,
          index: index,
          length: axisLength,
          theme: theme,
          l10n: l10n,
          onMove: (int delta) =>
              controller.moveCrosstabGroup(ct.id, group.id, delta),
          onRemove: axisLength == 1
              ? null
              : () => controller.removeCrosstabGroup(ct.id, group.id),
        ),
        const SizedBox(height: 8),
        _TextInput(
          fieldKey: ValueKey<String>('$base.name'),
          value: group.name,
          placeholder: l10n.propertiesName,
          onCommit: (String v) => controller.updateCrosstabGroup(
              ct.id, group.id, (CrosstabGroup g) => g.copyWith(name: v)),
        ),
        const SizedBox(height: 8),
        // The key expression, shown as the editable `[field]` shorthand the
        // group-key field uses, so both bucket-by inputs read alike.
        _TextInput(
          fieldKey: ValueKey<String>('$base.expression'),
          value: _groupKeyDisplay(group.expression),
          placeholder: l10n.bindingExpressionHint,
          fields: fields,
          pickerTooltip: l10n.bindingFieldPickerTooltip,
          pickerKeyPrefix: '$base.expression.pick',
          onCommit: (String v) => controller.updateCrosstabGroup(
              ct.id,
              group.id,
              (CrosstabGroup g) => g.copyWith(expression: _compileKey(v))),
        ),
        if (_crosstabUnresolved(group.expression, fields))
          _UnresolvedHint(message: l10n.bindingUnresolved),
        const SizedBox(height: 8),
        _PresetDropdown(
          fieldKey: ValueKey<String>('$base.sort'),
          label: _crosstabSortLabel(group.sort, l10n),
          tooltip: l10n.crosstabSort,
          options: <_DropdownOption>[
            for (final CrosstabSort sort in CrosstabSort.values)
              _DropdownOption(
                optionKey: ValueKey<String>('$base.sort.${sort.name}'),
                label: _crosstabSortLabel(sort, l10n),
                selected: group.sort == sort,
                onPick: () => controller.updateCrosstabGroup(ct.id, group.id,
                    (CrosstabGroup g) => g.copyWith(sort: sort)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // On the OUTERMOST level this switch is the grand total: spec A has one
        // concept at every level, not a separate grand-total flag.
        ShadSwitch(
          key: ValueKey<String>('$base.showTotal'),
          value: group.showTotal,
          onChanged: (bool v) => controller.updateCrosstabGroup(
              ct.id, group.id, (CrosstabGroup g) => g.copyWith(showTotal: v)),
          label: Text(l10n.crosstabShowTotal),
        ),
        if (group.showTotal) ...<Widget>[
          const SizedBox(height: 8),
          _TextInput(
            fieldKey: ValueKey<String>('$base.totalLabel'),
            value: group.totalLabel ?? '',
            placeholder: l10n.crosstabTotalLabel,
            onCommit: (String v) => controller.updateCrosstabGroup(
                ct.id,
                group.id,
                (CrosstabGroup g) =>
                    g.copyWith(totalLabel: () => v.trim().isEmpty ? null : v)),
          ),
        ],
      ],
    );
  }

  /// The measures, in column order — each a card — plus the add menu.
  List<Widget> _crosstabMeasureSection(
    JetReportDesignerController controller,
    Crosstab ct, {
    required List<FieldDef> fields,
    required ShadThemeData theme,
    required JetPrintLocalizations l10n,
  }) =>
      <Widget>[
        SectionLabel(l10n.crosstabMeasures),
        for (int i = 0; i < ct.measures.length; i++)
          _crosstabMeasureCard(controller, ct, ct.measures[i],
              index: i, fields: fields, theme: theme, l10n: l10n),
        const SizedBox(height: 8),
        _addFieldMenu(
          keyPrefix: '$_p.crosstab.measures.add',
          label: l10n.crosstabAddMeasure,
          fields: fields,
          onPick: (String name) =>
              controller.addCrosstabMeasure(ct.id, fieldName: name),
        ),
      ];

  /// One measure: name, per-row value expression, aggregate and format.
  Widget _crosstabMeasureCard(
    JetReportDesignerController controller,
    Crosstab ct,
    CrosstabMeasure measure, {
    required int index,
    required List<FieldDef> fields,
    required ShadThemeData theme,
    required JetPrintLocalizations l10n,
  }) {
    final String base = '$_p.crosstab.measure.${measure.id}';
    return _CrosstabCard(
      theme: theme,
      children: <Widget>[
        _crosstabCardHeader(
          base: base,
          index: index,
          length: ct.measures.length,
          theme: theme,
          l10n: l10n,
          onMove: (int delta) =>
              controller.moveCrosstabMeasure(ct.id, measure.id, delta),
          onRemove: ct.measures.length == 1
              ? null
              : () => controller.removeCrosstabMeasure(ct.id, measure.id),
        ),
        const SizedBox(height: 8),
        _TextInput(
          fieldKey: ValueKey<String>('$base.name'),
          value: measure.name,
          placeholder: l10n.propertiesName,
          onCommit: (String v) => controller.updateCrosstabMeasure(
              ct.id, measure.id, (CrosstabMeasure m) => m.copyWith(name: v)),
        ),
        const SizedBox(height: 8),
        _TextInput(
          fieldKey: ValueKey<String>('$base.expression'),
          value: _groupKeyDisplay(measure.expression),
          placeholder: l10n.bindingExpressionHint,
          fields: fields,
          pickerTooltip: l10n.bindingFieldPickerTooltip,
          pickerKeyPrefix: '$base.expression.pick',
          onCommit: (String v) => controller.updateCrosstabMeasure(
              ct.id,
              measure.id,
              (CrosstabMeasure m) => m.copyWith(expression: _compileKey(v))),
        ),
        if (_crosstabUnresolved(measure.expression, fields))
          _UnresolvedHint(message: l10n.bindingUnresolved),
        const SizedBox(height: 8),
        // JetCalculation.none is excluded deliberately: a cell folds many rows,
        // so it has no single row to pass through, and validate() rejects it.
        _PresetDropdown(
          fieldKey: ValueKey<String>('$base.aggregate'),
          label: measure.aggregate.name,
          tooltip: l10n.crosstabAggregate,
          options: <_DropdownOption>[
            for (final JetCalculation calc in JetCalculation.values)
              if (calc != JetCalculation.none)
                _DropdownOption(
                  optionKey: ValueKey<String>('$base.aggregate.${calc.name}'),
                  label: calc.name,
                  selected: measure.aggregate == calc,
                  onPick: () => controller.updateCrosstabMeasure(
                      ct.id,
                      measure.id,
                      (CrosstabMeasure m) => m.copyWith(aggregate: calc)),
                ),
          ],
        ),
        const SizedBox(height: 8),
        _FormatField(
          fieldKey: ValueKey<String>('$base.format'),
          value: measure.format ?? '',
          placeholder: l10n.formatHint,
          presets: formatPresets(l10n),
          fieldType: JetFieldType.double,
          pickerTooltip: l10n.formatPresetPickerTooltip,
          onCommit: (String v) => controller.updateCrosstabMeasure(
              ct.id,
              measure.id,
              (CrosstabMeasure m) =>
                  m.copyWith(format: () => v.trim().isEmpty ? null : v)),
        ),
      ],
    );
  }

  /// The size metrics, plus the width warning when even the minimum width
  /// (row-label column + one column per measure) exceeds the printable body.
  List<Widget> _crosstabLayoutSection(
    JetReportDesignerController controller,
    Crosstab ct,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final CrosstabStyle style = ct.style;
    Widget metric(String key, String label, double value,
            CrosstabStyle Function(double) update) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SectionLabel(label),
              _NumberField(
                fieldKey: ValueKey<String>('$_p.field.$key'),
                prefix: LucideIcons.ruler,
                value: value,
                onCommit: (double v) =>
                    controller.setCrosstabStyle(ct.id, update(v)),
              ),
            ],
          ),
        );

    return <Widget>[
      SectionLabel(l10n.crosstabLayout),
      const SizedBox(height: 8),
      if (_crosstabTooWide(controller.definition, ct)) ...<Widget>[
        _InlineWarning(text: l10n.crosstabTooWide, theme: theme),
        const SizedBox(height: 8),
      ],
      metric('crosstabRowLabelWidth', l10n.crosstabRowLabelWidth,
          style.rowLabelWidth, (double v) => style.copyWith(rowLabelWidth: v)),
      metric(
          'crosstabRowLabelIndent',
          l10n.crosstabRowLabelIndent,
          style.rowLabelIndent,
          (double v) => style.copyWith(rowLabelIndent: v)),
      metric(
          'crosstabMeasureColumnWidth',
          l10n.crosstabMeasureColumnWidth,
          style.measureColumnWidth,
          (double v) => style.copyWith(measureColumnWidth: v)),
      metric('crosstabRowHeight', l10n.crosstabRowHeight, style.rowHeight,
          (double v) => style.copyWith(rowHeight: v)),
      metric(
          'crosstabHeaderRowHeight',
          l10n.crosstabHeaderRowHeight,
          style.headerRowHeight,
          (double v) => style.copyWith(headerRowHeight: v)),
    ];
  }

  /// Whether [expression] references a field the crosstab's current source does
  /// not offer — the case a **rebind** creates, since rebinding preserves the
  /// authored expressions rather than rewriting or resetting them.
  ///
  /// Preserving them is the deliberate rule: a rebind is often one step of
  /// repointing a report at a renamed source, and silently reseeding the axes
  /// would throw away authored names, sorts, totals and formats to save one
  /// re-pick. The cost is that a stale binding is otherwise invisible, so it is
  /// surfaced here, per field, where the author fixes it.
  ///
  /// With no schema attached [fields] is empty and nothing is flagged — the
  /// binding still shows and resolution waits for a source (FR-019a), the rule
  /// the element inspector's `_unresolved` follows.
  bool _crosstabUnresolved(String expression, List<FieldDef> fields) {
    if (fields.isEmpty) return false;
    final Set<String> names = <String>{
      for (final FieldDef f in fields) f.name,
    };
    return RegExp(r'\$F\{([^}]*)\}')
        .allMatches(expression)
        .any((RegExpMatch m) => !names.contains(m.group(1)));
  }

  /// Whether [ct] cannot fit the printable body even at its minimum width — the
  /// row-label column plus one column per measure.
  ///
  /// Derived here rather than read from the engine's `Diagnostic`, because
  /// engine diagnostics are not localized: the same split `_columnDiagnostics`
  /// (spec 035) already makes.
  bool _crosstabTooWide(ReportDefinition def, Crosstab ct) {
    final double body =
        def.page.width - def.page.margins.left - def.page.margins.right;
    final double minimum = ct.style.rowLabelWidth +
        ct.measures.length * ct.style.measureColumnWidth;
    return minimum > body;
  }

  /// A level/measure card's top row: its ordinal, reorder arrows, and remove
  /// (omitted when [onRemove] is null — the last one on its list).
  Widget _crosstabCardHeader({
    required String base,
    required int index,
    required int length,
    required ShadThemeData theme,
    required JetPrintLocalizations l10n,
    required void Function(int delta) onMove,
    VoidCallback? onRemove,
  }) =>
      Row(
        children: <Widget>[
          Text('${index + 1}',
              style: theme.textTheme.muted
                  .copyWith(color: theme.colorScheme.mutedForeground)),
          const Spacer(),
          if (index > 0)
            _CardAction(
              actionKey: ValueKey<String>('$base.up'),
              icon: LucideIcons.arrowUp,
              tooltip: l10n.outlineMoveUp,
              onPressed: () => onMove(-1),
              theme: theme,
            ),
          if (index < length - 1)
            _CardAction(
              actionKey: ValueKey<String>('$base.down'),
              icon: LucideIcons.arrowDown,
              tooltip: l10n.outlineMoveDown,
              onPressed: () => onMove(1),
              theme: theme,
            ),
          if (onRemove != null)
            _CardAction(
              actionKey: ValueKey<String>('$base.remove'),
              icon: LucideIcons.trash2,
              tooltip: l10n.outlineRemove,
              onPressed: onRemove,
              theme: theme,
            ),
        ],
      );

  /// The "add a level / add a measure" dropdown: one option per bindable field.
  /// Inert with no schema attached, which is when [fields] is empty.
  Widget _addFieldMenu({
    required String keyPrefix,
    required String label,
    required List<FieldDef> fields,
    required ValueChanged<String> onPick,
  }) =>
      _PresetDropdown(
        fieldKey: ValueKey<String>(keyPrefix),
        label: label,
        tooltip: label,
        options: <_DropdownOption>[
          for (final FieldDef f in fields)
            _DropdownOption(
              optionKey: ValueKey<String>('$keyPrefix.field.${f.name}'),
              label: f.name,
              selected: false,
              onPick: () => onPick(f.name),
            ),
        ],
      );
}

/// The localized name of a crosstab axis sort mode.
String _crosstabSortLabel(CrosstabSort sort, JetPrintLocalizations l10n) =>
    switch (sort) {
      CrosstabSort.ascending => l10n.crosstabSortAscending,
      CrosstabSort.descending => l10n.crosstabSortDescending,
      CrosstabSort.dataOrder => l10n.crosstabSortDataOrder,
    };

/// A bordered container holding one axis level's or one measure's fields, so a
/// list of them reads as a list rather than a run of loose inputs.
class _CrosstabCard extends StatelessWidget {
  const _CrosstabCard({required this.theme, required this.children});

  final ShadThemeData theme;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

/// A compact icon action inside a [_CrosstabCard]'s header row.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.actionKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
  });

  final Key actionKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) => ShadTooltip(
        builder: (BuildContext _) => Text(tooltip),
        child: ShadButton.ghost(
          key: actionKey,
          height: 24,
          width: 24,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Icon(icon, size: 14, color: theme.colorScheme.mutedForeground),
        ),
      );
}
