import 'dart:io' show File, Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'invoice_sample.dart';
import 'rendered_invoice_example.dart';

void main() {
  // Fail fast on unsupported platforms so a wrong target surfaces a clear
  // message instead of rendering incorrectly (spec Edge Cases). The library is
  // platform-agnostic; only this playground app pins macOS desktop this iteration.
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'jet_print_playground targets macOS desktop this iteration.',
    );
  }
  runApp(const JetPrintPlaygroundApp());
}

/// Root widget of the playground app.
///
/// Wraps everything in a [ShadApp], owning the [ThemeMode] and the active
/// [Locale] so the in-app toggles can flip the whole tree's theme and language
/// live (FR-018). It consumes the library through its public entry point only,
/// rendering [JetReportDesigner] and wiring [JetPrintLocalizations] exactly as
/// an external consumer would.
class JetPrintPlaygroundApp extends StatefulWidget {
  /// Creates the playground app root.
  const JetPrintPlaygroundApp({super.key});

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
    required this.onToggleTheme,
    required this.onCycleLanguage,
  });

  final bool isDark;
  final String localeCode;
  final VoidCallback onToggleTheme;
  final VoidCallback onCycleLanguage;

  @override
  State<_PlaygroundHome> createState() => _PlaygroundHomeState();
}

class _PlaygroundHomeState extends State<_PlaygroundHome> {
  // Seed the designer with the bundled invoice sample so the data-aware
  // master/detail design is visible on first run (FR-021).
  final JetReportDesignerController _controller =
      JetReportDesignerController(template: invoiceSampleTemplate());

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

  /// Save: encode the current template and write it to a picked location.
  Future<void> _save(ReportTemplate template) async {
    final FileSaveLocation? location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[_reportType],
      suggestedName: 'report.jetreport',
    );
    if (location == null) return; // user cancelled
    await File(location.path)
        .writeAsString(JetReportFormat.encodeJson(template));
  }

  /// Open: read a picked file and decode it back into the controller.
  Future<void> _open() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_reportType],
    );
    if (file == null) return; // user cancelled
    final String contents = await file.readAsString();
    _controller.open(JetReportFormat.decodeJson(contents));
  }

  /// Preview path (011): open the rendered-invoice example — the invoice
  /// template filled with real data, shown in the paginated preview.
  void _openPreview() {
    Navigator.of(context).push(PageRouteBuilder<void>(
      pageBuilder:
          (BuildContext context, Animation<double> _, Animation<double> __) =>
              const _RenderedInvoicePreviewPage(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: JetReportDesigner(
            controller: _controller,
            dataSchema: invoiceSchema,
            onSaveRequested: _save,
            onOpenRequested: _open,
            // The designer's top-bar Preview action opens the rendered preview.
            onPreviewRequested: (ReportTemplate _) => _openPreview(),
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

/// Hosts [RenderedInvoiceExample]; the preview toolbar's own back button
/// returns to the designer.
class _RenderedInvoicePreviewPage extends StatelessWidget {
  const _RenderedInvoicePreviewPage();

  @override
  Widget build(BuildContext context) {
    return RenderedInvoiceExample(onBack: () => Navigator.of(context).pop());
  }
}
