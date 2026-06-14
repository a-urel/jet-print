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

/// Hosts the full-bleed [JetReportDesigner] with a small floating control
/// cluster (theme + language toggles) layered in the corner so the designer
/// stays the hero while both runtime switches remain reachable.
///
/// Owns the [JetReportDesignerController] and implements the host side of the
/// persistence seam (FR-022): Save encodes the live template to a file picked
/// with `file_selector`, Open decodes a picked file back into the controller.
/// The library itself performs no file I/O — this is the consumer's job.
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
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: JetReportWorkspace(
            controller: _controller,
            dataSchema: invoiceSchema,
            // The SAME host-font list reaches the designer picker/canvas here
            // and the engine via renderReport below (FR-012).
            fonts: widget.fonts,
            // Offer only the Google-Fonts catalog; the built-in Default stays
            // as the silent render fallback but is hidden from the picker (022).
            showBuiltInFonts: false,
            // Preview renders the LIVE definition the designer hands over,
            // through the native `renderDefinition` path (spec 024) — so every
            // edit on the reified canvas shows up in the preview.
            renderReport: (ReportDefinition definition) =>
                renderInvoiceDefinition(
                    definition: definition, fonts: widget.fonts),
            onSaveRequested: _save,
            onOpenRequested: _open,
            onExportPdf: _exportPdf,
            onPrint: (RenderedReport report) =>
                const JetReportPrinter().printReport(report),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: ShadCard(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ShadButton.ghost(
                  onPressed: widget.onToggleTheme,
                  child: Text(widget.isDark ? 'Light' : 'Dark'),
                ),
                const SizedBox(width: 8),
                ShadButton.outline(
                  onPressed: widget.onCycleLanguage,
                  child: Text(widget.localeCode.toUpperCase()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
