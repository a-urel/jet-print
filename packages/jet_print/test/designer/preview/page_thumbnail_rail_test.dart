// White-box widget test for the preview's page-thumbnail rail (044): tile
// count, selection chrome, tap-to-select, and the bounded picture cache. The
// rail is an unexported `src/` designer-internal seam (the
// expression_editor_dialog precedent), so this test imports it directly.
import 'dart:typed_data';
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

/// A report whose report-header (`body.title`, printed once on page 0 only —
/// the `imageReport` export-fixture precedent) embeds an image with garbage
/// bytes: `ui.instantiateImageCodec` throws for it inside
/// `CanvasPainter.prepare`, so recording page 0 always fails. Later pages hold
/// plain detail rows and record successfully, isolating the failure to one
/// known index.
RenderedReport _reportWithBadTitleImage({int rows = 6}) =>
    const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'Corrupt Image',
        page: _page,
        body: ReportBody(
          title: Band(
            id: 'body/title',
            type: BandType.title,
            height: 20,
            elements: <ReportElement>[
              ImageElement(
                id: 'bad-img',
                bounds: const JetRect(x: 0, y: 0, width: 16, height: 16),
                source: BytesImageSource(Uint8List.fromList(<int>[1, 2, 3, 4])),
              ),
            ],
          ),
          root: _definition().body.root,
        ),
      ),
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

  testWidgets(
      'a page whose recording throws is not stuck: a later rebuild retries it',
      (WidgetTester tester) async {
    // Page 0's report-header embeds a corrupt image, so
    // `CanvasPainter.prepare` throws every time page 0 is recorded; later
    // pages hold plain rows and record fine, isolating the failure.
    final RenderedReport report = _reportWithBadTitleImage();
    await _pumpRail(tester, report: report);
    final PageThumbnailRailState state =
        tester.state<PageThumbnailRailState>(find.byType(PageThumbnailRail));

    // The very first attempt at page 0 already ran to completion (inside
    // _pumpRail's pumpAndSettle) and threw. If the index leaked into
    // `_inFlight` forever (the bug), this would be stuck at 1 for the rest
    // of the widget's life; the `finally` fix clears it every time.
    expect(state.debugInFlightCount, 0);
    // Other pages succeeded, so the cache isn't empty even though page 0
    // never got a picture.
    expect(state.debugCachedCount, greaterThan(0));

    // Force a genuine second attempt: rebuilding with a different
    // `currentIndex` re-invokes `itemBuilder` (and so `_record`) for every
    // still-visible tile, including page 0's, whose picture is still null.
    // A stuck index would have no-op'd forever at `_record`'s first guard;
    // clearing it lets this second attempt actually run (and fail again).
    await _pumpRail(tester, report: report, currentIndex: 1);
    expect(state.debugInFlightCount, 0);
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
