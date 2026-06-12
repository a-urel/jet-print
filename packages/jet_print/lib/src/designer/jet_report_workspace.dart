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

import '../data/data_schema.dart';
import '../domain/report_template.dart';
import '../rendering/engine/rendered_report.dart';
import 'controller/jet_report_designer_controller.dart';
import 'jet_report_designer.dart';

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
  @override
  Widget build(BuildContext context) {
    return JetReportDesigner(
      controller: widget.controller,
      dataSchema: widget.dataSchema,
      onSaveRequested: widget.onSaveRequested,
      onOpenRequested: widget.onOpenRequested,
    );
  }
}
