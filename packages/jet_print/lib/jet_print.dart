/// jet_print — a layered, theme-aware Flutter widget library for building
/// WYSIWYG report designers.
///
/// This is the library's **single public entry point**. Consumers import only:
///
/// ```dart
/// import 'package:jet_print/jet_print.dart';
/// ```
///
/// Everything under `lib/src/` is private implementation detail and is never
/// importable through a `package:jet_print/src/...` path. The intentional,
/// documented public surface is re-exported from here.
///
/// The public surface for this iteration: the version constant, a theme-aware
/// placeholder widget, the report-designer shell ([JetReportDesigner]), and the
/// library's own localization delegate ([JetPrintLocalizations]). See
/// `contracts/designer-layout-api.md` for the authoritative contract.
library;

// --- Data-source API (009 structure + 011 data): the host describes its data
// source's structure as a [JetDataSchema] of [FieldDef]s (a field may be a
// nested [JetFieldType.collection]) and, since 011, supplies actual records
// through a [JetDataSource] (in-memory, JSON, or object-backed) whose
// [DataSet] cursor yields [DataRow]s — including nested collections for
// master/detail. ---
export 'src/data/data_row.dart' show DataRow;
export 'src/data/data_schema.dart' show JetDataSchema;
export 'src/data/data_set.dart' show DataSet;
export 'src/data/field_def.dart' show FieldDef;
export 'src/data/in_memory_data_source.dart' show JetInMemoryDataSource;
export 'src/data/jet_data_source.dart' show JetDataSource;
export 'src/data/json_data_source.dart' show JetJsonDataSource;
export 'src/data/object_data_source.dart' show JetObjectDataSource;
// --- Interactive editing seam (003): the controller + its public vocabulary. ---
export 'src/designer/canvas/design_tunables.dart' show DesignerToolType;
export 'src/designer/canvas/resize_handle.dart' show ResizeHandle;
export 'src/designer/controller/bulk_geometry.dart'
    show AlignKind, DistributeAxis;
export 'src/designer/controller/commands/reorder_command.dart' show ReorderMode;
export 'src/designer/controller/jet_report_designer_controller.dart'
    show JetReportDesignerController;
export 'src/designer/controller/selection.dart' show Selection;
export 'src/designer/jet_print_placeholder.dart' show JetPrintPlaceholder;
export 'src/designer/jet_report_designer.dart'
    show
        JetReportDesigner,
        ReportSaveRequestedCallback,
        ReportOpenRequestedCallback,
        ReportPreviewRequestedCallback;
export 'src/designer/jet_report_workspace.dart'
    show JetReportWorkspace, ReportRenderCallback;
// The generated localizations class carries its own `delegate` and
// `supportedLocales` statics; consumers wire them into their app shell.
export 'src/designer/l10n/jet_print_localizations.dart'
    show JetPrintLocalizations;
// The read-only paginated viewer over a rendered report (011).
export 'src/designer/preview/jet_report_preview.dart' show JetReportPreview;
// --- The reified section tree (024) — the public report model. The explicit,
// id'd tree — Band / DetailScope+ScopeNode / GroupLevel / ReportDefinition
// (PageFurniture + ReportBody) — plus author-time `validate()`, which returns
// the same [Diagnostic] type the render chain uses. BandType names a band's
// role. ---
export 'src/domain/band.dart' show Band;
export 'src/domain/column_layout.dart' show ColumnLayout;
export 'src/domain/detail_scope.dart'
    show BandNode, DetailScope, NestedScope, ScopeNode;
export 'src/domain/elements/barcode_element.dart'
    show BarcodeElement, BarcodeSymbology, QrErrorCorrectionLevel;
export 'src/domain/elements/image_element.dart' show ImageElement;
export 'src/domain/elements/image_source.dart'
    show
        BytesImageSource,
        FieldImageSource,
        JetBoxFit,
        JetImageSource,
        UrlImageSource;
export 'src/domain/elements/shape_element.dart' show ShapeElement, ShapeKind;
export 'src/domain/elements/text_element.dart' show TextElement;
export 'src/domain/geometry.dart'
    show JetEdgeInsets, JetOffset, JetRect, JetSize;
export 'src/domain/group_level.dart' show GroupLevel;
export 'src/domain/page_format.dart' show PageFormat;
export 'src/domain/report_band.dart' show BandType;
export 'src/domain/report_definition.dart'
    show PageFurniture, ReportBody, ReportDefinition;
export 'src/domain/report_element.dart' show ReportElement;
export 'src/domain/report_parameter.dart' show ReportParameter;
export 'src/domain/report_validation.dart' show validate;
export 'src/domain/report_variable.dart'
    show JetCalculation, ReportVariable, VariableResetScope;
export 'src/domain/scope_total.dart' show ScopeTotal;
export 'src/domain/serialization/report_format.dart' show JetReportFormat;
export 'src/domain/serialization/report_format_exception.dart'
    show ReportFormatException;
export 'src/domain/styles/box_style.dart' show JetBoxStyle;
export 'src/domain/styles/color.dart' show JetColor;
export 'src/domain/styles/text_style.dart'
    show JetFontWeight, JetTextAlign, JetTextStyle;
export 'src/domain/unknown_element.dart' show UnknownElement;
export 'src/domain/value_type.dart' show JetFieldType;
// --- Print (012): present the system print dialog for the exported PDF —
// the one sanctioned exception to the library's headlessness. The presenter
// seam is injectable; unavailability is a structured exception. ---
export 'src/print/jet_report_printer.dart'
    show JetReportPrinter, PrintDialogPresenter, PrintUnavailableException;
// --- Render engine (011): fill a designed template with real data, paginate
// lazily, and surface structured render diagnostics. The preview widget
// consumes the resulting [RenderedReport]. ---
export 'src/rendering/engine/jet_report_engine.dart' show JetReportEngine;
export 'src/rendering/engine/render_options.dart' show RenderOptions;
export 'src/rendering/engine/rendered_report.dart'
    show RenderedPage, RenderedReport;
// --- Export (012): turn the same RenderedReport the preview displays into
// shareable artifacts — a deterministic PDF document with real selectable
// text and embedded fonts. Headless: bytes in, bytes out; the host owns
// saving/sharing. ---
export 'src/rendering/export/jet_report_exporter.dart' show JetReportExporter;
export 'src/rendering/fill/report_diagnostics.dart'
    show Diagnostic, DiagnosticSeverity, ReportDiagnostics;
// --- Host fonts (022): the bytes-in value types a host uses to contribute its
// own fonts, plus the (now-public) exception their eager validation throws.
// `FontRegistry` stays internal — the render chain carries it. Pass the same
// `List<JetFontFamily>` to `JetReportDesigner`/`JetReportWorkspace.fonts` and
// to `RenderOptions.fonts`. ---
export 'src/rendering/text/font_format_exception.dart' show FontFormatException;
export 'src/rendering/text/jet_font.dart' show JetFontFace, JetFontFamily;
export 'src/version.dart' show jetPrintVersion;
