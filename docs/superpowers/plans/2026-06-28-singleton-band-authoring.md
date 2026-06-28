# First-Class "Add" for the Rendered Singleton Bands — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is Red→Green TDD.

**Goal:** Let designer users create the report header, report footer, page header, page footer, and no-data bands directly from the outline (instead of only by retyping), relabel `title`/`summary` as "Report Header"/"Report Footer", and fix the sales-ledger demo so its title prints once instead of on every page.

**Architecture:** Pure designer + l10n + one demo-data change. The controller command already exists (`JetReportDesignerController.addBand(BandType)` at `jet_report_designer_controller.dart:1027`); the work is (1) relabel two ARB captions, (2) add a report-root "+" menu in the outline that iterates the existing `_retypeTargets` whitelist and calls `addBand`, (3) move the ledger title from `pageHeader` into `body.title`. No domain, serialization, or render-engine change.

**Tech Stack:** Dart / Flutter, `flutter_test`, `flutter gen-l10n` (config in `packages/jet_print/l10n.yaml`).

## Global Constraints

- No change to the `BandType` enum, the domain model, or serialization. No schema version bump.
- No change to the render/fill/layout engine.
- No new l10n keys — only value changes to existing keys.
- The add-menu offers exactly the types in `_retypeTargets` (the five **rendered** singleton slots); the three reserved types (`columnHeader`, `columnFooter`, `background`) are never offered. Source the list from `_retypeTargets` — do not write a parallel literal.
- Run `flutter`/`dart` from `packages/jet_print` (or `apps/jet_print_playground` for the demo task). Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (the `flutter` tool leaves cwd inside the package).
- Branch is already `042-singleton-band-authoring`.

---

## File Map

- `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb` — **modify**: `bandTypeTitle`, `bandTypeSummary` values + their `@`-description blocks.
- `packages/jet_print/lib/src/designer/l10n/jet_print_de.arb` — **modify**: same two keys.
- `packages/jet_print/lib/src/designer/l10n/jet_print_tr.arb` — **modify**: same two keys.
- `packages/jet_print/lib/src/designer/l10n/jet_print_localizations*.dart` — **regenerated** (do not hand-edit) via `flutter gen-l10n`.
- `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart` — **modify**: new `_reportAddMenu(...)` helper; wire it into the Report root `_branchRow` `actions:` (line 131-143).
- `packages/jet_print/test/designer/outline_report_add_test.dart` — **create**: widget test for the report "+" menu.
- `apps/jet_print_playground/lib/ledger_sample.dart` — **modify**: move the `'Sales Ledger'` title element from `pageHeader` into `body.title`; shrink the page header.
- `apps/jet_print_playground/test/ledger_definition_test.dart` — **modify**: assert title now lives in `body.title`, not in the page header.
- `apps/jet_print_playground/test/rendered_ledger_example_test.dart` — **modify**: assert the title renders on page 0 only.

The controller (`addBand`) is **not** modified — it already does exactly what's needed, and is already covered by `test/designer/controller/band_lifecycle_test.dart`.

---

## Task 1: Relabel `title`/`summary` captions to Report Header / Report Footer

`bandTypeLabel` (`designer/l10n/band_type_label.dart`) is the single source for band captions, used by canvas band badges, the outline tree, the retype menu, and (after Task 2) the add menu. Relabeling the two ARB values flows everywhere at once.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_de.arb`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_tr.arb`
- Regenerated: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations*.dart`

- [ ] **Step 1: Edit `jet_print_en.arb`.** Change the two values and their descriptions (lines ~164 and ~196):

```json
  "bandTypeTitle": "Report Header",
  "@bandTypeTitle": {
    "description": "Caption on the design-surface badge for the report header band (printed once at the report start). Modelled as BandType.title."
  },
```
```json
  "bandTypeSummary": "Report Footer",
  "@bandTypeSummary": {
    "description": "Caption on the design-surface badge for the report footer band (printed once at the report end). Modelled as BandType.summary."
  },
```

- [ ] **Step 2: Edit `jet_print_de.arb`** (lines ~54 and ~62):

```json
  "bandTypeTitle": "Berichtskopf",
```
```json
  "bandTypeSummary": "Berichtsfuß",
```

- [ ] **Step 3: Edit `jet_print_tr.arb`** (lines ~54 and ~62):

```json
  "bandTypeTitle": "Rapor Başlığı",
```
```json
  "bandTypeSummary": "Rapor Altbilgisi",
```

- [ ] **Step 4: Regenerate the localization delegate.**

Run: `cd packages/jet_print && flutter gen-l10n`
Expected: regenerates `lib/src/designer/l10n/jet_print_localizations*.dart` with the new values; no errors. Confirm `bandTypeTitle`/`bandTypeSummary` getters return the new strings (grep the generated `jet_print_localizations_en.dart`).

- [ ] **Step 5: Run the localization tests.**

Run: `cd packages/jet_print && flutter test test/designer/localization_de_test.dart test/designer/localization_tr_test.dart`
Expected: PASS. If either test pins the old caption ("Title"/"Summary"/"Titel"/"Başlık"), update the expectation to the new value and note why in the diff.

- [ ] **Step 6: Refresh the affected canvas goldens (intentional churn).** The relabel changes the band-badge text on any designer golden that renders a title or summary band (e.g. `test/designer/goldens/data_aware_invoice_test.dart`, `test/designer/goldens/page_letter_landscape_test.dart`).

Run (detect): `cd packages/jet_print && flutter test test/designer/goldens`
For each failure, confirm the diff is only the badge caption (and any Skia glyph-cache drift on adjacent text — a known effect when designer text changes), then regenerate:
Run: `cd packages/jet_print && flutter test --update-goldens test/designer/goldens`
Re-run without `--update-goldens` → Expected: PASS. **If a golden's geometry (not just caption text) changed, STOP and inspect** — only caption text should move.

- [ ] **Step 7: Analyzer + format.**

Run: `cd packages/jet_print && dart format lib test && flutter analyze`
Expected: no issues.

- [ ] **Step 8: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/l10n packages/jet_print/test/designer/goldens
git commit -m "feat(designer): relabel title/summary bands as Report Header/Footer"
```

---

## Task 2: Report-root "+" menu that adds an empty singleton band

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart`
- Create (test): `packages/jet_print/test/designer/outline_report_add_test.dart`

**Interfaces:**
- Consumes: `controller.addBand(BandType)` (existing; fills an empty singleton slot and selects the new band, one undoable step, no-op on an occupied slot); `bandInSlot(definition, type)` (existing, `band_walker.dart`; returns the band in a slot or null); `_retypeTargets` (existing const list in `outline_panel.dart`); `bandTypeLabel(type, l10n)`; `_TypeMenu`/`_MenuOption` (existing private widgets in the same file); `l10n.outlineAddBand` (existing string "Add band").
- Produces: stable widget keys — trigger `jet_print.designer.outline.report.add`, one option per offered type `jet_print.designer.outline.report.add.<type.name>` (e.g. `.title`, `.summary`, `.pageHeader`, `.pageFooter`, `.noData`).

- [ ] **Step 1: Write the failing widget test.** Create `packages/jet_print/test/designer/outline_report_add_test.dart`:

```dart
// Widget test: the Outline's report-root "+" menu creates an empty singleton
// band (report header/footer, page header/footer, no-data) and selects it;
// occupied slots are not offered, and the reserved column/background types are
// never offered.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openOutline(WidgetTester tester) async {
  await tester.tap(find.text('Outline').first);
  await tester.pumpAndSettle();
}

// A report that already owns a report header (body.title) so its add option
// should be suppressed.
ReportDefinition _withTitle() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(id: 't', type: BandType.title, height: 24),
        root: DetailScope(id: 'root'),
      ),
    );

void main() {
  testWidgets('report "+" adds a report header into body.title and selects it',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await _openOutline(tester);

    expect(c.definition.body.title, isNull);
    await _tapKey(tester, 'jet_print.designer.outline.report.add');
    await _tapKey(tester, 'jet_print.designer.outline.report.add.title');

    final Band? title = c.definition.body.title;
    expect(title, isNotNull);
    expect(title!.type, BandType.title);
    expect(c.selection.bandId, title.id,
        reason: 'the freshly added band is selected');
  });

  testWidgets('an occupied slot is not offered, reserved types never appear',
      (WidgetTester tester) async {
    final JetReportDesignerController c = JetReportDesignerController(
      definition: _withTitle(),
    );
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.report.add');
    // body.title is occupied → its add option is absent.
    expect(find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.report.add.title')),
        findsNothing);
    // A free slot is still offered.
    expect(find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.report.add.summary')),
        findsOneWidget);
    // Reserved (unrendered) types are never listed.
    expect(find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.report.add.columnHeader')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.report.add.background')),
        findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails.**

Run: `cd packages/jet_print && flutter test test/designer/outline_report_add_test.dart`
Expected: FAIL — the trigger key `jet_print.designer.outline.report.add` does not exist yet (`findsNothing` on the tap target).

- [ ] **Step 3: Add the `_reportAddMenu` helper.** In `outline_panel.dart`, next to `_retypeMenu` (around line 540), add:

```dart
  /// The report-root "+" affordance: a menu that creates one of the empty
  /// **rendered** singleton-slot bands — report header/footer, page
  /// header/footer, or no-data. Mirrors [_retypeTargets] so the add- and
  /// retype-menus offer the identical slot set and cannot drift; the reserved
  /// furniture types (column header/footer, background) are excluded because the
  /// layouter does not lay them out yet. Inert when every such slot is occupied.
  Widget _reportAddMenu(
    JetReportDesignerController controller,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    const String base = 'jet_print.designer.outline.report.add';
    final List<_MenuOption> options = <_MenuOption>[
      for (final BandType type in _retypeTargets)
        if (bandInSlot(controller.definition, type) == null)
          _MenuOption(
            optionKey: ValueKey<String>('$base.${type.name}'),
            label: bandTypeLabel(type, l10n),
            onPick: () => controller.addBand(type),
          ),
    ];
    return _TypeMenu(
      triggerKey: const ValueKey<String>(base),
      icon: LucideIcons.plus,
      tooltip: l10n.outlineAddBand,
      options: options,
      colors: theme.colorScheme,
    );
  }
```

- [ ] **Step 4: Wire it into the Report root row.** In `build`, the Report root `_branchRow` (line 131-143) takes no `actions:`. Add one:

```dart
      _branchRow(
        rowKey: const ValueKey<String>('jet_print.designer.outline.report'),
        toggleKey:
            const ValueKey<String>('jet_print.designer.outline.report.toggle'),
        depth: 0,
        icon: LucideIcons.fileText,
        label: l10n.reportLabel,
        expanded: _rootExpanded,
        selected: selection.isReport,
        onToggle: () => setState(() => _rootExpanded = !_rootExpanded),
        onSelect: controller.selectReport,
        theme: theme,
        actions: <Widget>[
          _reportAddMenu(controller, theme, l10n),
        ],
      ),
```

- [ ] **Step 5: Run the test to verify it passes.**

Run: `cd packages/jet_print && flutter test test/designer/outline_report_add_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Run the full designer suite.** Adding an affordance to the report root row may shift other outline tests (row structure / golden of the outline tab).

Run: `cd packages/jet_print && flutter test test/designer`
Expected: PASS. If an outline golden now shows the "+" on the report root, that is the intended change — confirm the only diff is the added glyph, then `flutter test --update-goldens test/designer/<the file>` and re-run. If a structural test asserts the report row's exact children, update it to expect the new action and note why.

- [ ] **Step 7: Analyzer + format.**

Run: `cd packages/jet_print && dart format lib test && flutter analyze`
Expected: no issues.

- [ ] **Step 8: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart packages/jet_print/test/designer/outline_report_add_test.dart packages/jet_print/test/designer
git commit -m "feat(designer): report-root + menu adds empty singleton bands"
```

---

## Task 3: Fix the ledger demo — title prints once via `body.title`

The ledger sample puts "Sales Ledger" inside `pageHeader` (`ledger_sample.dart:49-54`), so it reprints on every page. Move it into `body.title` (the report header) and keep the column headings in the page header. Use band id `reportHeader` so it doesn't collide with the existing element id `title`.

**Files:**
- Modify: `apps/jet_print_playground/lib/ledger_sample.dart`
- Modify (test): `apps/jet_print_playground/test/ledger_definition_test.dart`
- Modify (test): `apps/jet_print_playground/test/rendered_ledger_example_test.dart`

- [ ] **Step 1: Write the failing definition test.** In `ledger_definition_test.dart`, add inside the `group('ledger sample', ...)`:

```dart
    test('the report title is a body.title band, not in the page header', () {
      final ReportDefinition def = ledgerSampleDefinition();

      final Band? title = def.body.title;
      expect(title, isNotNull, reason: 'the report header exists');
      expect(title!.type, BandType.title);
      expect(
        title.elements
            .whereType<TextElement>()
            .any((TextElement e) => e.text == 'Sales Ledger'),
        isTrue,
        reason: 'the title text lives on the report header',
      );

      // The page header no longer carries the title element.
      final Set<String> headerIds = def.furniture.pageHeader!.elements
          .map((ReportElement e) => e.id)
          .toSet();
      expect(headerIds.contains('title'), isFalse);
    });
```

- [ ] **Step 2: Write the failing render test.** In `rendered_ledger_example_test.dart`, add inside the group:

```dart
    test('the report title renders once (first page only)', () {
      final RenderedReport report = renderLedgerDefinition();
      final List<int> pagesWithTitle = <int>[
        for (int i = 0; i < report.pageCount; i++)
          if (_runsOnPage(report, i, 'title').isNotEmpty) i,
      ];
      expect(pagesWithTitle, <int>[0],
          reason: 'the report header prints once at the very start');
    });
```

- [ ] **Step 3: Run both tests to verify they fail.**

Run: `cd apps/jet_print_playground && flutter test test/ledger_definition_test.dart test/rendered_ledger_example_test.dart`
Expected: FAIL — `def.body.title` is currently null, and the `title` run currently appears on every page.

- [ ] **Step 4: Move the title into `body.title` and shrink the page header.** In `ledger_sample.dart`:

(a) In `furniture.pageHeader`, delete the `'title'` `TextElement` (lines 49-54), move the headings and rule up, and reduce `height` from `40` to `18`:

```dart
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 18,
          elements: <ReportElement>[
            // Column headings — repeat on every page via the page header.
            TextElement(
              id: 'hTime',
              bounds: JetRect(x: 0, y: 2, width: 92, height: 12),
              text: 'Time',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hReceipt',
              bounds: JetRect(x: 96, y: 2, width: 66, height: 12),
              text: 'Receipt',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hItem',
              bounds: JetRect(x: 166, y: 2, width: 190, height: 12),
              text: 'Item',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hQty',
              bounds: JetRect(x: 360, y: 2, width: 34, height: 12),
              text: 'Qty',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'hAmount',
              bounds: JetRect(x: 398, y: 2, width: 74, height: 12),
              text: 'Amount',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'hStatus',
              bounds: JetRect(x: 476, y: 2, width: 62, height: 12),
              text: 'Status',
              style: JetTextStyle(
                  fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            ShapeElement(
              id: 'headerRule',
              bounds: JetRect(x: 0, y: 16, width: 538, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _rule),
            ),
          ],
        ),
```

(b) In `ReportBody(...)`, add a `title:` band before `summary:`:

```dart
      body: ReportBody(
        title: const Band(
          id: 'reportHeader',
          type: BandType.title,
          height: 22,
          elements: <ReportElement>[
            TextElement(
              id: 'title',
              bounds: JetRect(x: 0, y: 2, width: 538, height: 18),
              text: 'Sales Ledger',
              style: JetTextStyle(fontSize: 14, weight: JetFontWeight.bold),
            ),
          ],
        ),
        summary: const Band(
          // ... unchanged ...
```

- [ ] **Step 5: Run the tests to verify they pass.**

Run: `cd apps/jet_print_playground && flutter test test/ledger_definition_test.dart test/rendered_ledger_example_test.dart`
Expected: PASS — `body.title` holds "Sales Ledger", the page header has no `title` element, and the title renders only on page 0. (The existing parity and grand-total tests still pass: the title moves identically for both sources, and totals are unaffected.)

- [ ] **Step 6: Run the full playground suite.**

Run: `cd apps/jet_print_playground && flutter test`
Expected: PASS.

- [ ] **Step 7: Analyzer + format.**

Run: `cd apps/jet_print_playground && dart format lib test && flutter analyze`
Expected: no issues.

- [ ] **Step 8: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/ledger_sample.dart apps/jet_print_playground/test/ledger_definition_test.dart apps/jet_print_playground/test/rendered_ledger_example_test.dart
git commit -m "fix(playground): ledger title prints once via report header"
```

---

## Self-Review

**Spec coverage:**
- "Component 1 dropped — wire to existing `addBand`" → Task 2 Step 3 calls `controller.addBand(type)`; no new controller method. ✓
- "Report-root + menu, list sourced from `_retypeTargets`" → Task 2 Steps 3-4. ✓
- "Menu offers only the 5 rendered slots; reserved 3 excluded" → guaranteed by iterating `_retypeTargets` (which excludes them); asserted in Task 2 Step 1 test. ✓
- "Omit occupied slots" → `if (bandInSlot(...) == null)`; asserted in Task 2 Step 1. ✓
- "Relabel title/summary to Report Header/Footer, single-sourced, no new keys" → Task 1. ✓
- "ARB sync discipline — edit ARBs + regen, don't hand-edit generated Dart" → Task 1 Steps 1-4. ✓
- "Ledger demo fix — title to body.title, headings stay in pageHeader" → Task 3. ✓
- "Intentional golden churn (ledger + canvas badges), flag don't fight" → Task 1 Step 6, Task 2 Step 6. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has an expected result. ✓

**Type consistency:** `addBand(BandType)`, `bandInSlot(ReportDefinition, BandType)`, `bandTypeLabel(BandType, JetPrintLocalizations)`, `_retypeTargets` (`List<BandType>`), `_MenuOption`/`_TypeMenu` constructors, and widget-key strings match across tasks and the existing source verified during planning. ✓
