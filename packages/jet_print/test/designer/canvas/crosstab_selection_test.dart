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
  // The block draws what the model alone determines — axis level names and the
  // real column widths. Row and column COUNTS are data-driven and unknowable at
  // design time, so they are stood in for, never invented.
  testWidgets('the block labels the crosstab and its axis levels',
      (WidgetTester tester) async {
    await _pump(tester);
    for (final String label in <String>['Sales pivot', 'Region', 'Year']) {
      expect(find.descendant(of: _block, matching: find.text(label)),
          findsOneWidget,
          reason: label);
    }
  });

  // A single measure prints no measure-name row (crosstab_planner emits that
  // band only when there are 2+, since one measure is already named by its leaf
  // column header) — and the block must not show one either, or the designer
  // would promise a row the report never prints.
  testWidgets('measure names appear only when there is more than one',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    expect(find.descendant(of: _block, matching: find.text('Amount')),
        findsNothing);

    c.addCrosstabMeasure('ct1', fieldName: 'qty');
    await tester.pumpAndSettle();
    expect(find.descendant(of: _block, matching: find.text('Amount')),
        findsOneWidget);
    expect(find.descendant(of: _block, matching: find.text('qty')),
        findsOneWidget);
  });

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
