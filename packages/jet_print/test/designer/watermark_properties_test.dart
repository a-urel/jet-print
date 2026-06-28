// Watermark section in the report-root Properties inspector (Task 3).
//
// Drives the public `JetReportDesigner` through the same harness used by
// `properties_editor_test.dart`. Every test opens the Properties tab, selects
// the report root, then asserts against the watermark section.
//
// ## Why tapAt rather than tap on ShadSwitch
//
// ShadSwitch wraps a 44 px GestureDetector. When it sits inside a wider
// container tester.getCenter() returns a point outside the narrow track.
// We use tapAt(rect.left + 22, rect.center.dy) to land on the 44 px track
// regardless of the containing box width (same pattern as
// properties_visible_test.dart).
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';
Finder _field(String name) => find.byKey(ValueKey<String>('$_p.field.$name'));
Finder _editable(String name) =>
    find.descendant(of: _field(name), matching: find.byType(EditableText));

Future<void> _openProperties(WidgetTester tester) async {
  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Taps the watermark enable switch by landing 22 px from its left edge —
/// the centre of the 44 px ShadSwitch track — so the hit always falls inside
/// the GestureDetector regardless of the wider containing box.
Future<void> _tapWatermarkEnable(WidgetTester tester) async {
  final Finder sw = _field('watermarkEnable');
  await tester.ensureVisible(sw);
  await tester.pumpAndSettle();
  final Rect r = tester.getRect(sw);
  await tester.tapAt(Offset(r.left + 22, r.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('report root shows the watermark toggle; enabling sets a default',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _openProperties(tester);
    c.selectReport();
    await tester.pumpAndSettle();

    expect(_field('watermarkEnable'), findsOneWidget);
    expect(c.definition.furniture.watermark, isNull);

    await _tapWatermarkEnable(tester);

    final Watermark? wm = c.definition.furniture.watermark;
    expect(wm, isNotNull);
    expect(wm!.text, isNotEmpty);
    expect(wm.textStyle.fontSize, 64); // large default, not 12
  });

  testWidgets('editing the watermark text commits as one undoable step',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setWatermark(
        const Watermark(text: 'DRAFT', textStyle: JetTextStyle(fontSize: 64)));
    await _openProperties(tester);
    c.selectReport();
    await tester.pumpAndSettle();

    await tester.enterText(_editable('watermarkText'), 'CONFIDENTIAL');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(c.definition.furniture.watermark?.text, 'CONFIDENTIAL');
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.definition.furniture.watermark?.text, 'DRAFT');
  });

  testWidgets('editing opacity commits to the model',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setWatermark(
        const Watermark(text: 'D', textStyle: JetTextStyle(fontSize: 64)));
    await _openProperties(tester);
    c.selectReport();
    await tester.pumpAndSettle();

    await tester.enterText(_editable('watermarkOpacity'), '0.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.definition.furniture.watermark?.opacity, 0.5);
  });

  testWidgets('disabling clears the watermark', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setWatermark(
        const Watermark(text: 'D', textStyle: JetTextStyle(fontSize: 64)));
    await _openProperties(tester);
    c.selectReport();
    await tester.pumpAndSettle();

    await _tapWatermarkEnable(tester);
    expect(c.definition.furniture.watermark, isNull);
  });

  testWidgets(
      'an image watermark shows the read-only note, text field hidden, '
      'and an opacity edit preserves the image bytes',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setWatermark(Watermark(
        imageBytes: Uint8List.fromList(<int>[1, 2, 3]), opacity: 0.3));
    await _openProperties(tester);
    c.selectReport();
    await tester.pumpAndSettle();

    expect(_field('watermarkText'), findsNothing);
    await tester.enterText(_editable('watermarkOpacity'), '0.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.definition.furniture.watermark?.imageBytes, isNotNull);
    expect(c.definition.furniture.watermark?.opacity, 0.5);
  });
}
