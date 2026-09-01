// Widget test: the crosstab Properties inspector (spec B). Selection
// granularity is the whole crosstab — its axis levels and measures are edited
// as lists here, not as separately selectable objects.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const JetDataSchema _schema = JetDataSchema(
  name: 'Sales',
  fields: <FieldDef>[
    FieldDef('region', type: JetFieldType.string),
    FieldDef('year', type: JetFieldType.string),
    FieldDef('amount', type: JetFieldType.double),
  ],
);

ReportDefinition _def() => const ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            CrosstabNode(Crosstab(
              id: 'ct1',
              name: 'Sales pivot',
              rowGroups: <CrosstabGroup>[
                CrosstabGroup(
                    id: 'g-region', name: 'Region', expression: r'$F{region}'),
              ],
              columnGroups: <CrosstabGroup>[
                CrosstabGroup(
                    id: 'g-year', name: 'Year', expression: r'$F{year}'),
              ],
              measures: <CrosstabMeasure>[
                CrosstabMeasure(
                  id: 'm-amount',
                  name: 'Amount',
                  expression: r'$F{amount}',
                  aggregate: JetCalculation.sum,
                ),
              ],
            )),
          ],
        ),
      ),
    );

Crosstab _ct(JetReportDesignerController c) =>
    c.definition.body.root.children.whereType<CrosstabNode>().single.crosstab;

Future<JetReportDesignerController> _pump(WidgetTester tester) async {
  final JetReportDesignerController controller =
      JetReportDesignerController(definition: _def());
  addTearDown(controller.dispose);
  await pumpDesigner(tester,
      designer: JetReportDesigner(controller: controller, dataSchema: _schema));
  controller.selectCrosstab('ct1');
  // The right panel opens on Data Source; the inspector lives behind the
  // Properties tab and ShadTabs builds only the active body.
  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
  return controller;
}

Finder _key(String suffix) =>
    find.byKey(ValueKey<String>('jet_print.designer.properties.$suffix'));

void main() {
  testWidgets('the inspector renders the crosstab, its axes and its measures',
      (WidgetTester tester) async {
    await _pump(tester);
    expect(_key('field.crosstabName'), findsOneWidget);
    expect(_key('field.crosstabCollection'), findsOneWidget);
    expect(_key('crosstab.group.g-region.name'), findsOneWidget);
    expect(_key('crosstab.group.g-year.name'), findsOneWidget);
    expect(_key('crosstab.measure.m-amount.name'), findsOneWidget);
    expect(_key('crosstab.measure.m-amount.aggregate'), findsOneWidget);
  });

  testWidgets('removing the last level and the last measure is not offered',
      (WidgetTester tester) async {
    await _pump(tester);
    expect(_key('crosstab.group.g-region.remove'), findsNothing);
    expect(_key('crosstab.measure.m-amount.remove'), findsNothing);
  });

  testWidgets('a second level can be added from the axis menu, then removed',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    await tester.tap(_key('crosstab.rowGroups.add'));
    await tester.pumpAndSettle();
    await tester.tap(_key('crosstab.rowGroups.add.field.year'));
    await tester.pumpAndSettle();
    expect(_ct(c).rowGroups, hasLength(2));
    // With two levels each row can now be removed.
    expect(_key('crosstab.group.g-region.remove'), findsOneWidget);
  });

  testWidgets('the layout metrics commit through the controller',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    await tester.enterText(_key('field.crosstabRowHeight'), '21');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_ct(c).style.rowHeight, 21);
  });

  testWidgets('the width warning appears only past the body width',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
        tester.element(find.byType(JetReportDesigner)));
    expect(find.text(l10n.crosstabTooWide), findsNothing);
    c.setCrosstabStyle('ct1', _ct(c).style.copyWith(rowLabelWidth: 900));
    await tester.pumpAndSettle();
    expect(find.text(l10n.crosstabTooWide), findsOneWidget);
  });
}
