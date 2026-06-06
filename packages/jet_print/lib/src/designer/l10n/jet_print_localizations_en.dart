// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'jet_print_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class JetPrintLocalizationsEn extends JetPrintLocalizations {
  JetPrintLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get reportTitlePlaceholder => 'Untitled report';

  @override
  String get actionPreview => 'Preview';

  @override
  String get actionPreviewTooltip => 'Preview the report';

  @override
  String get actionSave => 'Save';

  @override
  String get actionSaveTooltip => 'Save the report';

  @override
  String get actionExport => 'Export';

  @override
  String get actionExportTooltip => 'Export the report';

  @override
  String get actionUndoTooltip => 'Undo';

  @override
  String get actionRedoTooltip => 'Redo';

  @override
  String get actionZoomInTooltip => 'Zoom in';

  @override
  String get actionZoomOutTooltip => 'Zoom out';

  @override
  String get toggleGridTooltip => 'Show grid';

  @override
  String get toggleRulerTooltip => 'Show rulers';

  @override
  String get toggleSnapTooltip => 'Snap to grid';

  @override
  String get tabDataSource => 'Data Source';

  @override
  String get tabOutline => 'Outline';

  @override
  String get tabProperties => 'Properties';

  @override
  String get toolboxTextEntry => 'Text';

  @override
  String get toolboxTableEntry => 'Table';

  @override
  String get toolboxImageEntry => 'Image';

  @override
  String get toolboxChartEntry => 'Chart';

  @override
  String get toolboxBarcodeEntry => 'Barcode';

  @override
  String get surfaceEmptyHint =>
      'Drag elements from the toolbox onto the page to begin.';

  @override
  String get expandToolboxTooltip => 'Expand toolbox';

  @override
  String get collapseToolboxTooltip => 'Collapse toolbox';

  @override
  String get expandPanelTooltip => 'Expand panel';

  @override
  String get collapsePanelTooltip => 'Collapse panel';
}
