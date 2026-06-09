// T065 — arrange affordances (align / distribute / z-order) in the top bar,
// wired to the controller's bulk ops (FR-012 / FR-013 / US4.5–US4.6).
//
// The geometry of each op is already covered by the controller unit tests; this
// drives the public `JetReportDesigner` only — open the top-bar "Arrange" menu
// and confirm tapping an action mutates the model (and is undoable).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

final Finder _arrangeButton =
    find.byKey(const ValueKey<String>('jet_print.designer.action.arrange'));

Finder _menuItem(String name) =>
    find.byKey(ValueKey<String>('jet_print.designer.arrange.$name'));

double _leftOf(JetReportDesignerController c, String id) => c.template.bands
    .expand((ReportBand b) => b.elements)
    .firstWhere((ReportElement e) => e.id == id)
    .bounds
    .x;

List<String> _bandOrder(JetReportDesignerController c, int band) =>
    c.template.bands[band].elements.map((ReportElement e) => e.id).toList();

/// Creates three text elements at distinct positions in the detail band and
/// returns their ids (in creation order).
Future<List<String>> _threeInARow(
    WidgetTester tester, JetReportDesignerController c) async {
  final List<String> ids = <String>[];
  for (final double x in <double>[10, 60, 120]) {
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: JetOffset(x, 10 + x));
    ids.add(c.selection.singleOrNull!);
  }
  await tester.pumpAndSettle();
  return ids;
}

Future<void> _openArrange(WidgetTester tester) async {
  await tester.tap(_arrangeButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Arrange menu lists align, distribute and order actions',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final List<String> ids = await _threeInARow(tester, c);
    c.selectElements(ids);
    await tester.pumpAndSettle();

    await _openArrange(tester);

    expect(_menuItem('alignLeft'), findsOneWidget);
    expect(_menuItem('alignCenterHorizontal'), findsOneWidget);
    expect(_menuItem('alignRight'), findsOneWidget);
    expect(_menuItem('alignTop'), findsOneWidget);
    expect(_menuItem('alignMiddle'), findsOneWidget);
    expect(_menuItem('alignBottom'), findsOneWidget);
    expect(_menuItem('distributeHorizontal'), findsOneWidget);
    expect(_menuItem('distributeVertical'), findsOneWidget);
    expect(_menuItem('bringToFront'), findsOneWidget);
    expect(_menuItem('bringForward'), findsOneWidget);
    expect(_menuItem('sendBackward'), findsOneWidget);
    expect(_menuItem('sendToBack'), findsOneWidget);
  });

  testWidgets('Align left snaps the selection to the leftmost edge (undoable)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final List<String> ids = await _threeInARow(tester, c);
    c.selectElements(ids);
    await tester.pumpAndSettle();

    await _openArrange(tester);
    await tester.tap(_menuItem('alignLeft'));
    await tester.pumpAndSettle();

    final double leftmost = ids
        .map((String id) => _leftOf(c, id))
        .reduce((double a, double b) => a < b ? a : b);
    for (final String id in ids) {
      expect(_leftOf(c, id), leftmost,
          reason: 'every element shares the leftmost x after align-left');
    }
    expect(c.canUndo, isTrue);
  });

  testWidgets('Bring to front moves the selected element last in its band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final List<String> ids = await _threeInARow(tester, c);
    final String first = ids.first;
    c.select(first);
    await tester.pumpAndSettle();
    expect(_bandOrder(c, 1).first, first, reason: 'precondition: drawn first');

    await _openArrange(tester);
    await tester.tap(_menuItem('bringToFront'));
    await tester.pumpAndSettle();

    expect(_bandOrder(c, 1).last, first, reason: 'now drawn last (front)');
    expect(c.canUndo, isTrue);
  });

  testWidgets('the Arrange affordance is disabled with no element selected',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _threeInARow(tester, c);
    c.clearSelection();
    await tester.pumpAndSettle();

    // The trigger renders disabled, so tapping it cannot open the menu.
    await tester.tap(_arrangeButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_menuItem('alignLeft'), findsNothing);
  });
}
