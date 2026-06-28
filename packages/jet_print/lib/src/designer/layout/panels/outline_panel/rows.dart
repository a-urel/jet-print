// Outline tree row builders.
//
// A part of `outline_panel.dart` (extension), library-private.
part of '../outline_panel.dart';

extension _OutlineRows on _OutlinePanelState {
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
    JetDataSchema? schema,
  ) {
    final bool isRoot = controller.definition.body.root.id == scope.id;
    final bool expanded = !_collapsed.contains(scope.id);
    final String scopeBase = 'jet_print.designer.outline.scope.${scope.id}';
    rows.add(_branchRow(
      rowKey: ValueKey<String>(scopeBase),
      toggleKey: ValueKey<String>('$scopeBase.toggle'),
      depth: depth,
      icon: isRoot ? LucideIcons.rows3 : LucideIcons.list,
      label: isRoot
          ? l10n.propertiesScope
          : (scope.collectionField != null
              ? l10n.outlineListLabel(scope.collectionField!)
              : l10n.outlineListUnbound),
      expanded: expanded,
      selected: selection.scopeId == scope.id,
      onToggle: () => _toggle(scope.id),
      onSelect: () => controller.selectScope(scope.id),
      theme: theme,
      actions: <Widget>[
        _addMenu(controller, scope, theme, l10n, schema),
        // The root scope is the report body and is not deletable; a nested list
        // can be removed (with everything it contains) so redundant or empty
        // "List: <field>" nodes never get stuck in the tree.
        if (!isRoot)
          _act('$scopeBase.remove', LucideIcons.trash2, l10n.outlineRemove,
              () => controller.deleteScope(scope.id), theme.colorScheme),
      ],
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
          _addScopeRows(rows, inner, depth + 1, controller, selection, theme,
              l10n, schema);
      }
    }
    for (final GroupLevel group in scope.groups.reversed) {
      if (group.footer != null) {
        _addBandRows(
            rows, group.footer!, depth + 1, controller, selection, theme, l10n);
      }
    }
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
      label: bandDisplayLabel(band, l10n),
      expanded: expanded,
      selected: selection.bandId == band.id,
      onToggle: () => _toggle(band.id),
      onSelect: () => _handleTap(
        band.id,
        () => controller.selectBand(band.id),
        () => _rebuild(() => _editingId = band.id),
      ),
      theme: theme,
      rawName: band.name,
      fallback: bandTypeLabel(band.type, l10n),
      editing: _editingId == band.id,
      onEditingEnd: () => _rebuild(() => _editingId = null),
      onCommit: (String? name) {
        controller.renameBand(band.id, name);
        _rebuild(() => _editingId = null);
      },
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
        label: elementDisplayLabel(element, l10n),
        rawName: element.name,
        fallback: elementTypeLabel(element, l10n),
        editing: _editingId == element.id,
        onEditingEnd: () => _rebuild(() => _editingId = null),
        onCommit: (String? name) {
          controller.renameElement(element.id, name);
          _rebuild(() => _editingId = null);
        },
        selected: selection.contains(element.id),
        onSelect: () => _handleTap(
          element.id,
          () => controller.select(element.id),
          () => _rebuild(() => _editingId = element.id),
        ),
        theme: theme,
      ));
    }
  }

  /// An expandable branch row (the report, a scope, a group, or a band): a
  /// disclosure chevron that toggles, then the node glyph and label; tapping the
  /// row (not the chevron) selects the node.
  ///
  /// The optional editing params wire inline rename for band rows only. When
  /// [editing] is true the label is replaced with an [EditableLabel]. Pass
  /// [onEditingStart] to enable double-tap; leave all null for report/scope/group
  /// rows that are not renameable.
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
    String? rawName,
    String? fallback,
    bool editing = false,
    VoidCallback? onEditingEnd,
    ValueChanged<String?>? onCommit,
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
                      child: editing
                          ? Material(
                              type: MaterialType.transparency,
                              child: EditableLabel(
                                display: label,
                                value: rawName,
                                placeholder: fallback ?? label,
                                editing: true,
                                onEditingEnd: onEditingEnd,
                                onCommit: onCommit ?? (_) {},
                                textStyle: theme.textTheme.small,
                              ),
                            )
                          : Text(
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

  /// A leaf element row: the element glyph then its display label; tapping it
  /// selects the element; double-tapping starts an inline rename.
  /// Indented past the chevron column so it aligns under branch labels.
  Widget _leafRow({
    required Key rowKey,
    required int depth,
    required IconData icon,
    required String label,
    required String? rawName,
    required String fallback,
    required bool editing,
    required VoidCallback onEditingEnd,
    required ValueChanged<String?> onCommit,
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
                      child: editing
                          ? Material(
                              type: MaterialType.transparency,
                              child: EditableLabel(
                                display: label,
                                value: rawName,
                                placeholder: fallback,
                                editing: true,
                                onEditingEnd: onEditingEnd,
                                onCommit: onCommit,
                                textStyle: theme.textTheme.small,
                              ),
                            )
                          : Text(
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
