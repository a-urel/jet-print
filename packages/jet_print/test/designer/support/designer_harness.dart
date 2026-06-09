// Shared test harness for the report-designer widget tests.
//
// These tests stand in for an EXTERNAL consumer, so this harness imports only
// the public entry point (`package:jet_print/jet_print.dart`) plus the SDK
// localization delegates — never `package:jet_print/src/...` (enforced by
// encapsulation_test.dart).
//
// The `k*Key` constants below mirror the stable widget keys assigned inside
// `lib/src/designer/jet_report_designer.dart` and its region widgets. Keys (not
// private widget *types*) are the test seam: they let us locate and measure each
// region without reaching into `src/`. THESE STRINGS MUST STAY IN SYNC with the
// shell; the region-presence test fails loudly if a key disappears.
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// --- Region keys (must match jet_report_designer.dart) ---
const Key kTopBarKey = ValueKey<String>('jet_print.designer.topBar');
const Key kToolboxKey = ValueKey<String>('jet_print.designer.toolbox');
const Key kSurfaceKey = ValueKey<String>('jet_print.designer.surface');
const Key kRightPanelKey = ValueKey<String>('jet_print.designer.rightPanel');

// --- Narrow-window collapse affordances (must match the shell). Only the right
// panel collapses; the toolbox is a fixed icon strip that stays visible. ---
const Key kRightPanelRailKey =
    ValueKey<String>('jet_print.designer.rightPanelRail');
const Key kRightPanelExpandKey =
    ValueKey<String>('jet_print.designer.rightPanelExpand');

/// The interactive canvas key (must match `canvas/design_canvas.dart`).
const Key kDesignCanvasKey = ValueKey<String>('jet_print.designer.canvas');

/// A comfortable desktop size at/above the 1024px collapse breakpoint where all
/// regions render side by side.
const Size kDesktopSize = Size(1440, 900);

/// A narrow size below the breakpoint where the side regions collapse to rails.
const Size kNarrowSize = Size(800, 720);

/// Pumps [JetReportDesigner] inside a standard `ShadApp` at a fixed surface
/// [size], wiring the library's localization delegate exactly as a real
/// consumer would. The window size is restored automatically after the test.
Future<void> pumpDesigner(
  WidgetTester tester, {
  Size size = kDesktopSize,
  Locale? locale,
  ThemeMode themeMode = ThemeMode.light,
  Widget designer = const JetReportDesigner(),
}) async {
  // setSurfaceSize is the binding-level sizing API: it sets the logical surface
  // size (dpr 1.0) and resets cleanly between tests. Mutating tester.view
  // physicalSize/devicePixelRatio directly leaks across tests in the same file
  // and can leave a later pump rendering nothing.
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final Widget app = ShadApp(
    locale: locale,
    themeMode: themeMode,
    // Wire only the library's own (fully synchronous) delegate here. The Global*
    // delegates load CLDR data via static, async paths whose state leaks across
    // locales within one test isolate (e.g. exercising de then tr) — a framework
    // quirk unrelated to the library. Consumers' full Global* wiring is covered
    // by the tester app's consumption test.
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
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
    home: designer,
  );

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// Pumps the designer bound to a [controller] (created if none is supplied) and
/// returns it, so interaction tests can both drive and assert the model. The
/// controller is disposed automatically by the designer only when it created
/// the controller; here the test owns it, so we dispose on tear-down.
Future<JetReportDesignerController> pumpDesignerWith(
  WidgetTester tester, {
  JetReportDesignerController? controller,
  Size size = kDesktopSize,
  Locale? locale,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  final JetReportDesignerController c =
      controller ?? JetReportDesignerController();
  addTearDown(c.dispose);
  await pumpDesigner(
    tester,
    size: size,
    locale: locale,
    themeMode: themeMode,
    designer: JetReportDesigner(controller: c),
  );
  return c;
}
