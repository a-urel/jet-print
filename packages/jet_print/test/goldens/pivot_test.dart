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

/// A crosstab: Region > City rows (both totalled), Year > Quarter columns
/// (both totalled), Qty (sum) and Amount (sum of qty * price) measures. [page]
/// defaults wide enough (7 leaf columns of 2 measures at 64pt, plus the 110pt
/// row-label column) that everything fits in one horizontal slice; a narrower
/// [page] forces the column axis into more than one.
ReportDefinition _definition({
  PageFormat page = const PageFormat(
      width: 1100, height: 300, margins: JetEdgeInsets.all(20)),
}) =>
    ReportDefinition(
      name: 'Pivot',
      page: page,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            CrosstabNode(Crosstab(
              id: 'salesPivot',
              rowGroups: <CrosstabGroup>[
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
              columnGroups: <CrosstabGroup>[
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
              measures: <CrosstabMeasure>[
                CrosstabMeasure(
                  id: 'm-qty',
                  name: 'Qty',
                  expression: r'$F{qty}',
                  aggregate: JetCalculation.sum,
                ),
                CrosstabMeasure(
                  id: 'm-amount',
                  name: 'Amount',
                  expression: r'$F{qty} * $F{price}',
                  aggregate: JetCalculation.sum,
                  format: '#,##0.00',
                ),
              ],
            )),
          ],
        ),
      ),
    );

RenderedReport _report({PageFormat? page}) =>
    const JetReportEngine().renderDefinition(
      _definition(
          page: page ??
              const PageFormat(
                  width: 1100, height: 300, margins: JetEdgeInsets.all(20))),
      JetInMemoryDataSource(_pivotRows),
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1300, 380));
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
