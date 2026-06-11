// The value field's data-source field picker: a suffix button on the Value
// input that lists the in-scope schema fields and inserts the chosen one as a
// `[field]` binding — one undoable edit through the same `setValue` path the
// typed-in `[field]` token uses. Drives the public designer only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const ValueKey<String> _pickKey =
    ValueKey<String>('jet_print.designer.properties.field.value.pick');

Finder _pickItem(String field) => find.byKey(
    ValueKey<String>('jet_print.designer.properties.field.value.pick.$field'));

/// A schema with two master fields and a `lines` collection — the picker should
/// offer the two scalars at master scope and never the collection itself.
const JetDataSchema _schema = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef('total', type: JetFieldType.double),
    FieldDef(
      'lines',
      type: JetFieldType.collection,
      fields: <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
    ),
  ],
);

TextElement _text(JetReportDesignerController c, String id) => c.template.bands
    .expand((ReportBand b) => b.elements)
    .whereType<TextElement>()
    .firstWhere((TextElement e) => e.id == id);

/// Creates a text element in the master detail band, selects it, and opens the
/// Properties tab; returns its id.
Future<String> _selectedText(
  WidgetTester tester,
  JetReportDesignerController c,
) async {
  c.createElement(DesignerToolType.text,
      bandIndex: 1, at: const JetOffset(20, 20));
  final String id = c.selection.singleOrNull!;
  await tester.pumpAndSettle();
  await openPropertiesTab(tester);
  return id;
}

void main() {
  testWidgets('the Value field shows a field-picker button when a schema is '
      'attached', (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _schema);
    await _selectedText(tester, c);
    expect(find.byKey(_pickKey), findsOneWidget);
  });

  testWidgets('with no schema there is nothing to pick, so no picker button',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _selectedText(tester, c);
    expect(find.byKey(_pickKey), findsNothing);
  });

  testWidgets('the picker lists in-scope scalar fields, not the collection',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _schema);
    await _selectedText(tester, c);

    await tester.tap(find.byKey(_pickKey));
    await tester.pumpAndSettle();

    expect(_pickItem('customerName'), findsOneWidget);
    expect(_pickItem('total'), findsOneWidget);
    expect(_pickItem('lines'), findsNothing);
    expect(_pickItem('qty'), findsNothing);
  });

  testWidgets('each picker item shows its field-type glyph (matching the Data '
      'Source pane)', (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _schema);
    await _selectedText(tester, c);

    await tester.tap(find.byKey(_pickKey));
    await tester.pumpAndSettle();

    // string → type glyph; double → calculator glyph — the same mapping the
    // Data Source tree uses, so a field reads identically in both places.
    expect(
      find.descendant(
          of: _pickItem('customerName'),
          matching: find.byIcon(LucideIcons.type)),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: _pickItem('total'),
          matching: find.byIcon(LucideIcons.calculator)),
      findsOneWidget,
    );
  });

  testWidgets('choosing a field binds the element as a single undoable edit',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _schema);
    final String id = await _selectedText(tester, c);

    await tester.tap(find.byKey(_pickKey));
    await tester.pumpAndSettle();
    await tester.tap(_pickItem('customerName'));
    await tester.pumpAndSettle();

    expect(_text(c, id).expression, r'$F{customerName}');
    expect(c.canUndo, isTrue);
  });
}
