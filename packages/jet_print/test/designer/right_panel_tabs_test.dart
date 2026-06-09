// Right-panel tab-switching test (US2 / FR-004/005/006, FR-010) plus the US3
// panel-content shape assertions (T026).
//
// Asserts Data Source is active by default, that switching tabs swaps exactly
// one visible body while hiding the others, and that each body shows content
// shaped like its future purpose (field list / element tree / property rows).
//
// Because the right panel uses `maintainState: false`, an inactive tab's body
// leaves the widget tree entirely — so "hidden" is provable as `findsNothing`,
// giving an unambiguous "exactly one body visible" guarantee.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

/// Brings a tab caption into view (the tab bar scrolls horizontally when narrow)
/// and taps it. Robust to the inflated text metrics of the test font.
Future<void> _selectTab(WidgetTester tester, String caption) async {
  final Finder tab = find.text(caption);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

// A unique marker for each panel body, used to prove which one is mounted. All
// three panels dropped their header/hint, so each is detected by stable sample
// content: a root tree-node name (Data Source / Outline) or a property label
// (Properties).
// With no data source attached, the Data Source panel shows its empty state —
// its representative default content (the old hardcoded sample tree is gone).
const String _dataSourceMarker = 'No data source attached.';
const String _outlineMarker = 'Report';
// The Properties panel is model-driven; with nothing selected it shows its
// empty-state hint, which is its representative default content.
const String _propertiesMarker = 'Select an object to edit its properties.';

void main() {
  group('right panel tabs', () {
    testWidgets('Data Source is the default-active panel', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      expect(find.text(_dataSourceMarker), findsOneWidget);
      expect(find.text(_outlineMarker), findsNothing);
      expect(find.text(_propertiesMarker), findsNothing);
    });

    testWidgets('selecting a tab shows its body and hides the others', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // Data Source → Outline.
      await _selectTab(tester, 'Outline');
      expect(find.text(_outlineMarker), findsOneWidget);
      expect(find.text(_dataSourceMarker), findsNothing);
      expect(find.text(_propertiesMarker), findsNothing);

      // Outline → Properties.
      await _selectTab(tester, 'Properties');
      expect(find.text(_propertiesMarker), findsOneWidget);
      expect(find.text(_dataSourceMarker), findsNothing);
      expect(find.text(_outlineMarker), findsNothing);

      // Properties → back to Data Source.
      await _selectTab(tester, 'Data Source');
      expect(find.text(_dataSourceMarker), findsOneWidget);
      expect(find.text(_outlineMarker), findsNothing);
      expect(find.text(_propertiesMarker), findsNothing);
    });
  });

  // --- US3: each panel body shows representative placeholder content (T026) ---
  group('right panel placeholder content (US3 / FR-007)', () {
    testWidgets('Data Source shows the attached schema as a field tree', (
      WidgetTester tester,
    ) async {
      const JetDataSchema schema = JetDataSchema(
        name: 'Invoice',
        fields: <FieldDef>[FieldDef('customerName', type: JetFieldType.string)],
      );
      await pumpDesigner(
        tester,
        designer: const JetReportDesigner(dataSchema: schema),
      );

      // The attached schema's field is shown in the tree.
      expect(find.text('customerName'), findsOneWidget);
    });

    testWidgets('Outline shows an element-tree shape', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Outline');

      // A sample band node in the outline tree. Scoped to the right panel so it
      // does not collide with the canvas's band-type badges (which surface the
      // same caption on the design surface).
      expect(
        find.descendant(
          of: find.byKey(kRightPanelKey),
          matching: find.text('Page Header'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Properties shows its inspector (empty state by default)', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Properties');

      // With nothing selected the inspector prompts the user to select an object.
      expect(find.text(_propertiesMarker), findsOneWidget);
    });
  });
}
