import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../controller/bulk_geometry.dart';
import '../controller/jet_report_designer_controller.dart';
import '../designer_scope.dart';
import '../l10n/jet_print_localizations.dart';
import '../platform_shortcut.dart';
import 'unified_top_bar.dart';
import 'workspace_mode_switch.dart';

/// The designer's top strip: a command bar modelled on desktop report designers
/// such as DevExpress, Telerik and Stimulsoft. A document title sits on the
/// leading edge; the trailing edge clusters logical groups separated by
/// dividers — history (undo/redo), zoom (out / level / in), view toggles
/// (grid/rulers/snap) — followed by the primary Preview / Save / Export actions.
///
/// The zoom level and the view toggles are genuinely interactive (local-only
/// this iteration); the history and primary actions are non-functional
/// placeholders that render as enabled so the bar reads as a real toolbar
/// (FR-015). Every caption and tooltip is sourced from [JetPrintLocalizations]
/// (FR-016) and every color/text style from [ShadTheme] (FR-008/009). The title
/// ellipsizes so a longer translation never pushes the actions off-screen
/// (longer-text edge case / T037).
class DesignerTopBar extends StatefulWidget {
  /// Creates the designer top bar. Private to the library; composed by
  /// `JetReportDesigner`.
  ///
  /// [onOpen]/[onSave]/[onPreview] back the Open/Save/Preview actions; each is
  /// null when the host wired no corresponding callback, and the action then
  /// renders disabled (the library performs no file I/O itself — FR-022).
  const DesignerTopBar({super.key, this.onOpen, this.onSave, this.onPreview});

  /// Invoked when the user triggers Open (the host reads a template and calls
  /// `controller.open`). Null ⇒ the Open action is disabled.
  final VoidCallback? onOpen;

  /// Invoked when the user triggers Save (the host persists the current
  /// template). Null ⇒ the Save action is disabled.
  final VoidCallback? onSave;

  /// Invoked when the user triggers Preview (the host opens a rendered preview,
  /// e.g. via `JetReportEngine` + `JetReportPreview`). Null ⇒ Preview is
  /// disabled.
  final VoidCallback? onPreview;

  @override
  State<DesignerTopBar> createState() => _DesignerTopBarState();
}

class _DesignerTopBarState extends State<DesignerTopBar> {
  /// Below this width the labelled primary actions collapse to icon-only so the
  /// dense command cluster (≈731px labelled) keeps fitting beside the name +
  /// mode switch as the name ellipsizes.
  static const double _compactWidth = 1300;

  /// Below this width the whole bar scrolls horizontally so the name + switch
  /// stay reachable rather than overflowing. Sized so the compact (icon-only)
  /// cluster always fits above it, in every locale.
  static const double _scrollWidth = 1040;

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);

    // Compose the shared shell: the report name (leading) + the mode switch
    // (center) are the shell's own regions — positionally identical to the
    // preview (FR-001) — and the designer's command groups fill the right slot.
    return UnifiedTopBar(
      leadingIcon: LucideIcons.fileText,
      name: controller.definition.name,
      compactWidth: _compactWidth,
      scrollWidth: _scrollWidth,
      // The Preview segment of the switch IS the old Preview action: selecting
      // it emits the host's `onPreview` switch request (FR-002, research D2).
      center: WorkspaceModeSwitch(
        mode: WorkspaceMode.designer,
        onSwitchRequested: widget.onPreview,
      ),
      actions: (BuildContext context, bool compact) =>
          _actions(context, controller, compact),
    );
  }

  /// The designer's right-slot command groups (FR-011): the Open / Save file
  /// actions first (like a File menu, ahead of the editing commands), then
  /// history, clipboard, zoom, view toggles and arrange. Each group is fenced by
  /// a [_Divider]; the file actions render icon-only when [compact].
  List<Widget> _actions(
    BuildContext context,
    JetReportDesignerController controller,
    bool compact,
  ) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    return <Widget>[
      // File group — Open / Save are wired to the host's callbacks (FR-022) and
      // lead the bar, ahead of the editing commands. Export is not offered in
      // the designer; it lives in the preview where the artifact exists (017).
      _ActionButton(
        icon: LucideIcons.folderOpen,
        label: l10n.actionOpen,
        tooltip: l10n.actionOpenTooltip,
        compact: compact,
        onPressed: widget.onOpen,
      ),
      _ActionButton(
        icon: LucideIcons.save,
        label: l10n.actionSave,
        tooltip: l10n.actionSaveTooltip,
        compact: compact,
        onPressed: widget.onSave,
      ),

      // History group — wired to the controller, disabled at the ends (US3.4).
      const _Divider(),
      _IconButton(
        buttonKey: const ValueKey<String>('jet_print.designer.action.undo'),
        icon: LucideIcons.undo2,
        tooltip: labelWithShortcut(l10n.actionUndoTooltip, 'Z'),
        enabled: controller.canUndo,
        onPressed: controller.undo,
      ),
      _IconButton(
        buttonKey: const ValueKey<String>('jet_print.designer.action.redo'),
        icon: LucideIcons.redo2,
        tooltip: labelWithShortcut(l10n.actionRedoTooltip, 'Z', shift: true),
        enabled: controller.canRedo,
        onPressed: controller.redo,
      ),

      // Clipboard group — Cut/Copy/Paste, the conventional editing cluster beside
      // History. Enablement is bound to the same canCopy/canPaste predicates the
      // context menu reads (FR-012), so the two surfaces cannot diverge; tooltips
      // carry the platform shortcut hint (FR-001, FR-004, FR-005, FR-014).
      const _Divider(),
      _IconButton(
        buttonKey: const ValueKey<String>('jet_print.designer.action.cut'),
        icon: LucideIcons.scissors,
        tooltip: labelWithShortcut(l10n.actionCutTooltip, 'X'),
        enabled: controller.canCopy,
        onPressed: controller.cut,
      ),
      _IconButton(
        buttonKey: const ValueKey<String>('jet_print.designer.action.copy'),
        icon: LucideIcons.copy,
        tooltip: labelWithShortcut(l10n.actionCopyTooltip, 'C'),
        enabled: controller.canCopy,
        onPressed: controller.copy,
      ),
      _IconButton(
        buttonKey: const ValueKey<String>('jet_print.designer.action.paste'),
        icon: LucideIcons.clipboard,
        tooltip: labelWithShortcut(l10n.actionPasteTooltip, 'V'),
        enabled: controller.canPaste,
        onPressed: controller.paste,
      ),

      // Zoom group — driven by the controller's view state; tap the % to fit.
      const _Divider(),
      _IconButton(
        icon: LucideIcons.zoomOut,
        tooltip: l10n.actionZoomOutTooltip,
        onPressed: controller.zoomOut,
      ),
      ShadTooltip(
        builder: (BuildContext context) => Text(l10n.actionZoomFitTooltip),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.fitToView,
          child: SizedBox(
            width: 46,
            child: Text(
              '${(controller.viewScale * 100).round()}%',
              key:
                  const ValueKey<String>('jet_print.designer.action.zoomLevel'),
              textAlign: TextAlign.center,
              style: theme.textTheme.small.copyWith(color: colors.foreground),
            ),
          ),
        ),
      ),
      _IconButton(
        icon: LucideIcons.zoomIn,
        tooltip: l10n.actionZoomInTooltip,
        onPressed: controller.zoomIn,
      ),

      // View-toggle group.
      const _Divider(),
      _ToggleButton(
        buttonKey: const ValueKey<String>('jet_print.designer.toggle.ruler'),
        icon: LucideIcons.ruler,
        tooltip: l10n.toggleRulerTooltip,
        active: controller.rulersEnabled,
        onPressed: () => controller.setRulersEnabled(!controller.rulersEnabled),
      ),
      _ToggleButton(
        buttonKey: const ValueKey<String>('jet_print.designer.toggle.grid'),
        icon: LucideIcons.grid2x2,
        tooltip: l10n.toggleGridTooltip,
        active: controller.gridEnabled,
        onPressed: () => controller.setGridEnabled(!controller.gridEnabled),
      ),
      _ToggleButton(
        buttonKey: const ValueKey<String>('jet_print.designer.toggle.snap'),
        icon: LucideIcons.magnet,
        tooltip: l10n.toggleSnapTooltip,
        active: controller.snapEnabled,
        onPressed: () => controller.setSnapEnabled(!controller.snapEnabled),
      ),

      // Arrange group — align / distribute / z-order over the selection (US4).
      const _Divider(),
      _ArrangeMenu(controller: controller),
    ];
  }
}

/// A short vertical rule with horizontal breathing room, used to fence one
/// command group off from the next.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 22,
        child: ShadSeparator.vertical(margin: EdgeInsets.zero),
      ),
    );
  }
}

/// The "Arrange" dropdown: align / distribute / z-order actions over the current
/// selection, wired to the controller's bulk ops (FR-012/FR-013, US4.5–US4.6).
///
/// The trigger enables once any element is selected; the align/distribute items
/// further require two or more (a lone element has nothing to align against),
/// while the z-order items act on a single element too. Labels are English this
/// iteration, matching the still-unlocalized panels; their localization is
/// folded into T078 with the other new affordance strings.
class _ArrangeMenu extends StatefulWidget {
  const _ArrangeMenu({required this.controller});

  final JetReportDesignerController controller;

  @override
  State<_ArrangeMenu> createState() => _ArrangeMenuState();
}

class _ArrangeMenuState extends State<_ArrangeMenu> {
  final ShadPopoverController _popover = ShadPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  /// Runs a controller op, then closes the menu.
  void _run(VoidCallback op) {
    op();
    _popover.hide();
  }

  ShadContextMenuItem _action(
    String id,
    IconData icon,
    String label, {
    required bool enabled,
    required VoidCallback op,
  }) {
    return ShadContextMenuItem(
      key: ValueKey<String>('jet_print.designer.arrange.$id'),
      enabled: enabled,
      leading: Icon(icon, size: 16),
      onPressed: () => _run(op),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController c = widget.controller;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final int count = c.selection.ids.length;
    final bool hasSelection = count > 0;
    // Aligning/distributing a single element is a no-op, so those need a pair.
    final bool canAlign = count >= 2;

    return Padding(
      // ~4px between adjacent buttons (2 + 2), matching the other tool buttons.
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ShadContextMenu(
        controller: _popover,
        items: <Widget>[
          _action('alignLeft', LucideIcons.alignStartVertical,
              l10n.arrangeAlignLeft,
              enabled: canAlign, op: () => c.align(AlignKind.left)),
          _action('alignCenterHorizontal', LucideIcons.alignCenterVertical,
              l10n.arrangeAlignCenter,
              enabled: canAlign, op: () => c.align(AlignKind.centerHorizontal)),
          _action('alignRight', LucideIcons.alignEndVertical,
              l10n.arrangeAlignRight,
              enabled: canAlign, op: () => c.align(AlignKind.right)),
          _action('alignTop', LucideIcons.alignStartHorizontal,
              l10n.arrangeAlignTop,
              enabled: canAlign, op: () => c.align(AlignKind.top)),
          _action('alignMiddle', LucideIcons.alignCenterHorizontal,
              l10n.arrangeAlignMiddle,
              enabled: canAlign, op: () => c.align(AlignKind.middle)),
          _action('alignBottom', LucideIcons.alignEndHorizontal,
              l10n.arrangeAlignBottom,
              enabled: canAlign, op: () => c.align(AlignKind.bottom)),
          const _MenuDivider(),
          _action(
              'distributeHorizontal',
              LucideIcons.alignHorizontalDistributeCenter,
              l10n.arrangeDistributeHorizontally,
              enabled: canAlign,
              op: () => c.distribute(DistributeAxis.horizontal)),
          _action(
              'distributeVertical',
              LucideIcons.alignVerticalDistributeCenter,
              l10n.arrangeDistributeVertically,
              enabled: canAlign,
              op: () => c.distribute(DistributeAxis.vertical)),
          const _MenuDivider(),
          _action('bringToFront', LucideIcons.bringToFront,
              l10n.arrangeBringToFront,
              enabled: hasSelection, op: c.bringToFront),
          _action(
              'bringForward', LucideIcons.chevronUp, l10n.arrangeBringForward,
              enabled: hasSelection, op: c.bringForward),
          _action(
              'sendBackward', LucideIcons.chevronDown, l10n.arrangeSendBackward,
              enabled: hasSelection, op: c.sendBackward),
          _action('sendToBack', LucideIcons.sendToBack, l10n.arrangeSendToBack,
              enabled: hasSelection, op: c.sendToBack),
        ],
        // A labelled Semantics wrapper rather than a hover ShadTooltip: a
        // tooltip overlay would render on top of the just-opened menu. The
        // menu items are self-describing; this keeps an accessible name.
        // MergeSemantics folds the label onto the button's own node (role +
        // enabled state) so a screen reader announces a single "Arrange" button.
        child: MergeSemantics(
          child: Semantics(
            label: l10n.actionArrangeTooltip,
            button: true,
            child: ShadIconButton.ghost(
              key: const ValueKey<String>('jet_print.designer.action.arrange'),
              icon: const Icon(LucideIcons.layoutGrid, size: 16),
              width: 32,
              height: 32,
              padding: EdgeInsets.zero,
              // Disabled with nothing selected, so it cannot open an empty menu.
              onPressed: hasSelection ? _popover.toggle : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin horizontal rule fencing one group of arrange actions from the next.
class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: ShadSeparator.horizontal(margin: EdgeInsets.zero),
    );
  }
}

/// A compact ghost icon button with a tooltip, sized for the command bar.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    this.buttonKey,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// When false the button renders disabled (a null `onPressed`), e.g. an Undo
  /// button at the start of history (US3.4).
  final bool enabled;

  /// Optional stable key on the inner button (test seam).
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // ~4px between adjacent buttons (2 + 2).
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ShadTooltip(
        builder: (BuildContext context) => Text(tooltip),
        // The tooltip is hover-only; expose it as the button's accessible name
        // too (the glyph alone is not announced) — FR-024 / SC-008.
        child: MergeSemantics(
          child: Semantics(
            label: tooltip,
            button: true,
            child: ShadIconButton.ghost(
              key: buttonKey,
              icon: Icon(icon, size: 16),
              width: 32,
              height: 32,
              padding: EdgeInsets.zero,
              onPressed: enabled ? onPressed : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// A view-toggle icon button: filled ([ShadIconButton.secondary]) while [active],
/// otherwise a plain ghost button, so its on/off state reads at a glance.
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.buttonKey,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final Widget glyph = Icon(icon, size: 16);
    return Padding(
      // ~4px between adjacent buttons (2 + 2).
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ShadTooltip(
        builder: (BuildContext context) => Text(tooltip),
        child: active
            ? ShadIconButton.secondary(
                key: buttonKey,
                icon: glyph,
                width: 32,
                height: 32,
                padding: EdgeInsets.zero,
                onPressed: onPressed,
              )
            : ShadIconButton.ghost(
                key: buttonKey,
                icon: glyph,
                width: 32,
                height: 32,
                padding: EdgeInsets.zero,
                onPressed: onPressed,
              ),
      ),
    );
  }
}

/// A labelled primary action (icon + caption) such as Open / Save. A null
/// `onPressed` renders it disabled (the host wired no callback).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;

  /// The action handler. A null handler renders the button disabled (e.g. Save
  /// when the host wired no `onSaveRequested`).
  final VoidCallback? onPressed;

  /// When true the label (and the dropdown chevron) are dropped and only the
  /// glyph shows, so the action fits a narrow bar; the tooltip still names it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // ~4px between adjacent buttons (2 + 2).
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ShadTooltip(
        builder: (BuildContext context) => Text(tooltip),
        // Expose the tooltip as the accessible name (the glyph alone is not
        // announced, and the compact variant has no visible label) — FR-024.
        child: MergeSemantics(
          child: Semantics(
            label: tooltip,
            button: true,
            child: compact
                ? ShadIconButton.ghost(
                    icon: Icon(icon, size: 16),
                    width: 32,
                    height: 32,
                    padding: EdgeInsets.zero,
                    onPressed: onPressed,
                  )
                : ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    leading: Icon(icon, size: 16),
                    onPressed: onPressed,
                    child: Text(label),
                  ),
          ),
        ),
      ),
    );
  }
}
