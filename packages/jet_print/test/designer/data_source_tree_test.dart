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
}
