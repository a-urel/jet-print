/// Tests for the fx expression editor dialog (032): seeding, palette insertion,
/// live status (valid / syntax error / unresolved), and commit/cancel.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart' show FieldDef, JetFieldType;
import 'package:jet_print/src/designer/l10n/jet_print_localizations.dart';
import 'package:jet_print/src/designer/layout/panels/expression_editor_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const Key _editorKey = ValueKey<String>('jet_print.designer.exprEditor.input');
const Key _statusKey = ValueKey<String>('jet_print.designer.exprEditor.status');
const Key _insertKey = ValueKey<String>('jet_print.designer.exprEditor.insert');
const Key _cancelKey = ValueKey<String>('jet_print.designer.exprEditor.cancel');
Finder _fieldChip(String n) =>
    find.byKey(ValueKey<String>('jet_print.designer.exprEditor.field.$n'));

String _editorText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
          of: find.byKey(_editorKey), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _open(
  WidgetTester tester, {
  required String initial,
  Set<String> names = const <String>{'qty', 'price'},
  List<FieldDef> fields = const <FieldDef>[
    FieldDef('qty', type: JetFieldType.integer),
    FieldDef('price', type: JetFieldType.double),
  ],
}) async {
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: Builder(builder: (BuildContext context) {
      return Center(
        child: ShadButton(
          child: const Text('open'),
          onPressed: () => showExpressionEditor(context,
              initialText: initial, resolvableNames: names, fields: fields),
        ),
      );
    }),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('statusFor (pure)', () {
    const Set<String> names = <String>{'qty'};
    test('binding in scope is valid', () {
      expect(statusFor('{SUM([qty])}', names), isA<StatusValid>());
    });
    test('out-of-scope ref is unresolved and names the field', () {
      final EditorStatus s = statusFor('{SUM([bogus])}', names);
      expect(s, isA<StatusUnresolved>());
      expect((s as StatusUnresolved).name, 'bogus');
    });
    test('malformed template is a syntax error', () {
      expect(statusFor('{SUM([qty}', names), isA<StatusSyntaxError>());
    });
    test('plain literal text is valid', () {
      expect(statusFor('hello', names), isA<StatusValid>());
    });
  });

  testWidgets('seeds the editor with the current display token',
      (WidgetTester tester) async {
    await _open(tester, initial: '{SUM([qty])}');
    expect(_editorText(tester), '{SUM([qty])}');
  });

  testWidgets('tapping a field chip inserts its [token]',
      (WidgetTester tester) async {
    await _open(tester, initial: '');
    await tester.tap(_fieldChip('qty'));
    await tester.pumpAndSettle();
    expect(_editorText(tester), contains('[qty]'));
  });

  testWidgets('valid in-scope expression shows the valid status',
      (WidgetTester tester) async {
    await _open(tester, initial: '{SUM([qty])}');
    expect(find.byKey(_statusKey), findsOneWidget);
    expect(find.text('Valid'), findsOneWidget);
  });

  testWidgets('out-of-scope reference shows an unresolved status naming it',
      (WidgetTester tester) async {
    await _open(tester, initial: '{SUM([bogus])}');
    // The status line names the offending field. (The seeded editor text also
    // contains "bogus", so assert on the keyed status widget directly.)
    expect(tester.widget<Text>(find.byKey(_statusKey)).data, contains('bogus'));
  });

  testWidgets('malformed template shows a syntax-error status',
      (WidgetTester tester) async {
    await _open(tester, initial: '{SUM([qty}');
    expect(find.text('Incomplete or invalid expression'), findsOneWidget);
  });

  testWidgets('Insert closes the dialog (status gone)',
      (WidgetTester tester) async {
    await _open(tester, initial: '{UPPER([qty])}');
    await tester.tap(find.byKey(_insertKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_statusKey), findsNothing);
  });

  testWidgets('Cancel closes the dialog (status gone)',
      (WidgetTester tester) async {
    await _open(tester, initial: '{UPPER([qty])}');
    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_statusKey), findsNothing);
  });
}
