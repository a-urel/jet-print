// US1 end-to-end (011 — acceptance scenarios 1–5, SC-001/SC-002/SC-004/SC-005).
//
// The integration flow uses ONLY `package:jet_print/jet_print.dart`: build a
// data source, render a flat one-band template with a parameter, and preview
// it. The two `src/` imports below exist solely so ASSERTIONS can inspect the
// painted text runs (frame primitives are not part of the public surface);
// public-API sufficiency itself is enforced by the encapsulation test over
// the preview/playground tests, which use no `src/` import at all.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// 200x100 page, 10pt margins; 20pt header band + 30pt details -> 2 rows/page.
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ReportTemplate _template() => const ReportTemplate(
      name: 'US1',
      page: _page,
      parameters: <ReportParameter>[
        ReportParameter(name: 'printedBy', type: JetFieldType.string),
      ],
      bands: <ReportBand>[
        ReportBand(
          type: BandType.title,
          height: 20,
          elements: <ReportElement>[
            TextElement(
              id: 'by',
              bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
              text: 'by',
              expression: r'"Printed by " + $P{printedBy}',
            ),
          ],
        ),
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

JetInMemoryDataSource _source() => JetInMemoryDataSource(
      <Map<String, Object?>>[
        <String, Object?>{'name': 'alpha'},
        <String, Object?>{'name': 'beta'},
        <String, Object?>{'name': 'gamma'},
      ],
    );

RenderedReport _render() => const JetReportEngine().render(
      _template(),
      _source(),
      options: const RenderOptions(
        parameters: <String, Object?>{'printedBy': 'A. Urel'},
      ),
    );

List<String> _allRuns(RenderedReport report) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          p.lines.map((TextLine l) => l.text).join(),
    ];

void main() {
  test('scenario 1+2 — evaluated values and the parameter appear, no tokens',
      () {
    final RenderedReport report = _render();
    final List<String> runs = _allRuns(report);
    expect(runs, containsAll(<String>['alpha', 'beta', 'gamma']));
    expect(runs, contains('Printed by A. Urel'));
    for (final String run in runs) {
      expect(run, isNot(contains(r'$F{')));
      expect(run, isNot(contains(r'$P{')));
      expect(run, isNot(contains(r'$V{')));
    }
  });

  test('scenario 3 — the page count matches the content', () {
    // Title (20) + row (30) fill page 1 to 50/80, second row to 80/80; the
    // third row opens page 2.
    expect(_render().pageCount, 2);
  });

  test('scenario 5 — re-rendering identical inputs is deterministic', () {
    final RenderedReport a = _render();
    final RenderedReport b = _render();
    expect(a.pageCount, b.pageCount);
    for (int i = 0; i < a.pageCount; i++) {
      expect(a.pageAt(i).frame, b.pageAt(i).frame);
    }
  });

  testWidgets('scenario 4 — the preview opens and navigates between pages',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ShadApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: JetReportPreview(report: _render()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey<String>('jet_print.preview.next')));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
  });
}
