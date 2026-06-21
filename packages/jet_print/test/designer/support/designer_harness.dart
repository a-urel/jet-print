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

/// The paper page-surface key (must match `canvas/design_canvas.dart`).
const Key kDesignPageKey = ValueKey<String>('jet_print.designer.page');

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
    // by the playground app's consumption test.
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

/// The top-bar Arrange menu trigger key (must match `designer_top_bar.dart`).
const Key kArrangeButtonKey =
    ValueKey<String>('jet_print.designer.action.arrange');

/// The stable id of the first per-row band in the master scope of [c]'s
/// definition — the reified replacement for the old "detail band index". Tests
/// address bands by id now (spec 024); for the blank default that is `'detail'`.
String firstDetailBandId(JetReportDesignerController c) =>
    c.definition.body.root.children.whereType<BandNode>().first.band.id;

/// Creates two elements, selects them, and opens the top-bar **Arrange** menu,
/// so a test can assert the localized align/distribute/z-order item labels. The
/// trigger is found by its stable key, so this works in any locale.
Future<void> openArrangeMenu(
    WidgetTester tester, JetReportDesignerController c) async {
  final String bandId = firstDetailBandId(c);
  c.createElement(DesignerToolType.text,
      bandId: bandId, at: const JetOffset(10, 10));
  c.createElement(DesignerToolType.text,
      bandId: bandId, at: const JetOffset(80, 60));
  c.selectAll();
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(kArrangeButtonKey));
  await tester.pumpAndSettle();
}

/// Opens the right panel's **Properties** tab in any locale.
///
/// The tab caption is itself localized, so rather than hardcode "Properties"
/// (which would only work in English) this resolves the live caption from the
/// tree via the public [JetReportDesigner] context and [JetPrintLocalizations] —
/// the same string the tab rendered, so the match is exact and locale-agnostic.
Future<void> openPropertiesTab(WidgetTester tester) async {
  final JetPrintLocalizations l10n = JetPrintLocalizations.of(
    tester.element(find.byType(JetReportDesigner)),
  );
  final Finder tab = find.text(l10n.tabProperties);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
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
  JetDataSchema? dataSchema,
  bool rulers = true,
  bool grid = true,
  bool pinFitWidth = true,
}) async {
  final JetReportDesignerController c =
      controller ?? JetReportDesignerController();
  addTearDown(c.dispose);
  // Disabling BEFORE the first pump matters: the initial fit-to-width reads the
  // (un-inset) viewport, so a rulers-off pump reproduces the pre-rulers layout
  // byte-for-byte — which is why the design-surface goldens pass `rulers: false`.
  if (!rulers) c.setRulersEnabled(false);
  // The alignment grid (015) is on by default, but the pre-grid canvas goldens
  // lock element/band appearance only — they pass `grid: false` so their images
  // stay byte-identical (the grid-on appearance gets its own dedicated golden).
  if (!grid) c.setGridEnabled(false);
  await pumpDesigner(
    tester,
    size: size,
    locale: locale,
    themeMode: themeMode,
    designer: JetReportDesigner(controller: c, dataSchema: dataSchema),
  );
  // The screen-width default-zoom decision opens desktop-width canvases at 100%
  // (actual size). The coordinate/golden tests here were written against the
  // fit-to-width scale, so pin it back unless a test opts out to observe the
  // raw default (the default-zoom tests pass `pinFitWidth: false`).
  if (pinFitWidth) {
    c.fitToView();
    await tester.pumpAndSettle();
  }
  return c;
}
