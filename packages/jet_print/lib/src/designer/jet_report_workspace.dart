/// A keep-alive designer↔preview workspace (see
/// docs/superpowers/specs/2026-06-12-workspace-keep-alive-design.md).
///
/// Composes [JetReportDesigner] and [JetReportPreview] in an [IndexedStack] so
/// both stay mounted: switching modes is a pure visibility toggle (instant in
/// both directions, no canvas re-record). Entering preview renders the report
/// behind a loading indicator, caching it by template identity so an unedited
/// round trip is free.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/data_schema.dart';
import '../domain/report_template.dart';
import '../rendering/engine/rendered_report.dart';
import 'controller/jet_report_designer_controller.dart';
import 'jet_report_designer.dart';
import 'layout/unified_top_bar.dart';
import 'layout/workspace_mode_switch.dart';
import 'preview/jet_report_preview.dart';

/// Renders [template] into a [RenderedReport] for the preview. The host owns the
/// data source and render options; returning a `Future` lets a host render
/// off-thread without an API change (the workspace shows its loading indicator
/// until it completes).
typedef ReportRenderCallback = FutureOr<RenderedReport> Function(
    ReportTemplate template);

/// One workspace that hosts both the report designer and its preview, keeping
/// both alive so switching between them is instant.
///
/// ```dart
/// JetReportWorkspace(
///   controller: controller,
///   dataSchema: schema,
///   renderReport: (ReportTemplate t) =>
///       JetReportEngine().render(t, dataSource, options: options),
///   onSaveRequested: (ReportTemplate t) => write(JetReportFormat.encodeJson(t)),
///   onExportPdf: (RenderedReport r) => save(JetReportExporter().toPdf(r)),
/// );
/// ```
class JetReportWorkspace extends StatefulWidget {
  /// Creates the workspace over [controller], rendering the preview with
  /// [renderReport].
  const JetReportWorkspace({
    super.key,
    required this.controller,
    required this.renderReport,
    this.dataSchema,
    this.onSaveRequested,
    this.onOpenRequested,
    this.onExportPdf,
    this.onPrint,
    this.loadingBuilder,
  });

  /// The model + undo history shared with the designer canvas and panels.
  final JetReportDesignerController controller;

  /// Produces the [RenderedReport] shown in preview from the live template.
  final ReportRenderCallback renderReport;

  /// The data-source structure shown in the designer's Data Source panel.
  final JetDataSchema? dataSchema;

  /// Forwarded to the designer's Save action (the host persists the template).
  final ReportSaveRequestedCallback? onSaveRequested;

  /// Forwarded to the designer's Open action.
  final ReportOpenRequestedCallback? onOpenRequested;

  /// Invoked with the **current** rendered report when the preview's export
  /// action fires; null ⇒ no export action. The host performs the I/O.
  final ValueChanged<RenderedReport>? onExportPdf;

  /// Invoked with the **current** rendered report when the preview's print
  /// action fires; null ⇒ no print action.
  final ValueChanged<RenderedReport>? onPrint;

  /// Builds the indicator shown while a render is in flight; null ⇒ a themed
  /// indeterminate progress bar.
  final WidgetBuilder? loadingBuilder;

  @override
  State<JetReportWorkspace> createState() => _JetReportWorkspaceState();
}

class _JetReportWorkspaceState extends State<JetReportWorkspace> {
  /// The active mode; the workspace always opens in the designer.
  WorkspaceMode _mode = WorkspaceMode.designer;

  /// The most recent rendered report, or null before the first preview render
  /// completes. Kept across switches so re-entering preview is instant.
  RenderedReport? _report;

  /// The template identity [_report] was rendered from; an unchanged identity on
  /// the next preview entry means the cached report is still valid.
  ReportTemplate? _lastRendered;

  /// Whether a render is currently in flight (drives the loading indicator).
  bool _rendering = false;

  /// Monotonic render tag so a superseded async render cannot overwrite a newer
  /// result (mirrors the preview's own record-sequence guard).
  int _renderSeq = 0;

  void _enterPreview(ReportTemplate template) {
    setState(() => _mode = WorkspaceMode.preview);
    if (_report != null && identical(template, _lastRendered)) return;
    _startRender(template);
  }

  void _enterDesigner() => setState(() => _mode = WorkspaceMode.designer);

  Future<void> _startRender(ReportTemplate template) async {
    final int seq = ++_renderSeq;
    setState(() => _rendering = true);
    // Yield one frame so the loading indicator paints before a synchronous
    // render() blocks the UI thread (a zero-delay timer, not a microtask, so it
    // runs after the current frame is drawn).
    await Future<void>.delayed(Duration.zero);
    final RenderedReport report =
        await Future<RenderedReport>.sync(() => widget.renderReport(template));
    if (!mounted || seq != _renderSeq) return;
    setState(() {
      _report = report;
      _lastRendered = template;
      _rendering = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _mode == WorkspaceMode.designer ? 0 : 1,
      sizing: StackFit.expand,
      children: <Widget>[
        JetReportDesigner(
          controller: widget.controller,
          dataSchema: widget.dataSchema,
          onSaveRequested: widget.onSaveRequested,
          onOpenRequested: widget.onOpenRequested,
          onPreviewRequested: _enterPreview,
        ),
        _buildPreviewSlot(context),
      ],
    );
  }

  Widget _buildPreviewSlot(BuildContext context) {
    final bool active = _mode == WorkspaceMode.preview;
    final RenderedReport? report = _report;
    if (report == null) {
      // Before the first render completes. The animated indicator is built only
      // while preview is the active mode, so the offstage placeholder before any
      // preview never runs a perpetual ticker.
      return _LoadingScaffold(
        name: widget.controller.template.name,
        onSwitchToDesigner: _enterDesigner,
        showIndicator: active && _rendering,
        loadingBuilder: widget.loadingBuilder,
      );
    }
    final Widget preview = JetReportPreview(
      report: report,
      onBack: _enterDesigner,
      onExportPdf:
          widget.onExportPdf == null ? null : () => widget.onExportPdf!(report),
      onPrint: widget.onPrint == null ? null : () => widget.onPrint!(report),
    );
    if (!(active && _rendering)) return preview;
    // A re-render is in flight while the previous report is still visible: keep
    // the pages and overlay the indicator just under the toolbar (no blank flash).
    return Stack(
      children: <Widget>[
        preview,
        Positioned(
          left: 0,
          right: 0,
          top: UnifiedTopBar.height,
          child: widget.loadingBuilder?.call(context) ?? const _LoadingBar(),
        ),
      ],
    );
  }
}

/// The preview-mode chrome shown while the first report renders: the shared
/// toolbar (so the switch-back affordance is present) over an optional loading
/// bar.
class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold({
    required this.name,
    required this.onSwitchToDesigner,
    required this.showIndicator,
    this.loadingBuilder,
  });

  final String name;
  final VoidCallback onSwitchToDesigner;
  final bool showIndicator;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    return ColoredBox(
      color: colors.muted,
      child: Column(
        children: <Widget>[
          UnifiedTopBar(
            leadingIcon: LucideIcons.fileText,
            name: name,
            compactWidth: 880,
            scrollWidth: 880,
            center: WorkspaceModeSwitch(
              mode: WorkspaceMode.preview,
              onSwitchRequested: onSwitchToDesigner,
            ),
            actions: (BuildContext context, bool compact) => const <Widget>[],
          ),
          const ShadSeparator.horizontal(margin: EdgeInsets.zero),
          if (showIndicator) loadingBuilder?.call(context) ?? const _LoadingBar(),
        ],
      ),
    );
  }
}

/// The default loading indicator: a themed indeterminate progress bar.
class _LoadingBar extends StatelessWidget {
  const _LoadingBar();

  @override
  Widget build(BuildContext context) {
    return const ShadProgress(
      key: ValueKey<String>('jet_print.workspace.loading'),
    );
  }
}
