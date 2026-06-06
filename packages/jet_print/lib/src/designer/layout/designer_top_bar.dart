import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
  static const int _zoomStep = 10;
  static const int _zoomMin = 25;
  static const int _zoomMax = 400;

  int _zoom = 100;
  bool _grid = true;
  bool _ruler = true;
  bool _snap = false;

  void _nudgeZoom(int delta) {
    setState(() => _zoom = (_zoom + delta).clamp(_zoomMin, _zoomMax));
  }

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
              final Widget bar = _buildBar(context, compact: compact,
                  scrollable: scrollable);
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

      // History group.
      const _Divider(),
      _IconButton(
        icon: LucideIcons.undo2,
        tooltip: l10n.actionUndoTooltip,
        onPressed: () {},
      ),
      _IconButton(
        icon: LucideIcons.redo2,
        tooltip: l10n.actionRedoTooltip,
        onPressed: () {},
      ),

      // Zoom group.
      const _Divider(),
      _IconButton(
        icon: LucideIcons.zoomOut,
        tooltip: l10n.actionZoomOutTooltip,
        onPressed: () => _nudgeZoom(-_zoomStep),
      ),
      SizedBox(
        width: 40,
        child: Text(
          '$_zoom%',
          textAlign: TextAlign.center,
          style: theme.textTheme.small.copyWith(color: colors.foreground),
        ),
      ),
      _IconButton(
        icon: LucideIcons.zoomIn,
        tooltip: l10n.actionZoomInTooltip,
        onPressed: () => _nudgeZoom(_zoomStep),
      ),

      // View-toggle group.
      const _Divider(),
      _ToggleButton(
        icon: LucideIcons.grid2x2,
        tooltip: l10n.toggleGridTooltip,
        active: _grid,
        onPressed: () => setState(() => _grid = !_grid),
      ),
      _ToggleButton(
        icon: LucideIcons.ruler,
        tooltip: l10n.toggleRulerTooltip,
        active: _ruler,
        onPressed: () => setState(() => _ruler = !_ruler),
      ),
      _ToggleButton(
        icon: LucideIcons.magnet,
        tooltip: l10n.toggleSnapTooltip,
        active: _snap,
        onPressed: () => setState(() => _snap = !_snap),
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // ~4px between adjacent buttons (2 + 2).
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ShadTooltip(
        builder: (BuildContext context) => Text(tooltip),
        child: ShadIconButton.ghost(
          icon: Icon(icon, size: 16),
          width: 32,
          height: 32,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
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
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;

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
                icon: glyph,
                width: 32,
                height: 32,
                padding: EdgeInsets.zero,
                onPressed: onPressed,
              )
            : ShadIconButton.ghost(
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
