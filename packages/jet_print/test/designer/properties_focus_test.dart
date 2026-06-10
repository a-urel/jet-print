// Double-tap → Properties focus: a requestPropertiesFocus() brings the right
// panel to the Properties tab (this file grows shell-overlay and field-focus
// coverage in later tasks). Exercised through the public entry point only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

final Finder _xField =
    find.byKey(const ValueKey<String>('jet_print.designer.properties.field.x'));
final Finder _textField = find.byKey(
    const ValueKey<String>('jet_print.designer.properties.field.text'));

void main() {
  testWidgets('a focus request switches the right panel to the Properties tab',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();

    // Data Source is the default tab: no inspector fields are present.
    expect(_xField, findsNothing);

    controller.requestPropertiesFocus();
    await tester.pumpAndSettle();

    // The Properties tab is now active, showing the element inspector.
    expect(_xField, findsOneWidget);
    expect(_textField, findsOneWidget);
  });

  testWidgets(
      'narrow layout: a focus request opens the overlay on the Properties tab',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester, size: kNarrowSize);
    controller.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();

    // Collapsed: the right panel is not in the tree at all, only its rail.
    expect(find.byKey(kRightPanelKey), findsNothing);
    expect(find.byKey(kRightPanelRailKey), findsOneWidget);

    controller.requestPropertiesFocus();
    await tester.pumpAndSettle();

    // The overlay opened and mounted straight onto the Properties tab.
    expect(find.byKey(kRightPanelKey), findsOneWidget);
    expect(_xField, findsOneWidget);
  });
}
