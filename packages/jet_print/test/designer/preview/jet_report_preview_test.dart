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

const Key _backKey = ValueKey<String>('jet_print.preview.back');
const Key _zoomInKey = ValueKey<String>('jet_print.preview.zoomIn');
const Key _zoomOutKey = ValueKey<String>('jet_print.preview.zoomOut');
const Key _zoomLevelKey = ValueKey<String>('jet_print.preview.zoomLevel');

Future<void> _pumpPreview(
  WidgetTester tester, {
  RenderedReport? report,
  int initialPage = 0,
  Size size = const Size(800, 600),
  VoidCallback? onBack,
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
    ),
  ));
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
    await _pumpPreview(tester);

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

  testWidgets('an unnamed report falls back to the localized "Preview" title',
      (WidgetTester tester) async {
    final RenderedReport report = const JetReportEngine().render(
      const ReportTemplate(name: '', page: _page, bands: <ReportBand>[
        ReportBand(type: BandType.detail, height: 30),
      ]),
      JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{}]),
    );
    await _pumpPreview(tester, report: report);
    expect(find.text('Preview'), findsOneWidget);
  });

  group('back button (FR-018)', () {
    testWidgets('absent unless onBack is wired', (WidgetTester tester) async {
      await _pumpPreview(tester);
      expect(find.byKey(_backKey), findsNothing);
    });

    testWidgets('shown and invokes onBack when wired; carries its name',
        (WidgetTester tester) async {
      int taps = 0;
      await _pumpPreview(tester, onBack: () => taps++);
      expect(find.byKey(_backKey), findsOneWidget);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      await tester.tap(find.byKey(_backKey));
      await tester.pumpAndSettle();
      expect(taps, 1);
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
}
