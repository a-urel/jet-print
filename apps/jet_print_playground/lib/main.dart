import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';
import 'package:printing/printing.dart' show Printing;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'barcode_gallery_sample.dart';
import 'barcode_sample.dart';
import 'invoice_sample.dart';
import 'l10n/app_localizations.dart';
import 'label_sample.dart';
import 'ledger_sample.dart';
import 'menu_sample.dart';
import 'nested_list_sample.dart';
import 'packing_slip_sample.dart';
import 'payroll_sample.dart';
import 'rendered_barcode_example.dart';
import 'rendered_barcode_gallery_example.dart';
import 'rendered_invoice_example.dart';
import 'rendered_label_example.dart';
import 'rendered_ledger_example.dart';
import 'rendered_menu_example.dart';
import 'rendered_nested_list_example.dart';
import 'rendered_packing_slip_example.dart';
import 'rendered_payroll_example.dart';

Future<void> main() async {
  // Loading the bundled font assets needs the binding up before runApp.
  WidgetsFlutterBinding.ensureInitialized();
  // Fail fast on unsupported platforms so a wrong target surfaces a clear
  // message instead of rendering incorrectly (spec Edge Cases). The library is
  // platform-agnostic; this playground app targets desktop (macOS, Windows,
  // Linux), web, and mobile (iOS, Android).
  final bool supported = kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  if (!supported) {
    throw UnsupportedError(
      'jet_print_playground targets desktop (macOS, Windows, Linux), web, '
      'and mobile (iOS, Android).',
    );
  }
  // 022 + Google-Fonts catalog: a curated, offline set of real OFL families,
  // loaded BEFORE building anything and handed as the SAME list to the designer
  // (picker + canvas) and the render callback (preview + PDF + PNG).
  runApp(JetPrintPlaygroundApp(fonts: await loadGoogleFonts()));
}

/// Root widget of the playground app.
///
/// Wraps everything in a [ShadApp], owning the [ThemeMode] and the active
/// [Locale] so the in-app toggles can flip the whole tree's theme and language
/// live (FR-018). It consumes the library through its public entry point only,
/// rendering [JetReportDesigner] and wiring [JetPrintLocalizations] exactly as
/// an external consumer would.
class JetPrintPlaygroundApp extends StatefulWidget {
  /// Creates the playground app root over the host-registered [fonts].
  const JetPrintPlaygroundApp(
      {super.key, this.fonts = const <JetFontFamily>[]});

  /// The host-contributed fonts, passed to BOTH the workspace (picker + canvas)
  /// and the render callback (preview + export) — the single shared list that
  /// makes the designer and the rendered output agree (FR-012).
  final List<JetFontFamily> fonts;

  @override
  State<JetPrintPlaygroundApp> createState() => _JetPrintPlaygroundAppState();
}

class _JetPrintPlaygroundAppState extends State<JetPrintPlaygroundApp> {
  ThemeMode _themeMode = ThemeMode.light;

  /// Index into [JetPrintLocalizations.supportedLocales] (en → de → tr).
  int _localeIndex = 0;

  bool get _isDark => _themeMode == ThemeMode.dark;

  Locale get _locale => JetPrintLocalizations.supportedLocales[_localeIndex];

  void _toggleTheme() {
    setState(() {
      _themeMode = _isDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  void _cycleLanguage() {
    setState(() {
      _localeIndex =
          (_localeIndex + 1) % JetPrintLocalizations.supportedLocales.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'JetPrint Playground',
      themeMode: _themeMode,
      locale: _locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        // The playground's own demo strings (tab labels, "coming soon")…
        AppLocalizations.delegate,
        // …alongside the library's designer chrome strings.
        JetPrintLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadSlateColorScheme.light(),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: const ShadSlateColorScheme.dark(),
      ),
      home: _PlaygroundHome(
        isDark: _isDark,
        localeCode: _locale.languageCode,
        fonts: widget.fonts,
        onToggleTheme: _toggleTheme,
        onCycleLanguage: _cycleLanguage,
      ),
    );
  }
}

/// The playground shell: a `scrollable` [ShadTabs] strip used as a pure
/// selector, driving a structurally-stable [IndexedStack] that hosts all 8
/// live-designer demo bodies at once. Only the shown index changes on a switch,
/// so no designer is ever remounted — edits survive.
///
/// The app-global theme/language cluster switches the WHOLE app, not any single
/// report, so it rides beside the strip. The two are laid out by width: at
/// desktop/tablet widths the strip fills and the cluster is overlaid at its
/// (roomy) right end; on a phone the cluster moves to a compact row ABOVE the
/// full-width strip, so it never overlays — and hides — the strip's right-hand
/// demo tabs (an iOS-Simulator smoke caught that occlusion).
class _PlaygroundHome extends StatefulWidget {
  const _PlaygroundHome({
    required this.isDark,
    required this.localeCode,
    required this.fonts,
    required this.onToggleTheme,
    required this.onCycleLanguage,
  });

  final bool isDark;
  final String localeCode;
  final List<JetFontFamily> fonts;
  final VoidCallback onToggleTheme;
  final VoidCallback onCycleLanguage;

  @override
  State<_PlaygroundHome> createState() => _PlaygroundHomeState();
}

class _PlaygroundHomeState extends State<_PlaygroundHome> {
  /// Below this width the demo strip cannot share a row with the theme/locale
  /// toggle cluster without the cluster overlaying — and hiding — the strip's
  /// right-hand tabs (the iOS-Simulator smoke bug: only the first demo was
  /// reachable). At or above it the roomy desktop overlay layout is kept.
  static const double _narrowWidth = 600;

  /// A stable identity for the demo [ShadTabs] so the selector strip survives
  /// the narrow⇄wide layout swap (e.g. a phone rotation crossing [_narrowWidth])
  /// and the parent's theme/locale rebuilds.
  final GlobalKey _demoTabsKey = GlobalKey();

  /// The selected demo's value; drives the body IndexedStack and the strip.
  String _selectedDemo = 'fatura';

  /// The demo bodies, created once in [initState] so the same widget instances
  /// are handed to the [IndexedStack] on every rebuild. Only the index changes
  /// on a switch — the element subtrees are never remounted.
  late final List<({String value, IconData icon, Widget body})> _demoBodies;

  @override
  void initState() {
    super.initState();
    // Build the body widgets once. Labels come from l10n in build(); the bodies
    // (designer tabs) must be structurally stable across rebuilds.
    _DesignerTab tab(ReportDefinition seed, JetDataSchema? schema,
            RenderedReport Function(ReportDefinition) render,
            {bool fileIo = false, bool selectDataSource = false}) =>
        _DesignerTab(
            fonts: widget.fonts,
            seed: seed,
            dataSchema: schema,
            renderReport: render,
            enableFileIo: fileIo,
            enableSelectDataSource: selectDataSource);
    _demoBodies = <({String value, IconData icon, Widget body})>[
      (
        value: 'fatura',
        icon: LucideIcons.fileText,
        body: tab(invoiceSampleDefinition(), invoiceSchema,
            (d) => renderInvoiceDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'etiket',
        icon: LucideIcons.tag,
        body: tab(labelSampleDefinition(), labelSchema,
            (d) => renderLabelDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'barkod',
        icon: LucideIcons.barcode,
        body: tab(barcodeSampleDefinition(), barcodeSchema,
            (d) => renderBarcodeDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'barkod-galeri',
        icon: LucideIcons.qrCode,
        body: tab(barcodeGalleryDefinition(), barcodeGallerySchema,
            (d) =>
                renderBarcodeGalleryDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'makbuz',
        icon: LucideIcons.package,
        body: tab(
            packingSlipDefinition(),
            shipmentSchema,
            (d) => renderPackingSlipDefinition(
                definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'bordro',
        icon: LucideIcons.banknote,
        body: tab(payrollDefinition(), payrollSchema,
            (d) => renderPayrollDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'nested-lists',
        icon: LucideIcons.listTree,
        body: tab(
            nestedListsDefinition(),
            customersSchema,
            (d) => renderNestedListsDefinition(
                definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'defter',
        icon: LucideIcons.scrollText,
        body: tab(ledgerSampleDefinition(), ledgerSchema,
            (d) => renderLedgerDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'menu',
        icon: LucideIcons.image,
        body: tab(menuSampleDefinition(), menuSchema,
            (d) => renderMenuDefinition(definition: d, fonts: widget.fonts)),
      ),
      (
        value: 'bos',
        icon: LucideIcons.squareDashed,
        body: tab(emptyDesignDefinition(), null,
            (d) => renderInvoiceDefinition(definition: d, fonts: widget.fonts),
            fileIo: true, selectDataSource: true),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Labels are l10n-dependent so they're resolved per build; the bodies are
    // stable instances from initState.
    final List<String> labels = <String>[
      l10n.tabInvoice,
      l10n.tabLabel,
      l10n.tabBarcode,
      'Symbology gallery',
      l10n.tabPackingSlip,
      l10n.tabPayroll,
      l10n.tabList,
      l10n.tabLedger,
      l10n.tabMenu,
      l10n.tabEmpty,
    ];

    final int index = _demoBodies
        .indexWhere((d) => d.value == _selectedDemo)
        .clamp(0, _demoBodies.length - 1);

    // Selector only: tapping a tab changes _selectedDemo; the heavy bodies live
    // in the IndexedStack below, so the strip never hosts (or remounts) them.
    final Widget demoStrip = ShadTabs<String>(
      key: _demoTabsKey,
      value: _selectedDemo,
      onChanged: (String v) => setState(() => _selectedDemo = v),
      scrollable: true,
      tabs: <ShadTab<String>>[
        for (int i = 0; i < _demoBodies.length; i++)
          ShadTab<String>(
            value: _demoBodies[i].value,
            leading: Icon(_demoBodies[i].icon, size: 16),
            child: Text(labels[i]),
          ),
      ],
    );

    // The hero: one structurally-stable IndexedStack keeps every designer
    // mounted (edits survive) and swaps which is shown by index alone — no
    // Expanded-flip, so no remount on switch.
    final Widget bodies = IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: <Widget>[for (final d in _demoBodies) d.body],
    );

    // App-global theme + language toggles: they switch the WHOLE app, not any
    // single report, so they ride beside the demo strip rather than inside it.
    final Widget toggleCluster = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: widget.onToggleTheme,
          child: Text(widget.isDark ? 'Light' : 'Dark'),
        ),
        const SizedBox(width: 4),
        ShadButton.outline(
          size: ShadButtonSize.sm,
          onPressed: widget.onCycleLanguage,
          child: Text(widget.localeCode.toUpperCase()),
        ),
      ],
    );

    // Keep the shell clear of the status bar / notch / home indicator on mobile
    // (a no-op inset on desktop/web). The host app owns safe-area framing; the
    // library's JetReportDesigner fills whatever space it is given.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The selector header: width-gated like before — a compact row above
            // on a phone, an overlaid cluster on the right at desktop width.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                if (constraints.maxWidth < _narrowWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 4),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: toggleCluster,
                        ),
                      ),
                      demoStrip,
                    ],
                  );
                }
                return Stack(
                  children: <Widget>[
                    demoStrip,
                    Positioned(top: 0, right: 8, child: toggleCluster),
                  ],
                );
              },
            ),
            Expanded(child: bodies),
          ],
        ),
      ),
    );
  }
}

/// A live designer tab over the invoice data ([invoiceSchema]), seeded with
/// [seed] — the fully-authored [invoiceSampleDefinition] for the Fatura tab, or
/// the blank [emptyDesignDefinition] for the empty manual-testing tab. Both
/// share the same data source, so the same fields are bindable on either.
///
/// Owns the [JetReportDesignerController] and implements the host side of the
/// persistence seam (FR-022): Save encodes the live definition to a file picked
/// with `file_selector`, Open decodes a picked file back into the controller.
/// The library itself performs no file I/O — this is the consumer's job.
class _DesignerTab extends StatefulWidget {
  const _DesignerTab({
    required this.fonts,
    required this.seed,
    required this.dataSchema,
    required this.renderReport,
    this.enableFileIo = false,
    this.enableSelectDataSource = false,
  });

  /// The host-contributed fonts, shared by the designer (picker + canvas) and
  /// the render callback (preview + export) — see [JetPrintPlaygroundApp.fonts].
  final List<JetFontFamily> fonts;

  /// The initial design the controller opens with (the invoice sample, the
  /// nested-list sample, or a blank canvas) — authored in the reified band
  /// model (spec 024).
  final ReportDefinition seed;

  /// The data structure bound in this tab, or null when the tab starts with no
  /// data source (the Empty tab, which attaches one via "Select data source").
  final JetDataSchema? dataSchema;

  /// Whether this tab offers the "Select data source" action. Only the Empty
  /// tab does; the sample demos ship their own schema and leave it unwired so
  /// the designer hides those buttons.
  final bool enableSelectDataSource;

  /// Renders the live definition for the preview/export seam — the sample's own
  /// render entry point ([renderInvoiceDefinition] / [renderNestedListsDefinition]),
  /// closed over [fonts].
  final ReportRenderCallback renderReport;

  /// Whether this tab offers the host Open/Save file actions. Only the Empty
  /// manual-testing tab does; the read-only sample demos leave them unwired so
  /// the designer hides those buttons.
  final bool enableFileIo;

  @override
  State<_DesignerTab> createState() => _DesignerTabState();
}

class _DesignerTabState extends State<_DesignerTab> {
  // Seed the designer with the tab's starting design so it's editable on first
  // run (FR-021). `late` so the field initializer can read `widget.seed`.
  late final JetReportDesignerController _controller =
      JetReportDesignerController(definition: widget.seed);

  /// The live data source for this tab — seeded from the widget and replaced
  /// when the author attaches one via "Select data source".
  JetDataSchema? _schema;

  @override
  void initState() {
    super.initState();
    _schema = widget.dataSchema;
  }

  /// The data source attached via "Select" (Empty tab only): the picked file's
  /// sample rows, typed by its schema. Null until a source with sample rows is
  /// selected — then the preview renders against it instead of the bundled data.
  JetDataSource? _source;

  /// The file type the designer reads/writes: a JSON document produced by
  /// `JetReportFormat.encodeJson`.
  static const XTypeGroup _reportType = XTypeGroup(
    label: 'Jet report',
    extensions: <String>['jetreport', 'json'],
  );

  /// The data-source file the Empty tab attaches: a `*.jetreport.datasource`
  /// JSON document decoded by [JetDataSourceFile].
  static const XTypeGroup _dataSourceType = XTypeGroup(
    label: 'Jet data source',
    extensions: <String>['datasource', 'json'],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Select a data source: pick a `*.jetreport.datasource` file, decode it, and
  /// attach its schema **and** its sample rows. The schema drives the designer's
  /// binding affordances; the sample rows (built into a [JetInMemoryDataSource]
  /// typed by that same schema) become the preview's data, so what you select is
  /// what you preview. Decode failures surface through the workspace onError.
  Future<void> _selectDataSource() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_dataSourceType],
    );
    if (file == null) return; // user cancelled
    final JetDataSourceDocument doc =
        JetDataSourceFile.decodeJson(await file.readAsString());
    final List<Map<String, Object?>>? sample = doc.sample;
    setState(() {
      _schema = doc.schema;
      _source = sample == null
          ? null
          : JetInMemoryDataSource(sample, fields: doc.schema.fields);
    });
  }

  /// Cross-platform save: on web, download via the browser (file picking is
  /// unsupported there) — on desktop, pick a location then write. Both go
  /// through `cross_file`'s `XFile.saveTo`, which downloads on web and writes
  /// a file on desktop, so no `dart:io` is needed.
  Future<void> _saveBytes(
    Uint8List bytes, {
    required String suggestedName,
    required List<XTypeGroup> acceptedTypeGroups,
    String? mimeType,
  }) async {
    if (kIsWeb) {
      await XFile.fromData(bytes, name: suggestedName, mimeType: mimeType)
          .saveTo(suggestedName);
      return;
    }
    // Mobile: file_selector's getSaveLocation is desktop/web-only, so present
    // the OS share sheet for the bytes instead (minimal save — full mobile
    // file UX is deferred to E7).
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      await Printing.sharePdf(bytes: bytes, filename: suggestedName);
      return;
    }
    final FileSaveLocation? location = await getSaveLocation(
      acceptedTypeGroups: acceptedTypeGroups,
      suggestedName: suggestedName,
    );
    if (location == null) return; // user cancelled
    await XFile.fromData(bytes, mimeType: mimeType).saveTo(location.path);
  }

  /// Save: encode the current definition and write it to a picked location.
  Future<void> _save(ReportDefinition definition) async {
    final Uint8List bytes = Uint8List.fromList(
        utf8.encode(JetReportFormat.encodeDefinitionJson(definition)));
    await _saveBytes(
      bytes,
      suggestedName: 'report.jetreport',
      acceptedTypeGroups: const <XTypeGroup>[_reportType],
    );
  }

  /// Open: read a picked file and decode it back into the controller. The v2
  /// decoder migrates a v1 (flat-template) document forward automatically.
  Future<void> _open() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_reportType],
    );
    if (file == null) return; // user cancelled
    final String contents = await file.readAsString();
    _controller.open(JetReportFormat.decodeDefinitionJson(contents));
  }

  /// Export the rendered report as a PDF to a picked location (host-owned I/O).
  Future<void> _exportPdf(RenderedReport report) async {
    final Uint8List pdf = await const JetReportExporter().toPdf(report);
    await _saveBytes(
      pdf,
      suggestedName: 'invoice.pdf',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'PDF document', extensions: <String>['pdf']),
      ],
      mimeType: 'application/pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return JetReportWorkspace(
      controller: _controller,
      // Each sample brings its own data structure (invoice vs. customers).
      // The Empty tab starts null and gets its schema via _selectDataSource.
      dataSchema: _schema,
      // The SAME host-font list reaches the designer picker/canvas here and the
      // engine via renderReport below (FR-012).
      fonts: widget.fonts,
      // Offer only the Google-Fonts catalog; the built-in Default stays as the
      // silent render fallback but is hidden from the picker (022).
      showBuiltInFonts: false,
      // Preview renders the LIVE definition the designer hands over, through the
      // native `renderDefinition` path (spec 024) — so every edit on the reified
      // canvas shows up in the preview. When the Empty tab has a data source
      // attached via "Select", render against ITS sample rows + schema so the
      // preview resolves the selected source's fields; otherwise the sample's
      // own bundled render seam.
      renderReport: (ReportDefinition definition) {
        final JetDataSource? source = _source;
        final JetDataSchema? schema = _schema;
        if (source != null && schema != null) {
          return renderDefinitionAgainst(
            definition: definition,
            source: source,
            schema: schema,
            fonts: widget.fonts,
          );
        }
        return widget.renderReport(definition);
      },
      onSaveRequested: widget.enableFileIo ? _save : null,
      onOpenRequested: widget.enableFileIo ? _open : null,
      onSelectDataSchema:
          widget.enableSelectDataSource ? _selectDataSource : null,
      onExportPdf: _exportPdf,
      onPrint: (RenderedReport report) =>
          const JetReportPrinter().printReport(report),
    );
  }
}
