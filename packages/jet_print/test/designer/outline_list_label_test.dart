// Widget test: a nested list scope reads as "List: <field>" in the Outline.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

void main() {
  testWidgets('a bound nested list reads as "List: lines" in the Outline',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.createListWithBand(c.definition.body.root.id, collectionField: 'lines');
    await tester.tap(find.text('Outline').first);
    await tester.pumpAndSettle();

    expect(find.text('List: lines'), findsOneWidget);
  });
}
