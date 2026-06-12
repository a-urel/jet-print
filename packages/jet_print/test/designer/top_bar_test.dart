// Designer top bar test.
//
// The top bar was upgraded from a title + three action buttons into a grouped
// command bar in the style of desktop report designers (DevExpress / Telerik /
// Stimulsoft): a document title, then right-clustered groups separated by
// dividers — history (undo/redo), zoom (out / level / in), view toggles
// (grid/ruler/snap) — and the primary Preview / Save / Export actions. The zoom
// control and view toggles are genuinely interactive (local-only this
// iteration); the primary actions remain non-functional placeholders.
//
// Drives the public `JetReportDesigner` and never reaches into `src/`.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

// --- Clipboard-group helpers (016 / US1 / C2) ---
const Key _cutKey = ValueKey<String>('jet_print.designer.action.cut');
const Key _copyKey = ValueKey<String>('jet_print.designer.action.copy');
const Key _pasteKey = ValueKey<String>('jet_print.designer.action.paste');

ReportTemplate _oneElementFixture() => const ReportTemplate(
      name: 'F',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 300,
          elements: <ReportElement>[
            TextElement(
                id: 'a',
                bounds: JetRect(x: 10, y: 10, width: 20, height: 10),
                text: 'a'),
          ],
        ),
      ],
    );

int _elementCount(JetReportDesignerController c) => c.template.bands
    .fold<int>(0, (int n, ReportBand b) => n + b.elements.length);

/// True iff the icon button keyed [key] is disabled (its `onPressed` is null).
bool _disabled(WidgetTester tester, Key key) =>
    tester.widget<ShadIconButton>(find.byKey(key)).onPressed == null;

void main() {
  group('designer top bar', () {
    testWidgets('keeps the report title and primary actions', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      expect(find.text('Untitled report'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('shows history, zoom and view-toggle command groups', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // History.
      expect(find.byIcon(LucideIcons.undo2), findsOneWidget);
      expect(find.byIcon(LucideIcons.redo2), findsOneWidget);
      // Zoom.
      expect(find.byIcon(LucideIcons.zoomOut), findsOneWidget);
      expect(find.byIcon(LucideIcons.zoomIn), findsOneWidget);
      // View toggles.
      expect(find.byIcon(LucideIcons.grid2x2), findsOneWidget);
      expect(find.byIcon(LucideIcons.ruler), findsOneWidget);
    });

    testWidgets('the zoom control is interactive', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      // The canvas drives the zoom % (it fits the page to width on load).
      final Finder zoomLevel = find
          .byKey(const ValueKey<String>('jet_print.designer.action.zoomLevel'));
      int pct() =>
          int.parse(tester.widget<Text>(zoomLevel).data!.replaceAll('%', ''));

      final int initial = pct();
      await tester.tap(find.byIcon(LucideIcons.zoomIn));
      await tester.pumpAndSettle();
      expect(pct(), greaterThan(initial));

      final int zoomedIn = pct();
      await tester.tap(find.byIcon(LucideIcons.zoomOut));
      await tester.pumpAndSettle();
      expect(pct(), lessThan(zoomedIn));
    });

    testWidgets('tool buttons are left-aligned; primary actions stay right', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      final double mid = kDesktopSize.width / 2;
      // The tool groups sit on the left, next to the title…
      expect(
          tester.getCenter(find.byIcon(LucideIcons.undo2)).dx, lessThan(mid));
      expect(
        tester.getCenter(find.byIcon(LucideIcons.grid2x2)).dx,
        lessThan(mid),
      );
      // …while the primary actions remain on the right edge.
      expect(tester.getCenter(find.text('Export')).dx, greaterThan(mid));
    });

    testWidgets('adjacent tool buttons are separated by ~4px', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      Rect buttonOf(IconData icon) => tester.getRect(
            find.ancestor(
              of: find.byIcon(icon),
              matching: find.byType(ShadIconButton),
            ),
          );
      final double gap =
          buttonOf(LucideIcons.redo2).left - buttonOf(LucideIcons.undo2).right;
      expect(gap, closeTo(4, 1.5));
    });

    testWidgets('does not overflow at narrow widths in any locale', (
      WidgetTester tester,
    ) async {
      for (final Locale locale in const <Locale>[
        Locale('en'),
        Locale('tr'),
        Locale('de'),
      ]) {
        await pumpDesigner(
          tester,
          size: const Size(700, 760),
          locale: locale,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'top bar overflowed at 700px in ${locale.languageCode}',
        );
      }
    });

    testWidgets('does not overflow at a very narrow width (scrolls)', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        size: const Size(440, 760),
        locale: const Locale('tr'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapses action labels to icons and hides title when narrow',
        (WidgetTester tester) async {
      await pumpDesigner(tester, size: const Size(700, 760));

      // Labels disappear, but the action glyphs (and tooltips) remain.
      expect(find.text('Preview'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.text('Export'), findsNothing);
      expect(find.byIcon(LucideIcons.eye), findsOneWidget);
      expect(find.byIcon(LucideIcons.download), findsOneWidget);
      // The title yields its space to the tools when compact.
      expect(find.text('Untitled report'), findsNothing);
    });

    // US2 (C3.4): the ruler toggle is wired to the controller exactly like the
    // grid/snap toggles — it flips `rulersEnabled` and its active styling
    // (secondary vs ghost) tracks that flag at every step.
    testWidgets('the ruler toggle drives rulersEnabled and reflects its state',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      final Finder toggle =
          find.byKey(const ValueKey<String>('jet_print.designer.toggle.ruler'));
      ShadButtonVariant variant() =>
          tester.widget<ShadIconButton>(toggle).variant;

      // Default on → active (secondary) styling.
      expect(c.rulersEnabled, isTrue);
      expect(variant(), ShadButtonVariant.secondary);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.rulersEnabled, isFalse);
      expect(variant(), ShadButtonVariant.ghost);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.rulersEnabled, isTrue);
      expect(variant(), ShadButtonVariant.secondary);
    });

    // 015 (C5.1): the grid toggle flips `gridEnabled` (visibility only) and
    // reflects its state, WITHOUT touching `snapEnabled` — the two tools are
    // independent (FR-010).
    testWidgets('the grid toggle drives gridEnabled and leaves snap untouched',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      final Finder toggle =
          find.byKey(const ValueKey<String>('jet_print.designer.toggle.grid'));
      ShadButtonVariant variant() =>
          tester.widget<ShadIconButton>(toggle).variant;

      // Grid is on by default; snap is off by default.
      expect(c.gridEnabled, isTrue);
      expect(c.snapEnabled, isFalse);
      expect(variant(), ShadButtonVariant.secondary);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.gridEnabled, isFalse);
      expect(c.snapEnabled, isFalse, reason: 'grid toggle must not touch snap');
      expect(variant(), ShadButtonVariant.ghost);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.gridEnabled, isTrue);
      expect(c.snapEnabled, isFalse);
      expect(variant(), ShadButtonVariant.secondary);
    });

    // 015 (C5.2): the snap (magnet) toggle flips `snapEnabled` and reflects its
    // state, WITHOUT touching `gridEnabled` (FR-010).
    testWidgets('the snap toggle drives snapEnabled and leaves grid untouched',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      final Finder toggle =
          find.byKey(const ValueKey<String>('jet_print.designer.toggle.snap'));
      ShadButtonVariant variant() =>
          tester.widget<ShadIconButton>(toggle).variant;

      // Snap is off by default → ghost; grid is on.
      expect(c.snapEnabled, isFalse);
      expect(c.gridEnabled, isTrue);
      expect(variant(), ShadButtonVariant.ghost);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.snapEnabled, isTrue);
      expect(c.gridEnabled, isTrue, reason: 'snap toggle must not touch grid');
      expect(variant(), ShadButtonVariant.secondary);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(c.snapEnabled, isFalse);
      expect(c.gridEnabled, isTrue);
      expect(variant(), ShadButtonVariant.ghost);
    });
  });

  // 016 (C2 / US1): a fenced Cut / Copy / Paste icon-button group, fully
  // mouse-operable, with enablement bound to canCopy/canPaste and localized
  // tooltips carrying the platform shortcut glyph.
  group('designer top bar — clipboard group', () {
    testWidgets('presents Cut, Copy and Paste buttons', (
      WidgetTester tester,
    ) async {
      await pumpDesignerWith(tester);
      expect(find.byKey(_cutKey), findsOneWidget);
      expect(find.byKey(_copyKey), findsOneWidget);
      expect(find.byKey(_pasteKey), findsOneWidget);
    });

    testWidgets(
        'nothing selected ⇒ Cut & Copy disabled; empty ⇒ Paste disabled',
        (WidgetTester tester) async {
      // Blank document: no selection, empty clipboard (SC-003).
      await pumpDesignerWith(tester);
      expect(_disabled(tester, _cutKey), isTrue);
      expect(_disabled(tester, _copyKey), isTrue);
      expect(_disabled(tester, _pasteKey), isTrue);
    });

    testWidgets('select ⇒ Copy enabled; tap Copy ⇒ Paste re-enables reactively',
        (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_oneElementFixture());
      await pumpDesignerWith(tester, controller: c);

      // Selecting an element enables Cut/Copy; Paste still disabled (empty).
      c.select('a');
      await tester.pumpAndSettle();
      expect(_disabled(tester, _copyKey), isFalse);
      expect(_disabled(tester, _cutKey), isFalse);
      expect(_disabled(tester, _pasteKey), isTrue);

      // A mouse Copy must re-enable Paste with NO further interaction — this is
      // the D1 notify path flowing through DesignerScope's InheritedNotifier.
      await tester.tap(find.byKey(_copyKey));
      await tester.pumpAndSettle();
      expect(_disabled(tester, _pasteKey), isFalse);
    });

    testWidgets('mouse-only Copy then Paste inserts a selected offset copy',
        (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_oneElementFixture());
      await pumpDesignerWith(tester, controller: c);
      c.select('a');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_copyKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_pasteKey));
      await tester.pumpAndSettle();

      // Element count +1 and the pasted copy is the new selection (SC-001).
      expect(_elementCount(c), 2);
      expect(c.selection.singleOrNull, isNotNull);
      expect(c.selection.singleOrNull, isNot('a'));
    });

    testWidgets('Cut removes the element; Paste re-inserts it',
        (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_oneElementFixture());
      await pumpDesignerWith(tester, controller: c);
      c.select('a');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_cutKey)); // Acceptance 1.2
      await tester.pumpAndSettle();
      expect(_elementCount(c), 0);

      await tester.tap(find.byKey(_pasteKey));
      await tester.pumpAndSettle();
      expect(_elementCount(c), 1);
    });

    testWidgets('Cut then Undo restores the document in a single step',
        (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_oneElementFixture());
      await pumpDesignerWith(tester, controller: c);
      c.select('a');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_cutKey));
      await tester.pumpAndSettle();
      expect(_elementCount(c), 0);

      // A single Undo restores the cut element (Acceptance 1.5).
      await tester.tap(
          find.byKey(const ValueKey<String>('jet_print.designer.action.undo')));
      await tester.pumpAndSettle();
      expect(_elementCount(c), 1);
    });

    testWidgets(
        'tooltips carry the localized label and platform shortcut glyph',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await pumpDesignerWith(tester);
      // The _IconButton exposes its tooltip as the button's accessible name, so
      // it is observable without hovering. On Apple platforms the glyph is ⌘.
      final String cut = tester.getSemantics(find.byKey(_cutKey)).label;
      final String copy = tester.getSemantics(find.byKey(_copyKey)).label;
      final String paste = tester.getSemantics(find.byKey(_pasteKey)).label;
      // Reset the override before the test body ends — the binding asserts no
      // foundation debug var is left set (addTearDown would run too late).
      debugDefaultTargetPlatformOverride = null;
      expect(cut, allOf(contains('Cut'), contains('⌘X')));
      expect(copy, allOf(contains('Copy'), contains('⌘C')));
      expect(paste, allOf(contains('Paste'), contains('⌘V')));
    });
  });
}
