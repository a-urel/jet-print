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
export 'src/designer/jet_report_designer.dart' show JetReportDesigner;
// The generated localizations class carries its own `delegate` and
// `supportedLocales` statics; consumers wire them into their app shell.
export 'src/designer/l10n/jet_print_localizations.dart'
    show JetPrintLocalizations;
// --- The ReportTemplate-reachable model graph (003 — required to host, mutate,
// and serialize a design; supersedes the 002 "no model types" non-goal). ---
export 'src/domain/elements/barcode_element.dart'
    show BarcodeElement, BarcodeSymbology;
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
export 'src/domain/page_format.dart' show PageFormat;
export 'src/domain/report_band.dart' show BandType, ReportBand;
export 'src/domain/report_element.dart' show ReportElement;
export 'src/domain/report_group.dart' show ReportGroup;
export 'src/domain/report_parameter.dart' show ReportParameter;
export 'src/domain/report_template.dart' show ReportTemplate;
export 'src/domain/report_variable.dart'
    show JetCalculation, ReportVariable, VariableResetScope;
export 'src/domain/serialization/report_format.dart' show JetReportFormat;
export 'src/domain/serialization/report_format_exception.dart'
    show ReportFormatException;
export 'src/domain/styles/box_style.dart' show JetBoxStyle;
export 'src/domain/styles/color.dart' show JetColor;
export 'src/domain/styles/text_style.dart'
    show JetFontWeight, JetTextAlign, JetTextStyle;
export 'src/domain/unknown_element.dart' show UnknownElement;
export 'src/domain/value_type.dart' show JetFieldType;
// --- Render engine (011): fill a designed template with real data, paginate
// lazily, and surface structured render diagnostics. The preview widget
// consumes the resulting [RenderedReport]. ---
export 'src/rendering/engine/jet_report_engine.dart' show JetReportEngine;
export 'src/rendering/engine/render_options.dart' show RenderOptions;
export 'src/rendering/engine/rendered_report.dart'
    show RenderedPage, RenderedReport;
export 'src/rendering/fill/report_diagnostics.dart'
    show Diagnostic, DiagnosticSeverity, ReportDiagnostics;
export 'src/version.dart' show jetPrintVersion;
