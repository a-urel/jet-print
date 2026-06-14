// Data-aware invoice golden (US4 / FR-021; Constitution IV).
//
// Pins the data-aware invoice **design surface**: a populated Data Source panel
// (the invoice schema, incl. the nested `lines` collection) beside the canvas
// showing master header tokens and a `lines`-bound detail band of line tokens —
// in light and dark. Tokens render through the shared pipeline (no values).
// Public API only; regenerate with `--update-goldens`.
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

const JetDataSchema _schema = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef('total', type: JetFieldType.double),
    FieldDef(
      'lines',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('description', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
      ],
    ),
  ],
);

// The reified equivalent of the legacy three-band invoice (title + a
// `lines`-bound detail band + summary), authored directly with the SAME
// path-based ids the template→definition adapter assigns, so the design canvas
// renders byte-identically: the title/summary bands become body slots, and the
// `collectionField: 'lines'` detail band becomes a NestedScope whose first
// child is the per-row BandNode (spec 024).
ReportDefinition _definition() => const ReportDefinition(
      name: 'Invoice',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(
          id: 'body/title',
          type: BandType.title,
          height: 70,
          elements: <ReportElement>[
            TextElement(
              id: 'title',
              bounds: JetRect(x: 0, y: 0, width: 200, height: 26),
              text: 'INVOICE',
              style: JetTextStyle(fontSize: 22, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'cust',
              bounds: JetRect(x: 0, y: 40, width: 280, height: 18),
              text: 'customerName',
              expression: r'$F{customerName}',
            ),
          ],
        ),
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 36,
          elements: <ReportElement>[
            TextElement(
              id: 'total',
              bounds: JetRect(x: 360, y: 8, width: 180, height: 18),
              text: 'total',
              expression: r'$F{total}',
            ),
          ],
        ),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'root/c0',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'root/c0/c0',
                  type: BandType.detail,
                  height: 22,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'desc',
                      bounds: JetRect(x: 0, y: 2, width: 260, height: 16),
                      text: 'description',
                      expression: r'$F{description}',
                    ),
                    TextElement(
                      id: 'qty',
                      bounds: JetRect(x: 280, y: 2, width: 60, height: 16),
                      text: 'qty',
                      expression: r'$F{qty}',
                    ),
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );

Future<void> _pump(WidgetTester tester, ThemeMode mode) async {
  // pumpDesignerWith registers the controller's dispose tear-down itself.
  await pumpDesignerWith(
    tester,
    controller: JetReportDesignerController(definition: _definition()),
    themeMode: mode,
    dataSchema: _schema,
    // Rulers are pinned by widget tests, not goldens (decision V1) — off here so
    // the invoice golden stays byte-identical and snapshots only the report.
    rulers: false, grid: false,
  );
}

void main() {
  testWidgets('data-aware invoice matches its light golden', (
    WidgetTester tester,
  ) async {
    await _pump(tester, ThemeMode.light);
    await expectLater(
      find.byType(JetReportDesigner),
      matchesGoldenFile('data_aware_invoice_light.png'),
    );
  });

  testWidgets('data-aware invoice matches its dark golden', (
    WidgetTester tester,
  ) async {
    await _pump(tester, ThemeMode.dark);
    await expectLater(
      find.byType(JetReportDesigner),
      matchesGoldenFile('data_aware_invoice_dark.png'),
    );
  });
}
