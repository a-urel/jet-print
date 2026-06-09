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
  String get actionOpen => 'Open';

  @override
  String get actionOpenTooltip => 'Open a report';

  @override
  String get actionUndoTooltip => 'Undo';

  @override
  String get actionRedoTooltip => 'Redo';

  @override
  String get actionZoomInTooltip => 'Zoom in';

  @override
  String get actionZoomOutTooltip => 'Zoom out';

  @override
  String get actionZoomFitTooltip => 'Fit to width';

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
  String get toolboxShapeEntry => 'Shape';

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
  String get bandTypeTitle => 'Title';

  @override
  String get bandTypePageHeader => 'Page Header';

  @override
  String get bandTypeColumnHeader => 'Column Header';

  @override
  String get bandTypeGroupHeader => 'Group Header';

  @override
  String get bandTypeDetail => 'Detail';

  @override
  String get bandTypeGroupFooter => 'Group Footer';

  @override
  String get bandTypeColumnFooter => 'Column Footer';

  @override
  String get bandTypePageFooter => 'Page Footer';

  @override
  String get bandTypeSummary => 'Summary';

  @override
  String get bandTypeBackground => 'Background';

  @override
  String get bandTypeNoData => 'No Data';

  @override
  String get expandToolboxTooltip => 'Expand toolbox';

  @override
  String get collapseToolboxTooltip => 'Collapse toolbox';

  @override
  String get expandPanelTooltip => 'Expand panel';

  @override
  String get collapsePanelTooltip => 'Collapse panel';

  @override
  String get actionArrangeTooltip => 'Arrange';

  @override
  String get arrangeAlignLeft => 'Align left';

  @override
  String get arrangeAlignCenter => 'Align center';

  @override
  String get arrangeAlignRight => 'Align right';

  @override
  String get arrangeAlignTop => 'Align top';

  @override
  String get arrangeAlignMiddle => 'Align middle';

  @override
  String get arrangeAlignBottom => 'Align bottom';

  @override
  String get arrangeDistributeHorizontally => 'Distribute horizontally';

  @override
  String get arrangeDistributeVertically => 'Distribute vertically';

  @override
  String get arrangeBringToFront => 'Bring to front';

  @override
  String get arrangeBringForward => 'Bring forward';

  @override
  String get arrangeSendBackward => 'Send backward';

  @override
  String get arrangeSendToBack => 'Send to back';

  @override
  String get propertiesPosition => 'Position';

  @override
  String get propertiesSize => 'Size';

  @override
  String get propertiesText => 'Text';

  @override
  String get propertiesHeight => 'Height';

  @override
  String get propertiesPage => 'Page';

  @override
  String get propertiesMargins => 'Margins';

  @override
  String get reportLabel => 'Report';

  @override
  String get propertiesEmptyHint => 'Select an object to edit its properties.';

  @override
  String propertiesMultiSelected(int count) {
    return '$count elements selected';
  }

  @override
  String get elementTypeText => 'Text';

  @override
  String get elementTypeShape => 'Shape';

  @override
  String get elementTypeImage => 'Image';

  @override
  String get elementTypeBarcode => 'Barcode';

  @override
  String get elementTypeGeneric => 'Element';

  @override
  String elementSemanticLabel(String type, String id) {
    return '$type element $id';
  }

  @override
  String get resizeHandleTopLeft => 'Resize top-left corner';

  @override
  String get resizeHandleTop => 'Resize top edge';

  @override
  String get resizeHandleTopRight => 'Resize top-right corner';

  @override
  String get resizeHandleRight => 'Resize right edge';

  @override
  String get resizeHandleBottomRight => 'Resize bottom-right corner';

  @override
  String get resizeHandleBottom => 'Resize bottom edge';

  @override
  String get resizeHandleBottomLeft => 'Resize bottom-left corner';

  @override
  String get resizeHandleLeft => 'Resize left edge';

  @override
  String get resizeBandHandle => 'Resize band height';
}
