import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'invoice_sample.dart';
import 'l10n/app_localizations.dart';
import 'rendered_invoice_example.dart';

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

/// The playground shell: a [ShadTabs] strip whose first tab is the live invoice
/// designer ([_InvoiceDesignerTab]) and whose remaining tabs are placeholders
/// for future report demos ([_ComingSoonReport]).
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

  /// A placeholder report demo tab — the body is a centered "Yakında" card.
  ShadTab<String> _comingSoon(String value, String label, IconData icon) =>
      ShadTab<String>(
        value: value,
        leading: Icon(icon, size: 16),
        expandContent: true,
        content: _ComingSoonReport(title: label, icon: icon),
        child: Text(label),
      );

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
                  value: 'fatura',
                  leading: const Icon(LucideIcons.fileText, size: 16),
                  // The designer is the hero: fill the space below the strip.
                  expandContent: true,
                  content: _InvoiceDesignerTab(fonts: fonts),
                  child: Text(l10n.tabInvoice),
                ),
                _comingSoon('etiket', l10n.tabLabel, LucideIcons.tag),
                _comingSoon('liste', l10n.tabList, LucideIcons.list),
                _comingSoon('makbuz', l10n.tabReceipt, LucideIcons.receipt),
                _comingSoon(
                    'nested-lists', l10n.tabNestedLists, LucideIcons.listTree),
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

/// The **Fatura** tab: the full invoice designer.
///
/// Owns the [JetReportDesignerController] and implements the host side of the
/// persistence seam (FR-022): Save encodes the live definition to a file picked
/// with `file_selector`, Open decodes a picked file back into the controller.
/// The library itself performs no file I/O — this is the consumer's job.
class _InvoiceDesignerTab extends StatefulWidget {
  const _InvoiceDesignerTab({required this.fonts});

  /// The host-contributed fonts, shared by the designer (picker + canvas) and
  /// the render callback (preview + export) — see [JetPrintPlaygroundApp.fonts].
  final List<JetFontFamily> fonts;

  @override
  State<_InvoiceDesignerTab> createState() => _InvoiceDesignerTabState();
}

class _InvoiceDesignerTabState extends State<_InvoiceDesignerTab> {
  // Seed the designer with the bundled invoice sample — authored in the reified
  // band model (spec 024) — so the data-aware master/detail design is editable
  // on first run (FR-021).
  final JetReportDesignerController _controller =
      JetReportDesignerController(definition: invoiceSampleDefinition());

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
      dataSchema: invoiceSchema,
      // The SAME host-font list reaches the designer picker/canvas here and the
      // engine via renderReport below (FR-012).
      fonts: widget.fonts,
      // Offer only the Google-Fonts catalog; the built-in Default stays as the
      // silent render fallback but is hidden from the picker (022).
      showBuiltInFonts: false,
      // Preview renders the LIVE definition the designer hands over, through the
      // native `renderDefinition` path (spec 024) — so every edit on the reified
      // canvas shows up in the preview.
      renderReport: (ReportDefinition definition) =>
          renderInvoiceDefinition(definition: definition, fonts: widget.fonts),
      onSaveRequested: _save,
      onOpenRequested: _open,
      onExportPdf: _exportPdf,
      onPrint: (RenderedReport report) =>
          const JetReportPrinter().printReport(report),
    );
  }
}

/// A placeholder body for a report demo that isn't built yet — a centered card
/// with the demo's icon, name, and a "Yakında" (coming soon) note.
class _ComingSoonReport extends StatelessWidget {
  const _ComingSoonReport({required this.title, required this.icon});

  /// The demo's display name (also its tab label).
  final String title;

  /// The demo's tab/lead icon, echoed large inside the card.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    return Center(
      child: ShadCard(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: theme.colorScheme.mutedForeground),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.h4),
            const SizedBox(height: 4),
            Text(AppLocalizations.of(context).comingSoon,
                style: theme.textTheme.muted),
          ],
        ),
      ),
    );
  }
}
