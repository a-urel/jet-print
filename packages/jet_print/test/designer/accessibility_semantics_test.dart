// T079a — accessibility / semantics for the interactive editing affordances
// (FR-024 / SC-008). Asserts localized accessible NAMES and ROLES on:
//   * each canvas element hit region (e.g. "Text element text1"), button role,
//     reflecting selection;
//   * the eight element resize handles (directional names, button role);
//   * the band-height resize handle;
//   * the new top-bar editing actions (Arrange / zoom / save), which expose a
//     localized accessible name and are focus-reachable buttons (no mouse).
//
// Drives the public `JetReportDesigner` only.
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

Finder _element(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));
Finder _handle(String pos) =>
    find.byKey(ValueKey<String>('jet_print.designer.handle.$pos'));
final Finder _bandHandle =
    find.byKey(const ValueKey<String>('jet_print.designer.bandHandle'));

void main() {
  testWidgets('a selected element exposes a localized, role-tagged a11y name',
      (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.createElement(DesignerToolType.text,
        bandId: firstDetailBandId(c), at: const JetOffset(40, 40));
    final String id = c.selection.singleOrNull!;
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_element(id)),
      isSemantics(label: 'Text element $id', isButton: true, isSelected: true),
    );
    sem.dispose();
  });

  testWidgets('the eight resize handles carry localized names + button role',
      (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.createElement(DesignerToolType.text,
        bandId: firstDetailBandId(c), at: const JetOffset(60, 60));
    await tester.pumpAndSettle();

    const Map<String, String> names = <String, String>{
      'topLeft': 'Resize top-left corner',
      'top': 'Resize top edge',
      'topRight': 'Resize top-right corner',
      'right': 'Resize right edge',
      'bottomRight': 'Resize bottom-right corner',
      'bottom': 'Resize bottom edge',
      'bottomLeft': 'Resize bottom-left corner',
      'left': 'Resize left edge',
    };
    names.forEach((String pos, String label) {
      expect(
        tester.getSemantics(_handle(pos)),
        isSemantics(label: label, isButton: true),
        reason: 'handle "$pos" should announce "$label"',
      );
    });
    sem.dispose();
  });

  testWidgets('the band-height handle carries a localized accessible name',
      (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.selectBand(firstDetailBandId(c));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(_bandHandle),
      isSemantics(label: 'Resize band height', isButton: true),
    );
    sem.dispose();
  });

  testWidgets('new top-bar editing actions expose localized accessible names',
      (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.createElement(DesignerToolType.text,
        bandId: firstDetailBandId(c), at: const JetOffset(20, 20));
    c.selectAll();
    await tester.pumpAndSettle();

    // Each new/edit affordance is announced by name and reachable without a
    // mouse (it is a focusable button in the traversal order).
    expect(find.bySemanticsLabel('Arrange'), findsOneWidget);
    expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);
    expect(find.bySemanticsLabel('Zoom out'), findsOneWidget);
    expect(find.bySemanticsLabel('Save'), findsWidgets); // the Save action

    // The Arrange trigger is a button with the enabled state exposed.
    expect(
      tester.getSemantics(find.byKey(kArrangeButtonKey)),
      isSemantics(label: 'Arrange', isButton: true, isEnabled: true),
    );
    sem.dispose();
  });

  // --- Shape gallery thumbnails (020 / C9.1–C9.2 / FR-012) ------------------
  testWidgets(
      'each gallery thumbnail is a named, role-tagged, activatable button',
      (WidgetTester tester) async {
    final SemanticsHandle sem = tester.ensureSemantics();
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.createElement(DesignerToolType.shape,
        bandId: firstDetailBandId(c),
        at: const JetOffset(20, 20)); // a rectangle, auto-selected
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    Finder thumb(String name) => find
        .byKey(ValueKey<String>('jet_print.designer.properties.shape.$name'));

    // The active form (rectangle) is a selected button carrying its localized
    // name and a tap action — reachable and activatable without a mouse.
    expect(
      tester.getSemantics(thumb('rectangle')),
      isSemantics(
        label: 'Rectangle',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    // A non-active form is a named, unselected, activatable button.
    expect(
      tester.getSemantics(thumb('hexagon')),
      isSemantics(
        label: 'Hexagon',
        isButton: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
    sem.dispose();
  });

  // --- Font section controls (021 / C12 / FR-016) ---------------------------
  group('Font section a11y (021)', () {
    Finder field(String name) => find
        .byKey(ValueKey<String>('jet_print.designer.properties.field.$name'));

    Future<JetReportDesignerController> pumpWithText(
        WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.createElement(DesignerToolType.text,
          bandId: firstDetailBandId(c), at: const JetOffset(20, 20));
      await tester.pumpAndSettle();
      await openPropertiesTab(tester);
      return c;
    }

    testWidgets(
        'the B/I/U toggles are named, role-tagged, stateful, activatable '
        'buttons', (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await pumpWithText(tester);

      const Map<String, String> names = <String, String>{
        'bold': 'Bold',
        'italic': 'Italic',
        'underline': 'Underline',
      };
      for (final MapEntry<String, String> entry in names.entries) {
        expect(
          tester.getSemantics(field(entry.key)),
          isSemantics(
            label: entry.value,
            isButton: true,
            isSelected: false,
            hasTapAction: true,
          ),
          reason: '${entry.key} announces "${entry.value}"',
        );
      }
      sem.dispose();
    });

    testWidgets('an active toggle reports its selected state',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await pumpWithText(tester);

      await tester.tap(field('underline'));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(field('underline')),
        isSemantics(label: 'Underline', isButton: true, isSelected: true),
      );
      sem.dispose();
    });

    testWidgets(
        'the alignment segments are named buttons; the inactive ones are '
        'activatable', (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await pumpWithText(tester);

      // Left is the default — active and announced.
      expect(
        tester.getSemantics(field('align.left')),
        isSemantics(label: 'Align left', isButton: true, isSelected: true),
      );
      // Center/right are unselected and tappable.
      expect(
        tester.getSemantics(field('align.center')),
        isSemantics(
          label: 'Align center',
          isButton: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(field('align.right')),
        isSemantics(
          label: 'Align right',
          isButton: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      sem.dispose();
    });

    testWidgets(
        'the color trigger and palette swatches are named, activatable '
        'buttons', (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await pumpWithText(tester);

      // The trigger merges its current value into the accessible label
      // ("Choose color\n#000000") — the name AND the state are announced.
      final SemanticsNode trigger = tester.getSemantics(field('textColor'));
      expect(trigger, isSemantics(isButton: true, hasTapAction: true));
      expect(trigger.label, contains('Choose color'));

      await tester.tap(field('textColor'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(field('textColor.swatch.red')),
        isSemantics(label: 'Red', isButton: true, hasTapAction: true),
      );
      sem.dispose();
    });

    testWidgets('the family picker trigger is a named, activatable button',
        (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      await pumpWithText(tester);

      // The merged label carries the accessible name plus the current family.
      final SemanticsNode trigger = tester.getSemantics(field('fontFamily'));
      expect(trigger, isSemantics(isButton: true, hasTapAction: true));
      expect(trigger.label, contains('Choose font family'));
      sem.dispose();
    });
  });

  // --- Appearance section controls (021 / US2 / C12) ------------------------
  group('Appearance section a11y (021)', () {
    Finder field(String name) => find
        .byKey(ValueKey<String>('jet_print.designer.properties.field.$name'));

    testWidgets(
        'the fill/outline triggers and the None entry are named, activatable '
        'buttons', (WidgetTester tester) async {
      final SemanticsHandle sem = tester.ensureSemantics();
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.createElement(DesignerToolType.shape,
          bandId: firstDetailBandId(c), at: const JetOffset(20, 20));
      await tester.pumpAndSettle();
      await openPropertiesTab(tester);

      for (final String name in <String>['fill', 'stroke']) {
        final SemanticsNode trigger = tester.getSemantics(field(name));
        expect(trigger, isSemantics(isButton: true, hasTapAction: true),
            reason: '$name trigger is an activatable button');
        expect(trigger.label, contains('Choose color'));
      }

      await tester.tap(field('fill'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(field('fill.none')),
        isSemantics(label: 'None', isButton: true, hasTapAction: true),
      );
      sem.dispose();
    });
  });
}
