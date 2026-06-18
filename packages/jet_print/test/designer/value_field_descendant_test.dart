/// Widget tests: the Properties panel (and its embedded fx editor) surfaces
/// descendant-collection operands correctly (spec 033).
///
/// Pump setup: Customer ▸ Order ▸ Line schema; a summary band whose element
/// value is `{SUM([lineTotal])}` (which compiles to SUM($F{lineTotal})). The
/// band is at the root/summary level — lineTotal is a descendant leaf, not an
/// in-scope field.
///
/// Three assertions:
///   (a) Unresolved hint is NOT shown for `{SUM([lineTotal])}`.
///   (b) Unresolved hint IS shown for bare `[lineTotal]` (FR-006).
///   (c) Fx editor shows a deepField button for `lineTotal` and status = Valid
///       for `{SUM([lineTotal])}`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

// --- Key constants -----------------------------------------------------------

const Key _fxKey =
    ValueKey<String>('jet_print.designer.properties.field.value.fx');
const Key _editorStatus =
    ValueKey<String>('jet_print.designer.exprEditor.status');
const Key _deepLineTotalKey =
    ValueKey<String>('jet_print.designer.exprEditor.deepField.lineTotal');

// Unresolved hint text (matches the English localisation string).
const String _unresolvedMsg = 'Field not found in the data source';

// --- Schema: Customer ▸ Order ▸ Line -----------------------------------------

const JetDataSchema _schema = JetDataSchema(
  name: 'Customers',
  fields: <FieldDef>[
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef(
      'orders',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('orderNo', type: JetFieldType.string),
        FieldDef(
          'lines',
          type: JetFieldType.collection,
          fields: <FieldDef>[
            FieldDef('lineTotal', type: JetFieldType.double),
            FieldDef('qty', type: JetFieldType.integer),
          ],
        ),
      ],
    ),
  ],
);

// --- Report definition -------------------------------------------------------
//
// Root scope (customers) + a summary band.  The nested scopes are declared but
// we only put an element on the summary band so the test focuses on the
// root-level descendant aggregate case.

ReportDefinition _def() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(id: 'summary', type: BandType.summary, height: 40),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'ordersScope',
              collectionField: 'orders',
              children: <ScopeNode>[
                NestedScope(DetailScope(
                  id: 'linesScope',
                  collectionField: 'lines',
                  children: <ScopeNode>[
                    BandNode(Band(
                        id: 'lineDetail',
                        type: BandType.detail,
                        height: 20)),
                  ],
                )),
              ],
            )),
          ],
        ),
      ),
    );

// --- Pump helper -------------------------------------------------------------

Future<JetReportDesignerController> _pump(WidgetTester tester) async {
  final JetReportDesignerController c =
      JetReportDesignerController(definition: _def());
  await pumpDesignerWith(tester, controller: c, dataSchema: _schema);
  return c;
}

// =============================================================================

void main() {
  // (a) The Unresolved hint is NOT shown for {SUM([lineTotal])} on summary.
  testWidgets(
      'summary {SUM([lineTotal])} does not show the unresolved hint',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);

    // Create a bound element with the descendant aggregate expression.
    // SUM($F{lineTotal}) — lineTotal is a descendant leaf, not in summary scope.
    c.createBoundElement(
      bandId: 'summary',
      at: const JetOffset(10, 10),
      expression: r'SUM($F{lineTotal})',
    );
    await tester.pumpAndSettle();

    // Select the newly created element (it is the only text element on summary).
    // We need its id — query from the definition tree.
    final String elemId = c.definition.body.summary!.elements
        .whereType<TextElement>()
        .first
        .id;
    c.select(elemId);
    await tester.pumpAndSettle();

    await openPropertiesTab(tester);

    expect(find.text(_unresolvedMsg), findsNothing,
        reason: 'SUM([lineTotal]) is a valid descendant aggregate — no flag');
  });

  // (b) Bare [lineTotal] (not inside an aggregate) DOES show the hint (FR-006).
  testWidgets(
      'bare [lineTotal] on summary IS flagged as unresolved',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);

    // $F{lineTotal} is a direct field ref — lineTotal is not in root scope.
    c.createBoundElement(
      bandId: 'summary',
      at: const JetOffset(10, 10),
      expression: r'$F{lineTotal}',
    );
    await tester.pumpAndSettle();

    final String elemId = c.definition.body.summary!.elements
        .whereType<TextElement>()
        .first
        .id;
    c.select(elemId);
    await tester.pumpAndSettle();

    await openPropertiesTab(tester);

    expect(find.text(_unresolvedMsg), findsOneWidget,
        reason: 'bare lineTotal ref is out-of-scope at root level');
  });

  // (c) Fx editor: descendant deep-field button present + status Valid.
  testWidgets(
      'fx editor shows deepField.lineTotal button and Valid status for '
      '{SUM([lineTotal])}', (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);

    c.createBoundElement(
      bandId: 'summary',
      at: const JetOffset(10, 10),
      expression: r'SUM($F{lineTotal})',
    );
    await tester.pumpAndSettle();

    final String elemId = c.definition.body.summary!.elements
        .whereType<TextElement>()
        .first
        .id;
    c.select(elemId);
    await tester.pumpAndSettle();

    await openPropertiesTab(tester);

    // Open the fx editor.
    await tester.tap(find.byKey(_fxKey));
    await tester.pumpAndSettle();

    // Descendant field button must be present.
    expect(find.byKey(_deepLineTotalKey), findsOneWidget,
        reason: 'lineTotal is a descendant leaf — palette must offer it marked');

    // Status must be Valid for the current text ({SUM([lineTotal])} round-trips
    // to the display text the editor seeds from).
    final Text statusText =
        tester.widget<Text>(find.byKey(_editorStatus));
    // The English Valid string from the l10n catalog.
    expect(statusText.data, contains('Valid'),
        reason: 'SUM([lineTotal]) must resolve as Valid in the fx editor');
  });
}
