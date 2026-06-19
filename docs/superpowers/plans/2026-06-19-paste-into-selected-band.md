# Paste into selected band — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a band is explicitly selected and every clipboard object comes from a single source band, paste all objects into the selected band; otherwise keep today's per-source-band paste.

**Architecture:** The paste pipeline already routes each copy purely off its `ClipboardEntry.bandId` (`ClipboardCommand.updateBand`). So the whole feature is: (1) a private `_pasteTargetBand()` resolver in the controller that returns the selected band id when the trigger holds, else `null`; (2) an optional `targetBandId` parameter on `_buildCopies` that overrides each copy's destination band and clamps bounds to that band; (3) wiring `paste()` to pass the resolved target. No new command, no change to clipboard storage, copy/cut, or undo.

**Tech Stack:** Dart / Flutter, package `jet_print`. Tests via `flutter test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-19-paste-into-selected-band-design.md`.
- Paste offset constant is `kPasteOffset = JetOffset(8, 8)` (`designer/canvas/design_tunables.dart`).
- Geometry types: `JetRect(x, y, width, height)`, `JetOffset(dx, dy)` — both already imported in the controller.
- `duplicate()` MUST remain unchanged in behavior (always per-source-band).
- Run the full package suite before claiming done: `flutter test` from `packages/jet_print`. Goldens must be unchanged (this is designer-controller-only; no render path touched).
- Run `git` commands from the repo root `/Users/ahmeturel/Projects/oss/jet-print` (flutter leaves cwd inside the package).

---

### Task 1: Redirect paste into the selected band

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` — `paste()` (~line 1175) and `_buildCopies` (~line 1220); add private `_pasteTargetBand()`.
- Create: `packages/jet_print/test/designer/controller/paste_into_selected_band_test.dart`

**Interfaces:**
- Consumes (existing, unchanged signatures):
  - `typedef ClipboardEntry = ({String bandId, ReportElement element});`
  - `Clipboard get _clipboard` with `bool get isEmpty` and `List<ClipboardEntry> get entries`.
  - `Selection get selection` (and `_document.selection`) exposing `String? get bandId`.
  - `Band? findBand(ReportDefinition def, String bandId)`.
  - `void selectBand(String bandId)` — sets `Selection.band(bandId)`, exclusive with element selection; unknown id ignored.
  - `JetRect clampToBand(JetRect bounds, Band band, PageFormat page)`.
  - `ReportElement cloneElement(ReportElement source, {required String id, required JetRect bounds})`.
  - `const JetOffset kPasteOffset` (= (8, 8)).
- Produces (private; nothing else depends on these): new method `String? _pasteTargetBand()`; new optional parameter `_buildCopies(List<ClipboardEntry> source, {String? targetBandId})`.

- [ ] **Step 1: Write the failing tests**

Create `packages/jet_print/test/designer/controller/paste_into_selected_band_test.dart`:

```dart
// Paste-into-selected-band redirect (single-source clipboard + band selected).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

// Two-band fixture: a 'header' band (one element) and a 'detail' band (two).
ReportDefinition _fixture() => const ReportDefinition(
      name: 'F',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'header',
              type: BandType.detail,
              height: 300,
              elements: <ReportElement>[
                TextElement(
                    id: 'h1',
                    bounds: JetRect(x: 10, y: 10, width: 20, height: 10),
                    text: 'h1'),
              ],
            )),
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 300,
              elements: <ReportElement>[
                TextElement(
                    id: 'd1',
                    bounds: JetRect(x: 50, y: 60, width: 20, height: 10),
                    text: 'd1'),
                TextElement(
                    id: 'd2',
                    bounds: JetRect(x: 80, y: 90, width: 20, height: 10),
                    text: 'd2'),
              ],
            )),
          ],
        ),
      ),
    );

Band _band(JetReportDesignerController c, String id) => c.definition.body.root
    .children
    .whereType<BandNode>()
    .firstWhere((BandNode n) => n.band.id == id)
    .band;

JetReportDesignerController _open() =>
    JetReportDesignerController()..open(_fixture());

void main() {
  test('single-source clipboard + foreign band selected pastes into that band '
      'at original X/Y', () {
    final JetReportDesignerController c = _open()..select('d1');
    c.copy();
    c.selectBand('header');
    c.paste();

    // Copy lands in the selected (header) band, not back in detail.
    expect(_band(c, 'header').elements.length, 2);
    expect(_band(c, 'detail').elements.length, 2);

    final String newId = c.selection.singleOrNull!;
    final ReportElement pasted = _band(c, 'header')
        .elements
        .firstWhere((ReportElement e) => e.id == newId);
    // Original X/Y preserved (no +8/+8 across bands).
    expect(pasted.bounds.x, 50);
    expect(pasted.bounds.y, 60);
    c.dispose();
  });

  test('multi-element single-source clipboard all land in the selected band',
      () {
    final JetReportDesignerController c = _open()
      ..select('d1')
      ..addToSelection('d2');
    c.copy();
    c.selectBand('header');
    c.paste();

    expect(_band(c, 'header').elements.length, 3); // h1 + two copies
    expect(_band(c, 'detail').elements.length, 2); // originals untouched
    expect(c.selection.length, 2); // the two copies are selected
    c.dispose();
  });

  test('same band selected keeps the +8/+8 offset', () {
    final JetReportDesignerController c = _open()..select('d1');
    c.copy();
    c.selectBand('detail'); // selected == source band
    c.paste();

    expect(_band(c, 'detail').elements.length, 3);
    final String newId = c.selection.singleOrNull!;
    final ReportElement pasted = _band(c, 'detail')
        .elements
        .firstWhere((ReportElement e) => e.id == newId);
    expect(pasted.bounds.x, 58); // 50 + 8
    expect(pasted.bounds.y, 68); // 60 + 8
    c.dispose();
  });

  test('no band selected keeps per-source-band paste (+8/+8 in source band)',
      () {
    final JetReportDesignerController c = _open()..select('d1');
    c.copy();
    c.clearSelection();
    c.paste();

    expect(_band(c, 'detail').elements.length, 3); // back in source band
    expect(_band(c, 'header').elements.length, 1); // unchanged
    c.dispose();
  });

  test('multi-source clipboard + band selected keeps per-source-band paste',
      () {
    final JetReportDesignerController c = _open()
      ..select('h1')
      ..addToSelection('d1');
    c.copy();
    c.selectBand('detail'); // a band IS selected, but clipboard spans 2 bands
    c.paste();

    // Each copy returns to its own source band, not the selected one.
    expect(_band(c, 'header').elements.length, 2); // h1 + its copy
    expect(_band(c, 'detail').elements.length, 3); // d1, d2 + d1's copy
    c.dispose();
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/designer/controller/paste_into_selected_band_test.dart`
Expected: the "foreign band selected" / "multi-element" / "multi-source" tests FAIL (copies still land in the source band, original X/Y not honored) because the redirect does not exist yet. The "same band" and "no band selected" tests may already pass.

- [ ] **Step 3: Add the target-band resolver and parameterize `_buildCopies`**

In `jet_report_designer_controller.dart`, change `paste()` (currently):

```dart
  void paste() {
    if (_clipboard.isEmpty) return;
    final List<ClipboardEntry> copies = _buildCopies(_clipboard.entries);
    if (copies.isNotEmpty) _commit(ClipboardCommand(copies));
  }
```

to:

```dart
  void paste() {
    if (_clipboard.isEmpty) return;
    final List<ClipboardEntry> copies =
        _buildCopies(_clipboard.entries, targetBandId: _pasteTargetBand());
    if (copies.isNotEmpty) _commit(ClipboardCommand(copies));
  }

  /// The band to paste into, or `null` to keep per-source-band paste.
  ///
  /// Returns the explicitly selected band's id only when a band is selected,
  /// that band still exists, and every clipboard entry shares one source band.
  String? _pasteTargetBand() {
    final String? selected = _document.selection.bandId;
    if (selected == null) return null;
    if (findBand(_document.definition, selected) == null) return null;
    final Iterable<String> sources =
        _clipboard.entries.map((ClipboardEntry e) => e.bandId);
    final String first = sources.first;
    if (sources.every((String b) => b == first)) return selected;
    return null;
  }
```

Then change `_buildCopies` (currently):

```dart
  List<ClipboardEntry> _buildCopies(List<ClipboardEntry> source) {
    final PageFormat page = _document.definition.page;
    final List<ClipboardEntry> copies = <ClipboardEntry>[];
    for (final ClipboardEntry entry in source) {
      final Band? band = findBand(_document.definition, entry.bandId);
      if (band == null) continue;
      final String id = _ids.next(entry.element.typeKey);
      final JetRect b = entry.element.bounds;
      final JetRect offset = clampToBand(
        JetRect(
            x: b.x + kPasteOffset.dx,
            y: b.y + kPasteOffset.dy,
            width: b.width,
            height: b.height),
        band,
        page,
      );
      copies.add((
        bandId: entry.bandId,
        element: cloneElement(entry.element, id: id, bounds: offset),
      ));
    }
    return copies;
  }
```

to:

```dart
  List<ClipboardEntry> _buildCopies(List<ClipboardEntry> source,
      {String? targetBandId}) {
    final PageFormat page = _document.definition.page;
    final List<ClipboardEntry> copies = <ClipboardEntry>[];
    for (final ClipboardEntry entry in source) {
      final String destBandId = targetBandId ?? entry.bandId;
      final Band? band = findBand(_document.definition, destBandId);
      if (band == null) continue;
      final String id = _ids.next(entry.element.typeKey);
      final JetRect b = entry.element.bounds;
      // Nudge by +8/+8 only when the copy stays in its own band; across bands
      // keep the original X/Y so it lands where the user expects.
      final JetOffset nudge =
          destBandId == entry.bandId ? kPasteOffset : const JetOffset(0, 0);
      final JetRect placed = clampToBand(
        JetRect(
            x: b.x + nudge.dx,
            y: b.y + nudge.dy,
            width: b.width,
            height: b.height),
        band,
        page,
      );
      copies.add((
        bandId: destBandId,
        element: cloneElement(entry.element, id: id, bounds: placed),
      ));
    }
    return copies;
  }
```

`duplicate()` already calls `_buildCopies(_collectSelected())` with no `targetBandId`, so it is unaffected — leave it as-is.

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/controller/paste_into_selected_band_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 5: Run the existing clipboard/bulk tests to verify no regression**

Run: `cd packages/jet_print && flutter test test/designer/controller/bulk_commands_test.dart test/designer/controller/clipboard_reactivity_test.dart test/designer/canvas/context_menu_test.dart`
Expected: PASS (existing copy/paste/duplicate/cut behavior unchanged).

- [ ] **Step 6: Run the full package suite**

Run: `cd packages/jet_print && flutter test`
Expected: all green, 0 golden diffs.

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart \
        packages/jet_print/test/designer/controller/paste_into_selected_band_test.dart
git commit -m "feat(designer): paste single-source clipboard into the selected band"
```

---

## Self-Review

**Spec coverage:**
- Trigger condition (band selected + exists + single-source clipboard) → `_pasteTargetBand()` (Step 3); tested by foreign-band, multi-source, no-band-selected, same-band tests.
- Positioning: original X/Y across bands; +8/+8 same band → `nudge` ternary in `_buildCopies`; tested by "foreign band ... original X/Y" and "same band ... +8/+8".
- Multi-band / no-band-selected / empty-clipboard unchanged → `targetBandId == null` path (empty clipboard already short-circuits in `paste()`); tested by the two "keeps per-source-band paste" tests.
- Missing selected band id → `findBand(...) == null` guard returns `null` (covered by the resolver; selectBand already rejects unknown ids, so the guard is defense-in-depth).
- `duplicate()` unchanged → explicitly left calling `_buildCopies` with no `targetBandId`.
- Scope = `paste()` only (covers shortcut + toolbar/menu, both call `paste()`).

**Placeholder scan:** none — all steps contain full code and exact commands.

**Type consistency:** `_buildCopies(List<ClipboardEntry>, {String? targetBandId})`, `_pasteTargetBand() -> String?`, `ClipboardEntry.(bandId, element)`, `JetOffset.(dx, dy)`, `JetRect.(x, y, width, height)` used consistently across the task and tests.
