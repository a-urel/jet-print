// Data Source panel tree test (US1 / FR-005..FR-008).
//
// The Data Source tab renders the *attached* `JetDataSchema` as an expandable
// tree — dataset → fields, with a nested `collection` field expanding to its
// own child fields — replacing the old hardcoded placeholder. With no schema
// attached, the panel shows an empty state and no field names.
//
// These tests stand in for an external consumer: they drive the public
// `JetReportDesigner` (Data Source is the default-active tab) and never reach
// into `src/`.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

/// A small invoice structure: scalar master fields plus a nested `lines`
/// collection carrying its own child fields.
const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('total', type: JetFieldType.double),
    FieldDef(
      'lines',
      type: JetFieldType.collection,
      fields: <FieldDef>[
        FieldDef('description', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
      ],
    ),
  ],
);

/// Brings [text] into the viewport (the tree scrolls) and taps it.
Future<void> _tapNode(WidgetTester tester, String text) async {
  final Finder node = find.text(text);
  await tester.ensureVisible(node);
  await tester.pumpAndSettle();
  await tester.tap(node);
  await tester.pumpAndSettle();
}

/// A schema whose fields carry human-friendly descriptions (leaf + collection).
const JetDataSchema _described = JetDataSchema(
  name: 'Sales',
  fields: <FieldDef>[
    FieldDef('customerTotal',
        type: JetFieldType.double, description: 'Total spend per customer'),
    FieldDef('plainField', type: JetFieldType.string),
    FieldDef(
      'orders',
      type: JetFieldType.collection,
      description: 'Orders placed',
      fields: <FieldDef>[FieldDef('lineTotal', type: JetFieldType.double)],
    ),
  ],
);

void main() {
  group('data source tree (attached schema)', () {
    testWidgets('renders the dataset name and its scalar fields', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: const JetReportDesigner(dataSchema: _invoice),
      );

      expect(find.text('Invoice'), findsOneWidget); // dataset root
      expect(find.text('invoiceNo'), findsOneWidget);
      expect(find.text('total'), findsOneWidget);
      expect(find.text('lines'), findsOneWidget); // collection node
    });

    testWidgets('a nested collection expands to its child fields', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: const JetReportDesigner(dataSchema: _invoice),
      );

      // `lines` starts collapsed — its child fields are hidden.
      expect(find.text('description'), findsNothing);
      expect(find.text('qty'), findsNothing);

      await _tapNode(tester, 'lines');
      expect(find.text('description'), findsOneWidget);
      expect(find.text('qty'), findsOneWidget);
    });

    testWidgets('fields carry data-type-appropriate icons', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: const JetReportDesigner(dataSchema: _invoice),
      );

      // `total` is a decimal (double) and `lines` is a collection at top level.
      expect(find.byIcon(LucideIcons.calculator), findsWidgets); // double
      expect(find.byIcon(LucideIcons.list), findsWidgets); // collection
      // After expanding `lines`, its integer child surfaces a hash glyph.
      await _tapNode(tester, 'lines');
      expect(find.byIcon(LucideIcons.hash), findsWidgets); // integer
    });

    testWidgets('shows an empty state and no fields when no schema is attached',
        (WidgetTester tester) async {
      await pumpDesigner(tester); // no dataSchema

      expect(find.text('No data source attached.'), findsOneWidget);
      // No schema fields and no remnant of the old hardcoded placeholder.
      expect(find.text('Invoice'), findsNothing);
      expect(find.text('SalesDB'), findsNothing);
    });
  });

  group('data source tree (field descriptions)', () {
    testWidgets('a leaf field shows its description under the name', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: const JetReportDesigner(dataSchema: _described),
      );
      expect(find.text('customerTotal'), findsOneWidget);
      expect(find.text('Total spend per customer'), findsOneWidget);
    });

    testWidgets('a field without a description shows only its name', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: const JetReportDesigner(dataSchema: _described),
      );
      expect(find.text('plainField'), findsOneWidget);
      // No stray empty subtitle: the only texts are node names + type tokens.
      expect(find.text(''), findsNothing);
    });

    testWidgets('a collection field shows its description under the name', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: const JetReportDesigner(dataSchema: _described),
      );
      expect(find.text('orders'), findsOneWidget);
      expect(find.text('Orders placed'), findsOneWidget);
    });

    testWidgets(
        'drag feedback chip shows the field name, never the description', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: const JetReportDesigner(dataSchema: _described),
      );

      // Before dragging: the name and description each appear exactly once
      // (the tree row).
      expect(find.text('customerTotal'), findsOneWidget);
      expect(find.text('Total spend per customer'), findsOneWidget);

      // Start a drag on the `customerTotal` leaf row so the feedback chip
      // materialises in the Overlay.
      final TestGesture gesture = await tester
          .startGesture(tester.getCenter(find.text('customerTotal')));
      // Move enough for Flutter to recognise a drag and render the feedback.
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump();

      // The feedback chip (_FieldDragChip) also renders the field NAME as text,
      // so `customerTotal` now appears in TWO places: the original row + the chip.
      // This directly proves the chip carries the name, not the description.
      expect(find.text('customerTotal'), findsAtLeastNWidgets(2));
      // The description must NOT appear in the chip (still exactly one instance).
      expect(find.text('Total spend per customer'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
