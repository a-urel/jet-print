// JetReportPreview widget (011 — contracts C6/C11; FR-008/FR-018).
//
// Black-box: this test stands in for an external consumer and imports only the
// public entry point (enforced by encapsulation_test.dart). It covers bounded
// prev/next navigation, the "page X of N" indicator, fit-to-width sizing,
// keyboard operation, and accessible names. WYSIWYG parity with the designer
// surface (the shared paint pipeline) is pinned by the rendered-invoice
// goldens.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// 200x100 page, 10pt margins -> 80pt body; 30pt detail bands -> 2 rows/page.
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

const Key _prevKey = ValueKey<String>('jet_print.preview.prev');
const Key _nextKey = ValueKey<String>('jet_print.preview.next');
const Key _pageKey = ValueKey<String>('jet_print.preview.page');

ReportTemplate _template() => const ReportTemplate(
      name: 'Quarterly Report',
      page: _page,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 30,
          elements: <ReportElement>[
            TextElement(
              id: 'name',
              bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
              text: 'name',
              expression: r'$F{name}',
            ),
          ],
        ),
      ],
    );

/// A three-page report (6 rows, 2 per page) rendered via the public engine.
RenderedReport _report() => const JetReportEngine().render(
      _template(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < 6; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

// --- Unified-toolbar mode switch (017 / US1 / C2). In the preview shell the
// Designer segment replaces the old standalone back button; selecting it emits
// the existing onBack switch request. ---
const Key _modeDesignerKey =
    ValueKey<String>('jet_print.toolbar.mode.designer');
const Key _modePreviewKey = ValueKey<String>('jet_print.toolbar.mode.preview');

ShadButtonVariant _segmentVariant(WidgetTester tester, Key key) =>
    tester.widget<ShadButton>(find.byKey(key)).variant;

bool _segmentDisabled(WidgetTester tester, Key key) =>
    tester.widget<ShadButton>(find.byKey(key)).onPressed == null;

const Key _zoomInKey = ValueKey<String>('jet_print.preview.zoomIn');
const Key _zoomOutKey = ValueKey<String>('jet_print.preview.zoomOut');
const Key _zoomLevelKey = ValueKey<String>('jet_print.preview.zoomLevel');

const Key _exportKey = ValueKey<String>('jet_print.preview.export');
const Key _printKey = ValueKey<String>('jet_print.preview.print');

Future<void> _pumpPreview(
  WidgetTester tester, {
  RenderedReport? report,
  int initialPage = 0,
  Size size = const Size(800, 600),
  VoidCallback? onBack,
  VoidCallback? onExportPdf,
  VoidCallback? onPrint,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: JetReportPreview(
      report: report ?? _report(),
      initialPage: initialPage,
      onBack: onBack,
      onExportPdf: onExportPdf,
      onPrint: onPrint,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Focuses the button identified by [key] via its internal focus node (the
/// icon sits inside the button's `Focus`), then activates it with [trigger].
Future<void> _activateWithKeyboard(
    WidgetTester tester, Key key, LogicalKeyboardKey trigger) async {
  final Element icon = tester.element(
      find.descendant(of: find.byKey(key), matching: find.byType(Icon)));
  Focus.of(icon).requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(trigger);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the first page with a correct "page X of N" indicator',
      (WidgetTester tester) async {
    await _pumpPreview(tester);
    // The top toolbar titles itself with the report's name.
    expect(find.text('Quarterly Report'), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.byKey(_pageKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_pageKey),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
      reason: 'the page paints through a CustomPaint over the rendered frame',
    );
  });

  testWidgets('next/prev navigate one page at a time, bounded at the ends',
      (WidgetTester tester) async {
    // Wide enough that the 017 mode switch + viewing actions fit without the
    // toolbar entering its horizontal-scroll regime (< 880 px), so the
    // page-navigation buttons stay on-screen and tappable.
    await _pumpPreview(tester, size: const Size(1000, 600));

    // Bounded at the first page: prev is disabled.
    expect(
        tester.widget<ShadIconButton>(find.byKey(_prevKey)).onPressed, isNull);

    await tester.tap(find.byKey(_nextKey));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);

    await tester.tap(find.byKey(_nextKey));
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);

    // Bounded at the last page: next is disabled and tapping does nothing.
    expect(
        tester.widget<ShadIconButton>(find.byKey(_nextKey)).onPressed, isNull);
    await tester.tap(find.byKey(_nextKey), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);

    await tester.tap(find.byKey(_prevKey));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('initialPage opens the requested page (clamped to range)',
      (WidgetTester tester) async {
    await _pumpPreview(tester, initialPage: 2);
    expect(find.text('Page 3 of 3'), findsOneWidget);
  });

  testWidgets(
      'fit-to-width: the page fills the available width at the page '
      'aspect ratio', (WidgetTester tester) async {
    await _pumpPreview(tester, size: const Size(700, 500));
    final Size pageSize = tester.getSize(find.byKey(_pageKey));
    expect(pageSize.height / pageSize.width,
        moreOrLessEquals(_page.height / _page.width, epsilon: 0.01));
    // Fit-to-width: the page tracks the viewport width (minus fixed chrome
    // padding), substantially wider than any fixed-size fallback.
    expect(pageSize.width, greaterThan(500));
  });

  testWidgets('arrow keys navigate (keyboard-operable, FR-018)',
      (WidgetTester tester) async {
    await _pumpPreview(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
    // Bounded: arrow-left on the first page stays on the first page.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
  });

  testWidgets('nav controls carry accessible names (FR-018)',
      (WidgetTester tester) async {
    await _pumpPreview(tester);
    expect(find.bySemanticsLabel('Next page'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous page'), findsOneWidget);
  });

  testWidgets('a single-page report disables both nav buttons',
      (WidgetTester tester) async {
    final RenderedReport report = const JetReportEngine().render(
      _template(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'name': 'only'},
      ]),
    );
    await _pumpPreview(tester, report: report);
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(
        tester.widget<ShadIconButton>(find.byKey(_prevKey)).onPressed, isNull);
    expect(
        tester.widget<ShadIconButton>(find.byKey(_nextKey)).onPressed, isNull);
  });

  testWidgets(
      'an unnamed report shows the shared "Untitled report" placeholder (017)',
      (WidgetTester tester) async {
    // The unified shell renders one placeholder in both modes (FR-006, parity)
    // — the designer's reportTitlePlaceholder, not the old preview-only label.
    final RenderedReport report = const JetReportEngine().render(
      const ReportTemplate(name: '', page: _page, bands: <ReportBand>[
        ReportBand(type: BandType.detail, height: 30),
      ]),
      JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{}]),
    );
    await _pumpPreview(tester, report: report);
    final Text nameText = tester.widget<Text>(
        find.byKey(const ValueKey<String>('jet_print.toolbar.name')));
    expect(nameText.data, 'Untitled report');
  });

  // 017 (US1 / C2): the preview hosts the same two-segment mode switch. Preview
  // is the active segment; selecting Designer emits the existing onBack switch
  // request (the standalone back button is gone, folded into the switch).
  group('mode switch (017 / US1)', () {
    testWidgets('renders the two-segment switch with Preview active', (
      WidgetTester tester,
    ) async {
      await _pumpPreview(tester, onBack: () {});
      expect(find.byKey(_modeDesignerKey), findsOneWidget);
      expect(find.byKey(_modePreviewKey), findsOneWidget);
      expect(_segmentVariant(tester, _modePreviewKey),
          ShadButtonVariant.secondary);
      expect(
          _segmentVariant(tester, _modeDesignerKey), ShadButtonVariant.ghost);
    });

    testWidgets('the Designer segment is disabled when onBack is null', (
      WidgetTester tester,
    ) async {
      await _pumpPreview(tester); // no onBack
      expect(_segmentDisabled(tester, _modeDesignerKey), isTrue);
    });

    testWidgets('selecting Designer fires onBack once (C2.3)', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await _pumpPreview(tester, onBack: () => taps++);
      expect(_segmentDisabled(tester, _modeDesignerKey), isFalse);
      await tester.tap(find.byKey(_modeDesignerKey));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('selecting the already-active Preview segment is a no-op', (
      WidgetTester tester,
    ) async {
      int backs = 0;
      await _pumpPreview(tester, onBack: () => backs++);
      await tester.tap(find.byKey(_modePreviewKey), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(backs, 0);
    });
  });

  group('zoom (fit-to-width multiplier)', () {
    String level(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(_zoomLevelKey)).data!;

    testWidgets('opens at 100% (fit to width)', (WidgetTester tester) async {
      await _pumpPreview(tester);
      expect(level(tester), '100%');
    });

    testWidgets('zoom in enlarges the page and updates the indicator',
        (WidgetTester tester) async {
      await _pumpPreview(tester, size: const Size(800, 600));
      final double fitWidth = tester.getSize(find.byKey(_pageKey)).width;
      await tester.tap(find.byKey(_zoomInKey));
      await tester.pumpAndSettle();
      expect(level(tester), '125%');
      expect(tester.getSize(find.byKey(_pageKey)).width, greaterThan(fitWidth));
    });

    testWidgets('zoom out shrinks the page below fit',
        (WidgetTester tester) async {
      await _pumpPreview(tester, size: const Size(800, 600));
      final double fitWidth = tester.getSize(find.byKey(_pageKey)).width;
      await tester.tap(find.byKey(_zoomOutKey));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_pageKey)).width, lessThan(fitWidth));
    });

    testWidgets('tapping the indicator resets to fit (100%)',
        (WidgetTester tester) async {
      await _pumpPreview(tester);
      await tester.tap(find.byKey(_zoomInKey));
      await tester.tap(find.byKey(_zoomInKey));
      await tester.pumpAndSettle();
      expect(level(tester), isNot('100%'));
      await tester.tap(find.byKey(_zoomLevelKey));
      await tester.pumpAndSettle();
      expect(level(tester), '100%');
    });

    testWidgets('zoom is bounded: zoom-out disables at the minimum',
        (WidgetTester tester) async {
      await _pumpPreview(tester);
      // 1.0 / 1.25^n reaches the 0.25 floor after enough steps.
      for (int i = 0; i < 12; i++) {
        final ShadIconButton out =
            tester.widget<ShadIconButton>(find.byKey(_zoomOutKey));
        if (out.onPressed == null) break;
        await tester.tap(find.byKey(_zoomOutKey));
        await tester.pumpAndSettle();
      }
      expect(tester.widget<ShadIconButton>(find.byKey(_zoomOutKey)).onPressed,
          isNull);
    });
  });

  group('export/print toolbar actions (012 — contract B8; FR-014/FR-015)', () {
    testWidgets(
        'absent (no buttons, no reserved space, no semantics) when both '
        'callbacks are null — 011 behavior bit-preserved',
        (WidgetTester tester) async {
      await _pumpPreview(tester);
      expect(find.byKey(_exportKey), findsNothing);
      expect(find.byKey(_printKey), findsNothing);
      expect(find.bySemanticsLabel('Export as PDF'), findsNothing);
      expect(find.bySemanticsLabel('Print'), findsNothing);
    });

    testWidgets(
        'a non-null onExportPdf adds the export action; tap invokes the '
        'callback; print stays absent', (WidgetTester tester) async {
      int exports = 0;
      await _pumpPreview(tester, onExportPdf: () => exports++);
      expect(find.byKey(_exportKey), findsOneWidget);
      expect(find.byKey(_printKey), findsNothing,
          reason: 'each action appears only with its own callback');
      expect(find.bySemanticsLabel('Export as PDF'), findsOneWidget,
          reason: 'localized accessible name (FR-014)');
      await tester.tap(find.byKey(_exportKey));
      await tester.pumpAndSettle();
      expect(exports, 1,
          reason: 'the library invokes the callback and performs no I/O');
    });

    testWidgets('a non-null onPrint adds the print action; tap invokes it',
        (WidgetTester tester) async {
      int prints = 0;
      await _pumpPreview(tester, onPrint: () => prints++);
      expect(find.byKey(_printKey), findsOneWidget);
      expect(find.byKey(_exportKey), findsNothing);
      expect(find.bySemanticsLabel('Print'), findsOneWidget);
      await tester.tap(find.byKey(_printKey));
      await tester.pumpAndSettle();
      expect(prints, 1);
    });

    testWidgets('both callbacks wired -> both actions, independently invoked',
        (WidgetTester tester) async {
      int exports = 0;
      int prints = 0;
      await _pumpPreview(tester,
          onExportPdf: () => exports++, onPrint: () => prints++);
      await tester.tap(find.byKey(_exportKey));
      await tester.tap(find.byKey(_printKey));
      await tester.pumpAndSettle();
      expect(exports, 1);
      expect(prints, 1);
    });

    testWidgets('keyboard activation invokes the callbacks (FR-014)',
        (WidgetTester tester) async {
      int exports = 0;
      int prints = 0;
      await _pumpPreview(tester,
          onExportPdf: () => exports++, onPrint: () => prints++);
      await _activateWithKeyboard(tester, _exportKey, LogicalKeyboardKey.enter);
      expect(exports, 1, reason: 'Enter activates the focused export action');
      await _activateWithKeyboard(tester, _printKey, LogicalKeyboardKey.enter);
      expect(prints, 1, reason: 'Enter activates the focused print action');
    });
  });

  // 017 (US3 / C5.2 / SC-005): the preview's right slot carries the viewing
  // actions exclusively — none of the designer's editing-only actions appear.
  group('preview — mode-specific actions (017 / US3)', () {
    testWidgets('the right slot shows the viewing actions (C5.2)', (
      WidgetTester tester,
    ) async {
      await _pumpPreview(tester, onExportPdf: () {}, onPrint: () {});
      expect(find.byKey(_exportKey), findsOneWidget);
      expect(find.byKey(_printKey), findsOneWidget);
      expect(find.byKey(_zoomInKey), findsOneWidget);
      expect(find.byKey(_zoomOutKey), findsOneWidget);
      expect(find.byKey(_prevKey), findsOneWidget);
      expect(find.byKey(_nextKey), findsOneWidget);
    });

    testWidgets('no designer-only signature action is present (SC-005)', (
      WidgetTester tester,
    ) async {
      await _pumpPreview(tester, onExportPdf: () {}, onPrint: () {});
      // Undo/redo and the editing groups are designer-only.
      expect(
          find.byKey(const ValueKey<String>('jet_print.designer.action.undo')),
          findsNothing);
      expect(
          find.byKey(const ValueKey<String>('jet_print.designer.action.redo')),
          findsNothing);
      expect(
          find.byKey(const ValueKey<String>('jet_print.designer.action.cut')),
          findsNothing);
    });
  });
}
