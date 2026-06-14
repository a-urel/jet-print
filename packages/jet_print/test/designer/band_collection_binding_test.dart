// Scope collection designation, scope resolution, and the unresolved indicator,
// exercised through the UI (US3 / FR-015, FR-016, FR-017, FR-018). Public API.
//
// Reification (spec 024): the iterated collection is a SCOPE property now, not a
// band flag. The old per-band `bandCollection` field is gone; a nested
// `DetailScope` carries the `collectionField`, edited in the Scope inspector
// ('scopeCollection'). These tests therefore select a scope (not a band) to bind
// a collection, but every original assertion's intent is preserved: the picker
// lists only collection fields, a pick is one undoable edit, and a `$F{}` field
// binding resolves only against the fields in its enclosing scope chain.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const ValueKey<String> _scopeCollectionKey =
    ValueKey<String>('jet_print.designer.properties.field.scopeCollection');

const ValueKey<String> _scopePickKey = ValueKey<String>(
    'jet_print.designer.properties.field.scopeCollection.pick');

Finder _scopePickItem(String field) => find.byKey(ValueKey<String>(
    'jet_print.designer.properties.field.scopeCollection.pick.$field'));

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef(
      'lines',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('description', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
      ],
    ),
  ],
);

const String _unresolvedMsg = 'Field not found in the data source';

/// A definition with a master detail band plus a nested (initially unbound)
/// scope `linesScope` holding its own per-row band, so the Scope inspector can
/// drive collection binding and the unresolved-field diagnostic exercises both
/// the master and the child scope chains.
ReportDefinition _masterDetail() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 80)),
            NestedScope(DetailScope(
              id: 'linesScope',
              children: <ScopeNode>[
                BandNode(
                    Band(id: 'lineBand', type: BandType.detail, height: 40)),
              ],
            )),
          ],
        ),
      ),
    );

/// The nested scope `linesScope` in [c]'s current definition.
DetailScope _linesScope(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<NestedScope>()
        .map((NestedScope n) => n.scope)
        .firstWhere((DetailScope s) => s.id == 'linesScope');

Future<JetReportDesignerController> _pumpMasterDetail(
  WidgetTester tester, {
  JetDataSchema? dataSchema,
}) async {
  final JetReportDesignerController c = JetReportDesignerController(
    definition: _masterDetail(),
  );
  await pumpDesignerWith(tester, controller: c, dataSchema: dataSchema);
  return c;
}

void main() {
  testWidgets(
      'designates the selected scope as collection-bound via Properties',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await _pumpMasterDetail(tester, dataSchema: _invoice);
    c.selectScope('linesScope'); // the nested scope
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    await tester.enterText(find.byKey(_scopeCollectionKey), 'lines');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_linesScope(c).collectionField, 'lines');
  });

  testWidgets(
      'the scope binding shows a field-picker button when a schema with a '
      'collection is attached', (WidgetTester tester) async {
    final JetReportDesignerController c =
        await _pumpMasterDetail(tester, dataSchema: _invoice);
    c.selectScope('linesScope');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    expect(find.byKey(_scopePickKey), findsOneWidget);
  });

  testWidgets('with no schema there is nothing to pick, so no picker button',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpMasterDetail(tester);
    c.selectScope('linesScope');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    expect(find.byKey(_scopePickKey), findsNothing);
  });

  testWidgets('the scope picker lists only collection fields, not scalars',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await _pumpMasterDetail(tester, dataSchema: _invoice);
    c.selectScope('linesScope');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    await tester.tap(find.byKey(_scopePickKey));
    await tester.pumpAndSettle();

    expect(_scopePickItem('lines'), findsOneWidget);
    expect(_scopePickItem('customerName'), findsNothing); // scalar, not a scope
  });

  testWidgets('choosing a collection binds the scope as a single undoable edit',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await _pumpMasterDetail(tester, dataSchema: _invoice);
    c.selectScope('linesScope');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    await tester.tap(find.byKey(_scopePickKey));
    await tester.pumpAndSettle();
    await tester.tap(_scopePickItem('lines'));
    await tester.pumpAndSettle();

    expect(_linesScope(c).collectionField, 'lines');
    expect(c.canUndo, isTrue);
  });

  testWidgets('flags a binding whose field is missing from the master scope',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await _pumpMasterDetail(tester, dataSchema: _invoice);
    c.createBoundElement(
        bandId: 'detail', at: const JetOffset(20, 20), expression: r'$F{nope}');
    final String id = c.selection.singleOrNull!;
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    expect(find.text(_unresolvedMsg), findsOneWidget); // missing field
    c.setBinding(id, r'$F{customerName}'); // a real master field
    await tester.pumpAndSettle();
    expect(find.text(_unresolvedMsg), findsNothing);
  });

  testWidgets('resolves child-scope fields and flags master/scope mismatches',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await _pumpMasterDetail(tester, dataSchema: _invoice);
    // The nested scope iterates the lines collection; its band sees line fields.
    c.setScopeCollection('linesScope', 'lines');
    c.createBoundElement(
        bandId: 'lineBand',
        at: const JetOffset(20, 20),
        expression: r'$F{description}'); // a line field
    final String id = c.selection.singleOrNull!;
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    // `description` is in the lines (child) scope → resolved.
    expect(find.text(_unresolvedMsg), findsNothing);

    // `customerName` is a master field, out of the line scope → unresolved.
    c.setBinding(id, r'$F{customerName}');
    await tester.pumpAndSettle();
    expect(find.text(_unresolvedMsg), findsOneWidget);
  });
}
