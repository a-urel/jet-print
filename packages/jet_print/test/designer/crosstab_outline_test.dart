// Widget test: a crosstab (spec A / Task 13) gets a minimal, read-only
// representation in the designer — an Outline row (its name, or the localized
// fallback label when nameless) and a fixed-size placeholder block on the
// canvas. No selection, no Properties, no drag, no delete: authoring a
// crosstab is a later spec.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

Finder _inPanel(String text) =>
    find.descendant(of: find.byKey(kRightPanelKey), matching: find.text(text));

/// A one-row-group x one-column-group crosstab, id `ct1` (matching the canvas
/// placeholder key under test), as the sole child of an otherwise-blank body.
ReportDefinition _defWithCrosstab({String? name = 'Sales pivot'}) =>
    ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            CrosstabNode(Crosstab(
              id: 'ct1',
              name: name,
              rowGroups: const <CrosstabGroup>[
                CrosstabGroup(
                  id: 'g-region',
                  name: 'Region',
                  expression: r'$F{region}',
                ),
              ],
              columnGroups: const <CrosstabGroup>[
                CrosstabGroup(
                    id: 'g-year', name: 'Year', expression: r'$F{year}'),
              ],
              measures: const <CrosstabMeasure>[
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

/// Pumps the designer over a definition holding [_defWithCrosstab]([name]),
/// mirroring the other outline tests' `pumpDesigner`/harness pattern rather
/// than hand-rolling the `ShadApp`/localization wiring here.
Future<JetReportDesignerController> _designerWith(
  WidgetTester tester, {
  String? name = 'Sales pivot',
}) async {
  final JetReportDesignerController controller =
      JetReportDesignerController(definition: _defWithCrosstab(name: name));
  addTearDown(controller.dispose);
  await pumpDesigner(tester,
      designer: JetReportDesigner(controller: controller));
  return controller;
}

Future<void> _openOutline(WidgetTester tester) async {
  await tester.tap(find.text('Outline').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a crosstab appears as a read-only outline row',
      (WidgetTester tester) async {
    await _designerWith(tester);
    await _openOutline(tester);
    expect(_inPanel('Sales pivot'), findsOneWidget);
  });

  testWidgets('a nameless crosstab falls back to the localized label',
      (WidgetTester tester) async {
    await _designerWith(tester, name: null);
    await _openOutline(tester);
    expect(_inPanel('Crosstab'), findsOneWidget);
  });

  testWidgets('the canvas reserves a block for the crosstab',
      (WidgetTester tester) async {
    await _designerWith(tester);
    expect(find.byKey(const ValueKey<String>('crosstab-placeholder-ct1')),
        findsOneWidget);
  });
}
