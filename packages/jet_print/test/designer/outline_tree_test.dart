// Outline panel tree test.
//
// The Outline tab presents the report's bands and elements as an indented tree.
// Like the Data Source tab it dropped its header title and descriptive hint so
// the tree fills the panel, and it now renders the same chevron + node-icon row
// shape: every band (branch) shows its own glyph next to the disclosure chevron,
// and element (leaf) rows reuse the toolbox glyphs so an outline entry and its
// palette element read as the same thing.
//
// These tests drive the public `JetReportDesigner` (Outline is reached by
// selecting its tab) and never reach into `src/`.
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

/// A tree node labelled [text] *within the Outline panel*. Scoped to the right
/// panel so band names like "Page Header" don't collide with the canvas's
/// band-type badges (which surface the same captions on the design surface).
Finder _node(String text) =>
    find.descendant(of: find.byKey(kRightPanelKey), matching: find.text(text));

/// Brings a tree node labelled [text] into view and taps it (toggles a branch).
Future<void> _tapNode(WidgetTester tester, String text) async {
  final Finder node = _node(text);
  await tester.ensureVisible(node);
  await tester.pumpAndSettle();
  await tester.tap(node);
  await tester.pumpAndSettle();
}

void main() {
  group('outline tree', () {
    testWidgets('shows the report band/element hierarchy', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Outline');

      expect(_node('Report'), findsOneWidget);
      expect(_node('Page Header'), findsOneWidget);
      expect(_node('Detail'), findsOneWidget);
      expect(_node('Page Footer'), findsOneWidget);
    });

    testWidgets('band rows show their band glyph beside the chevron', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Outline');

      // These band glyphs used to be defined but never rendered (branches drew
      // only a chevron). They now appear alongside the chevron.
      expect(find.byIcon(LucideIcons.panelTop), findsOneWidget); // Page Header
      expect(
          find.byIcon(LucideIcons.panelBottom), findsOneWidget); // Page Footer
      // The Report root shares the top bar's report-document glyph (both denote
      // the report), so it appears in the outline as well as the top bar.
      expect(find.byIcon(LucideIcons.fileText), findsWidgets);
    });

    testWidgets('the Title text element drops the inconsistent tag glyph', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Outline');

      // Title is a text element, so it should reuse the toolbox Text glyph
      // (`type`), not a one-off `tag` icon. The tag glyph is gone entirely.
      expect(find.byIcon(LucideIcons.tag), findsNothing);
    });

    testWidgets('the panel no longer shows a header title or hint', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Outline');

      expect(
        find.text("The report's bands and elements appear here as a tree."),
        findsNothing,
      );
    });

    testWidgets('collapsing a band hides its child elements', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Outline');

      // Bands start expanded, so the Title element is visible under Page Header.
      expect(_node('Title'), findsOneWidget);

      await _tapNode(tester, 'Page Header');
      expect(_node('Title'), findsNothing);
    });

    testWidgets('re-expanding a band restores its elements', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Outline');

      await _tapNode(tester, 'Page Header');
      expect(_node('Title'), findsNothing);

      await _tapNode(tester, 'Page Header');
      expect(_node('Title'), findsOneWidget);
    });

    testWidgets('collapsing the report root hides the whole tree', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);
      await _selectTab(tester, 'Outline');

      expect(_node('Page Header'), findsOneWidget);

      await _tapNode(tester, 'Report');
      expect(_node('Page Header'), findsNothing);
      expect(_node('Detail'), findsNothing);
      expect(_node('PageInfo'), findsNothing);
    });
  });
}
