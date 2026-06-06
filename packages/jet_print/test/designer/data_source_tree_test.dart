// Data Source panel tree test.
//
// The Data Source tab presents the bound dataset as a three-level explorer
// tree — database → tables/collections → fields — instead of a flat field list
// behind a header + hint. Database and table nodes expand/collapse; each field
// carries an icon chosen for its data type. The panel header title and the
// descriptive hint were removed so the tree fills the panel (the tab caption
// still names the panel).
//
// These tests stand in for an external consumer: they drive the public
// `JetReportDesigner` (Data Source is the default-active tab) and never reach
// into `src/`.
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

/// Brings [text] into the viewport (the tree scrolls) and taps it.
Future<void> _tapNode(WidgetTester tester, String text) async {
  final Finder node = find.text(text);
  await tester.ensureVisible(node);
  await tester.pumpAndSettle();
  await tester.tap(node);
  await tester.pumpAndSettle();
}

void main() {
  group('data source tree', () {
    testWidgets('shows the database → tables hierarchy', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      expect(find.text('SalesDB'), findsOneWidget); // database node
      expect(find.text('Orders'), findsOneWidget); // table node
      expect(find.text('Customers'), findsOneWidget); // table node
    });

    testWidgets('an expanded table shows its typed fields', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // Orders is expanded by default → its fields are visible.
      expect(find.text('OrderID'), findsOneWidget);
      expect(find.text('CustomerName'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('a collapsed table hides its fields until expanded', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // Customers starts collapsed.
      expect(find.text('Email'), findsNothing);

      await _tapNode(tester, 'Customers');
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('collapsing a table hides its fields', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      expect(find.text('OrderID'), findsOneWidget);

      await _tapNode(tester, 'Orders');
      expect(find.text('OrderID'), findsNothing);
    });

    testWidgets('fields carry data-type-appropriate icons', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // Orders (expanded) holds an Int32, two DateTimes and a Decimal field, so
      // the matching type glyphs are on screen.
      expect(find.byIcon(LucideIcons.hash), findsWidgets); // Int32
      expect(find.byIcon(LucideIcons.calendarClock), findsWidgets); // DateTime
      expect(find.byIcon(LucideIcons.calculator), findsWidgets); // Decimal
    });

    testWidgets('the panel no longer shows a header title or hint', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // The descriptive hint that used to sit above the field list is gone.
      expect(
        find.text('Bind report elements to fields from your data source.'),
        findsNothing,
      );
    });
  });
}
