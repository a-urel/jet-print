/// The playground's pivot-grid sample: a two-level row axis (Region over
/// City, both totalled) crossed with a two-level column axis (Year over
/// Quarter) and two measures — authored entirely through the library's public
/// API (`package:jet_print/jet_print.dart`), the way an external consumer
/// would.
///
/// One flat row per (region, city, year, quarter) combination; the
/// [CrosstabNode] folds the root scope's own rows directly (no nested
/// collection). The column axis alone — two years x two quarters, each level
/// totalled — already produces more leaves than fit in a narrow page body, so
/// this sample also exercises the crosstab's horizontal-continuation path
/// (see `rendered_pivot_example.dart` / `pivot_test.dart`).
library;

import 'package:jet_print/jet_print.dart';

/// The data structure: one flat row per (region, city, year, quarter) slice,
/// carrying a quantity and a unit price. Attach it via `dataSchema:` on the
/// designer tab.
const JetDataSchema pivotSchema = JetDataSchema(
  name: 'Sales Pivot',
  fields: <FieldDef>[
    FieldDef('region', type: JetFieldType.string),
    FieldDef('city', type: JetFieldType.string),
    FieldDef('year', type: JetFieldType.string),
    FieldDef('quarter', type: JetFieldType.string),
    FieldDef('qty', type: JetFieldType.integer),
    FieldDef('price', type: JetFieldType.double),
  ],
);

/// The page: wide enough for the whole crosstab (2 years x 2 quarters, each
/// level totalled -> 7 leaf columns of 2 measures at 64pt each, plus the
/// 110pt row-label column) to fit in one horizontal slice.
const PageFormat _pivotPage =
    PageFormat(width: 1100, height: 300, margins: JetEdgeInsets.all(20));

/// The pivot report: title band + one [CrosstabNode], reading the flat rows
/// [pivotData] supplies directly (no `collectionField` — the crosstab folds
/// the root scope's own rows). [page] defaults to [_pivotPage]; a narrower
/// page format forces the column axis into more than one horizontal slice
/// (see the golden's continuation-page expectation).
ReportDefinition pivotDefinition({PageFormat page = _pivotPage}) =>
    ReportDefinition(
      name: 'Sales Pivot',
      page: page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'title',
              type: BandType.title,
              height: 24,
              elements: <ReportElement>[
                TextElement(
                  id: 'heading',
                  bounds: const JetRect(x: 0, y: 2, width: 400, height: 20),
                  text: 'Sales by Region and Quarter',
                  style: const JetTextStyle(
                      fontSize: 14, weight: JetFontWeight.bold),
                ),
              ],
            )),
            const CrosstabNode(Crosstab(
              id: 'salesPivot',
              name: 'Sales Pivot',
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

/// One flat row per (region, city, year, quarter) combination — two regions,
/// two cities each, two years, two quarters each: 16 rows.
List<Map<String, Object?>> pivotData() {
  const List<(String region, String city)> places = <(String, String)>[
    ('North', 'Istanbul'),
    ('North', 'Ankara'),
    ('South', 'Izmir'),
    ('South', 'Antalya'),
  ];
  const List<String> years = <String>['2025', '2026'];
  const List<String> quarters = <String>['Q1', 'Q2'];

  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  int seed = 0;
  for (final (String region, String city) in places) {
    for (final String year in years) {
      for (final String quarter in quarters) {
        seed++;
        rows.add(<String, Object?>{
          'region': region,
          'city': city,
          'year': year,
          'quarter': quarter,
          'qty': 10 + seed,
          'price': 5.0 + (seed % 3),
        });
      }
    }
  }
  return rows;
}
