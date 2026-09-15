// The preview's thumbnail rail and its toolbar toggle (044). Black-box: this
// test stands in for an external consumer and imports only the public entry
// point.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

const Key _toggleKey = ValueKey<String>('jet_print.preview.thumbnails');
const Key _listKey = ValueKey<String>('jet_print.preview.thumbnails.list');
const Key _nextKey = ValueKey<String>('jet_print.preview.next');
Key _tileKey(int index) =>
    ValueKey<String>('jet_print.preview.thumbnail.$index');

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

RenderedReport _report({int rows = 6}) =>
    const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < rows; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

/// A tiny but genuinely valid PNG (the export-fixtures precedent,
/// `test/rendering/export/support/export_fixtures.dart`) — real bytes, not
/// corrupt ones, so decoding it never throws; it just never *finishes*
/// without `tester.runAsync()` (below).
Uint8List _validPngBytes() {
  final img.Image image = img.Image(width: 4, height: 2);
  for (int y = 0; y < 2; y++) {
    for (int x = 0; x < 4; x++) {
      image.setPixelRgba(x, y, 32 + 48 * x, 64 + 64 * y, 200, 255);
    }
  }
  return img.encodePng(image);
}

/// A report whose report-header (`body.title`, printed once on page 0 only —
/// the `imageReport`/rail-test precedent) embeds a valid image: recording
/// page 0 calls `ui.instantiateImageCodec`, a genuinely engine-mediated async
/// operation that a plain widget test (no `tester.runAsync()`) never
/// completes — the initial page's record stays reliably in flight for the
/// whole test, so nothing can race the toolbar assertions below. Using real
/// (not corrupt) bytes matters: the preview's own `_record()` has no
/// try/catch around `paintFrame`, so a genuinely failing decode would
/// eventually surface as an uncaught async error once it settled.
RenderedReport _reportWithBlockingImage() =>
    const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'Quarterly Report',
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
        for (int i = 0; i < 6; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

Future<void> _pumpPreview(
  WidgetTester tester, {
  Size size = const Size(1000, 700),
  bool showThumbnails = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: JetReportPreview(
      report: _report(),
      showThumbnails: showThumbnails,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a wide preview opens with the rail shown', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester);
    expect(find.byKey(_listKey), findsOneWidget);
  });

  testWidgets('the toolbar toggle hides and re-shows the rail', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsNothing);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);
  });

  testWidgets('showThumbnails: false opens hidden, and the toggle still works',
      (WidgetTester tester) async {
    await _pumpPreview(tester, showThumbnails: false);
    expect(find.byKey(_listKey), findsNothing);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);
  });

  testWidgets('a narrow preview opens with the rail auto-hidden', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, size: const Size(600, 700));
    expect(find.byKey(_listKey), findsNothing);

    // The breakpoint only picks the default; the user can still open it.
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);
  });

  testWidgets(
      'a narrow preview repaints the toolbar toggle to OFF on its own, not '
      'only once the unrelated async page record happens to complete', (
    WidgetTester tester,
  ) async {
    // The narrow one-shot resolves during the BODY LayoutBuilder's layout —
    // after the toolbar (a Column sibling built earlier in the same frame)
    // already painted using the pre-one-shot (`true`) value. `initState`'s
    // unrelated async `_record()` is what accidentally fixes the toolbar
    // today (its `setState` forces a correcting rebuild) — so to prove THIS
    // fix, not that accident, the report's page 0 embeds an image: recording
    // it calls `ui.instantiateImageCodec`, a genuinely engine-mediated async
    // call this plain widget test (no `tester.runAsync()`) never completes,
    // so `_record()` stays reliably in flight for the test's whole lifetime
    // and cannot race these assertions.
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ShadApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: JetReportPreview(report: _reportWithBlockingImage()),
    ));
    await tester.pump();

    expect(find.byKey(_listKey), findsNothing,
        reason: 'the rail itself already hides on this frame (a plain field '
            'write consumed by the same LayoutBuilder build)');
    expect(find.bySemanticsLabel('Show page thumbnails'), findsOneWidget,
        reason: 'the toggle should already read as OFF here, not still '
            'showing the stale pre-one-shot ON state');
    expect(find.bySemanticsLabel('Hide page thumbnails'), findsNothing);
    expect(
      tester.widget<ShadIconButton>(find.byKey(_toggleKey)).variant,
      ShadButtonVariant.ghost,
      reason: 'the inactive (ghost) variant, not the active (secondary) one',
    );
  });

  testWidgets('tapping a thumbnail navigates the preview to that page', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester);
    expect(find.text('Page 1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(_tileKey(2)));
    await tester.pumpAndSettle();

    expect(find.text('Page 3 of 3'), findsOneWidget);
  });

  testWidgets('the toggle carries a state-dependent accessible name', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester);
    expect(find.bySemanticsLabel('Hide page thumbnails'), findsOneWidget);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Show page thumbnails'), findsOneWidget);
  });

  testWidgets(
      'a host rebuild never re-seeds showThumbnails — it is an initial value',
      (WidgetTester tester) async {
    // Same root widget type/position at every pump (no key change), so
    // Flutter runs didUpdateWidget on the existing State instead of
    // remounting a fresh one — a fresh State would make this test pass
    // vacuously. A fresh RenderedReport on each pump (varied row count, so
    // it's a genuinely different, non-identical report — an innocuous stand-
    // in for "the host re-rendered after some unrelated change") makes the
    // rebuild observable and exercises the same `!identical(oldWidget.report,
    // widget.report)` branch a real host hits after e.g. a rename.
    Widget host(RenderedReport report) => ShadApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            JetPrintLocalizations.delegate,
          ],
          supportedLocales: JetPrintLocalizations.supportedLocales,
          home: JetReportPreview(report: report, showThumbnails: true),
        );

    await tester.pumpWidget(host(_report()));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);

    // The user explicitly hides the rail.
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsNothing);

    // The host rebuilds — same showThumbnails: true it always passed — after
    // some unrelated change (a fresh report). The user's toggle must still
    // win: showThumbnails is an initial value, not re-seeded on every build.
    await tester.pumpWidget(host(_report(rows: 9)));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsNothing);

    // Converse direction: re-open, then rebuild again — stays open.
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);

    await tester.pumpWidget(host(_report(rows: 12)));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);
  });

  testWidgets('navigating from the toolbar scrolls the rail to that page', (
    WidgetTester tester,
  ) async {
    // 60 rows -> 30 pages: far more tiles than fit in a 700pt-tall rail.
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ShadApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: JetReportPreview(report: _report(rows: 60), initialPage: 0),
    ));
    await tester.pumpAndSettle();

    final double before =
        tester.widget<ListView>(find.byKey(_listKey)).controller!.offset;
    expect(before, 0);

    // Walk far enough that the target tile is well below the fold.
    for (int i = 0; i < 20; i++) {
      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
    }

    final double after =
        tester.widget<ListView>(find.byKey(_listKey)).controller!.offset;
    expect(after, greaterThan(before),
        reason: 'the rail should have scrolled to follow the current page');
    expect(find.byKey(_tileKey(20)), findsOneWidget,
        reason: 'the current page tile should be built and visible');
  });

  testWidgets(
      'opening deep into a report reveals the current tile without any user '
      'interaction', (WidgetTester tester) async {
    // 60 rows -> 30 pages, opened at page 20 (well below the fold in a
    // 700pt-tall rail): the rail must sync to it on its own first layout,
    // not wait for a page-navigation event.
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ShadApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: JetReportPreview(report: _report(rows: 60), initialPage: 20),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(_tileKey(20)), findsOneWidget,
        reason: 'the current page tile should be built and visible on open, '
            'without any user interaction');
  });
}
