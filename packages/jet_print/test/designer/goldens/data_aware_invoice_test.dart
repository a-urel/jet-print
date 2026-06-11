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

ReportTemplate _template() => const ReportTemplate(
      name: 'Invoice',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
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
        ReportBand(
          type: BandType.detail,
          height: 22,
          collectionField: 'lines',
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
        ),
        ReportBand(
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
      ],
    );

Future<void> _pump(WidgetTester tester, ThemeMode mode) async {
  // pumpDesignerWith registers the controller's dispose tear-down itself.
  await pumpDesignerWith(
    tester,
    controller: JetReportDesignerController(template: _template()),
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
