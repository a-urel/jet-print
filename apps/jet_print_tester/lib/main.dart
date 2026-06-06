import 'dart:io' show Platform;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  // Fail fast on unsupported platforms so a wrong target surfaces a clear
  // message instead of rendering incorrectly (spec Edge Cases). The library is
  // platform-agnostic; only this tester app pins macOS desktop this iteration.
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'jet_print_tester targets macOS desktop this iteration.',
    );
  }
  runApp(const JetPrintTesterApp());
}

/// Root widget of the tester app.
///
/// Wraps everything in a [ShadApp], owning the [ThemeMode] and the active
/// [Locale] so the in-app toggles can flip the whole tree's theme and language
/// live (FR-018). It consumes the library through its public entry point only,
/// rendering [JetReportDesigner] and wiring [JetPrintLocalizations] exactly as
/// an external consumer would.
class JetPrintTesterApp extends StatefulWidget {
  /// Creates the tester app root.
  const JetPrintTesterApp({super.key});

  @override
  State<JetPrintTesterApp> createState() => _JetPrintTesterAppState();
}

class _JetPrintTesterAppState extends State<JetPrintTesterApp> {
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
      title: 'jet_print tester',
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
      home: _TesterHome(
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
class _TesterHome extends StatelessWidget {
  const _TesterHome({
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
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: JetReportDesigner()),
        Positioned(
          right: 16,
          bottom: 16,
          child: ShadCard(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ShadButton.ghost(
                  onPressed: onToggleTheme,
                  child: Text(isDark ? 'Light' : 'Dark'),
                ),
                const SizedBox(width: 8),
                ShadButton.outline(
                  onPressed: onCycleLanguage,
                  child: Text(localeCode.toUpperCase()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
