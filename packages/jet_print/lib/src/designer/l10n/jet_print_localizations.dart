import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'jet_print_localizations_de.dart';
import 'jet_print_localizations_en.dart';
import 'jet_print_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of JetPrintLocalizations
/// returned by `JetPrintLocalizations.of(context)`.
///
/// Applications need to include `JetPrintLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/jet_print_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: JetPrintLocalizations.localizationsDelegates,
///   supportedLocales: JetPrintLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the JetPrintLocalizations.supportedLocales
/// property.
abstract class JetPrintLocalizations {
  JetPrintLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static JetPrintLocalizations of(BuildContext context) {
    return Localizations.of<JetPrintLocalizations>(
        context, JetPrintLocalizations)!;
  }

  static const LocalizationsDelegate<JetPrintLocalizations> delegate =
      _JetPrintLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('de'),
    Locale('tr')
  ];

  /// Placeholder report name shown in the designer top bar before a report is named.
  ///
  /// In en, this message translates to:
  /// **'Untitled report'**
  String get reportTitlePlaceholder;

  /// Top-bar action: open a print preview of the report. Non-functional placeholder this iteration.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get actionPreview;

  /// Tooltip for the Preview top-bar action.
  ///
  /// In en, this message translates to:
  /// **'Preview the report'**
  String get actionPreviewTooltip;

  /// Top-bar action: save the report. Non-functional placeholder this iteration.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// Tooltip for the Save top-bar action.
  ///
  /// In en, this message translates to:
  /// **'Save the report'**
  String get actionSaveTooltip;

  /// Top-bar action: export the report. Non-functional placeholder this iteration.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get actionExport;

  /// Tooltip for the Export top-bar action.
  ///
  /// In en, this message translates to:
  /// **'Export the report'**
  String get actionExportTooltip;

  /// Top-bar action: open a saved report from a file (wired to the host's onOpenRequested).
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// Tooltip for the Open top-bar action.
  ///
  /// In en, this message translates to:
  /// **'Open a report'**
  String get actionOpenTooltip;

  /// Tooltip for the Undo top-bar icon button (history group).
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndoTooltip;

  /// Tooltip for the Redo top-bar icon button (history group).
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get actionRedoTooltip;

  /// Tooltip for the Zoom in top-bar icon button (zoom group).
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get actionZoomInTooltip;

  /// Tooltip for the Zoom out top-bar icon button (zoom group).
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get actionZoomOutTooltip;

  /// Tooltip for the zoom-level label, which fits the page to the viewport width when tapped.
  ///
  /// In en, this message translates to:
  /// **'Fit to width'**
  String get actionZoomFitTooltip;

  /// Tooltip for the grid view-toggle in the top bar.
  ///
  /// In en, this message translates to:
  /// **'Show grid'**
  String get toggleGridTooltip;

  /// Tooltip for the rulers view-toggle in the top bar.
  ///
  /// In en, this message translates to:
  /// **'Show rulers'**
  String get toggleRulerTooltip;

  /// Tooltip for the snap-to-grid view-toggle in the top bar.
  ///
  /// In en, this message translates to:
  /// **'Snap to grid'**
  String get toggleSnapTooltip;

  /// Label for the Cut clipboard action — toolbar tooltip and context-menu item. The keyboard-shortcut hint (e.g. ⌘X / Ctrl+X) is composed in code, not in this string.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get actionCutTooltip;

  /// Label for the Copy clipboard action — toolbar tooltip and context-menu item. The keyboard-shortcut hint (e.g. ⌘C / Ctrl+C) is composed in code, not in this string.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopyTooltip;

  /// Label for the Paste clipboard action — toolbar tooltip and context-menu item. The keyboard-shortcut hint (e.g. ⌘V / Ctrl+V) is composed in code, not in this string.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get actionPasteTooltip;

  /// Context-menu item: duplicate the selection in place (fresh ids, offset copy). Menu-only; the shortcut hint (⌘D / Ctrl+D) is composed in code.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get menuDuplicate;

  /// Context-menu item: delete the selection. Menu-only; the Delete-key hint has no modifier glyph.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get menuDelete;

  /// Right-panel tab caption for the data source / fields panel (default-active tab).
  ///
  /// In en, this message translates to:
  /// **'Data Source'**
  String get tabDataSource;

  /// Right-panel tab caption for the report outline / element tree panel.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get tabOutline;

  /// Right-panel tab caption for the properties panel.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get tabProperties;

  /// Data Source panel empty state shown when no data-source structure is attached to the designer (009).
  ///
  /// In en, this message translates to:
  /// **'No data source attached.'**
  String get dataSourceEmpty;

  /// Toolbox element: a static or data-bound text element. Shown as an icon-button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get toolboxTextEntry;

  /// Toolbox element: a line or rectangle shape element.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get toolboxShapeEntry;

  /// Toolbox element: a tabular layout element.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get toolboxTableEntry;

  /// Toolbox element: a picture / logo element.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get toolboxImageEntry;

  /// Toolbox element: a chart / graph element.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get toolboxChartEntry;

  /// Toolbox element: a barcode / QR element.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get toolboxBarcodeEntry;

  /// Hint shown on the empty design surface page so it never reads as a blank void.
  ///
  /// In en, this message translates to:
  /// **'Drag elements from the toolbox onto the page to begin.'**
  String get surfaceEmptyHint;

  /// Caption on the design-surface badge for a Title band (printed once at the report start).
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get bandTypeTitle;

  /// Caption on the design-surface badge for a Page Header band (repeated atop every page).
  ///
  /// In en, this message translates to:
  /// **'Page Header'**
  String get bandTypePageHeader;

  /// Caption on the design-surface badge for a Column Header band.
  ///
  /// In en, this message translates to:
  /// **'Column Header'**
  String get bandTypeColumnHeader;

  /// Caption on the design-surface badge for a Group Header band (printed when a group key changes).
  ///
  /// In en, this message translates to:
  /// **'Group Header'**
  String get bandTypeGroupHeader;

  /// Caption on the design-surface badge for a Detail band (repeated once per data row).
  ///
  /// In en, this message translates to:
  /// **'Detail'**
  String get bandTypeDetail;

  /// Caption on the design-surface badge for a Group Footer band (printed when a group ends).
  ///
  /// In en, this message translates to:
  /// **'Group Footer'**
  String get bandTypeGroupFooter;

  /// Caption on the design-surface badge for a Column Footer band.
  ///
  /// In en, this message translates to:
  /// **'Column Footer'**
  String get bandTypeColumnFooter;

  /// Caption on the design-surface badge for a Page Footer band (repeated at the bottom of every page).
  ///
  /// In en, this message translates to:
  /// **'Page Footer'**
  String get bandTypePageFooter;

  /// Caption on the design-surface badge for a Summary band (printed once at the report end).
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get bandTypeSummary;

  /// Caption on the design-surface badge for a Background band (drawn behind every page).
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get bandTypeBackground;

  /// Caption on the design-surface badge for a No Data band (printed instead of details when the data set is empty).
  ///
  /// In en, this message translates to:
  /// **'No Data'**
  String get bandTypeNoData;

  /// Tooltip on the collapsed toolbox rail's expand button (narrow window).
  ///
  /// In en, this message translates to:
  /// **'Expand toolbox'**
  String get expandToolboxTooltip;

  /// Tooltip on the expanded toolbox overlay's collapse button (narrow window).
  ///
  /// In en, this message translates to:
  /// **'Collapse toolbox'**
  String get collapseToolboxTooltip;

  /// Tooltip on the collapsed right-panel rail's expand button (narrow window).
  ///
  /// In en, this message translates to:
  /// **'Expand panel'**
  String get expandPanelTooltip;

  /// Tooltip on the expanded right-panel overlay's collapse button (narrow window).
  ///
  /// In en, this message translates to:
  /// **'Collapse panel'**
  String get collapsePanelTooltip;

  /// Accessible name / tooltip for the top-bar Arrange menu button (align, distribute and z-order actions).
  ///
  /// In en, this message translates to:
  /// **'Arrange'**
  String get actionArrangeTooltip;

  /// Arrange menu: align the selection's left edges.
  ///
  /// In en, this message translates to:
  /// **'Align left'**
  String get arrangeAlignLeft;

  /// Arrange menu: center the selection horizontally.
  ///
  /// In en, this message translates to:
  /// **'Align center'**
  String get arrangeAlignCenter;

  /// Arrange menu: align the selection's right edges.
  ///
  /// In en, this message translates to:
  /// **'Align right'**
  String get arrangeAlignRight;

  /// Arrange menu: align the selection's top edges.
  ///
  /// In en, this message translates to:
  /// **'Align top'**
  String get arrangeAlignTop;

  /// Arrange menu: center the selection vertically.
  ///
  /// In en, this message translates to:
  /// **'Align middle'**
  String get arrangeAlignMiddle;

  /// Arrange menu: align the selection's bottom edges.
  ///
  /// In en, this message translates to:
  /// **'Align bottom'**
  String get arrangeAlignBottom;

  /// Arrange menu: space the selection evenly along the horizontal axis.
  ///
  /// In en, this message translates to:
  /// **'Distribute horizontally'**
  String get arrangeDistributeHorizontally;

  /// Arrange menu: space the selection evenly along the vertical axis.
  ///
  /// In en, this message translates to:
  /// **'Distribute vertically'**
  String get arrangeDistributeVertically;

  /// Arrange menu: move the selection to the very front of the z-order.
  ///
  /// In en, this message translates to:
  /// **'Bring to front'**
  String get arrangeBringToFront;

  /// Arrange menu: move the selection one step toward the front.
  ///
  /// In en, this message translates to:
  /// **'Bring forward'**
  String get arrangeBringForward;

  /// Arrange menu: move the selection one step toward the back.
  ///
  /// In en, this message translates to:
  /// **'Send backward'**
  String get arrangeSendBackward;

  /// Arrange menu: move the selection to the very back of the z-order.
  ///
  /// In en, this message translates to:
  /// **'Send to back'**
  String get arrangeSendToBack;

  /// Properties panel section label for the element's X/Y position.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get propertiesPosition;

  /// Properties panel section label for the element's width/height (also the report page size).
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get propertiesSize;

  /// Properties panel section label for a text element's content.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get propertiesText;

  /// Properties panel section label for a text element's unified value (literal text or a [field]/{ … } binding) (013).
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get propertiesValue;

  /// Placeholder for the unified value input — a [field] token, a { … } template, or literal text (013).
  ///
  /// In en, this message translates to:
  /// **'[field] or text'**
  String get valueFieldHint;

  /// Accessible label / tooltip for the value input's suffix button that opens the data-source field picker.
  ///
  /// In en, this message translates to:
  /// **'Insert a data field'**
  String get valueFieldPickerTooltip;

  /// Properties panel section label for a text element's number/date display format (013).
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get propertiesFormat;

  /// Placeholder for the format input (an ICU number/date pattern) (013).
  ///
  /// In en, this message translates to:
  /// **'e.g. #,##0.00'**
  String get formatHint;

  /// Accessible label/tooltip for the Format field's preset-picker suffix button (013).
  ///
  /// In en, this message translates to:
  /// **'Choose a format preset'**
  String get formatPresetPickerTooltip;

  /// Format preset that clears the format (unformatted) (013).
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get formatPresetNone;

  /// Format preset for a grouped integer, e.g. 1,234 (013).
  ///
  /// In en, this message translates to:
  /// **'Integer'**
  String get formatPresetInteger;

  /// Format preset for a grouped number with two decimals, e.g. 1,234.50 (013).
  ///
  /// In en, this message translates to:
  /// **'Decimal'**
  String get formatPresetDecimal;

  /// Format preset for a currency amount (013).
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get formatPresetCurrency;

  /// Format preset for a percentage (013).
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get formatPresetPercent;

  /// Format preset for a date, e.g. 2026-06-11 (013).
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get formatPresetDate;

  /// Format preset for a date and time, e.g. 2026-06-11 14:30 (013).
  ///
  /// In en, this message translates to:
  /// **'Date & time'**
  String get formatPresetDateTime;

  /// Rendered in place of a binding whose field is not in the data source (013 / FR-007).
  ///
  /// In en, this message translates to:
  /// **'#ERROR'**
  String get errorUnresolvedToken;

  /// Properties panel section label for an element's data binding (009).
  ///
  /// In en, this message translates to:
  /// **'Binding'**
  String get propertiesBinding;

  /// Properties panel section label for the selected group band's group settings (023).
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get propertiesGroup;

  /// Properties panel toggle label: start each group instance on a new page (023).
  ///
  /// In en, this message translates to:
  /// **'Start on new page'**
  String get propertiesGroupNewPage;

  /// Properties panel label for a group's grouping-key expression (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Group key'**
  String get propertiesGroupKey;

  /// Properties panel toggle label: keep a group's whole instance on one page (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Keep together'**
  String get propertiesGroupKeepTogether;

  /// Properties panel toggle label: reprint a group header atop each continuation page (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Reprint header on each page'**
  String get propertiesGroupReprintHeader;

  /// Read-only hint shown when the group row is selected, pointing the author to the group header band where the key + pagination flags are edited (2026-06-14 design note).
  ///
  /// In en, this message translates to:
  /// **'Edit page & group settings on the group header band.'**
  String get propertiesGroupOnHeaderHint;

  /// Properties panel header label for a selected detail scope (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get propertiesScope;

  /// Outline row action: move a per-row band up within its scope (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get outlineMoveUp;

  /// Outline row action: move a per-row band down within its scope (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get outlineMoveDown;

  /// Outline row action: remove a band (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Remove band'**
  String get outlineRemove;

  /// Outline row action: relocate a band to a different slot, changing its type (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Change band type'**
  String get outlineRetype;

  /// Outline row action: add a per-row band to a scope (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Add band'**
  String get outlineAddBand;

  /// Outline row action: add a group header band (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Add header'**
  String get outlineAddHeader;

  /// Outline row action: add a group footer band (spec 024).
  ///
  /// In en, this message translates to:
  /// **'Add footer'**
  String get outlineAddFooter;

  /// Placeholder for the text binding input (a field reference or a full expression).
  ///
  /// In en, this message translates to:
  /// **'Field or expression'**
  String get bindingExpressionHint;

  /// Placeholder for the image binding input (the data field supplying the picture).
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get bindingImageFieldHint;

  /// Accessible name / tooltip for the button that clears an element's data binding.
  ///
  /// In en, this message translates to:
  /// **'Clear binding'**
  String get bindingClearTooltip;

  /// Placeholder for the band collection-binding input (the nested-collection field this band iterates, for master/detail).
  ///
  /// In en, this message translates to:
  /// **'Collection field'**
  String get bindingCollectionHint;

  /// Accessible name / tooltip for the suffix button that opens a menu of in-scope data fields to fill a binding input.
  ///
  /// In en, this message translates to:
  /// **'Select a field'**
  String get bindingFieldPickerTooltip;

  /// Shown under a binding whose field is missing from, or out of scope in, the attached data source (009).
  ///
  /// In en, this message translates to:
  /// **'Field not found in the data source'**
  String get bindingUnresolved;

  /// Properties panel field label for a band's height.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get propertiesHeight;

  /// Properties panel section label for the report page information.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get propertiesPage;

  /// Properties panel read-only field label for the report page margins.
  ///
  /// In en, this message translates to:
  /// **'Margins'**
  String get propertiesMargins;

  /// Properties panel label for the paper-size picker in the PAGE section (018).
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get propertiesPaper;

  /// Paper-size / margin value shown when the page matches no standard preset (018).
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get propertiesCustom;

  /// Properties panel field label for a custom page width (018).
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get propertiesWidth;

  /// Accessible label for the paper-size picker button (018).
  ///
  /// In en, this message translates to:
  /// **'Choose a paper size'**
  String get paperPickerTooltip;

  /// Page orientation: taller than wide (018).
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get orientationPortrait;

  /// Page orientation: wider than tall (018).
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get orientationLandscape;

  /// Margin preset name: the ~1 cm default on all four sides (018).
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get marginPresetNormal;

  /// Margin preset name: ~0.5 cm on all four sides (018).
  ///
  /// In en, this message translates to:
  /// **'Narrow'**
  String get marginPresetNarrow;

  /// Margin preset name: ~2 cm on all four sides (018).
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get marginPresetWide;

  /// Margin preset name: zero margins, flush to the page edge (018).
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get marginPresetNone;

  /// Accessible label for the margin-preset picker button (018).
  ///
  /// In en, this message translates to:
  /// **'Choose margins'**
  String get marginPickerTooltip;

  /// Properties panel field label for the left page margin (018).
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get propertiesMarginLeft;

  /// Properties panel field label for the top page margin (018).
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get propertiesMarginTop;

  /// Properties panel field label for the right page margin (018).
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get propertiesMarginRight;

  /// Properties panel field label for the bottom page margin (018).
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get propertiesMarginBottom;

  /// The report root: the Outline tree root row and the Properties panel header when the report itself is selected.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportLabel;

  /// Properties panel section label for the report's primary Name property (the report/template name).
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get propertiesName;

  /// Placeholder shown in the report Name field when the report has no name yet.
  ///
  /// In en, this message translates to:
  /// **'Report name'**
  String get reportNameHint;

  /// Properties panel empty state shown when nothing is selected.
  ///
  /// In en, this message translates to:
  /// **'Select an object to edit its properties.'**
  String get propertiesEmptyHint;

  /// Properties panel state shown when several elements are selected at once.
  ///
  /// In en, this message translates to:
  /// **'{count} elements selected'**
  String propertiesMultiSelected(int count);

  /// Element type name (accessibility / outline) for a text element.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get elementTypeText;

  /// Element type name (accessibility / outline) for a shape element.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get elementTypeShape;

  /// Element type name (accessibility / outline) for an image element.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get elementTypeImage;

  /// Element type name (accessibility / outline) for a barcode element.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get elementTypeBarcode;

  /// Element type name (accessibility / outline) fallback for an unknown element type.
  ///
  /// In en, this message translates to:
  /// **'Element'**
  String get elementTypeGeneric;

  /// Accessible name for an element's hit region on the canvas, e.g. 'Text element heading1'.
  ///
  /// In en, this message translates to:
  /// **'{type} element {id}'**
  String elementSemanticLabel(String type, String id);

  /// Accessible name for the top-left element resize handle.
  ///
  /// In en, this message translates to:
  /// **'Resize top-left corner'**
  String get resizeHandleTopLeft;

  /// Accessible name for the top-edge element resize handle.
  ///
  /// In en, this message translates to:
  /// **'Resize top edge'**
  String get resizeHandleTop;

  /// Accessible name for the top-right element resize handle.
  ///
  /// In en, this message translates to:
  /// **'Resize top-right corner'**
  String get resizeHandleTopRight;

  /// Accessible name for the right-edge element resize handle.
  ///
  /// In en, this message translates to:
  /// **'Resize right edge'**
  String get resizeHandleRight;

  /// Accessible name for the bottom-right element resize handle.
  ///
  /// In en, this message translates to:
  /// **'Resize bottom-right corner'**
  String get resizeHandleBottomRight;

  /// Accessible name for the bottom-edge element resize handle.
  ///
  /// In en, this message translates to:
  /// **'Resize bottom edge'**
  String get resizeHandleBottom;

  /// Accessible name for the bottom-left element resize handle.
  ///
  /// In en, this message translates to:
  /// **'Resize bottom-left corner'**
  String get resizeHandleBottomLeft;

  /// Accessible name for the left-edge element resize handle.
  ///
  /// In en, this message translates to:
  /// **'Resize left edge'**
  String get resizeHandleLeft;

  /// Accessible name for the band height resize handle.
  ///
  /// In en, this message translates to:
  /// **'Resize band height'**
  String get resizeBandHandle;

  /// Tooltip + accessible name of the report preview's back button, which returns to wherever the preview was opened from (the designer).
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get previewBack;

  /// Tooltip + accessible name of the report preview's previous-page navigation button.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get previewPreviousPage;

  /// Tooltip + accessible name of the report preview's next-page navigation button.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get previewNextPage;

  /// The report preview's page-position indicator between the navigation buttons, e.g. 'Page 2 of 5'.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String previewPageIndicator(int current, int total);

  /// Accessible name of the preview's page surface, describing its fit-to-width sizing.
  ///
  /// In en, this message translates to:
  /// **'Fit to width'**
  String get previewFitToWidth;

  /// Tooltip + accessible name of the report preview's export toolbar action; the host decides what export means (save dialog, share sheet, upload).
  ///
  /// In en, this message translates to:
  /// **'Export as PDF'**
  String get previewExport;

  /// Tooltip + accessible name of the report preview's print toolbar action.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get previewPrint;

  /// Label + accessible name for the Designer segment of the unified toolbar's two-segment Designer|Preview workspace-mode switch (017).
  ///
  /// In en, this message translates to:
  /// **'Designer'**
  String get modeDesigner;

  /// Label + accessible name for the Preview segment of the unified toolbar's two-segment Designer|Preview workspace-mode switch (017).
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get modePreview;

  /// Tooltip + accessible name for the inline-rename affordance beside the report name in the unified toolbar (017).
  ///
  /// In en, this message translates to:
  /// **'Rename report'**
  String get actionRenameTooltip;

  /// Accessible label for the inline report-name edit field opened by the rename affordance in the unified toolbar (017).
  ///
  /// In en, this message translates to:
  /// **'Report name'**
  String get renameFieldLabel;

  /// Properties panel section label for the shape form gallery shown when a shape element is selected (020).
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get propertiesShape;

  /// Shape gallery thumbnail name: a straight line across the element's box (020).
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get shapeFormLine;

  /// Shape gallery thumbnail name: a rectangle filling the element's box (020).
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get shapeFormRectangle;

  /// Shape gallery thumbnail name: an ellipse inscribed in the element's box (020).
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get shapeFormEllipse;

  /// Shape gallery thumbnail name: a triangle, apex at top-centre (020).
  ///
  /// In en, this message translates to:
  /// **'Triangle'**
  String get shapeFormTriangle;

  /// Shape gallery thumbnail name: a diamond touching the four edge midpoints (020).
  ///
  /// In en, this message translates to:
  /// **'Diamond'**
  String get shapeFormDiamond;

  /// Shape gallery thumbnail name: a regular, point-up pentagon (020).
  ///
  /// In en, this message translates to:
  /// **'Pentagon'**
  String get shapeFormPentagon;

  /// Shape gallery thumbnail name: a regular, point-up hexagon (020).
  ///
  /// In en, this message translates to:
  /// **'Hexagon'**
  String get shapeFormHexagon;

  /// Shape gallery thumbnail name: a five-point, point-up star (020).
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get shapeFormStar;

  /// Properties panel section label for the text styling controls shown when a text element is selected (021).
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get propertiesFont;

  /// Row label for the font-family picker in the Font section (021).
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get fontFamilyLabel;

  /// Accessible name for the font-family picker trigger (021).
  ///
  /// In en, this message translates to:
  /// **'Choose font family'**
  String get fontFamilyPickerTooltip;

  /// Picker label shown when an element uses the renderer default font and the built-in families are hidden from the picker (022).
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get fontFamilyDefault;

  /// Picker entry for a stored font family that is not registered with the designer: the name is preserved but renders with the default font until repicked (021).
  ///
  /// In en, this message translates to:
  /// **'{family} (unavailable)'**
  String fontFamilyUnavailable(String family);

  /// Row label for the font-size field in the Font section (021).
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get fontSizeLabel;

  /// Accessible name for the Bold style toggle (021).
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get fontBoldTooltip;

  /// Accessible name for the Italic style toggle (021).
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get fontItalicTooltip;

  /// Accessible name for the Underline style toggle (021).
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get fontUnderlineTooltip;

  /// Accessible name for the left horizontal-alignment segment (021).
  ///
  /// In en, this message translates to:
  /// **'Align left'**
  String get alignLeftTooltip;

  /// Accessible name for the center horizontal-alignment segment (021).
  ///
  /// In en, this message translates to:
  /// **'Align center'**
  String get alignCenterTooltip;

  /// Accessible name for the right horizontal-alignment segment (021).
  ///
  /// In en, this message translates to:
  /// **'Align right'**
  String get alignRightTooltip;

  /// Row label for a color editor (text color, barcode color) in the Properties panel (021).
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get propertiesColor;

  /// Accessible name for a color-editor trigger that opens the swatch/hex popover (021).
  ///
  /// In en, this message translates to:
  /// **'Choose color'**
  String get colorPickerTooltip;

  /// Label for the hex color input inside the color popover (021).
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get colorHexLabel;

  /// Color popover entry that clears an optional color (no fill / no outline) (021).
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get colorNone;

  /// Accessible name of the black palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get swatchBlack;

  /// Accessible name of the white palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get swatchWhite;

  /// Accessible name of the gray palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get swatchGray;

  /// Accessible name of the light-gray palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get swatchSilver;

  /// Accessible name of the red palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get swatchRed;

  /// Accessible name of the orange palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get swatchOrange;

  /// Accessible name of the amber palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get swatchAmber;

  /// Accessible name of the yellow palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get swatchYellow;

  /// Accessible name of the green palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get swatchGreen;

  /// Accessible name of the emerald palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Emerald'**
  String get swatchEmerald;

  /// Accessible name of the teal palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get swatchTeal;

  /// Accessible name of the cyan palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get swatchCyan;

  /// Accessible name of the blue palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get swatchBlue;

  /// Accessible name of the indigo palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get swatchIndigo;

  /// Accessible name of the violet palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get swatchViolet;

  /// Accessible name of the pink palette swatch (021).
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get swatchPink;

  /// Properties panel section label for the fill/outline controls shown when a shape element is selected (021).
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get propertiesAppearance;

  /// Row label for a shape's fill-color editor in the Appearance section (021).
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get propertiesFill;

  /// Row label for a shape's outline-color editor in the Appearance section (021).
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get propertiesOutline;

  /// Row label for a shape's outline-width field in the Appearance section (021).
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get propertiesOutlineWidth;
}

class _JetPrintLocalizationsDelegate
    extends LocalizationsDelegate<JetPrintLocalizations> {
  const _JetPrintLocalizationsDelegate();

  @override
  Future<JetPrintLocalizations> load(Locale locale) {
    return SynchronousFuture<JetPrintLocalizations>(
        lookupJetPrintLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_JetPrintLocalizationsDelegate old) => false;
}

JetPrintLocalizations lookupJetPrintLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return JetPrintLocalizationsDe();
    case 'en':
      return JetPrintLocalizationsEn();
    case 'tr':
      return JetPrintLocalizationsTr();
  }

  throw FlutterError(
      'JetPrintLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
