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
      name: 'preview',
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

Future<void> _pumpPreview(
  WidgetTester tester, {
  RenderedReport? report,
  int initialPage = 0,
  Size size = const Size(800, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home:
        JetReportPreview(report: report ?? _report(), initialPage: initialPage),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the first page with a correct "page X of N" indicator',
      (WidgetTester tester) async {
    await _pumpPreview(tester);
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
}
