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

  /// Properties panel section label for an element's data binding (009).
  ///
  /// In en, this message translates to:
  /// **'Binding'**
  String get propertiesBinding;

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

  /// The report root: the Outline tree root row and the Properties panel header when the report itself is selected.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportLabel;

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
