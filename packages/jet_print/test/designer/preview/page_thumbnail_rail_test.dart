// White-box widget test for the preview's page-thumbnail rail (044): tile
// count, selection chrome, tap-to-select, and the bounded picture cache. The
// rail is an unexported `src/` designer-internal seam (the
// expression_editor_dialog precedent), so this test imports it directly.
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/preview/page_thumbnail_rail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// 200x100 page, 10pt margins -> 80pt body; 30pt detail bands -> 2 rows/page.
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ReportDefinition _definition() => const ReportDefinition(
      name: 'Quarterly Report',
      page: _page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
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
            )),
          ],
        ),
      ),
    );

/// A report of `rows / 2` pages (2 rows fit per page).
RenderedReport _report({int rows = 6}) =>
    const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < rows; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

Key _tileKey(int index) => ValueKey<String>('jet_print.preview.thumbnail.$index');

Future<void> _pumpRail(
  WidgetTester tester, {
  required RenderedReport report,
  int currentIndex = 0,
  Size size = const Size(400, 600),
  void Function(int)? onSelect,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: Align(
      alignment: Alignment.topLeft,
      child: PageThumbnailRail(
        report: report,
        currentIndex: currentIndex,
        onSelect: onSelect ?? (int _) {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders one tile per page, captioned with the page number', (
    WidgetTester tester,
  ) async {
    await _pumpRail(tester, report: _report()); // 3 pages

    expect(find.byKey(_tileKey(0)), findsOneWidget);
    expect(find.byKey(_tileKey(1)), findsOneWidget);
    expect(find.byKey(_tileKey(2)), findsOneWidget);
    expect(find.byKey(_tileKey(3)), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping a tile reports that page index', (
    WidgetTester tester,
  ) async {
    final List<int> selected = <int>[];
    await _pumpRail(tester, report: _report(), onSelect: selected.add);

    await tester.tap(find.byKey(_tileKey(2)));
    await tester.pumpAndSettle();

    expect(selected, <int>[2]);
  });

  testWidgets('the current page tile is marked selected for a11y', (
    WidgetTester tester,
  ) async {
    // A live semantics tree requires an explicit handle in a widget test (no
    // assistive technology is attached to request one). Disposed synchronously
    // at the end of the test body: flutter_test's end-of-test semantics check
    // runs before `addTearDown` callbacks would fire.
    final SemanticsHandle handle = tester.ensureSemantics();
    await _pumpRail(tester, report: _report(), currentIndex: 1);

    final SemanticsNode node = tester.getSemantics(find.byKey(_tileKey(1)));
    expect(node.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
    final SemanticsNode other = tester.getSemantics(find.byKey(_tileKey(0)));
    expect(
        other.getSemanticsData().flagsCollection.isSelected, Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('records a picture for the visible tiles', (
    WidgetTester tester,
  ) async {
    await _pumpRail(tester, report: _report());

    final PageThumbnailRailState state =
        tester.state<PageThumbnailRailState>(find.byType(PageThumbnailRail));
    expect(state.debugCachedCount, greaterThan(0));
  });

  testWidgets('the picture cache stays within its cap while scrolling', (
    WidgetTester tester,
  ) async {
    // 120 rows -> 60 pages, far more than the 24-picture cap.
    await _pumpRail(tester, report: _report(rows: 120));
    final PageThumbnailRailState state =
        tester.state<PageThumbnailRailState>(find.byType(PageThumbnailRail));

    for (int i = 0; i < 10; i++) {
      await tester.drag(
        find.byKey(const ValueKey<String>('jet_print.preview.thumbnails.list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(state.debugCachedCount, lessThanOrEqualTo(24));
    }
  });
}
