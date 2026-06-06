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

  /// Toolbox element: a static or data-bound text element. Shown as an icon-button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get toolboxTextEntry;

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
