// Widget test: a crosstab is selectable on the design canvas (spec B). Spec A's
// block was wrapped in IgnorePointer and sat outside hit-testing entirely.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

/// A body with a detail band FIRST and the crosstab after it, so the two
/// occupy different vertical ranges and a tap can tell them apart.
ReportDefinition _def() => const ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 60)),
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

Future<JetReportDesignerController> _pump(WidgetTester tester) async {
  final JetReportDesignerController controller =
      JetReportDesignerController(definition: _def());
  addTearDown(controller.dispose);
  await pumpDesigner(tester,
      designer: JetReportDesigner(controller: controller));
  return controller;
}

Finder get _block =>
    find.byKey(const ValueKey<String>('crosstab-placeholder-ct1'));

void main() {
  testWidgets('a tap inside the block selects the crosstab',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    await tester.tapAt(tester.getCenter(_block));
    await tester.pumpAndSettle();
    expect(c.selection.crosstabId, 'ct1');
  });

  testWidgets('a tap above it still selects the band underneath',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    final Offset top = tester.getTopLeft(_block);
    await tester.tapAt(Offset(top.dx + 20, top.dy - 20));
    await tester.pumpAndSettle();
    expect(c.selection.bandId, 'detail');
    expect(c.selection.crosstabId, isNull);
  });
}
