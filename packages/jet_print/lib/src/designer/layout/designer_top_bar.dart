import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../controller/jet_report_designer_controller.dart';
import '../designer_scope.dart';
import '../l10n/jet_print_localizations.dart';

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
  const DesignerTopBar({super.key});

  @override
  State<DesignerTopBar> createState() => _DesignerTopBarState();
}

class _DesignerTopBarState extends State<DesignerTopBar> {
  static const double _height = 52;

  bool _ruler = true;

  /// Below this width the labelled actions collapse to icon-only buttons and the
  /// title yields its space, so the dense command groups keep fitting.
  static const double _compactWidth = 920;

  /// Below this width even the compact bar can't fit, so it scrolls
  /// horizontally instead of overflowing.
  static const double _scrollWidth = 560;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;

    return ColoredBox(
      color: colors.card,
      child: SizedBox(
        height: _height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double width = constraints.maxWidth;
              final bool compact = width < _compactWidth;
              final bool scrollable = width < _scrollWidth;
              final Widget bar =
                  _buildBar(context, compact: compact, scrollable: scrollable);
              if (!scrollable) return bar;
              // Final safety net: keep every control reachable by scrolling
              // rather than overflowing at extreme widths.
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(height: _height, child: bar),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Builds the bar's content. When [scrollable] the children keep their natural
  /// width (no flex) so they can be scrolled; otherwise the left cluster expands
  /// to pin the primary actions to the right edge. When [compact] the title is
  /// dropped and the primary actions render icon-only.
  Widget _buildBar(
    BuildContext context, {
    required bool compact,
    required bool scrollable,
  }) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final JetReportDesignerController controller = DesignerScope.of(context);

    final List<Widget> leftChildren = <Widget>[
      const SizedBox(width: 4),
      Icon(LucideIcons.fileText, size: 18, color: colors.mutedForeground),
      const SizedBox(width: 10),
      // The title is the left cluster's only flexible child (when shown), so it
      // ellipsizes first; it is dropped entirely once compact to free room.
      if (!compact)
        Flexible(
          child: Text(
            l10n.reportTitlePlaceholder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.large.copyWith(color: colors.foreground),
          ),
        ),

      // History group — wired to the controller, disabled at the ends (US3.4).
      const _Divider(),
      _IconButton(
        buttonKey: const ValueKey<String>('jet_print.designer.action.undo'),
        icon: LucideIcons.undo2,
        tooltip: l10n.actionUndoTooltip,
        enabled: controller.canUndo,
        onPressed: controller.undo,
      ),
      _IconButton(
        buttonKey: const ValueKey<String>('jet_print.designer.action.redo'),
        icon: LucideIcons.redo2,
        tooltip: l10n.actionRedoTooltip,
        enabled: controller.canRedo,
        onPressed: controller.redo,
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
              key: const ValueKey<String>('jet_print.designer.action.zoomLevel'),
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
        buttonKey: const ValueKey<String>('jet_print.designer.toggle.grid'),
        icon: LucideIcons.grid2x2,
        tooltip: l10n.toggleGridTooltip,
        active: controller.gridEnabled,
        onPressed: () => controller.setGridEnabled(!controller.gridEnabled),
      ),
      _ToggleButton(
        icon: LucideIcons.ruler,
        tooltip: l10n.toggleRulerTooltip,
        active: _ruler,
        onPressed: () => setState(() => _ruler = !_ruler),
      ),
      _ToggleButton(
        buttonKey: const ValueKey<String>('jet_print.designer.toggle.snap'),
        icon: LucideIcons.magnet,
        tooltip: l10n.toggleSnapTooltip,
        active: controller.snapEnabled,
        onPressed: () => controller.setSnapEnabled(!controller.snapEnabled),
      ),
    ];

    final List<Widget> actions = <Widget>[
      const _Divider(),
      _ActionButton(
        icon: LucideIcons.eye,
        label: l10n.actionPreview,
        tooltip: l10n.actionPreviewTooltip,
        compact: compact,
      ),
      _ActionButton(
        icon: LucideIcons.save,
        label: l10n.actionSave,
        tooltip: l10n.actionSaveTooltip,
        compact: compact,
      ),
      _ActionButton(
        icon: LucideIcons.download,
        label: l10n.actionExport,
        tooltip: l10n.actionExportTooltip,
        trailing: LucideIcons.chevronDown,
        compact: compact,
      ),
    ];

    if (scrollable) {
      // No flex children: everything keeps its natural width so it can scroll.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[...leftChildren, ...actions],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: Row(children: leftChildren)),
        ...actions,
      ],
    );
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
        child: ShadIconButton.ghost(
          key: buttonKey,
          icon: Icon(icon, size: 16),
          width: 32,
          height: 32,
          padding: EdgeInsets.zero,
          onPressed: enabled ? onPressed : null,
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

/// A labelled primary action (icon + caption, optional [trailing] chevron for a
/// dropdown affordance). Its `onPressed` is a deliberate no-op this iteration
/// (FR-015) but it renders as enabled so the bar reads as a real toolbar.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.trailing,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final IconData? trailing;

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
        child: compact
            ? ShadIconButton.ghost(
                icon: Icon(icon, size: 16),
                width: 32,
                height: 32,
                padding: EdgeInsets.zero,
                onPressed: () {},
              )
            : ShadButton.ghost(
                size: ShadButtonSize.sm,
                leading: Icon(icon, size: 16),
                trailing: trailing == null ? null : Icon(trailing, size: 14),
                onPressed: () {},
                child: Text(label),
              ),
      ),
    );
  }
}
