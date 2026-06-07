// Properties panel editor test.
//
// The Properties tab dropped its header title and hint (like the Data Source
// and Outline tabs) and turned its static name/value rows into a real, editable
// property inspector built only from shadcn widgets: text fields (`ShadInput`),
// dropdowns (`ShadSelect`) and a boolean toggle (`ShadSwitch`), grouped under
// section labels.
//
// These tests drive the public `JetReportDesigner` (Properties is reached by
// selecting its tab) and never reach into `src/`.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

/// Brings [caption] into view and taps it (the tab bar can scroll when narrow).
Future<void> _selectTab(WidgetTester tester, String caption) async {
  final Finder tab = find.text(caption);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  group('properties editor', () {
    testWidgets('renders editable shadcn controls', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      expect(find.byType(ShadInput), findsWidgets); // text fields
      expect(find.byType(ShadSelect<String>), findsWidgets); // dropdowns
      expect(find.byType(ShadSwitch), findsOneWidget); // boolean toggle
    });

    testWidgets('the Visible toggle flips when tapped', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      ShadSwitch toggle() => tester.widget<ShadSwitch>(find.byType(ShadSwitch));
      expect(toggle().value, isTrue); // starts on

      await tester.tap(find.byType(ShadSwitch));
      await tester.pumpAndSettle();

      expect(toggle().value, isFalse); // genuinely editable, not static text
    });

    testWidgets('keeps property labels and section groupings', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Visible'), findsOneWidget);
    });

    testWidgets('no longer shows a header title or hint', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      expect(
        find.text('Select an element to edit its properties here.'),
        findsNothing,
      );
    });
  });

  group('element selector', () {
    // Stable key mirroring the one assigned to the selector in
    // properties_panel.dart (key-as-test-seam, like the region keys).
    const Finder Function() selector = _elementSelector;

    testWidgets('shows the current element with its glyph at the top', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      expect(selector(), findsOneWidget);
      // The closed dropdown displays the selected element name…
      expect(
        find.descendant(of: selector(), matching: find.text('label1')),
        findsOneWidget,
      );
      // …paired with its element glyph (a text element → the Text glyph).
      expect(
        find.descendant(
            of: selector(), matching: find.byIcon(LucideIcons.type)),
        findsOneWidget,
      );
    });

    testWidgets('lists the report elements as a flat list when opened', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      await tester.tap(selector());
      await tester.pumpAndSettle();

      expect(find.text('Title'), findsOneWidget);
      expect(find.text('OrdersTable'), findsOneWidget);
      expect(find.text('PageInfo'), findsOneWidget);
    });

    testWidgets('pairs each element row with a proper glyph', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      await tester.tap(selector());
      await tester.pumpAndSettle();

      // The table element row shows the Table glyph beside its name.
      final Finder tableRow = find
          .ancestor(of: find.text('OrdersTable'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: tableRow, matching: find.byIcon(LucideIcons.table)),
        findsOneWidget,
      );
    });
  });

  _refinementTests();
}

/// Locates the Properties-panel element selector by its stable key.
Finder _elementSelector() => find.byKey(
      const ValueKey<String>('jet_print.designer.elementSelector'),
    );

void _refinementTests() {
  group('properties refinements', () {
    testWidgets('section headers are flush with the panel content edge', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      final Padding box = tester.widget<Padding>(
        find
            .ancestor(of: find.text('LAYOUT'), matching: find.byType(Padding))
            .first,
      );
      final EdgeInsets insets = box.padding.resolve(TextDirection.ltr);
      expect(insets.left, 0); // no left indent before the heading
    });

    testWidgets('font size is a dropdown of point sizes', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      // The size control shows its current value '9' inside a ShadSelect…
      final Finder sizeSelect = find
          .ancestor(
              of: find.text('9'), matching: find.byType(ShadSelect<String>))
          .first;
      expect(sizeSelect, findsOneWidget);

      // …and opening it reveals standard point sizes.
      await tester.tap(sizeSelect);
      await tester.pumpAndSettle();
      expect(find.text('72'), findsOneWidget);
    });

    testWidgets('Location fields use axis icon prefixes, not letters', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      // Single-direction position arrows (X →, Y ↓) replace the old letters.
      expect(find.byIcon(LucideIcons.arrowRight), findsOneWidget); // X
      expect(find.byIcon(LucideIcons.arrowDown), findsOneWidget); // Y
      expect(find.text('X'), findsNothing);
      expect(find.text('Y'), findsNothing);
    });

    testWidgets('Size fields use width/height icon prefixes, not letters', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      // The width/height dimension glyphs replace the old W/H letters.
      expect(find.byIcon(LucideIcons.moveHorizontal), findsOneWidget); // width
      expect(find.byIcon(LucideIcons.moveVertical), findsOneWidget); // height
      expect(find.text('W'), findsNothing);
      expect(find.text('H'), findsNothing);
    });

    testWidgets('the numeric stepper increments the field value', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      // The Location X field starts at 10; its up-chevron bumps it to 11.
      final Finder xField = find.ancestor(
        of: find.byIcon(LucideIcons.arrowRight),
        matching: find.byType(ShadInput),
      );
      await tester.tap(
        find.descendant(
            of: xField, matching: find.byIcon(LucideIcons.chevronUp)),
      );
      await tester.pumpAndSettle();

      expect(find.text('11'), findsOneWidget); // genuinely editable
    });

    testWidgets('text align is an icon toggle group, not a dropdown', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      expect(find.byIcon(LucideIcons.alignLeft), findsOneWidget);
      expect(find.byIcon(LucideIcons.alignCenter), findsOneWidget);
      expect(find.byIcon(LucideIcons.alignRight), findsOneWidget);
      expect(find.byIcon(LucideIcons.alignJustify), findsOneWidget);

      // The old dropdown displayed its value as text; the icon group doesn't.
      expect(find.text('Left'), findsNothing);
    });

    testWidgets('the active alignment starts at Left and switches on tap', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      // The selected button uses the filled (primary) variant; the rest ghost.
      ShadButtonVariant variantOf(IconData icon) => tester
          .widget<ShadIconButton>(
            find.ancestor(
              of: find.byIcon(icon),
              matching: find.byType(ShadIconButton),
            ),
          )
          .variant;

      expect(variantOf(LucideIcons.alignLeft), ShadButtonVariant.primary);
      expect(variantOf(LucideIcons.alignCenter), ShadButtonVariant.ghost);

      await tester.tap(find.byIcon(LucideIcons.alignCenter));
      await tester.pumpAndSettle();

      expect(variantOf(LucideIcons.alignCenter), ShadButtonVariant.primary);
      expect(variantOf(LucideIcons.alignLeft), ShadButtonVariant.ghost);
    });
  });
}
