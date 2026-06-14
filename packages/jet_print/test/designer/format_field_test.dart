// The Format field (013): free-text ICU pattern + a suffix preset-picker button
// (mirroring the Value field's field picker). Each pick is a single undoable
// edit on TextElement.format. When the value binds a field of a known type, the
// presets that cannot apply to that type are disabled (numeric/date split).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const ValueKey<String> _formatKey =
    ValueKey<String>('jet_print.designer.properties.field.format');

const ValueKey<String> _pickKey =
    ValueKey<String>('jet_print.designer.properties.field.format.pick');

Finder _preset(String label) => find.byKey(ValueKey<String>(
    'jet_print.designer.properties.field.format.preset.$label'));

/// A schema with one field of each formattable kind so a label can bind a
/// numeric, date, or string value and the picker reflect its type.
const JetDataSchema _schema = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('amount', type: JetFieldType.double),
    FieldDef('issuedAt', type: JetFieldType.dateTime),
    FieldDef('customerName', type: JetFieldType.string),
  ],
);

TextElement _text(JetReportDesignerController c, String id) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements)
        .whereType<TextElement>()
        .firstWhere((TextElement e) => e.id == id);

Future<String> _selectedText(
  WidgetTester tester,
  JetReportDesignerController c,
) async {
  c.createElement(DesignerToolType.text,
      bandId: firstDetailBandId(c), at: const JetOffset(20, 20));
  final String id = c.selection.singleOrNull!;
  await tester.pumpAndSettle();
  await openPropertiesTab(tester);
  return id;
}

/// Opens the format preset dropdown.
Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(_pickKey));
  await tester.pumpAndSettle();
}

/// Whether the preset menu item [label] is currently enabled.
bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ShadContextMenuItem>(_preset(label)).enabled;

void main() {
  testWidgets('the Format field is present for a text element',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _selectedText(tester, c);
    expect(find.byKey(_formatKey), findsOneWidget);
  });

  testWidgets('the Format field shows a preset-picker suffix button',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _selectedText(tester, c);
    expect(find.byKey(_pickKey), findsOneWidget);
  });

  testWidgets('typing a pattern sets the format as one undoable edit',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);

    await tester.enterText(find.byKey(_formatKey), '#,##0.00');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_text(c, id).format, '#,##0.00');
    expect(c.canUndo, isTrue);
  });

  testWidgets('picking the Decimal preset from the dropdown fills the pattern',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);

    await _openPicker(tester);
    await tester.tap(_preset('Decimal'));
    await tester.pumpAndSettle();
    expect(_text(c, id).format, '#,##0.00');
  });

  testWidgets('picking None from the dropdown clears the format',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String id = await _selectedText(tester, c);
    c.setFormat(id, '#,##0.00');
    await tester.pumpAndSettle();

    await _openPicker(tester);
    await tester.tap(_preset('None'));
    await tester.pumpAndSettle();
    expect(_text(c, id).format, isNull);
  });

  testWidgets('a numeric binding disables the date presets, keeps numeric ones',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _schema);
    final String id = await _selectedText(tester, c);
    c.setValue(id, '[amount]');
    await tester.pumpAndSettle();

    await _openPicker(tester);
    expect(_enabled(tester, 'None'), isTrue);
    expect(_enabled(tester, 'Integer'), isTrue);
    expect(_enabled(tester, 'Decimal'), isTrue);
    expect(_enabled(tester, 'Currency'), isTrue);
    expect(_enabled(tester, 'Percent'), isTrue);
    expect(_enabled(tester, 'Date'), isFalse);
    expect(_enabled(tester, 'Date & time'), isFalse);
  });

  testWidgets('a date binding disables the numeric presets, keeps date ones',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _schema);
    final String id = await _selectedText(tester, c);
    c.setValue(id, '[issuedAt]');
    await tester.pumpAndSettle();

    await _openPicker(tester);
    expect(_enabled(tester, 'None'), isTrue);
    expect(_enabled(tester, 'Integer'), isFalse);
    expect(_enabled(tester, 'Decimal'), isFalse);
    expect(_enabled(tester, 'Currency'), isFalse);
    expect(_enabled(tester, 'Percent'), isFalse);
    expect(_enabled(tester, 'Date'), isTrue);
    expect(_enabled(tester, 'Date & time'), isTrue);
  });

  testWidgets('a string binding leaves only None enabled',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _schema);
    final String id = await _selectedText(tester, c);
    c.setValue(id, '[customerName]');
    await tester.pumpAndSettle();

    await _openPicker(tester);
    expect(_enabled(tester, 'None'), isTrue);
    expect(_enabled(tester, 'Integer'), isFalse);
    expect(_enabled(tester, 'Date'), isFalse);
  });

  testWidgets('a literal value (no known field type) enables every preset',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _schema);
    final String id = await _selectedText(tester, c);
    c.setValue(id, 'Paid in full');
    await tester.pumpAndSettle();

    await _openPicker(tester);
    expect(_enabled(tester, 'None'), isTrue);
    expect(_enabled(tester, 'Integer'), isTrue);
    expect(_enabled(tester, 'Date'), isTrue);
    expect(_enabled(tester, 'Date & time'), isTrue);
  });
}
