// Properties "Column Layout" section: add / edit / remove + gating (spec 035 /
// Task 2). Drives the public JetReportDesigner via the shared harness.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';
Finder _add = find.byKey(const ValueKey<String>('$_p.field.columnLayoutAdd'));
Finder _remove =
    find.byKey(const ValueKey<String>('$_p.field.columnLayoutRemove'));
Finder _field(String name) =>
    find.byKey(ValueKey<String>('$_p.field.$name'));
Finder _editable(String name) =>
    find.descendant(of: _field(name), matching: find.byType(EditableText));

Future<void> _openProperties(WidgetTester tester) async {
  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Eligible: one root scope, one detail band, nothing else.
ReportDefinition _pure() => const ReportDefinition(
      name: 'labels',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );

/// Ineligible: a title once-band makes the body not pure-single-detail.
ReportDefinition _withTitle() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(id: 'title', type: BandType.title, height: 30),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );

Band _detail(JetReportDesignerController c) =>
    (c.definition.body.root.children.single as BandNode).band;

void main() {
  testWidgets('Add is enabled on a pure single-detail body and creates a default layout',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();

    expect(_add, findsOneWidget);
    await tester.tap(_add);
    await tester.pumpAndSettle();

    final ColumnLayout? layout = _detail(c).columnLayout;
    final double bodyWidth = c.definition.page.width -
        c.definition.page.margins.left -
        c.definition.page.margins.right;
    expect(layout, isNotNull);
    expect(layout!.columnCount, 2);
    expect(layout.columnWidth, bodyWidth / 2);
    expect(layout.columnSpacing, 0);
    expect(layout.rowSpacing, 0);
  });

  testWidgets('Add does nothing on an ineligible body', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        controller: JetReportDesignerController(definition: _withTitle()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();

    expect(_add, findsOneWidget); // shown, but disabled
    await tester.tap(_add, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(_detail(c).columnLayout, isNull);
  });

  testWidgets('editing the Columns field commits the rounded value',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();
    await tester.tap(_add);
    await tester.pumpAndSettle();

    await tester.enterText(_editable('columnCount'), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_detail(c).columnLayout!.columnCount, 3);
  });

  testWidgets('Remove clears the layout', (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();
    await tester.tap(_add);
    await tester.pumpAndSettle();

    expect(_remove, findsOneWidget);
    await tester.tap(_remove);
    await tester.pumpAndSettle();

    expect(_detail(c).columnLayout, isNull);
  });
}
