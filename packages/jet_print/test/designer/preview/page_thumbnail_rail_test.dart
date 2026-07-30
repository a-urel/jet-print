// White-box widget test for the preview's page-thumbnail rail (044): tile
// count, selection chrome, tap-to-select, and the bounded picture cache. The
// rail is an unexported `src/` designer-internal seam (the
// expression_editor_dialog precedent), so this test imports it directly.
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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

/// A report whose report-header (`body.title`, printed once on page 0 only)
/// embeds a GENUINE (not corrupt) image: recording page 0 calls
/// `ui.instantiateImageCodec`, an engine-mediated async decode a plain widget
/// test (no `tester.runAsync()`) never completes, so the record for index 0
/// stays reliably in flight for the whole test — unlike `_reportWithBadTitleImage`,
/// whose corrupt bytes fail fast and settle within a single `pumpAndSettle`.
RenderedReport _reportWithBlockingImage({int rows = 6}) =>
    const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'Blocking Image',
        page: _page,
        body: ReportBody(
          title: Band(
            id: 'body/title',
            type: BandType.title,
            height: 20,
            elements: <ReportElement>[
              ImageElement(
                id: 'blocking-img',
                bounds: const JetRect(x: 0, y: 0, width: 16, height: 16),
                source: BytesImageSource(_validPngBytes()),
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

/// A tiny but genuinely valid PNG (the export-fixtures precedent) — real
/// bytes, so decoding never throws; it just never *finishes* without
/// `tester.runAsync()`.
Uint8List _validPngBytes() {
  final img.Image image = img.Image(width: 4, height: 2);
  for (int y = 0; y < 2; y++) {
    for (int x = 0; x < 4; x++) {
      image.setPixelRgba(x, y, 32 + 48 * x, 64 + 64 * y, 200, 255);
    }
  }
  return img.encodePng(image);
}

Key _tileKey(int index) => ValueKey<String>('jet_print.preview.thumbnail.$index');

Future<void> _pumpRail(
  WidgetTester tester, {
  required RenderedReport report,
  int currentIndex = 0,
  Size size = const Size(400, 600),
  void Function(int)? onSelect,
  Brightness brightness = Brightness.light,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadSlateColorScheme.light(),
    ),
    darkTheme: ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadSlateColorScheme.dark(),
    ),
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

/// Like [_pumpRail], but a single `pump()` instead of `pumpAndSettle()` — for
/// a report whose page 0 embeds a genuinely blocking image (never resolves
/// without `tester.runAsync()`), `pumpAndSettle()` would otherwise be safe
/// (no Timer/animation keeps rescheduling frames), but a plain `pump()`
/// keeps the intent explicit: this call observes the state right after one
/// frame, deliberately before anything could settle.
Future<void> _pumpRailWithoutSettling(
  WidgetTester tester, {
  required RenderedReport report,
  int currentIndex = 0,
  Size size = const Size(400, 600),
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
        onSelect: (int _) {},
      ),
    ),
  ));
  await tester.pump();
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

  testWidgets(
      'a report swap while a record is in flight leaves debugInFlightCount '
      'consistent with the new report/generation, not a stale-plus-fresh '
      'double count', (WidgetTester tester) async {
    // NOTE on what this test can and cannot prove: the reviewer-identified
    // race is between a STALE record's `finally` (from before a swap)
    // actually firing, and a FRESH record already tracking the same index
    // under the new generation. Reliably forcing that exact interleaving
    // would need either (a) a real image decode's completion timed to land
    // precisely between two specific test steps — not controllable without
    // `tester.runAsync()`, whose real-world timing this test cannot pin to a
    // specific frame — or (b) a new test-only seam into `_record` (a pause
    // point), which the brief explicitly asked not to invent. So instead
    // this pins what IS deterministically reachable: that swapping the
    // report while an old record is verifiably still in flight (blocking
    // image, never resolves without runAsync) leaves the rail's bookkeeping
    // internally consistent — exactly one in-flight record, matching the
    // freshly (re)scheduled request for the CURRENT report — rather than
    // either losing track of it (0) or somehow double-tracking it. The
    // generation-guard's specific job (not letting a stale completion clear
    // a slot a newer record now owns) was verified by code inspection instead
    // — see the task-8 report for the full reasoning — and by this suite's
    // existing throwing-record test still passing unchanged (proving the
    // guard doesn't break the ordinary, same-generation retry contract).
    // A single-page report (2 rows -> 1 page): its ONE tile is index 0, so the
    // aggregate `debugCachedCount`/`debugInFlightCount` counters map exactly
    // onto that one blocked record, with no other (unblocked) visible tiles
    // muddying the counts.
    final RenderedReport reportA = _reportWithBlockingImage(rows: 2);
    await _pumpRailWithoutSettling(tester, report: reportA, currentIndex: 0);
    final PageThumbnailRailState state =
        tester.state<PageThumbnailRailState>(find.byType(PageThumbnailRail));

    expect(state.debugInFlightCount, 1,
        reason: 'report A page 0 is genuinely recording (blocking image, '
            'never resolves without runAsync)');
    expect(state.debugCachedCount, 0);

    // Swap to a different report — also with a blocking image on page 0, so
    // neither the abandoned old record nor the fresh new one can settle
    // during this test, keeping the observation window open.
    final RenderedReport reportB = _reportWithBlockingImage(rows: 2);
    await _pumpRailWithoutSettling(tester, report: reportB, currentIndex: 0);

    expect(state.debugInFlightCount, 1,
        reason: 'the swap should track exactly the freshly-scheduled record '
            'for the new report/generation — not 0 (lost track of it) and '
            'not more than 1 (double-tracking the same index)');
    expect(state.debugCachedCount, 0,
        reason: 'neither the abandoned old record nor the fresh new one has '
            'settled — both stay genuinely blocked without runAsync');
  });

  testWidgets(
      'the rail is a distinct surface from the preview body, in both themes',
      (WidgetTester tester) async {
    for (final Brightness brightness in <Brightness>[
      Brightness.light,
      Brightness.dark,
    ]) {
      await _pumpRail(tester, report: _report(), brightness: brightness);

      // `.first` is the rail's own surface: depth-first order puts it ahead
      // of the per-tile decorations nested inside the list.
      final BoxDecoration decoration = tester
          .widget<DecoratedBox>(find
              .descendant(
                of: find.byType(PageThumbnailRail),
                matching: find.byType(DecoratedBox),
              )
              .first)
          .decoration as BoxDecoration;
      final ShadColorScheme colors = ShadTheme.of(
        tester.element(find.byType(PageThumbnailRail)),
      ).colorScheme;

      // The preview body paints `muted` behind everything; a rail painted the
      // same colour has no visible edge of its own — which is exactly what
      // went wrong in dark mode.
      expect(decoration.color, isNot(colors.muted),
          reason: 'the rail must not reuse the body backdrop colour '
              '($brightness)');
      expect(decoration.boxShadow, isNotNull, reason: '$brightness');
      expect(decoration.boxShadow, isNotEmpty,
          reason: 'the rail should cast a shadow over the page area '
              '($brightness)');
    }
  });

  testWidgets(
      'the selected tile carries a primary-coloured border the unselected '
      'tile lacks', (WidgetTester tester) async {
    await _pumpRail(tester, report: _report(), currentIndex: 0);

    final Container selectedTile =
        tester.widget<Container>(find.byKey(_tileKey(0)));
    final Container unselectedTile =
        tester.widget<Container>(find.byKey(_tileKey(1)));

    expect(selectedTile.foregroundDecoration, isNotNull,
        reason: 'the selected sheet should carry a selection border');
    expect((selectedTile.foregroundDecoration! as BoxDecoration).border,
        isNotNull);
    expect(unselectedTile.foregroundDecoration, isNull,
        reason: 'an unselected sheet should carry no selection border');
  });

  testWidgets('selection never changes the sheet geometry (no zoom)',
      (WidgetTester tester) async {
    await _pumpRail(tester, report: _report(), currentIndex: 0);

    // The selection border is painted as a foreground decoration precisely so
    // it costs no layout: a border in `decoration` would inset the child,
    // shrinking the box the page picture is blitted into while its scale
    // stays fixed — i.e. the selected page would look zoomed and cropped.
    final Size selectedSize = tester.getSize(find.byKey(_tileKey(0)));
    final Size unselectedSize = tester.getSize(find.byKey(_tileKey(1)));
    expect(selectedSize, unselectedSize);

    final BoxDecoration selectedDecoration = tester
        .widget<Container>(find.byKey(_tileKey(0)))
        .decoration! as BoxDecoration;
    final BoxDecoration unselectedDecoration = tester
        .widget<Container>(find.byKey(_tileKey(1)))
        .decoration! as BoxDecoration;
    expect(
      selectedDecoration.border!.dimensions,
      unselectedDecoration.border!.dimensions,
      reason: 'the laid-out border must be identical, so the blitted picture '
          'occupies the same box on every tile',
    );
    expect(selectedDecoration.boxShadow, anyOf(isNull, isEmpty),
        reason: 'no halo — selection is carried by the border alone');
  });

  testWidgets(
      'the selected tile\'s caption is a filled pill; the unselected caption '
      'is plain text', (WidgetTester tester) async {
    await _pumpRail(tester, report: _report(), currentIndex: 0);

    // The selected caption ('1') sits inside a decorated Container (the
    // pill); the unselected caption ('2') is a bare Text with no ancestor
    // Container between it and the tile's Column.
    final Finder selectedPill = find.ancestor(
      of: find.text('1'),
      matching: find.byType(Container),
    );
    expect(selectedPill, findsOneWidget,
        reason: 'the selected page number should be wrapped in a filled pill');
    final BoxDecoration pillDecoration =
        tester.widget<Container>(selectedPill).decoration! as BoxDecoration;
    expect(pillDecoration.color, isNotNull);

    final Finder unselectedPill = find.ancestor(
      of: find.text('2'),
      matching: find.byType(Container),
    );
    expect(unselectedPill, findsNothing,
        reason: 'an unselected page number should stay plain text, no pill');
  });

  testWidgets(
      'the first tile sits below the rail top edge by the inter-tile gap',
      (WidgetTester tester) async {
    await _pumpRail(tester, report: _report());

    final double railTop =
        tester.getTopLeft(find.byType(PageThumbnailRail)).dy;
    final double tileTop = tester.getTopLeft(find.byKey(_tileKey(0))).dy;

    expect(tileTop - railTop, 10,
        reason: 'the first tile should have the same breathing room above it '
            'as the gap between tiles, not sit flush against the rail top');
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
