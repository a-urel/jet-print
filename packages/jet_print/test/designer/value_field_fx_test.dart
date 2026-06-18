/// The Value field's fx button opens the expression editor and commits its
/// result through the same setValue path as the inline field (032).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const Key _fxKey =
    ValueKey<String>('jet_print.designer.properties.field.value.fx');
const Key _editorInsert =
    ValueKey<String>('jet_print.designer.exprEditor.insert');
const Key _editorInput =
    ValueKey<String>('jet_print.designer.exprEditor.input');

const JetDataSchema _schema = JetDataSchema(name: 'R', fields: <FieldDef>[
  FieldDef('qty', type: JetFieldType.integer),
]);

ReportDefinition _def() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
            id: 'detail',
            type: BandType.detail,
            height: 40,
            elements: <ReportElement>[
              TextElement(
                id: 't1',
                bounds: JetRect(x: 0, y: 0, width: 80, height: 12),
                text: 'x',
              ),
            ],
          )),
        ]),
      ),
    );

// Helper: read t1's expression from the controller's current definition, via
// the public ReportDefinition tree (findBandOfElement is internal-only).
String? _t1Expression(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .whereType<TextElement>()
        .firstWhere((TextElement e) => e.id == 't1')
        .expression;

void main() {
  testWidgets('fx button is present for a selected text element',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _def());
    await pumpDesignerWith(tester, controller: c, dataSchema: _schema);
    c.select('t1');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);
    expect(find.byKey(_fxKey), findsOneWidget);
  });

  testWidgets('fx → edit → Insert commits via setValue (undo restores)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _def());
    await pumpDesignerWith(tester, controller: c, dataSchema: _schema);
    c.select('t1');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    await tester.tap(find.byKey(_fxKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_editorInput), '{SUM([qty])}');
    await tester.tap(find.byKey(_editorInsert));
    await tester.pumpAndSettle();

    expect(_t1Expression(c), r'SUM($F{qty})');

    c.undo();
    expect(_t1Expression(c), isNull);
  });
}
