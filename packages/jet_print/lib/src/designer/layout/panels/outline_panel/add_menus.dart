// Outline "+" add / retype menus.
//
// A part of `outline_panel.dart` (extension), library-private.
part of '../outline_panel.dart';

/// The singleton slots a band can be retyped into (FR-012 / FR-001a).
///
/// The reserved furniture types (columnHeader, columnFooter, background) are
/// deliberately omitted: they are modelled and round-trip through
/// serialization, but the layouter does not lay them out yet, so offering
/// them as authorable targets would mislead. The domain/data layers keep full
/// support; only this UI affordance hides them.
const List<BandType> _retypeTargets = <BandType>[
  BandType.pageHeader,
  BandType.pageFooter,
  BandType.title,
  BandType.summary,
  BandType.noData,
];

extension _OutlineAddMenus on _OutlinePanelState {
  /// The scope "+" affordance: a menu that adds a per-row detail band, or adds a
  /// missing group header/footer band for one of the scope's groups. Group bands
  /// are added here because the group node was removed from the tree (2026-06-14
  /// design note). Always offers at least the detail option.
  Widget _addMenu(
    JetReportDesignerController controller,
    DetailScope scope,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
    JetDataSchema? schema,
  ) {
    final String scopeBase = 'jet_print.designer.outline.scope.${scope.id}';
    // Disambiguate the group-band options by name only when more than one group
    // could receive them.
    final bool many = scope.groups.length > 1;
    String groupLabel(String base, GroupLevel g) =>
        many ? '$base · ${g.name}' : base;
    final List<FieldDef> groupFields = _groupFields(controller, scope, schema);
    final List<FieldDef> listCollections =
        collectionFieldsForScope(schema, controller.definition, scope.id);
    final List<_MenuOption> options = <_MenuOption>[
      _MenuOption(
        optionKey: ValueKey<String>('$scopeBase.add.detail'),
        label: l10n.outlineAddBand,
        onPick: () => controller.addDetailBand(scope.id),
      ),
      _MenuOption(
        optionKey: ValueKey<String>('$scopeBase.add.list'),
        label: l10n.outlineAddList,
        enabled: listCollections.isNotEmpty,
        children: <_MenuOption>[
          for (final FieldDef f in listCollections)
            _MenuOption(
              optionKey:
                  ValueKey<String>('$scopeBase.add.list.field.${f.name}'),
              label: f.name,
              onPick: () => controller.createListWithBand(scope.id,
                  collectionField: f.name),
            ),
        ],
      ),
      _MenuOption(
        optionKey: ValueKey<String>('$scopeBase.add.group'),
        label: l10n.outlineAddGroup,
        enabled: groupFields.isNotEmpty,
        children: <_MenuOption>[
          for (final FieldDef f in groupFields)
            _MenuOption(
              optionKey:
                  ValueKey<String>('$scopeBase.add.group.field.${f.name}'),
              label: f.name,
              onPick: () =>
                  controller.createGroupBoundToField(scope.id, f.name),
            ),
        ],
      ),
      for (final GroupLevel g in scope.groups)
        if (g.header == null)
          _MenuOption(
            optionKey: ValueKey<String>('$scopeBase.add.groupHeader.${g.id}'),
            label: groupLabel(l10n.outlineAddHeader, g),
            onPick: () => controller.addGroupBand(g.id, header: true),
          ),
      for (final GroupLevel g in scope.groups)
        if (g.footer == null)
          _MenuOption(
            optionKey: ValueKey<String>('$scopeBase.add.groupFooter.${g.id}'),
            label: groupLabel(l10n.outlineAddFooter, g),
            onPick: () => controller.addGroupBand(g.id, header: false),
          ),
    ];
    return _TypeMenu(
      triggerKey: ValueKey<String>('$scopeBase.add'),
      icon: LucideIcons.plus,
      tooltip: l10n.outlineAddBand,
      options: options,
      colors: theme.colorScheme,
    );
  }
  /// The scalar fields a new group on [scope] may key on — the choices behind
  /// the "Add group ▸" submenu (empty disables it).
  List<FieldDef> _groupFields(
    JetReportDesignerController controller,
    DetailScope scope,
    JetDataSchema? schema,
  ) =>
      scalarFieldsForScope(schema, controller.definition, scope.id);
  /// The "change band type" affordance: a menu of the empty singleton slots
  /// this band could move into (FR-012). Inert when no target slot is free.
  Widget _retypeMenu(
    JetReportDesignerController controller,
    Band band,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final String base = 'jet_print.designer.outline.band.${band.id}.retype';
    final List<_MenuOption> options = <_MenuOption>[
      for (final BandType type in _retypeTargets)
        if (type != band.type &&
            bandInSlot(controller.definition, type) == null)
          _MenuOption(
            optionKey: ValueKey<String>('$base.${type.name}'),
            label: bandTypeLabel(type, l10n),
            onPick: () => controller.retypeBand(band.id, type),
          ),
    ];
    return _TypeMenu(
      triggerKey: ValueKey<String>(base),
      icon: LucideIcons.replace,
      tooltip: l10n.outlineRetype,
      options: options,
      colors: theme.colorScheme,
    );
  }
  /// The report-root "+" affordance: a menu that creates one of the empty
  /// **rendered** singleton-slot bands — report header/footer, page
  /// header/footer, or no-data. Mirrors [_retypeTargets] so the add- and
  /// retype-menus offer the identical slot set and cannot drift; the reserved
  /// furniture types (column header/footer, background) are excluded because the
  /// layouter does not lay them out yet. Inert when every such slot is occupied.
  Widget _reportAddMenu(
    JetReportDesignerController controller,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    const String base = 'jet_print.designer.outline.report.add';
    final List<_MenuOption> options = <_MenuOption>[
      for (final BandType type in _retypeTargets)
        if (bandInSlot(controller.definition, type) == null)
          _MenuOption(
            optionKey: ValueKey<String>('$base.${type.name}'),
            label: bandTypeLabel(type, l10n),
            onPick: () => controller.addBand(type),
          ),
    ];
    return _TypeMenu(
      triggerKey: const ValueKey<String>(base),
      icon: LucideIcons.plus,
      tooltip: l10n.outlineAddBand,
      options: options,
      colors: theme.colorScheme,
    );
  }
}
