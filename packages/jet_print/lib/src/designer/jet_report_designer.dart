import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/data_schema.dart';
import '../domain/report_definition.dart';
import '../rendering/text/font_registry.dart';
import '../rendering/text/jet_font.dart';
import 'controller/jet_report_designer_controller.dart';
import 'designer_font_scope.dart';
import 'designer_schema_scope.dart';
import 'designer_scope.dart';
import 'font_preload.dart';
import 'l10n/jet_print_localizations.dart';
import 'layout/designer_right_panel.dart';
import 'layout/designer_surface.dart';
import 'layout/designer_toolbox.dart';
import 'layout/designer_top_bar.dart';

/// Invoked when the user triggers Save; receives the current [ReportDefinition]
/// to persist. The library performs no file I/O itself (FR-022) — a host encodes
/// it (e.g. via `JetReportFormat.encodeDefinitionJson`) and writes it.
typedef ReportSaveRequestedCallback = void Function(ReportDefinition current);

/// Invoked when the user triggers Open; a host reads a definition (e.g. via
/// `JetReportFormat.decodeDefinitionJson`) and calls `controller.open(...)`.
typedef ReportOpenRequestedCallback = void Function();

/// Invoked when the user triggers Preview; receives the current
/// [ReportDefinition] so a host can render it (e.g. via `JetReportEngine`) and
/// show a `JetReportPreview`.
typedef ReportPreviewRequestedCallback = void Function(
    ReportDefinition current);

/// The report designer **shell**: the visual workspace that arranges the
/// regions of the designer — a top command bar, a left element toolbox, an
/// interactive center design surface, and a right three-tab context panel
/// (Data Source / Outline / Properties) — inside one theme-driven frame.
///
/// The center surface is a live WYSIWYG canvas: authors drag toolbox element
/// types onto bands, then select, move, resize, align, multi-select, reorder,
/// copy/paste, nudge, and delete — a double-tap on any element jumps to its
/// Properties inspector with the most relevant field focused. Every edit runs
/// against an in-memory [ReportTemplate] held by a
/// [JetReportDesignerController], with unlimited session undo/redo. Property
/// editing this iteration is geometry + text only (the full per-type suite is
/// deferred).
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
///     onSaveRequested: (ReportDefinition d) => writeFile(JetReportFormat.encodeDefinitionJson(d)),
///     onOpenRequested: () async => controller.open(JetReportFormat.decodeDefinitionJson(await readFile())),
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
    this.onPreviewRequested,
    this.dataSchema,
    this.fonts = const <JetFontFamily>[],
    this.showBuiltInFonts = true,
  });

  /// An externally-owned controller. When provided, the host owns its lifecycle
  /// and [initialReport] is ignored.
  final JetReportDesignerController? controller;

  /// The structure of the data source this design binds against (009), shown in
  /// the Data Source panel and used to resolve bindings. Null (the default)
  /// means no source is attached — the panel shows an empty state, and any
  /// existing element bindings still display their tokens (they are
  /// self-describing). Supplying or changing it never mutates the template.
  final JetDataSchema? dataSchema;

  /// The design to seed an internally-created controller with (ignored when
  /// [controller] is given). Null seeds a blank default design.
  final ReportDefinition? initialReport;

  /// Invoked when the user triggers Save (wired to the top bar).
  final ReportSaveRequestedCallback? onSaveRequested;

  /// Invoked when the user triggers Open (wired to the top bar).
  final ReportOpenRequestedCallback? onOpenRequested;

  /// Invoked when the user triggers Preview (wired to the top bar); receives
  /// the live template to render. Null ⇒ the Preview action renders disabled.
  final ReportPreviewRequestedCallback? onPreviewRequested;

  /// Host-contributed font families the designer makes selectable (022 / FR-002).
  ///
  /// Each face is the bytes the host hands in. They are added to the designer's
  /// one hoisted registry **after** the bundled defaults
  /// (last-registration-wins), so the family picker lists them after the
  /// built-ins (previewed in their own typeface) and the canvas measures and
  /// paints with them. Register **before** building the designer; the empty
  /// default keeps the designer built-ins-only (SC-005).
  ///
  /// Pass the **same** `List<JetFontFamily>` here and to `RenderOptions.fonts`
  /// (the render the preview/export consume) so design == preview == export.
  final List<JetFontFamily> fonts;

  /// Whether the bundled built-in Default family appears as a selectable
  /// option in the family picker (022). Defaults to `true`. Set
  /// `false` when you supply your own [fonts] catalog and want only those
  /// offered — Default still resolves as the silent render fallback, so text
  /// with no/unknown family always renders; it is just hidden from the picker.
  final bool showBuiltInFonts;

  @override
  State<JetReportDesigner> createState() => _JetReportDesignerState();
}

class _JetReportDesignerState extends State<JetReportDesigner> {
  late JetReportDesignerController _controller;

  /// The designer's ONE font registry, hoisted here (021 / research §1) so the
  /// canvas frame builder and the Properties panel's family picker share the
  /// same family set — what the picker offers is exactly what the canvas
  /// measures and paints with. The bundled defaults first, then the host
  /// [JetReportDesigner.fonts] (022, last-registration-wins).
  final FontRegistry _fonts = FontRegistry()..registerDefault();

  /// Whether this state created (and must dispose) [_controller]. A
  /// host-supplied controller is owned by the host.
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    // Layer the host families on top of the bundled defaults (022 / FR-002),
    // last-registration-wins — before any build, so the picker and canvas see
    // them and `preloadUiFontFamilies` below previews them in their own type.
    _fonts.registerHostFonts(widget.fonts);
    _adoptController();
    // Make every registered family's Regular face available to the engine up
    // front, so the family picker previews each option in its own typeface
    // even before the canvas has painted that family. Fire-and-forget: when a
    // face lands, the engine's system-fonts notification re-renders text.
    unawaited(preloadUiFontFamilies(_fonts));
  }

  @override
  void didUpdateWidget(JetReportDesigner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_handlePropertiesFocusRequest);
      if (_ownsController) _controller.dispose();
      _adoptController();
    }
  }

  void _adoptController() {
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller =
          JetReportDesignerController(definition: widget.initialReport);
      _ownsController = true;
    }
    _controller.addListener(_handlePropertiesFocusRequest);
  }

  @override
  void dispose() {
    _controller.removeListener(_handlePropertiesFocusRequest);
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

  /// Whether the last laid-out main area was the wide (≥ breakpoint) variant;
  /// written during build, read by [_handlePropertiesFocusRequest] so a focus
  /// request only opens the overlay when the panel is actually collapsed.
  /// Starts false so a request arriving before the first layout is never
  /// dropped: a spurious early open is harmless in the wide layout (which
  /// ignores [_rightOpen]), while the reverse would silently lose the request.
  bool _lastLayoutWide = false;

  /// Opens the collapsed narrow-layout overlay when a Properties-focus request
  /// arrives, so the panel that must consume it can mount. Peeks only — the
  /// Properties panel consumes the request.
  void _handlePropertiesFocusRequest() {
    if (_lastLayoutWide || _rightOpen) return;
    if (!_controller.pendingPropertiesFocus) return;
    setState(() => _rightOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    // Share the controller with the canvas and panels so a change in any one
    // rebuilds the others (FR-018), and the attached data-source structure (009)
    // so the panels can display it and resolve bindings.
    return DesignerSchemaScope(
      dataSchema: widget.dataSchema,
      child: DesignerFontScope(
        fonts: _fonts,
        showBuiltIns: widget.showBuiltInFonts,
        child: DesignerScope(
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
        ),
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
                : () => widget.onSaveRequested!(_controller.definition),
            onOpen: widget.onOpenRequested,
            onPreview: widget.onPreviewRequested == null
                ? null
                : () => widget.onPreviewRequested!(_controller.definition),
          ),
          const ShadSeparator.horizontal(margin: EdgeInsets.zero),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth >= _breakpoint;
                _lastLayoutWide = wide;
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
