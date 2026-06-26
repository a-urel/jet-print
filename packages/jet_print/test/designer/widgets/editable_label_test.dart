import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/layout/widgets/editable_label.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('shows display text when not editing', (tester) async {
    await tester.pumpWidget(host(EditableLabel(
      display: 'Greeting',
      value: 'Greeting',
      placeholder: 'Text',
      editing: false,
      onCommit: (_) {},
    )));
    expect(find.text('Greeting'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Enter commits trimmed text', (tester) async {
    String? committed = 'unset';
    await tester.pumpWidget(host(EditableLabel(
      display: 'Greeting',
      value: 'Greeting',
      placeholder: 'Text',
      editing: true,
      onCommit: (v) => committed = v,
    )));
    await tester.enterText(find.byType(TextField), '  Total  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(committed, 'Total');
  });

  testWidgets('empty commit yields null', (tester) async {
    String? committed = 'unset';
    await tester.pumpWidget(host(EditableLabel(
      display: 'Greeting',
      value: 'Greeting',
      placeholder: 'Text',
      editing: true,
      onCommit: (v) => committed = v,
    )));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(committed, isNull);
  });

  testWidgets('Esc cancels without committing', (tester) async {
    String? committed = 'unset';
    await tester.pumpWidget(host(EditableLabel(
      display: 'Greeting',
      value: 'Greeting',
      placeholder: 'Text',
      editing: true,
      onCommit: (v) => committed = v,
    )));
    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(committed, 'unset');
  });
}
