// Rendered crosstab (pivot grid) golden (spec A / Task 12). Public API only;
// regenerate with `--update-goldens`.
//
// Region over City on the row axis (both totalled), Year over Quarter on the
// column axis (both totalled), two measures. The column axis alone already
// produces more leaf columns than fit on a narrow page, so a second
// expectation below renders the same crosstab on a narrow page and asserts
// the layout paginates — the horizontal-continuation path this golden suite
// had not exercised before.
@Tags(['golden'])
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// One flat row per (region, city, year, quarter) combination, folded
/// directly by the crosstab (no `collectionField`).
const List<Map<String, Object?>> _pivotRows = <Map<String, Object?>>[
  <String, Object?>{
    'region': 'North',
    'city': 'Istanbul',
    'year': '2025',
    'quarter': 'Q1',
    'qty': 12,
    'price': 5.0
  },
  <String, Object?>{
    'region': 'North',
    'city': 'Istanbul',
    'year': '2025',
    'quarter': 'Q2',
    'qty': 15,
    'price': 5.5
  },
  <String, Object?>{
    'region': 'North',
    'city': 'Istanbul',
    'year': '2026',
    'quarter': 'Q1',
    'qty': 18,
    'price': 6.0
  },
  <String, Object?>{
    'region': 'North',
    'city': 'Istanbul',
    'year': '2026',
    'quarter': 'Q2',
    'qty': 20,
    'price': 6.5
  },
  <String, Object?>{
    'region': 'North',
    'city': 'Ankara',
    'year': '2025',
    'quarter': 'Q1',
    'qty': 8,
    'price': 4.0
  },
  <String, Object?>{
    'region': 'North',
    'city': 'Ankara',
    'year': '2025',
    'quarter': 'Q2',
    'qty': 9,
    'price': 4.5
  },
  <String, Object?>{
    'region': 'North',
    'city': 'Ankara',
    'year': '2026',
    'quarter': 'Q1',
    'qty': 11,
    'price': 4.0
  },
  <String, Object?>{
    'region': 'North',
    'city': 'Ankara',
    'year': '2026',
    'quarter': 'Q2',
    'qty': 13,
    'price': 4.5
  },
  <String, Object?>{
    'region': 'South',
    'city': 'Izmir',
    'year': '2025',
    'quarter': 'Q1',
    'qty': 10,
    'price': 3.5
  },
  <String, Object?>{
    'region': 'South',
    'city': 'Izmir',
    'year': '2025',
    'quarter': 'Q2',
    'qty': 12,
    'price': 3.5
  },
  <String, Object?>{
    'region': 'South',
    'city': 'Izmir',
    'year': '2026',
    'quarter': 'Q1',
    'qty': 14,
    'price': 4.0
  },
  <String, Object?>{
    'region': 'South',
    'city': 'Izmir',
    'year': '2026',
    'quarter': 'Q2',
    'qty': 16,
    'price': 4.0
  },
  <String, Object?>{
    'region': 'South',
    'city': 'Antalya',
    'year': '2025',
    'quarter': 'Q1',
    'qty': 6,
    'price': 3.0
  },
  <String, Object?>{
    'region': 'South',
    'city': 'Antalya',
    'year': '2025',
    'quarter': 'Q2',
    'qty': 7,
    'price': 3.0
  },
  <String, Object?>{
    'region': 'South',
    'city': 'Antalya',
    'year': '2026',
    'quarter': 'Q1',
    'qty': 9,
    'price': 3.5
  },
  <String, Object?>{
    'region': 'South',
    'city': 'Antalya',
    'year': '2026',
    'quarter': 'Q2',
    'qty': 10,
    'price': 3.5
  },
];

/// The default page: 7 leaf columns of 2 measures at 50pt, plus the 90pt
/// row-label column — 790pt of content, needing a 700pt slice budget
/// (790 - 90 rowLabelWidth). `sliceColumns` packs that content into ONE
/// slice here only because its trailing-total reservation check is `<=`: 6
/// data leaves at 100pt plus a 100pt grand-total reservation is *exactly*
/// 700. A page sized to that boundary is one rounding error, one extra
/// total, or one wider measure column away from silently becoming a
/// two-slice pagination test instead of a one-slice layout test — so this
/// page is 20pt wider than the content strictly needs, landing the real
/// budget (720) comfortably clear of it. A narrower [page] forces the column
/// axis into more than one slice regardless (see the pagination test below).
/// Wider than [_pump]'s surface on purpose — see [_pump]'s dartdoc for why
/// that's fine here.
const PageFormat _pivotPage =
    PageFormat(width: 840, height: 260, margins: JetEdgeInsets.all(15));

/// Mildly compact metrics — smaller than [CrosstabStyle]'s defaults, but each
/// measure column (50pt) still comfortably clears the widest value this
/// fixture prints ('858.00', ~40pt at the default 12pt font) with room to
/// spare, and the row-label column (90pt) comfortably clears 'Total North' /
/// 'Total South'. A tighter width (36pt was tried) let adjacent cells' text
/// visually run together — column width must fit the *content*, independent
/// of whatever zoom the preview later applies (a uniform canvas scale changes
/// how large everything looks, never whether one cell's text overflows into
/// its neighbor).
const CrosstabStyle _style = CrosstabStyle(
  rowLabelWidth: 90,
  rowLabelIndent: 10,
  measureColumnWidth: 50,
  rowHeight: 13,
  headerRowHeight: 13,
);

/// A crosstab: Region > City rows (both totalled), Year > Quarter columns
/// (both totalled), Qty (sum, formatted as an integer) and Amount (sum of qty
/// * price) measures.
ReportDefinition _definition({PageFormat page = _pivotPage}) =>
    ReportDefinition(
      name: 'Pivot',
      page: page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            CrosstabNode(Crosstab(
              id: 'salesPivot',
              rowGroups: const <CrosstabGroup>[
                CrosstabGroup(
                  id: 'g-region',
                  name: 'Region',
                  expression: r'$F{region}',
                  showTotal: true,
                ),
                CrosstabGroup(
                  id: 'g-city',
                  name: 'City',
                  expression: r'$F{city}',
                  showTotal: true,
                ),
              ],
              columnGroups: const <CrosstabGroup>[
                CrosstabGroup(
                  id: 'g-year',
                  name: 'Year',
                  expression: r'$F{year}',
                  showTotal: true,
                ),
                CrosstabGroup(
                  id: 'g-quarter',
                  name: 'Quarter',
                  expression: r'$F{quarter}',
                  showTotal: true,
                ),
              ],
              measures: const <CrosstabMeasure>[
                CrosstabMeasure(
                  id: 'm-qty',
                  name: 'Qty',
                  expression: r'$F{qty}',
                  aggregate: JetCalculation.sum,
                  format: '#,##0',
                ),
                CrosstabMeasure(
                  id: 'm-amount',
                  name: 'Amount',
                  expression: r'$F{qty} * $F{price}',
                  aggregate: JetCalculation.sum,
                  format: '#,##0.00',
                ),
              ],
              style: _style,
            )),
          ],
        ),
      ),
    );

RenderedReport _report({PageFormat? page}) =>
    const JetReportEngine().renderDefinition(
      _definition(page: page ?? _pivotPage),
      JetInMemoryDataSource(_pivotRows),
    );

/// Deliberately narrower than [_pivotPage] (840pt): staying under 600px here
/// clears TWO of [JetReportPreview]'s breakpoints at once — its 700px
/// thumbnail-rail auto-hide (so this golden shows only the toolbar and
/// canvas, matching `label_sheet_light.png` and its siblings) and its 600px
/// desktop-vs-phone default-zoom split (`kDefaultZoomDesktopMinWidth`), which
/// keeps the preview in fit-to-width mode. Fit-to-width uniformly rescales
/// the whole page to the viewport, so it can never crop — a wider surface
/// that instead landed in the ">=600 -> 100% actual size" branch would need
/// the FULL 840pt-plus-margins page to already fit in the window, and did not
/// (an earlier 1300px-wide attempt showed the whole crosstab but pulled in
/// the thumbnail rail as a side effect — see Task 12's review history).
Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(560, 380));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    themeMode: ThemeMode.light,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadSlateColorScheme.light(),
    ),
    home: JetReportPreview(report: _report()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rendered pivot page 1 matches its light golden',
      (WidgetTester tester) async {
    await _pump(tester);
    await expectLater(
      find.byType(JetReportPreview),
      matchesGoldenFile('pivot_light.png'),
    );
  });

  test('a narrow page forces the crosstab into more than one page', () {
    final RenderedReport narrow = _report(
      page: const PageFormat(
          width: 300, height: 300, margins: JetEdgeInsets.all(20)),
    );
    expect(narrow.pageCount, greaterThan(1));
  });
}
