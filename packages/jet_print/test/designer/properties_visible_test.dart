// Properties panel Visible section test (task 9).
//
// Verifies that the "Visible" toggle in the Properties panel is wired to
// `setElementVisible` and `setBandVisible` on the controller.  Drives only the
// public entry point (`package:jet_print/jet_print.dart`).
//
// ## Why tapAt rather than tap
//
// ShadSwitch without a label wraps a 44 px GestureDetector inside Expanded.
// When the switch sits inside a _LabeledRow the outer widget is constrained to
// the full Expanded width (~90 px), so tester.getCenter() returns a point that
// is OUTSIDE the narrow GestureDetector. We use tapAt(rect.topLeft + Offset(22,
// rect.height/2)) to land squarely on the 44 px track regardless of how wide
// the containing Expanded box is.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';

final Finder _visibleSwitchWidget =
    find.byKey(const ValueKey<String>('$_p.field.visible'));

/// Taps the visible switch by hitting 22 px from its left edge (the centre of
/// the 44 px ShadSwitch track), which lies within the GestureDetector
/// regardless of the wider Expanded constraint.
Future<void> _tapVisibleSwitch(WidgetTester tester) async {
  await tester.ensureVisible(_visibleSwitchWidget);
  await tester.pumpAndSettle();
  final Rect r = tester.getRect(_visibleSwitchWidget);
  await tester.tapAt(Offset(r.left + 22, r.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  group('properties — Visible (element)', () {
    testWidgets('Visible switch is shown when a text element is selected',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await openPropertiesTab(tester);
      c.createElement(DesignerToolType.text,
          bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
      await tester.pumpAndSettle();

      expect(_visibleSwitchWidget, findsOneWidget);
    });

    testWidgets('toggling the Visible switch off sets element visible to false',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await openPropertiesTab(tester);
      c.createElement(DesignerToolType.text,
          bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
      final String id = c.selection.singleOrNull!;
      await tester.pumpAndSettle();

      // Element starts visible (default BoolProperty value is true).
      ReportElement element() => c.definition.body.root.children
          .whereType<BandNode>()
          .first
          .band
          .elements
          .firstWhere((ReportElement e) => e.id == id);
      expect(element().visible.value, isTrue);

      await _tapVisibleSwitch(tester);

      expect(element().visible, const BoolProperty(value: false));
    });

    testWidgets('toggling Visible off is undoable',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await openPropertiesTab(tester);
      c.createElement(DesignerToolType.text,
          bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
      final String id = c.selection.singleOrNull!;
      await tester.pumpAndSettle();

      ReportElement element() => c.definition.body.root.children
          .whereType<BandNode>()
          .first
          .band
          .elements
          .firstWhere((ReportElement e) => e.id == id);

      await _tapVisibleSwitch(tester);
      expect(element().visible.value, isFalse);

      c.undo();
      await tester.pumpAndSettle();
      expect(element().visible.value, isTrue);
    });

    testWidgets('Visible switch shown for a shape element too',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await openPropertiesTab(tester);
      c.createElement(DesignerToolType.shape,
          bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
      await tester.pumpAndSettle();

      expect(_visibleSwitchWidget, findsOneWidget);
    });
  });

  group('properties — Visible (band)', () {
    testWidgets('Visible switch is shown when a band is selected',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await openPropertiesTab(tester);
      c.selectBand(firstDetailBandId(c));
      await tester.pumpAndSettle();

      expect(_visibleSwitchWidget, findsOneWidget);
    });

    testWidgets(
        'toggling the band Visible switch off sets band visible to false',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await openPropertiesTab(tester);
      c.selectBand(firstDetailBandId(c));
      await tester.pumpAndSettle();

      Band band() =>
          c.definition.body.root.children.whereType<BandNode>().first.band;
      expect(band().visible.value, isTrue);

      await _tapVisibleSwitch(tester);

      expect(band().visible, const BoolProperty(value: false));
    });
  });

  group('properties — Visible expression state', () {
    final Finder exprField =
        find.byKey(const ValueKey<String>('$_p.field.visibleExpression'));
    final Finder clearButton =
        find.byKey(const ValueKey<String>('$_p.field.visibleClear'));

    testWidgets(
        'an expression hides the switch and shows the field + clear button',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await openPropertiesTab(tester);
      c.createElement(DesignerToolType.text,
          bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
      final String id = c.selection.singleOrNull!;
      c.setElementVisible(id, const BoolProperty(expression: '1 == 2'));
      await tester.pumpAndSettle();

      expect(_visibleSwitchWidget, findsNothing);
      expect(exprField, findsOneWidget);
      expect(clearButton, findsOneWidget);
    });

    testWidgets('clearing the expression reverts to the static switch',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await openPropertiesTab(tester);
      c.createElement(DesignerToolType.text,
          bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
      final String id = c.selection.singleOrNull!;
      c.setElementVisible(id, const BoolProperty(expression: '1 == 2'));
      await tester.pumpAndSettle();

      ReportElement element() => c.definition.body.root.children
          .whereType<BandNode>()
          .first
          .band
          .elements
          .firstWhere((ReportElement e) => e.id == id);

      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(element().visible.expression, isNull);
      expect(_visibleSwitchWidget, findsOneWidget);
      expect(exprField, findsNothing);
    });
  });
}
