import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../domain/band.dart';
import '../../../domain/detail_scope.dart';
import '../../../domain/elements/barcode_element.dart';
import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/shape_element.dart';
import '../../../domain/elements/text_element.dart';
import '../../../domain/group_level.dart';
import '../../../domain/report_band.dart';
import '../../../domain/report_definition.dart';
import '../../../domain/report_element.dart';
import '../../controller/band_walker.dart';
import '../../controller/jet_report_designer_controller.dart';
import '../../controller/selection.dart';
import '../../designer_scope.dart';
import '../../l10n/band_type_label.dart';
import '../../l10n/jet_print_localizations.dart';
import '../region_chrome.dart';

/// Subtle accent tint marking the row whose object is currently selected; matches
/// the canvas selection accent at a low alpha so the highlight reads on white.
const Color _selectedRowColor = Color(0x142563EB);

/// Body of the **Outline** tab: the live report as an indented, collapsible tree
/// reflecting the reified structure (spec 024) — a Report root, the record-blind
/// furniture and once-bands, then the master scope with its first-class groups
/// (each owning its header/footer bands) and nested detail scopes, and a leaf per
/// element (FR-007). The tree is driven entirely by the controller's
/// `definition`/`selection`:
///
/// * the row whose object is selected is highlighted (and marked selected for
///   accessibility);
/// * tapping a row selects that object — the report, a band, a **group**, a
///   **scope**, or an element — through the controller, which the canvas and
///   Properties panel observe;
/// * the disclosure chevron collapses/expands a branch (independent of select).
///
/// Expansion is view state held here (not in the model); it resets when the tab
/// is re-opened, with everything expanded.
class OutlinePanel extends StatefulWidget {
  /// Creates the Outline panel body. Private to the library.
  const OutlinePanel({super.key});

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  bool _rootExpanded = true;

  /// Stable ids of branches (bands, groups, scopes) the user has collapsed
  /// (absent ⇒ expanded). Keyed by id so it survives add/remove/reorder.
  final Set<String> _collapsed = <String>{};

  void _toggle(String id) => setState(() {
        // Set.add returns false when already collapsed → expand instead.
        if (!_collapsed.add(id)) _collapsed.remove(id);
      });

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final ReportDefinition def = controller.definition;
    final Selection selection = controller.selection;
    final ShadThemeData theme = ShadTheme.of(context);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    final List<Widget> rows = <Widget>[
      _branchRow(
        rowKey: const ValueKey<String>('jet_print.designer.outline.report'),
        toggleKey:
            const ValueKey<String>('jet_print.designer.outline.report.toggle'),
        depth: 0,
        icon: LucideIcons.fileText,
        label: l10n.reportLabel,
        expanded: _rootExpanded,
        selected: selection.isReport,
        onToggle: () => setState(() => _rootExpanded = !_rootExpanded),
        onSelect: controller.selectReport,
        theme: theme,
      ),
    ];

    if (_rootExpanded) {
      // Record-blind chrome + once-bands above the data body, in visual order.
      for (final Band? band in <Band?>[
        def.furniture.pageHeader,
        def.furniture.columnHeader,
        def.body.title,
      ]) {
        if (band != null) {
          _addBandRows(rows, band, 1, controller, selection, theme, l10n);
        }
      }
      // The data body: the master scope and everything it owns.
      _addScopeRows(rows, def.body.root, 1, controller, selection, theme, l10n);
      // Below the data body, in visual order.
      for (final Band? band in <Band?>[
        def.body.noData,
        def.body.summary,
        def.furniture.columnFooter,
        def.furniture.pageFooter,
      ]) {
        if (band != null) {
          _addBandRows(rows, band, 1, controller, selection, theme, l10n);
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  /// Appends a scope branch (selectable → Scope inspector) and, when expanded,
  /// its groups (each selectable → Group inspector, owning its header/footer
  /// bands) and its ordered children (per-row bands and nested scopes).
  void _addScopeRows(
    List<Widget> rows,
    DetailScope scope,
    int depth,
    JetReportDesignerController controller,
    Selection selection,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final bool isRoot = controller.definition.body.root.id == scope.id;
    final bool expanded = !_collapsed.contains(scope.id);
    final String scopeBase = 'jet_print.designer.outline.scope.${scope.id}';
    rows.add(_branchRow(
      rowKey: ValueKey<String>(scopeBase),
      toggleKey: ValueKey<String>('$scopeBase.toggle'),
      depth: depth,
      icon: LucideIcons.rows3,
      label: isRoot
          ? l10n.propertiesScope
          : (scope.collectionField ?? l10n.propertiesScope),
      expanded: expanded,
      selected: selection.scopeId == scope.id,
      onToggle: () => _toggle(scope.id),
      onSelect: () => controller.selectScope(scope.id),
      theme: theme,
      actions: <Widget>[_addMenu(controller, scope, theme, l10n)],
    ));
    if (!expanded) return;
    // Groups are not shown as separate nodes (Jasper-style): they surface
    // through their header/footer bands. Document order under the scope is the
    // group headers (outer→inner), then the ordered children, then the group
    // footers (inner→outer). A group's settings are edited on its header band;
    // a missing group band is added from the scope's "+" menu.
    for (final GroupLevel group in scope.groups) {
      if (group.header != null) {
        _addBandRows(
            rows, group.header!, depth + 1, controller, selection, theme, l10n);
      }
    }
    for (final ScopeNode node in scope.children) {
      switch (node) {
        case BandNode(band: final Band band):
          _addBandRows(
              rows, band, depth + 1, controller, selection, theme, l10n,
              reorderable: true);
        case NestedScope(scope: final DetailScope inner):
          _addScopeRows(
              rows, inner, depth + 1, controller, selection, theme, l10n);
      }
    }
    for (final GroupLevel group in scope.groups.reversed) {
      if (group.footer != null) {
        _addBandRows(
            rows, group.footer!, depth + 1, controller, selection, theme, l10n);
      }
    }
  }

  /// The scope "+" affordance: a menu that adds a per-row detail band, or adds a
  /// missing group header/footer band for one of the scope's groups. Group bands
  /// are added here because the group node was removed from the tree (2026-06-14
  /// design note). Always offers at least the detail option.
  Widget _addMenu(
    JetReportDesignerController controller,
    DetailScope scope,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final String scopeBase = 'jet_print.designer.outline.scope.${scope.id}';
    // Disambiguate the group-band options by name only when more than one group
    // could receive them.
    final bool many = scope.groups.length > 1;
    String groupLabel(String base, GroupLevel g) =>
        many ? '$base · ${g.name}' : base;
    final List<_MenuOption> options = <_MenuOption>[
      _MenuOption(
        optionKey: ValueKey<String>('$scopeBase.add.detail'),
        label: l10n.outlineAddBand,
        onPick: () => controller.addDetailBand(scope.id),
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

  /// Appends a band branch (selectable → Properties) and, when expanded, a leaf
  /// per element it contains. Trailing lifecycle affordances (FR-012): move
  /// up/down for a [reorderable] scope per-row band, retype, and remove.
  void _addBandRows(
    List<Widget> rows,
    Band band,
    int depth,
    JetReportDesignerController controller,
    Selection selection,
    ShadThemeData theme,
    JetPrintLocalizations l10n, {
    bool reorderable = false,
  }) {
    final bool expanded = !_collapsed.contains(band.id);
    final ShadColorScheme colors = theme.colorScheme;
    final String base = 'jet_print.designer.outline.band.${band.id}';
    rows.add(_branchRow(
      rowKey: ValueKey<String>(base),
      toggleKey: ValueKey<String>('$base.toggle'),
      depth: depth,
      icon: _bandGlyph(band.type),
      label: bandTypeLabel(band.type, l10n),
      expanded: expanded,
      selected: selection.bandId == band.id,
      onToggle: () => _toggle(band.id),
      onSelect: () => controller.selectBand(band.id),
      theme: theme,
      actions: <Widget>[
        if (reorderable) ...<Widget>[
          _act('$base.up', LucideIcons.arrowUp, l10n.outlineMoveUp,
              () => controller.moveBand(band.id, -1), colors),
          _act('$base.down', LucideIcons.arrowDown, l10n.outlineMoveDown,
              () => controller.moveBand(band.id, 1), colors),
        ],
        _retypeMenu(controller, band, theme, l10n),
        _act('$base.remove', LucideIcons.trash2, l10n.outlineRemove,
            () => controller.removeBand(band.id), colors),
      ],
    ));
    if (!expanded) return;
    for (final ReportElement element in band.elements) {
      rows.add(_leafRow(
        rowKey: ValueKey<String>(
            'jet_print.designer.outline.element.${element.id}'),
        depth: depth + 1,
        icon: _elementGlyph(element),
        label: element.id,
        selected: selection.contains(element.id),
        onSelect: () => controller.select(element.id),
        theme: theme,
      ));
    }
  }

  /// An expandable branch row (the report, a scope, a group, or a band): a
  /// disclosure chevron that toggles, then the node glyph and label; tapping the
  /// row (not the chevron) selects the node.
  Widget _branchRow({
    required Key rowKey,
    required Key toggleKey,
    required int depth,
    required IconData icon,
    required String label,
    required bool expanded,
    required bool selected,
    required VoidCallback onToggle,
    required VoidCallback onSelect,
    required ShadThemeData theme,
    List<Widget> actions = const <Widget>[],
  }) {
    final ShadColorScheme colors = theme.colorScheme;
    return KeyedSubtree(
      key: rowKey,
      child: MergeSemantics(
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: ColoredBox(
              color: selected ? _selectedRowColor : const Color(0x00000000),
              child: Padding(
                padding: EdgeInsets.only(
                    left: treeRowInset(depth), top: 4, bottom: 4, right: 8),
                child: Row(
                  children: <Widget>[
                    GestureDetector(
                      key: toggleKey,
                      behavior: HitTestBehavior.opaque,
                      onTap: onToggle,
                      child: Icon(
                        expanded
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronRight,
                        size: 14,
                        color: colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(icon, size: 14, color: colors.mutedForeground),
                    const SizedBox(width: 8),
                    // The label fills the slack so the lifecycle actions trail
                    // at the row's right edge.
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small,
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A compact trailing affordance on an outline row (add / remove / move): a
  /// keyed, button-role tappable glyph. Its own tap handler wins over the row's
  /// select gesture, so an action never doubles as a selection.
  Widget _act(
    String key,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
    ShadColorScheme colors,
  ) =>
      Padding(
        padding: const EdgeInsets.only(left: 2),
        child: MergeSemantics(
          child: Semantics(
            button: true,
            label: tooltip,
            child: GestureDetector(
              key: ValueKey<String>(key),
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Icon(icon, size: 13, color: colors.mutedForeground),
            ),
          ),
        ),
      );

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

  /// The singleton slots a band can be retyped into (FR-012 / FR-001a).
  ///
  /// The reserved furniture types (columnHeader, columnFooter, background) are
  /// deliberately omitted: they are modelled and round-trip through
  /// serialization, but the layouter does not lay them out yet, so offering
  /// them as authorable targets would mislead. The domain/data layers keep full
  /// support; only this UI affordance hides them.
  static const List<BandType> _retypeTargets = <BandType>[
    BandType.pageHeader,
    BandType.pageFooter,
    BandType.title,
    BandType.summary,
    BandType.noData,
  ];

  /// A leaf element row: the element glyph then its id; tapping it selects the
  /// element. Indented past the chevron column so it aligns under branch labels.
  Widget _leafRow({
    required Key rowKey,
    required int depth,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onSelect,
    required ShadThemeData theme,
  }) {
    final ShadColorScheme colors = theme.colorScheme;
    return KeyedSubtree(
      key: rowKey,
      child: MergeSemantics(
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: ColoredBox(
              color: selected ? _selectedRowColor : const Color(0x00000000),
              child: Padding(
                // +18 ≈ chevron width + gap, aligning the glyph under branches'.
                padding: EdgeInsets.only(
                    left: treeRowInset(depth) + 18,
                    top: 4,
                    bottom: 4,
                    right: 8),
                child: Row(
                  children: <Widget>[
                    Icon(icon, size: 14, color: colors.mutedForeground),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The tree glyph for a band: header-like bands get a top-panel glyph,
  /// footer-like bands a bottom-panel glyph, detail/no-data a rows glyph.
  IconData _bandGlyph(BandType type) {
    switch (type) {
      case BandType.title:
      case BandType.pageHeader:
      case BandType.columnHeader:
      case BandType.groupHeader:
        return LucideIcons.panelTop;
      case BandType.groupFooter:
      case BandType.columnFooter:
      case BandType.pageFooter:
      case BandType.summary:
        return LucideIcons.panelBottom;
      case BandType.detail:
      case BandType.noData:
        return LucideIcons.rows3;
      case BandType.background:
        return LucideIcons.image;
    }
  }

  /// The toolbox glyph for an element, so an outline leaf and the palette element
  /// it came from read as the same thing.
  IconData _elementGlyph(ReportElement element) {
    if (element is TextElement) return LucideIcons.type;
    if (element is ShapeElement) return LucideIcons.square;
    if (element is ImageElement) return LucideIcons.image;
    if (element is BarcodeElement) return LucideIcons.barcode;
    return LucideIcons.square;
  }
}

/// One option in a [_TypeMenu].
class _MenuOption {
  const _MenuOption({
    required this.optionKey,
    required this.label,
    required this.onPick,
  });

  final Key optionKey;
  final String label;
  final VoidCallback onPick;
}

/// A compact popup that picks a target band type/slot: the trigger is a keyed
/// glyph; tapping it drops a menu of [options]. Inert (no menu) when [options]
/// is empty — e.g. a band that has no free slot to retype into.
class _TypeMenu extends StatefulWidget {
  const _TypeMenu({
    required this.triggerKey,
    required this.icon,
    required this.tooltip,
    required this.options,
    required this.colors,
  });

  final Key triggerKey;
  final IconData icon;
  final String tooltip;
  final List<_MenuOption> options;
  final ShadColorScheme colors;

  @override
  State<_TypeMenu> createState() => _TypeMenuState();
}

class _TypeMenuState extends State<_TypeMenu> {
  final ShadPopoverController _menu = ShadPopoverController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.options.isNotEmpty;
    return ShadContextMenu(
      controller: _menu,
      items: <Widget>[
        for (final _MenuOption opt in widget.options)
          ShadContextMenuItem(
            key: opt.optionKey,
            onPressed: () {
              _menu.hide();
              opt.onPick();
            },
            child: Text(opt.label),
          ),
      ],
      child: MergeSemantics(
        child: Semantics(
          button: true,
          enabled: enabled,
          label: widget.tooltip,
          child: GestureDetector(
            key: widget.triggerKey,
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _menu.toggle : null,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(
                widget.icon,
                size: 13,
                color: enabled
                    ? widget.colors.mutedForeground
                    : widget.colors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
