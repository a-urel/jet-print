// Properties "Column Layout" section: add / edit / remove + gating (spec 035 /
// Task 2 + Task 3). Drives the public JetReportDesigner via the shared harness.
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

Finder _textContains(String needle) =>
    find.byWidgetPredicate((Widget w) => w is Text && (w.data?.contains(needle) ?? false));

/// Orphaned: a title makes the body ineligible, yet the detail band still
/// carries a column layout (the user added it earlier, then added a title).
ReportDefinition _orphaned() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(id: 'title', type: BandType.title, height: 30),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 80,
              columnLayout: ColumnLayout(
                  columnCount: 2, columnWidth: 100, columnSpacing: 0, rowSpacing: 0),
            )),
          ],
        ),
      ),
    );

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

  testWidgets('no section header until a layout exists; header appears with it',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();

    // No layout yet: the Add button is self-describing, so the "Column Layout"
    // section header is not shown.
    expect(_add, findsOneWidget);
    expect(find.text('Column Layout'), findsNothing);

    await tester.tap(_add);
    await tester.pumpAndSettle();

    // Once a layout exists, the editor is headed by the section title.
    expect(find.text('Column Layout'), findsOneWidget);
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

  testWidgets('changing the column count refits the width so the grid fits',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();
    await tester.tap(_add); // default 2 cols at bodyWidth/2
    await tester.pumpAndSettle();

    await tester.enterText(_editable('columnCount'), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final ColumnLayout layout = _detail(c).columnLayout!;
    final double bodyWidth = c.definition.page.width -
        c.definition.page.margins.left -
        c.definition.page.margins.right;
    expect(layout.columnCount, 3);
    // Width refit so the 3-column grid fills the body exactly (spacing 0).
    expect(layout.columnWidth, closeTo(bodyWidth / 3, 1e-9));
    final double grid = layout.columnCount * layout.columnWidth +
        (layout.columnCount - 1) * layout.columnSpacing;
    expect(grid, closeTo(bodyWidth, 1e-9));
    // No 'wider than the page body' error after a count bump.
    expect(validate(c.definition), isEmpty);
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

  testWidgets('a grid wider than the body shows a verbatim error row',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();
    await tester.tap(_add);
    await tester.pumpAndSettle();

    // Make the single column wider than the whole page body.
    final double tooWide = c.definition.page.width;
    await tester.enterText(_editable('columnWidth'), tooWide.toStringAsFixed(0));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_textContains('wider than the page body'), findsOneWidget);
  });

  testWidgets('an orphaned layout shows the inactive notice and stays editable',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        controller: JetReportDesignerController(definition: _orphaned()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();

    expect(_field('columnCount'), findsOneWidget); // fields still shown
    expect(_remove, findsOneWidget); // remove still available
    expect(_textContains('inactive'), findsOneWidget); // localized notice
    // The raw engine "is ignored" stray-band warning is NOT also shown.
    expect(_textContains('is ignored'), findsNothing);
  });
}
