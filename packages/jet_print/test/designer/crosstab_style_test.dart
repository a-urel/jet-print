// Widget test: the composed style editors extracted for spec C
// (_TextStyleEditor / _BoxStyleEditor). This file pins behaviour that the
// element-inspector suite (properties_editor_test.dart) only covers
// indirectly, and owns the pump/finder helpers later crosstab-style tasks
// build on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';

/// Finds a Properties-panel widget by its key suffix (the part after
/// `'jet_print.designer.properties.'`).
Finder findPanelKey(String suffix) =>
    find.byKey(ValueKey<String>('$_p.$suffix'));

/// Pumps the designer, adds a shape of [kind], selects it, and opens the
/// Properties tab so its inspector is in the tree.
///
/// Reaching Properties is non-obvious: the right panel is a `ShadTabs` that
/// opens on Data Source and builds only the active tab's body, so the
/// Properties tab must be scrolled into view before it can be tapped.
Future<JetReportDesignerController> pumpDesignerWithShape(
    WidgetTester tester, ShapeKind kind) async {
  final JetReportDesignerController c = await pumpDesignerWith(tester);
  c.createElement(DesignerToolType.shape,
      bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
  final String id = c.selection.singleOrNull!;
  c.setShapeKind(id, kind);
  await tester.pumpAndSettle();

  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('a line shape has no fill swatch, a rectangle does',
      (WidgetTester tester) async {
    await pumpDesignerWithShape(tester, ShapeKind.line);
    expect(findPanelKey('field.fill'), findsNothing,
        reason: 'a line has no interior, so the fill swatch is dropped');
    expect(findPanelKey('field.stroke'), findsOneWidget);

    await pumpDesignerWithShape(tester, ShapeKind.rectangle);
    expect(findPanelKey('field.fill'), findsOneWidget);
  });
}
