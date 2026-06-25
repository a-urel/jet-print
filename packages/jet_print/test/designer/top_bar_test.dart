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

// --- Unified-toolbar mode switch (017 / US1 / C2) ---
const Key _nameKey = ValueKey<String>('jet_print.toolbar.name');
const Key _modeSwitchKey = ValueKey<String>('jet_print.toolbar.modeSwitch');
const Key _modeDesignerKey =
    ValueKey<String>('jet_print.toolbar.mode.designer');
const Key _modePreviewKey = ValueKey<String>('jet_print.toolbar.mode.preview');

/// The active mode segment renders filled (secondary); the inactive one renders
/// ghost — the same variant proxy the view-toggle tests use for on/off state.
ShadButtonVariant _segmentVariant(WidgetTester tester, Key key) =>
    tester.widget<ShadButton>(find.byKey(key)).variant;

bool _segmentDisabled(WidgetTester tester, Key key) =>
    tester.widget<ShadButton>(find.byKey(key)).onPressed == null;

/// Pumps the designer bound to [controller] with an optional
/// [onPreviewRequested], so the mode-switch tests can observe the switch
/// request without the harness owning the callback.
Future<void> _pumpDesignerWithPreview(
  WidgetTester tester,
  JetReportDesignerController controller, {
  void Function(ReportDefinition current)? onPreviewRequested,
}) async {
  await pumpDesigner(
    tester,
    designer: JetReportDesigner(
      controller: controller,
      onPreviewRequested: onPreviewRequested,
    ),
  );
}

ReportDefinition _oneElementFixture() => const ReportDefinition(
      name: 'F',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(
              Band(
                id: 'detail',
                type: BandType.detail,
                height: 300,
                elements: <ReportElement>[
                  TextElement(
                      id: 'a',
                      bounds: JetRect(x: 10, y: 10, width: 20, height: 10),
                      text: 'a'),
                ],
              ),
            ),
          ],
        ),
      ),
    );

int _elementCount(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .fold<int>(0, (int n, BandNode node) => n + node.band.elements.length);

/// True iff the icon button keyed [key] is disabled (its `onPressed` is null).
bool _disabled(WidgetTester tester, Key key) =>
    tester.widget<ShadIconButton>(find.byKey(key)).onPressed == null;

void _noOpOpen() {}
void _noOpSave(ReportDefinition _) {}

void main() {
  group('designer top bar', () {
    testWidgets('keeps the report title and primary actions', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onOpenRequested: _noOpOpen,
          onSaveRequested: _noOpSave,
        ),
      );

      expect(find.text('Untitled report'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      // Export is no longer offered in the designer (it lives in the preview).
      expect(find.text('Export'), findsNothing);
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

      // The canvas drives the zoom % (it fits the page to width on load); the
      // bar shows it as a compact "X%" label (the editable field now lives in
      // the popup).
      final Finder zoomLabel = find.descendant(
        of: find.byKey(
            const ValueKey<String>('jet_print.designer.zoom.menuToggle')),
        matching: find.byType(Text),
      );
      int pct() =>
          int.parse(tester.widget<Text>(zoomLabel).data!.replaceAll('%', ''));

      final int initial = pct();
      await tester.tap(find.byIcon(LucideIcons.zoomIn));
      await tester.pumpAndSettle();
      expect(pct(), greaterThan(initial));

      final int zoomedIn = pct();
      await tester.tap(find.byIcon(LucideIcons.zoomOut));
      await tester.pumpAndSettle();
      expect(pct(), lessThan(zoomedIn));
    });

    // 017: the unified layout puts the report name on the leading edge and the
    // mode switch beside it; ALL mode-specific actions (tools + primary) now
    // live in the right slot, to the right of the switch and pinned to the edge.
    testWidgets('name + switch lead; mode actions sit to their right', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(tester);

      final Rect nameRect = tester.getRect(find.byKey(_nameKey));
      final Rect switchRect = tester.getRect(find.byKey(_modeSwitchKey));
      // Name precedes the switch on the leading edge.
      expect(nameRect.right, lessThanOrEqualTo(switchRect.left + 0.5));
      // The action groups sit to the right of the switch (the right slot)…
      expect(tester.getCenter(find.byIcon(LucideIcons.undo2)).dx,
          greaterThan(switchRect.right));
      expect(tester.getCenter(find.byIcon(LucideIcons.grid2x2)).dx,
          greaterThan(switchRect.right));
      // …and the trailing action (the Arrange menu) pins to the right edge.
      expect(
          tester
              .getCenter(find.byKey(
                  const ValueKey<String>('jet_print.designer.action.arrange')))
              .dx,
          greaterThan(kDesktopSize.width / 2));
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

    // 017 (C6.2): when narrow the action LABELS collapse to icons, but the name
    // region and the mode switch are never the regions that collapse — they stay
    // visible and reachable.
    testWidgets('collapses action labels to icons but keeps name + switch',
        (WidgetTester tester) async {
      await pumpDesigner(
        tester,
        size: const Size(700, 760),
        designer: JetReportDesigner(
          onOpenRequested: _noOpOpen,
          onSaveRequested: _noOpSave,
        ),
      );

      // File-action labels disappear, but their glyphs remain.
      expect(find.text('Open'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.byIcon(LucideIcons.folderOpen), findsOneWidget);
      expect(find.byIcon(LucideIcons.save), findsOneWidget);
      // The name region and the mode switch stay put (C6.2).
      expect(find.text('Untitled report'), findsOneWidget);
      expect(find.byKey(_modeDesignerKey), findsOneWidget);
      expect(find.byKey(_modePreviewKey), findsOneWidget);
    });

    // E5 smoke round 2: on a phone / very narrow bar (< 600px) the mode switch
    // drops its segment labels. The zoom control is a compact label + popup (the
    // editable field is no longer on the bar), so it stays at every width.
    const Key zoomToggleKey =
        ValueKey<String>('jet_print.designer.zoom.menuToggle');
    const Key zoomFieldKey =
        ValueKey<String>('jet_print.designer.action.zoomLevel');
    testWidgets('phone width: mode switch is icon-only; zoom % label stays',
        (WidgetTester tester) async {
      await pumpDesigner(tester, size: const Size(390, 760));

      // Mode switch: both segments stay (by key + glyph) but show no text label.
      expect(find.byKey(_modeDesignerKey), findsOneWidget);
      expect(find.byKey(_modePreviewKey), findsOneWidget);
      expect(find.byIcon(LucideIcons.pencilRuler), findsOneWidget,
          reason: 'the Designer segment keeps its glyph');
      expect(find.byIcon(LucideIcons.fileSearch), findsOneWidget,
          reason: 'the Preview segment keeps its glyph');
      expect(find.text('Designer'), findsNothing,
          reason: 'the Designer segment is icon-only on a phone');
      expect(find.text('Preview'), findsNothing,
          reason: 'the Preview segment is icon-only on a phone');

      // Zoom: the compact % label trigger stays on the bar; the editable field
      // is in the (closed) popup, and the +/− buttons remain.
      expect(find.byKey(zoomToggleKey), findsOneWidget,
          reason: 'the compact zoom % label stays on a phone bar');
      expect(find.byKey(zoomFieldKey), findsNothing,
          reason: 'the editable field is in the popup, not on the bar');
      expect(find.byIcon(LucideIcons.zoomOut), findsOneWidget);
      expect(find.byIcon(LucideIcons.zoomIn), findsOneWidget);
    });

    // The width-gated companion: at a desktop width the segment labels and the
    // zoom % label are present, so desktop rendering is unchanged.
    testWidgets(
        'desktop width: mode switch keeps its labels and the zoom % label shows',
        (WidgetTester tester) async {
      await pumpDesigner(tester); // kDesktopSize (1440)

      expect(find.text('Designer'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.byKey(zoomToggleKey), findsOneWidget,
          reason: 'the compact zoom % label is shown at desktop width');
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

  // 017 (US1 / C2): the designer hosts the unified toolbar's two-segment
  // Designer|Preview mode switch. Designer is the active segment; selecting
  // Preview emits the host switch-request via the existing onPreviewRequested.
  group('designer top bar — mode switch (017 / US1)', () {
    testWidgets('renders the two-segment switch with Designer active', (
      WidgetTester tester,
    ) async {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      await _pumpDesignerWithPreview(tester, c, onPreviewRequested: (_) {});

      expect(find.byKey(_modeDesignerKey), findsOneWidget);
      expect(find.byKey(_modePreviewKey), findsOneWidget);
      // Active = filled (secondary); inactive = ghost (C2.1).
      expect(_segmentVariant(tester, _modeDesignerKey),
          ShadButtonVariant.secondary);
      expect(_segmentVariant(tester, _modePreviewKey), ShadButtonVariant.ghost);
    });

    testWidgets('tapping Preview fires onPreviewRequested(template) once', (
      WidgetTester tester,
    ) async {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      int calls = 0;
      ReportDefinition? got;
      await _pumpDesignerWithPreview(tester, c,
          onPreviewRequested: (ReportDefinition t) {
        calls++;
        got = t;
      });

      await tester.tap(find.byKey(_modePreviewKey));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(identical(got, c.definition), isTrue,
          reason: 'the live definition is handed to the host (C2.2)');
    });

    testWidgets(
        'the Preview segment is disabled when onPreviewRequested is null',
        (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      await _pumpDesignerWithPreview(tester, c); // no callback

      expect(_segmentDisabled(tester, _modePreviewKey), isTrue);
    });

    testWidgets('tapping the already-active Designer segment is a no-op (C2.5)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = JetReportDesignerController();
      addTearDown(c.dispose);
      int calls = 0;
      await _pumpDesignerWithPreview(tester, c,
          onPreviewRequested: (_) => calls++);

      await tester.tap(find.byKey(_modeDesignerKey), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(calls, 0, reason: 'the active segment performs no switch');
    });

    // 017 (FR-005 / SC-002 / C2.4): a switch request must NOT mutate the
    // controller — the host owns the swap; edits, history and selection survive.
    testWidgets('a switch request never mutates the controller', (
      WidgetTester tester,
    ) async {
      final JetReportDesignerController c = JetReportDesignerController()
        ..open(_oneElementFixture());
      addTearDown(c.dispose);
      await _pumpDesignerWithPreview(tester, c, onPreviewRequested: (_) {});

      // Make an undoable edit and select the element.
      c.select('a');
      c.nudge(5, 0);
      await tester.pumpAndSettle();
      final ReportDefinition beforeDefinition = c.definition;
      final bool undoBefore = c.canUndo;
      final bool redoBefore = c.canRedo;
      final Selection selectionBefore = c.selection;

      await tester.tap(find.byKey(_modePreviewKey));
      await tester.pumpAndSettle();

      expect(identical(c.definition, beforeDefinition), isTrue,
          reason: 'the switch request leaves the model untouched (FR-005)');
      expect(c.canUndo, undoBefore);
      expect(c.canRedo, redoBefore);
      expect(c.selection, selectionBefore);
    });
  });

  // 017 (US3 / C5.1 / SC-005): the designer's right slot carries the editing
  // actions exclusively — none of the preview's viewing-only actions appear.
  group('designer top bar — mode-specific actions (017 / US3)', () {
    testWidgets('the right slot shows the editing actions (C5.1)', (
      WidgetTester tester,
    ) async {
      await pumpDesigner(
        tester,
        designer: JetReportDesigner(
          onOpenRequested: _noOpOpen,
          onSaveRequested: _noOpSave,
        ),
      );
      // Open/save file actions, history, clipboard, zoom, view toggles, arrange.
      expect(find.byIcon(LucideIcons.undo2), findsOneWidget);
      expect(find.byIcon(LucideIcons.redo2), findsOneWidget);
      expect(find.byKey(_cutKey), findsOneWidget);
      expect(find.byKey(_pasteKey), findsOneWidget);
      expect(find.byIcon(LucideIcons.zoomIn), findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('jet_print.designer.toggle.grid')),
          findsOneWidget);
      expect(
          find.byKey(
              const ValueKey<String>('jet_print.designer.action.arrange')),
          findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('no preview-only signature action is present (SC-005)', (
      WidgetTester tester,
    ) async {
      await pumpDesignerWith(tester);
      // Page navigation is a preview-only affordance — it must not leak here.
      expect(find.byKey(const ValueKey<String>('jet_print.preview.prev')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('jet_print.preview.next')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('jet_print.preview.print')),
          findsNothing);
    });
  });
}
