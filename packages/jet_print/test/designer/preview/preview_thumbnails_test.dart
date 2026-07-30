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
}
