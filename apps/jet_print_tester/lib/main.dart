import 'dart:io' show Platform;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
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
/// Wraps everything in a [ShadApp] with both light and dark [ShadThemeData] and
/// owns the [ThemeMode] so the in-app toggle can flip the whole tree's theme.
/// It consumes the library through its public entry point only.
class JetPrintTesterApp extends StatefulWidget {
  /// Creates the tester app root.
  const JetPrintTesterApp({super.key});

  @override
  State<JetPrintTesterApp> createState() => _JetPrintTesterAppState();
}

class _JetPrintTesterAppState extends State<JetPrintTesterApp> {
  ThemeMode _themeMode = ThemeMode.light;

  bool get _isDark => _themeMode == ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _isDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'jet_print tester',
      themeMode: _themeMode,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadSlateColorScheme.light(),
      ),
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: const ShadSlateColorScheme.dark(),
      ),
      home: _TesterHome(isDark: _isDark, onToggleTheme: _toggleTheme),
    );
  }
}

/// The single screen: the library placeholder plus a light/dark toggle, painted
/// on the active theme's background so the theme switch is visible everywhere.
class _TesterHome extends StatelessWidget {
  const _TesterHome({required this.isDark, required this.onToggleTheme});

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const JetPrintPlaceholder(),
              const SizedBox(height: 24),
              ShadButton(
                onPressed: onToggleTheme,
                child: Text(isDark ? 'Switch to light' : 'Switch to dark'),
              ),
              const SizedBox(height: 12),
              Text(
                'jet_print v$jetPrintVersion',
                style: theme.textTheme.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
