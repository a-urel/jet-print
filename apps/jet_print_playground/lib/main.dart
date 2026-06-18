import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'barcode_sample.dart';
import 'invoice_sample.dart';
import 'l10n/app_localizations.dart';
import 'label_sample.dart';
import 'nested_list_sample.dart';
import 'packing_slip_sample.dart';
import 'rendered_barcode_example.dart';
import 'rendered_invoice_example.dart';
import 'rendered_label_example.dart';
import 'rendered_nested_list_example.dart';
import 'rendered_packing_slip_example.dart';

Future<void> main() async {
  // Loading the bundled font assets needs the binding up before runApp.
  WidgetsFlutterBinding.ensureInitialized();
  // Fail fast on unsupported platforms so a wrong target surfaces a clear
  // message instead of rendering incorrectly (spec Edge Cases). The library is
  // platform-agnostic; only this playground app pins macOS desktop this iteration.
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'jet_print_playground targets macOS desktop this iteration.',
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
      title: 'jet_print playground',
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

/// The playground shell: a [ShadTabs] strip whose first two tabs are live
/// designers ([_DesignerTab]) — a blank canvas and the invoice sample, both
/// over the same data — and whose remaining tabs are placeholders for future
/// report demos ([_ComingSoonReport]).
///
/// The strip is `scrollable` so the tabs size to their labels and sit
/// left-aligned, leaving the right end free for the app-global theme/language
/// cluster — which is overlaid there because it switches the WHOLE app, not any
/// single report. Each tab uses `expandContent` so the selected body fills the
/// space below the strip, and the default `maintainState` keeps every tab alive
/// (Offstage) so the designer's edits survive a tab switch.
class _PlaygroundHome extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: ShadTabs<String>(
              value: 'fatura',
              // Intrinsic-width, left-aligned tabs (vs. the default full-width
              // stretch) so the strip leaves room for the toggle cluster.
              scrollable: true,
              tabs: <ShadTab<String>>[
                ShadTab<String>(
                  value: 'bos',
                  leading: const Icon(LucideIcons.squareDashed, size: 16),
                  // A blank canvas over the SAME invoice data — for exercising
                  // the designer by hand from nothing.
                  expandContent: true,
                  content: _FillTabHeight(
                    child: _DesignerTab(
                      fonts: fonts,
                      seed: emptyDesignDefinition(),
                      dataSchema: invoiceSchema,
                      renderReport: (ReportDefinition def) =>
                          renderInvoiceDefinition(
                              definition: def, fonts: fonts),
                    ),
                  ),
                  child: Text(l10n.tabEmpty),
                ),
                ShadTab<String>(
                  value: 'fatura',
                  leading: const Icon(LucideIcons.fileText, size: 16),
                  // The designer is the hero: fill the space below the strip.
                  expandContent: true,
                  content: _FillTabHeight(
                    child: _DesignerTab(
                      fonts: fonts,
                      seed: invoiceSampleDefinition(),
                      dataSchema: invoiceSchema,
                      renderReport: (ReportDefinition def) =>
                          renderInvoiceDefinition(
                              definition: def, fonts: fonts),
                    ),
                  ),
                  child: Text(l10n.tabInvoice),
                ),
                ShadTab<String>(
                  value: 'etiket',
                  leading: const Icon(LucideIcons.tag, size: 16),
                  expandContent: true,
                  // A live designer over the address-label data — 100 flat
                  // records laid out as a 3-column label sheet via the detail
                  // band's native ColumnLayout (label_sample.dart).
                  content: _FillTabHeight(
                    child: _DesignerTab(
                      fonts: fonts,
                      seed: labelSampleDefinition(),
                      dataSchema: labelSchema,
                      renderReport: (ReportDefinition def) =>
                          renderLabelDefinition(definition: def, fonts: fonts),
                    ),
                  ),
                  child: Text(l10n.tabLabel),
                ),
                ShadTab<String>(
                  value: 'barkod',
                  leading: const Icon(LucideIcons.barcode, size: 16),
                  expandContent: true,
                  // A live designer over the product data — 28 flat records laid
                  // out as a 2-column product-label sheet via the detail band's
                  // native ColumnLayout, each cell carrying a real EAN-13 barcode
                  // bound to the product number (barcode_sample.dart).
                  content: _FillTabHeight(
                    child: _DesignerTab(
                      fonts: fonts,
                      seed: barcodeSampleDefinition(),
                      dataSchema: barcodeSchema,
                      renderReport: (ReportDefinition def) =>
                          renderBarcodeDefinition(
                              definition: def, fonts: fonts),
                    ),
                  ),
                  child: Text(l10n.tabBarcode),
                ),
                ShadTab<String>(
                  value: 'makbuz',
                  leading: const Icon(LucideIcons.package, size: 16),
                  expandContent: true,
                  // A live designer over a single shipment — Shipment ▸ Box ▸
                  // Item with a two-column address header, a QR tracking code,
                  // per-box subtotals and grand totals (packing_slip_sample.dart).
                  content: _FillTabHeight(
                    child: _DesignerTab(
                      fonts: fonts,
                      seed: packingSlipDefinition(),
                      dataSchema: shipmentSchema,
                      renderReport: (ReportDefinition def) =>
                          renderPackingSlipDefinition(
                              definition: def, fonts: fonts),
                    ),
                  ),
                  child: Text(l10n.tabPackingSlip),
                ),
                ShadTab<String>(
                  value: 'nested-lists',
                  leading: const Icon(LucideIcons.listTree, size: 16),
                  expandContent: true,
                  // A live designer over the customers data — Customer ▸ Order ▸
                  // Line, two nested scopes deep (nested_list_sample.dart).
                  content: _FillTabHeight(
                    child: _DesignerTab(
                      fonts: fonts,
                      seed: nestedListsDefinition(),
                      dataSchema: customersSchema,
                      renderReport: (ReportDefinition def) =>
                          renderNestedListsDefinition(
                              definition: def, fonts: fonts),
                    ),
                  ),
                  child: Text(l10n.tabList),
                ),
              ],
            ),
          ),
          // App-global theme + language toggles, overlaid at the right end of the
          // tab strip. Left unconstrained vertically so the 36px small buttons
          // keep their natural height inside the 32px strip + 8px gap band — no
          // tight constraint to overflow, no negative offset to clip.
          Positioned(
            top: 0,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: onToggleTheme,
                  child: Text(isDark ? 'Light' : 'Dark'),
                ),
                const SizedBox(width: 4),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: onCycleLanguage,
                  child: Text(localeCode.toUpperCase()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bounds a designer tab body's height so it survives sitting **offstage** in
/// [ShadTabs].
///
/// `ShadTabs` wraps only the *selected* tab's body in an [Expanded]; a
/// maintained-but-unselected tab (the default `maintainState` keep-alive that
/// lets edits survive a tab switch) is laid out as a bare [Column] child — i.e.
/// with **unbounded height**. The workspace's `StackFit.expand` [IndexedStack]
/// can't accept that and asserts, even while invisible. Since the offstage copy
/// is never painted, any finite height is fine — fall back to the screen height
/// — while the selected copy (already bounded by the `Expanded`) passes straight
/// through. Only the designer tabs need this; the placeholder cards size to
/// their content under unbounded height already.
class _FillTabHeight extends StatelessWidget {
  const _FillTabHeight({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            constraints.hasBoundedHeight
                ? child
                : SizedBox(
                    height: MediaQuery.sizeOf(context).height,
                    child: child,
                  ),
      );
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
  });

  /// The host-contributed fonts, shared by the designer (picker + canvas) and
  /// the render callback (preview + export) — see [JetPrintPlaygroundApp.fonts].
  final List<JetFontFamily> fonts;

  /// The initial design the controller opens with (the invoice sample, the
  /// nested-list sample, or a blank canvas) — authored in the reified band
  /// model (spec 024).
  final ReportDefinition seed;

  /// The data structure bound in this tab — drives the field palette and
  /// binding validation. Each sample brings its own schema (invoice vs.
  /// customers).
  final JetDataSchema dataSchema;

  /// Renders the live definition for the preview/export seam — the sample's own
  /// render entry point ([renderInvoiceDefinition] / [renderNestedListsDefinition]),
  /// closed over [fonts].
  final ReportRenderCallback renderReport;

  @override
  State<_DesignerTab> createState() => _DesignerTabState();
}

class _DesignerTabState extends State<_DesignerTab> {
  // Seed the designer with the tab's starting design so it's editable on first
  // run (FR-021). `late` so the field initializer can read `widget.seed`.
  late final JetReportDesignerController _controller =
      JetReportDesignerController(definition: widget.seed);

  /// The file type the designer reads/writes: a JSON document produced by
  /// `JetReportFormat.encodeJson`.
  static const XTypeGroup _reportType = XTypeGroup(
    label: 'Jet report',
    extensions: <String>['jetreport', 'json'],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Save: encode the current definition and write it to a picked location.
  Future<void> _save(ReportDefinition definition) async {
    final FileSaveLocation? location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[_reportType],
      suggestedName: 'report.jetreport',
    );
    if (location == null) return; // user cancelled
    await File(location.path)
        .writeAsString(JetReportFormat.encodeDefinitionJson(definition));
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
    final FileSaveLocation? location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'PDF document', extensions: <String>['pdf']),
      ],
      suggestedName: 'invoice.pdf',
    );
    if (location == null) return; // user cancelled
    await XFile.fromData(pdf, mimeType: 'application/pdf')
        .saveTo(location.path);
  }

  @override
  Widget build(BuildContext context) {
    return JetReportWorkspace(
      controller: _controller,
      // Each sample brings its own data structure (invoice vs. customers).
      dataSchema: widget.dataSchema,
      // The SAME host-font list reaches the designer picker/canvas here and the
      // engine via renderReport below (FR-012).
      fonts: widget.fonts,
      // Offer only the Google-Fonts catalog; the built-in Default stays as the
      // silent render fallback but is hidden from the picker (022).
      showBuiltInFonts: false,
      // Preview renders the LIVE definition the designer hands over, through the
      // native `renderDefinition` path (spec 024) — so every edit on the reified
      // canvas shows up in the preview.
      renderReport: widget.renderReport,
      onSaveRequested: _save,
      onOpenRequested: _open,
      onExportPdf: _exportPdf,
      onPrint: (RenderedReport report) =>
          const JetReportPrinter().printReport(report),
    );
  }
}
