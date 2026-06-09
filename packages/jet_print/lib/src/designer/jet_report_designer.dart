import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../domain/report_template.dart';
import 'controller/jet_report_designer_controller.dart';
import 'designer_scope.dart';
import 'l10n/jet_print_localizations.dart';
import 'layout/designer_right_panel.dart';
import 'layout/designer_surface.dart';
import 'layout/designer_toolbox.dart';
import 'layout/designer_top_bar.dart';

/// Invoked when the user triggers Save; receives the current [ReportTemplate] to
/// persist. The library performs no file I/O itself (FR-022) — a host encodes it
/// (e.g. via `JetReportFormat.encodeJson`) and writes it.
typedef ReportSaveRequestedCallback = void Function(ReportTemplate current);

/// Invoked when the user triggers Open; a host reads a template (e.g. via
/// `JetReportFormat.decodeJson`) and calls `controller.open(...)`.
typedef ReportOpenRequestedCallback = void Function();

/// The report designer **shell**: the visual workspace that arranges the
/// regions of the designer — a top command bar, a left element toolbox, an
/// interactive center design surface, and a right three-tab context panel
/// (Data Source / Outline / Properties) — inside one theme-driven frame.
///
/// The center surface is a live WYSIWYG canvas: authors drag toolbox element
/// types onto bands, then select, move, resize, align, multi-select, reorder,
/// copy/paste, nudge, delete, and inline-edit text — every edit against an
/// in-memory [ReportTemplate] held by a [JetReportDesignerController], with
/// unlimited session undo/redo. Property editing this iteration is geometry +
/// text only (the full per-type suite is deferred).
///
/// Stays drop-in: with no arguments it owns an internal controller over a blank
/// default design, reading only the ambient [ShadTheme] and
/// [JetPrintLocalizations]. Supply a [controller] to own the model and drive
/// save/open (the library performs **no** file I/O itself — FR-022):
///
/// ```dart
/// final controller = JetReportDesignerController();
/// ShadApp(
///   localizationsDelegates: JetPrintLocalizations.localizationsDelegates,
///   supportedLocales: JetPrintLocalizations.supportedLocales,
///   home: JetReportDesigner(
///     controller: controller,
///     onSaveRequested: (ReportTemplate t) => writeFile(JetReportFormat.encodeJson(t)),
///     onOpenRequested: () async => controller.open(JetReportFormat.decodeJson(await readFile())),
///   ),
/// );
/// ```
class JetReportDesigner extends StatefulWidget {
  /// Creates the report designer. All parameters are optional; with none it
  /// owns an internal controller over a blank default design (so
  /// `const JetReportDesigner()` remains valid — the 002 contract).
  const JetReportDesigner({
    super.key,
    this.controller,
    this.initialReport,
    this.onSaveRequested,
    this.onOpenRequested,
  });

  /// An externally-owned controller. When provided, the host owns its lifecycle
  /// and [initialReport] is ignored.
  final JetReportDesignerController? controller;

  /// The design to seed an internally-created controller with (ignored when
  /// [controller] is given). Null seeds a blank default design.
  final ReportTemplate? initialReport;

  /// Invoked when the user triggers Save (wired to the top bar).
  final ReportSaveRequestedCallback? onSaveRequested;

  /// Invoked when the user triggers Open (wired to the top bar).
  final ReportOpenRequestedCallback? onOpenRequested;

  @override
  State<JetReportDesigner> createState() => _JetReportDesignerState();
}

class _JetReportDesignerState extends State<JetReportDesigner> {
  late JetReportDesignerController _controller;

  /// Whether this state created (and must dispose) [_controller]. A
  /// host-supplied controller is owned by the host.
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _adoptController();
  }

  @override
  void didUpdateWidget(JetReportDesigner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) _controller.dispose();
      _adoptController();
    }
  }

  void _adoptController() {
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = JetReportDesignerController(template: widget.initialReport);
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// Below this logical width the right panel collapses to an icon rail
  /// (FR-011). The left toolbox is already a compact icon strip and stays put.
  static const double _breakpoint = 1024;

  /// The shell's minimum usable width. Below it the whole shell is laid out at
  /// this width and scrolls horizontally instead of squeezing its fixed chrome
  /// (toolbox + rail + the dense top bar) past the point where it overflows.
  static const double _minShellWidth = 600;

  // Right-panel sizing in logical pixels; converted to the panel group's
  // fractional sizes against the live width so the minimum holds as the window
  // grows or shrinks (research D3).
  static const double _rightMinWidth = 280;
  static const double _rightDefaultWidth = 360;
  static const double _surfaceMinWidth = 360;

  // Narrow-window chrome.
  static const double _railWidth = 48;
  static const double _overlayWidth = 300;

  /// Whether the collapsed right panel is currently expanded as an overlay.
  bool _rightOpen = false;

  @override
  Widget build(BuildContext context) {
    // Share the controller with the canvas and panels so a change in any one
    // rebuilds the others (FR-018).
    return DesignerScope(
      controller: _controller,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget shell = _buildShell(context);
          if (constraints.maxWidth >= _minShellWidth) return shell;
          // Too narrow: lay the shell out at its minimum width and let the user
          // reach the off-screen edge by scrolling, rather than overflowing.
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _minShellWidth,
              height: constraints.maxHeight,
              child: shell,
            ),
          );
        },
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;

    return ColoredBox(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DesignerTopBar(
            key: _topBarKey,
            // Bridge the host callbacks to the top bar: Save hands over the
            // live template; Open just signals intent (the host reads + calls
            // controller.open). Null host callbacks ⇒ the actions render
            // disabled (the library performs no file I/O itself — FR-022).
            onSave: widget.onSaveRequested == null
                ? null
                : () => widget.onSaveRequested!(_controller.template),
            onOpen: widget.onOpenRequested,
          ),
          const ShadSeparator.horizontal(margin: EdgeInsets.zero),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth >= _breakpoint;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // The toolbox is a fixed icon strip in every layout.
                    const DesignerToolbox(key: _toolboxKey),
                    const ShadSeparator.vertical(margin: EdgeInsets.zero),
                    Expanded(
                      child: wide ? _buildWideMain() : _buildNarrowMain(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Desktop main area (≥ [_breakpoint]): a resizable surface and right panel,
  /// the surface absorbing the remaining width and the right panel honoring its
  /// minimum (FR-013).
  Widget _buildWideMain() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double rightMin = _rightMinWidth / width;
        final double rightDefault = _rightDefaultWidth / width;
        final double surfaceDefault = 1 - rightDefault;
        final double surfaceMin = _surfaceMinWidth / width;

        return ShadResizablePanelGroup(
          children: <ShadResizablePanel>[
            ShadResizablePanel(
              id: 'surface',
              defaultSize: surfaceDefault,
              minSize: surfaceMin,
              child: const DesignerSurface(key: _surfaceKey),
            ),
            ShadResizablePanel(
              id: 'right',
              defaultSize: rightDefault,
              minSize: rightMin,
              maxSize: 0.5,
              child: const DesignerRightPanel(key: _rightPanelKey),
            ),
          ],
        );
      },
    );
  }

  /// Narrow main area (< [_breakpoint]): the surface stays visible with the right
  /// panel collapsed to an icon rail; tapping the rail expands it as an overlay
  /// over the surface, and a collapse control returns it to a rail
  /// (FR-011/FR-014).
  Widget _buildNarrowMain() {
    return Stack(
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Expanded(child: DesignerSurface(key: _surfaceKey)),
            const ShadSeparator.vertical(margin: EdgeInsets.zero),
            _CollapsedRail(
              key: _rightPanelRailKey,
              icon: LucideIcons.panelRight,
              expandButtonKey: _rightPanelExpandKey,
              tooltip: JetPrintLocalizations.of(context).expandPanelTooltip,
              onExpand: () => setState(() => _rightOpen = true),
            ),
          ],
        ),
        if (_rightOpen)
          _OverlayRegion(
            width: _overlayWidth,
            tooltip: JetPrintLocalizations.of(context).collapsePanelTooltip,
            onCollapse: () => setState(() => _rightOpen = false),
            child: const DesignerRightPanel(key: _rightPanelKey),
          ),
      ],
    );
  }
}

/// A narrow vertical strip standing in for the collapsed right panel, with a
/// single ghost icon button that expands it (FR-014).
class _CollapsedRail extends StatelessWidget {
  const _CollapsedRail({
    required this.icon,
    required this.expandButtonKey,
    required this.tooltip,
    required this.onExpand,
    super.key,
  });

  final IconData icon;
  final Key expandButtonKey;
  final String tooltip;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return SizedBox(
      width: _JetReportDesignerState._railWidth,
      child: ColoredBox(
        color: colors.card,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            ShadTooltip(
              builder: (BuildContext context) => Text(tooltip),
              child: ShadIconButton.ghost(
                key: expandButtonKey,
                icon: Icon(icon),
                onPressed: onExpand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The expanded right panel drawn as a floating overlay over the surface in the
/// narrow layout, anchored to the right edge, with a collapse control.
class _OverlayRegion extends StatelessWidget {
  const _OverlayRegion({
    required this.width,
    required this.tooltip,
    required this.onCollapse,
    required this.child,
  });

  final double width;
  final String tooltip;
  final VoidCallback onCollapse;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.card,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.border,
              blurRadius: 12,
              offset: const Offset(-3, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: ShadTooltip(
                  builder: (BuildContext context) => Text(tooltip),
                  child: ShadIconButton.ghost(
                    icon: const Icon(LucideIcons.panelRightClose),
                    onPressed: onCollapse,
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

// --- Stable widget keys (the test seam; mirrored in
// test/designer/support/designer_harness.dart). They are private constants, not
// part of the public API. ---
const Key _topBarKey = ValueKey<String>('jet_print.designer.topBar');
const Key _toolboxKey = ValueKey<String>('jet_print.designer.toolbox');
const Key _surfaceKey = ValueKey<String>('jet_print.designer.surface');
const Key _rightPanelKey = ValueKey<String>('jet_print.designer.rightPanel');
const Key _rightPanelRailKey = ValueKey<String>(
  'jet_print.designer.rightPanelRail',
);
const Key _rightPanelExpandKey = ValueKey<String>(
  'jet_print.designer.rightPanelExpand',
);
