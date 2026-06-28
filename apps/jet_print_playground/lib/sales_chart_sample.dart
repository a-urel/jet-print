/// The playground's sales-chart sample: three chart types (bar, line, pie)
/// over monthly revenue/unit data — authored entirely through the library's
/// public API (`package:jet_print/jet_print.dart`), the way an external
/// consumer would.
///
/// One master row carries a `months` nested collection; the three [ChartElement]
/// bands each read that same collection and render a different chart type from
/// it. The schema is supplied so the designer's binding affordances resolve the
/// nested fields correctly.
library;

import 'package:jet_print/jet_print.dart';

/// The data structure: one master row with a nested `months` collection.
/// Attach it via `dataSchema:` on the designer tab.
const JetDataSchema salesChartSchema = JetDataSchema(
  name: 'Sales',
  fields: <FieldDef>[
    FieldDef('months', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('month', type: JetFieldType.string),
      FieldDef('revenue', type: JetFieldType.double),
      FieldDef('units', type: JetFieldType.integer),
    ]),
  ],
);

/// The sales-chart report: title band + bar, line, and pie chart bands, all
/// reading the same `months` collection from the single master row.
ReportDefinition salesChartDefinition() => const ReportDefinition(
      name: 'Sales Chart',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            // Report title.
            BandNode(Band(
              id: 'title',
              type: BandType.title,
              height: 30,
              elements: <ReportElement>[
                TextElement(
                  id: 'heading',
                  bounds: JetRect(x: 0, y: 4, width: 500, height: 22),
                  text: 'Monthly Sales',
                  style: JetTextStyle(fontSize: 16, weight: JetFontWeight.bold),
                ),
              ],
            )),
            // Bar chart — revenue per month.
            BandNode(Band(
              id: 'barBand',
              type: BandType.detail,
              height: 160,
              elements: <ReportElement>[
                ChartElement(
                  id: 'barChart',
                  bounds: JetRect(x: 0, y: 0, width: 500, height: 155),
                  chartType: ChartType.bar,
                  collectionField: 'months',
                  valueExpression: r'$F{revenue}',
                  categoryExpression: r'$F{month}',
                  title: 'Revenue (Bar)',
                  showAxes: true,
                  showValueLabels: true,
                ),
              ],
            )),
            // Line chart — units sold per month.
            BandNode(Band(
              id: 'lineBand',
              type: BandType.detail,
              height: 160,
              elements: <ReportElement>[
                ChartElement(
                  id: 'lineChart',
                  bounds: JetRect(x: 0, y: 0, width: 500, height: 155),
                  chartType: ChartType.line,
                  collectionField: 'months',
                  valueExpression: r'$F{units}',
                  categoryExpression: r'$F{month}',
                  title: 'Units Sold (Line)',
                  showAxes: true,
                ),
              ],
            )),
            // Pie chart — revenue share per month.
            BandNode(Band(
              id: 'pieBand',
              type: BandType.detail,
              height: 180,
              elements: <ReportElement>[
                ChartElement(
                  id: 'pieChart',
                  bounds: JetRect(x: 50, y: 0, width: 400, height: 175),
                  chartType: ChartType.pie,
                  collectionField: 'months',
                  valueExpression: r'$F{revenue}',
                  categoryExpression: r'$F{month}',
                  title: 'Revenue Share (Pie)',
                  showAxes: false,
                  showValueLabels: true,
                ),
              ],
            )),
          ],
        ),
      ),
    );
