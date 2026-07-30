// The preview's thumbnail rail and its toolbar toggle (044). Black-box: this
// test stands in for an external consumer and imports only the public entry
// point.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

const Key _toggleKey = ValueKey<String>('jet_print.preview.thumbnails');
const Key _listKey = ValueKey<String>('jet_print.preview.thumbnails.list');
Key _tileKey(int index) => ValueKey<String>('jet_print.preview.thumbnail.$index');

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
}
