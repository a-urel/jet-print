// Outline panel tree test (model-driven, T071).
//
// The Outline tab renders the live `ReportTemplate` as an indented tree: a
// Report root, one branch per band (localized band-type caption), and a leaf per
// element. The current selection is highlighted; tapping a row selects that
// object (report / band / element) through the controller; the disclosure
// chevron collapses/expands a branch.
//
// These tests drive the public `JetReportDesigner` (Outline is reached by
// selecting its tab) and never reach into `src/`.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

Key _reportRow = const ValueKey<String>('jet_print.designer.outline.report');
Key _reportToggle =
    const ValueKey<String>('jet_print.designer.outline.report.toggle');
Key _bandRow(int i) => ValueKey<String>('jet_print.designer.outline.band.$i');
Key _bandToggle(int i) =>
    ValueKey<String>('jet_print.designer.outline.band.$i.toggle');
Key _elementRow(String id) =>
    ValueKey<String>('jet_print.designer.outline.element.$id');

Finder _inPanel(String text) =>
    find.descendant(of: find.byKey(kRightPanelKey), matching: find.text(text));

Future<void> _openOutline(WidgetTester tester) async {
  final Finder tab = find.text('Outline');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  group('outline tree (model-driven)', () {
    testWidgets('reflects the template: a Report root over each band',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);
      await _openOutline(tester);

      // Default template: page header, detail, page footer.
      expect(find.byKey(_reportRow), findsOneWidget);
      expect(find.byKey(_bandRow(0)), findsOneWidget);
      expect(find.byKey(_bandRow(1)), findsOneWidget);
      expect(find.byKey(_bandRow(2)), findsOneWidget);
      // The old hard-coded sample content is gone.
      expect(_inPanel('OrdersTable'), findsNothing);
      expect(_inPanel('PageInfo'), findsNothing);
    });

    testWidgets('shows an element created in the model under its band',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openOutline(tester);
      c.createElement(DesignerToolType.text,
          bandIndex: 1, at: const JetOffset(10, 10));
      final String id = c.selection.singleOrNull!;
      await tester.pumpAndSettle();

      expect(find.byKey(_elementRow(id)), findsOneWidget);
    });

    testWidgets('tapping a band row selects that band',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openOutline(tester);

      await tester.tap(find.byKey(_bandRow(1)));
      await tester.pumpAndSettle();
      expect(c.selection.bandIndex, 1);
    });

    testWidgets('tapping an element row selects that element',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openOutline(tester);
      c.createElement(DesignerToolType.text,
          bandIndex: 1, at: const JetOffset(10, 10));
      final String id = c.selection.singleOrNull!;
      c.selectReport(); // move selection away
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_elementRow(id)));
      await tester.pumpAndSettle();
      expect(c.selection.singleOrNull, id);
    });

    testWidgets('tapping the Report root selects the report',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openOutline(tester);
      c.selectBand(0); // move selection away
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_reportRow));
      await tester.pumpAndSettle();
      expect(c.selection.isReport, isTrue);
    });

    testWidgets('the row matching the selection is marked selected',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openOutline(tester);
      c.selectBand(1);
      await tester.pumpAndSettle();

      final SemanticsHandle handle = tester.ensureSemantics();
      expect(tester.getSemantics(find.byKey(_bandRow(1))),
          isSemantics(isSelected: true));
      expect(tester.getSemantics(find.byKey(_bandRow(0))),
          isSemantics(isSelected: false));
      handle.dispose();
    });

    testWidgets('the chevron collapses and re-expands a band',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      await _openOutline(tester);
      c.createElement(DesignerToolType.text,
          bandIndex: 1, at: const JetOffset(10, 10));
      final String id = c.selection.singleOrNull!;
      await tester.pumpAndSettle();
      expect(find.byKey(_elementRow(id)), findsOneWidget);

      await tester.tap(find.byKey(_bandToggle(1)));
      await tester.pumpAndSettle();
      expect(find.byKey(_elementRow(id)), findsNothing);

      await tester.tap(find.byKey(_bandToggle(1)));
      await tester.pumpAndSettle();
      expect(find.byKey(_elementRow(id)), findsOneWidget);
    });

    testWidgets('collapsing the Report root hides the bands',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);
      await _openOutline(tester);
      expect(find.byKey(_bandRow(0)), findsOneWidget);

      await tester.tap(find.byKey(_reportToggle));
      await tester.pumpAndSettle();
      expect(find.byKey(_bandRow(0)), findsNothing);
      expect(find.byKey(_bandRow(2)), findsNothing);
    });
  });
}
