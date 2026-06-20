# Band-Bounded Selection Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep a selected element's chrome — the selection outline and its eight resize handles — fully inside the element's band at all times: idle, during a live move, and during a resize.

**Architecture:** Two focused changes to the live selection overlay, no model/engine touch. (1) Wire `DesignerSelectionOverlay` to the canvas's existing **display layout** (built from `controller.displayDefinition`, which already routes every in-progress move/resize/band-resize through the single `clampToBand` authority) instead of the committed layout + a raw drag delta — so the chrome derives from the same clamped geometry the element body is painted from. (2) Clamp each resize-handle box to its element's band rect so an edge handle on a flush element never pokes past the band border.

**Tech Stack:** Dart / Flutter; package `jet_print` (run all commands from `packages/jet_print/`). Widget tests via `flutter_test`. Geometry types from `domain/geometry.dart` (`JetRect`, `JetOffset`). No new dependencies.

## Global Constraints

- **No engine/model/serialization change.** Do not modify `clampToBand`, the controller's move/resize/band-resize state machine, the commit commands (`MoveCommand` / `ResizeCommand` / `SetBandHeightCommand` / `CreateElementCommand`), the domain model, serialization, or `validate()`. (spec Out of scope; FR-007)
- **Goldens must stay byte-identical.** The only selection golden (`test/designer/goldens/design_surface_test.dart`) selects a text element at `(24, 24)` — clear of all band edges — so neither change moves its handles. (SC-005)
- **Single clamp authority.** Containment is already guaranteed by `clampToBand` via the display layout; do NOT re-implement element clamping in the overlay. The only new clamp is the handle-*box* clamp (a rendering concern), which targets the band rect, not the element bounds. (spec Clarifications)
- **Test seam is stable widget keys** from `package:jet_print/jet_print.dart` only (the harness is an external-consumer stand-in; never import `package:jet_print/src/...`). Handles: `jet_print.designer.handle.<position>`. Element regions: `jet_print.designer.element.<id>`.
- **Tolerances:** on-screen geometry assertions use a small slop (`1.0`–`0.5` logical px) to absorb sub-pixel rounding.

---

## File Structure

- **Modify** `lib/src/designer/canvas/design_canvas.dart` (1 line + comment) — pass `displayLayout` (not `layout`) to `DesignerSelectionOverlay`.
- **Modify** `lib/src/designer/canvas/selection_overlay.dart`:
  - `build()` / `rectFor` — derive chrome geometry straight from `widget.layout.elementRect(id)`; drop the raw-`moveDelta` addition and the resize `previewBoundsFor` band-local conversion.
  - `_handle()` — clamp the handle box to the element's band rect (resolved via `widget.layout.bandOfElement(id)` → `widget.layout.bandRect(bandId)`).
  - Add one top-level private helper `_clampAxis`.
- **Create** `test/designer/canvas/band_bounded_chrome_test.dart` — the three new widget tests (one for drift, two for protrusion).

No file is restructured; both source files are existing and focused. The new tests live beside the other canvas interaction tests (`place_select_move_test.dart`, `resize_clamp_teardown_test.dart`).

---

## Task 1: Selection chrome tracks the clamped element during a live move

Fixes the drift (spec issue 1 / FR-001, FR-002, FR-003): the overlay currently reads the committed `layout` and re-adds the raw drag delta, so during a clamped move the outline + handles slide past the band while the element body stops at the edge. Wiring the overlay to the display layout makes the chrome derive from the same clamped geometry as the painted element.

**Files:**
- Test: `test/designer/canvas/band_bounded_chrome_test.dart` (create)
- Modify: `lib/src/designer/canvas/design_canvas.dart` (~line 1147)
- Modify: `lib/src/designer/canvas/selection_overlay.dart` (~lines 104, 119–141)

**Interfaces:**
- Consumes (existing, unchanged): `DesignTimeLayout.elementRect(String id) -> JetRect?`; the canvas-local `displayLayout` (a `DesignTimeLayout` built from `controller.displayDefinition`); `JetReportDesignerController.createElement(DesignerToolType, {required String bandId, required JetOffset at})` (clamps + auto-selects the new element); `JetReportDesignerController.selection.singleOrNull -> String?`; harness `pumpDesignerWith`, `firstDetailBandId`.
- Produces: no new public API. After this task the overlay's `rectFor(id)` returns `widget.layout.elementRect(id)` and the overlay is fed the display layout.

- [ ] **Step 1: Write the failing test**

Create `test/designer/canvas/band_bounded_chrome_test.dart`:

```dart
// Spec 038: a selected element's chrome (outline + handles) must stay inside its
// band — during a clamped live move (this file's first test) and at rest when the
// element is flush against a band edge (Task 2's tests).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));
final Finder _topLeftHandle =
    find.byKey(const ValueKey<String>('jet_print.designer.handle.topLeft'));
final Finder _bottomRightHandle =
    find.byKey(const ValueKey<String>('jet_print.designer.handle.bottomRight'));

void main() {
  testWidgets(
      'live move clamped at a band edge keeps the chrome glued to the element',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    // Mid-band element (clear of the left/top edges) so its top-left handle is a
    // clean probe, unaffected by Task 2's edge clamp.
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(60, 40));
    await tester.pumpAndSettle();
    final String id = c.selection.singleOrNull!;

    // Drag the element far past the band's RIGHT edge and HOLD (no release), so
    // the model clamps it at the boundary mid-drag.
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(_elementFinder(id)));
    for (int i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
    }

    // The painted element (drawn from the clamped display layout) and the chrome
    // must coincide. The top-left handle is clear of every band edge, so it is a
    // faithful "does the chrome track the element?" probe.
    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect tl = tester.getRect(_topLeftHandle);
    expect(tl.center.dx, closeTo(elem.left, 1.0), reason: 'chrome tracks element x');
    expect(tl.center.dy, closeTo(elem.top, 1.0), reason: 'chrome tracks element y');

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/designer/canvas/band_bounded_chrome_test.dart`
Expected: FAIL. The held drag pushes the element ~hundreds of points right; the committed-layout overlay places the top-left handle far to the right of the clamped element (`tl.center.dx` ≫ `elem.left`), so the `closeTo(elem.left, 1.0)` assertion fails.

- [ ] **Step 3: Wire the overlay to the display layout (canvas)**

In `lib/src/designer/canvas/design_canvas.dart`, find the selection-chrome block (~line 1144):

```dart
                  // Selection chrome (outline + handles), on top.
                  Positioned.fill(
                    child:
                        DesignerSelectionOverlay(layout: layout, scale: scale),
                  ),
```

Replace with:

```dart
                  // Selection chrome (outline + handles), on top. Fed the DISPLAY
                  // layout so the outline + handles ride the same clamped geometry
                  // as the element picture during a live move/resize (spec 038).
                  Positioned.fill(
                    child: DesignerSelectionOverlay(
                        layout: displayLayout, scale: scale),
                  ),
```

- [ ] **Step 4: Simplify the overlay geometry (remove raw-delta + preview branches)**

In `lib/src/designer/canvas/selection_overlay.dart`, in `build()`, delete the `move` line (~line 104):

```dart
    final JetOffset move = controller.moveDelta ?? const JetOffset(0, 0);
```

Then replace the entire `rectFor` local function (~lines 119–141):

```dart
    JetRect? rectFor(String id) {
      final JetRect? preview = controller.previewBoundsFor(id);
      if (preview != null) {
        // Resize preview is band-relative; convert to page coords.
        final String? band = controller.activeBandId;
        final JetRect? bandRect =
            band == null ? null : widget.layout.bandRect(band);
        if (bandRect != null) {
          return JetRect(
              x: bandRect.x + preview.x,
              y: bandRect.y + preview.y,
              width: preview.width,
              height: preview.height);
        }
      }
      final JetRect? rect = widget.layout.elementRect(id);
      if (rect == null) return null;
      return JetRect(
          x: rect.x + move.dx,
          y: rect.y + move.dy,
          width: rect.width,
          height: rect.height);
    }
```

with:

```dart
    // Geometry comes straight from the (display) layout, which already bakes any
    // in-progress move / resize / band-resize through the single `clampToBand`
    // authority — so the chrome can never exceed the band (spec 038, FR-002).
    JetRect? rectFor(String id) => widget.layout.elementRect(id);
```

(Leave `controller.moveDelta`, `controller.previewBoundsFor`, and `controller.activeBandId` defined on the controller — they are still used elsewhere, e.g. `_guideWidgets` reads `controller.activeBandId`. Only the overlay's *geometry* path stops using `moveDelta` / `previewBoundsFor`.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/designer/canvas/band_bounded_chrome_test.dart`
Expected: PASS. The overlay now reads the display layout, so the top-left handle sits on the clamped element's top-left corner (`tl.center` ≈ `elem.topLeft`).

- [ ] **Step 6: Guard against regressions in neighboring interaction tests**

Run: `flutter test test/designer/canvas/place_select_move_test.dart test/designer/canvas/resize_clamp_teardown_test.dart`
Expected: PASS (these assert the model + teardown, which are unchanged).

- [ ] **Step 7: Commit**

```bash
git add lib/src/designer/canvas/design_canvas.dart lib/src/designer/canvas/selection_overlay.dart test/designer/canvas/band_bounded_chrome_test.dart
git commit -m "fix(designer): selection chrome tracks the clamped element during a move (038)"
```

---

## Task 2: Clamp resize-handle boxes to the band

> **REVERTED (2026-06-20, post-manual-GUI).** This task's inward handle-box clamp
> shipped, but at a band edge it tucked the edge handles ≈8 px off the outline
> corners, so the selection looked detached/lopsided. Decision reversed: handles
> now **hug the outline** (centered on the element edge/corner, overflowing a flush
> band edge by half a handle — Figma/PowerPoint convention). The clamp + `_clampAxis`
> were removed (commit `d78bae7`); see the spec's 2026-06-20 clarification and the
> rewritten FR-004..006 / SC-002..004. Task 1 (the move-drift fix) stands. The
> description below is retained as the historical record of the original approach.

Fixes the static protrusion (spec issue 2 / FR-004, FR-005, FR-006): handles are centered on the element's edges, so when an element sits flush against a band edge the handle box pokes ~4–8 px past the band border. Clamp each handle box to its element's band rect.

**Files:**
- Test: `test/designer/canvas/band_bounded_chrome_test.dart` (append two tests)
- Modify: `lib/src/designer/canvas/selection_overlay.dart` (`_handle`, ~lines 325–339; add top-level `_clampAxis`)

**Interfaces:**
- Consumes (existing, unchanged): `DesignTimeLayout.bandOfElement(String id) -> String?`; `DesignTimeLayout.bandRect(String bandId) -> JetRect?`; tunable `kHandleHitSize` (16). `CreateElementCommand` clamps a created element into its band (so a huge `at` lands it flush in the bottom-right corner) and auto-selects it.
- Produces: no new public API. `_handle` now positions each handle clamped to the band screen rect; new private `double _clampAxis(double v, double min, double max)`.

- [ ] **Step 1: Write the failing tests**

Append these two tests inside `main()` in `test/designer/canvas/band_bounded_chrome_test.dart`:

```dart
  testWidgets('a flush element top-left handle stays inside the band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    // Flush at the band's top-left: the element's own rect top/left ARE the
    // band's top/left edge, so they are a faithful band-boundary probe.
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(0, 0));
    await tester.pumpAndSettle();

    final String id = c.selection.singleOrNull!;
    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect tl = tester.getRect(_topLeftHandle);
    expect(tl.top, greaterThanOrEqualTo(elem.top - 0.5),
        reason: 'top handle box stays below the band top');
    expect(tl.left, greaterThanOrEqualTo(elem.left - 0.5),
        reason: 'left handle box stays right of the band left');
  });

  testWidgets('a flush element bottom-right handle stays inside the band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    final String bandId = firstDetailBandId(c);
    // A huge offset clamps the element flush into the band's bottom-right corner.
    c.createElement(DesignerToolType.text,
        bandId: bandId, at: const JetOffset(1000000, 1000000));
    await tester.pumpAndSettle();

    final String id = c.selection.singleOrNull!;
    final Rect elem = tester.getRect(_elementFinder(id));
    final Rect br = tester.getRect(_bottomRightHandle);
    expect(br.bottom, lessThanOrEqualTo(elem.bottom + 0.5),
        reason: 'bottom handle box stays above the band bottom');
    expect(br.right, lessThanOrEqualTo(elem.right + 0.5),
        reason: 'right handle box stays left of the band right');
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/designer/canvas/band_bounded_chrome_test.dart`
Expected: the two new tests FAIL. The top-left handle box renders at `elem.top - 8` / `elem.left - 8` (poking above/left of the band); the bottom-right box at `elem.bottom + 8` / `elem.right + 8` (poking below/right). (Task 1's drift test still PASSES.)

- [ ] **Step 3: Clamp the handle box to the band in `_handle`**

In `lib/src/designer/canvas/selection_overlay.dart`, in `_handle`, replace the head of the method (~lines 333–339):

```dart
    final ({double x, double y}) center = _handleCenter(position, pageRect);
    const double hit = kHandleHitSize;
    return Positioned(
      left: center.x * widget.scale - hit / 2,
      top: center.y * widget.scale - hit / 2,
      width: hit,
      height: hit,
```

with:

```dart
    final ({double x, double y}) center = _handleCenter(position, pageRect);
    const double hit = kHandleHitSize;
    final double s = widget.scale;
    // Keep the whole handle box (hit area + chip) inside the element's band, so a
    // handle centered on a flush element's edge never pokes past the band border
    // (spec 038, FR-004). A handle clear of every edge is left untouched.
    final String? bandId = widget.layout.bandOfElement(id);
    final JetRect? band =
        bandId == null ? null : widget.layout.bandRect(bandId);
    double left = center.x * s - hit / 2;
    double top = center.y * s - hit / 2;
    if (band != null) {
      left = _clampAxis(left, band.x * s, (band.x + band.width) * s - hit);
      top = _clampAxis(top, band.y * s, (band.y + band.height) * s - hit);
    }
    return Positioned(
      left: left,
      top: top,
      width: hit,
      height: hit,
```

Then add this top-level private helper at the end of the file (after the closing brace of `_DesignerSelectionOverlayState`):

```dart
/// Clamps [v] into `[min, max]`, pinning to [min] when the range is empty — i.e.
/// when the band is shorter/narrower than a handle box (a degenerate near-minimum
/// band). The far edge may then still overflow because a fixed-size handle box
/// physically cannot fit; the near edge stays anchored to the band (spec 038,
/// FR-006).
double _clampAxis(double v, double min, double max) {
  if (max <= min) return min;
  if (v < min) return min;
  if (v > max) return max;
  return v;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/designer/canvas/band_bounded_chrome_test.dart`
Expected: all three tests PASS — the flush handles are clamped inside the band, and Task 1's drift test still holds (its top-left probe is mid-band, so the clamp leaves it untouched).

- [ ] **Step 5: Commit**

```bash
git add lib/src/designer/canvas/selection_overlay.dart test/designer/canvas/band_bounded_chrome_test.dart
git commit -m "fix(designer): clamp resize handles inside their band on flush elements (038)"
```

---

## Task 3: Full verification

Confirms no regression across the package and that goldens are byte-identical (SC-005). No code change unless a failure surfaces.

**Files:** none (verification only).

- [ ] **Step 1: Run the full package test suite**

Run: `flutter test`
Expected: PASS (all existing tests + the three new ones). If a golden test fails, inspect the diff: the only expected-zero-diff selection golden is `design_surface_test.dart` (selected element at `(24,24)`, clear of edges). A diff there would mean the clamp is firing on a non-flush handle — investigate rather than re-baseline.

- [ ] **Step 2: Run the analyzer**

Run: `flutter analyze`
Expected: "No issues found!" In particular, confirm no "unused" warning crept in from removing the `move` local / preview branch in the overlay.

- [ ] **Step 3: Manual GUI confirmation (smoke)**

Run the playground designer, select an element, drag it hard against each band edge, and resize it past each edge. Confirm the blue outline and all handles stay inside the band the whole time, and that an element placed flush against a band edge shows handles tucked just inside the border (not poking across it). (This is a manual check; no automated step.)

---

## Self-Review

**Spec coverage:**
- FR-001 (overlay fed display layout) → Task 1, Step 3.
- FR-002 (rectFor reads display layout; drop raw delta + preview branch) → Task 1, Step 4.
- FR-003 (outline coincides with element during clamped move) → Task 1 test (Step 1) asserts handle tracks the element rect.
- FR-004 (handle box clamped to band) → Task 2, Step 3.
- FR-005 (band rect resolved from the layout) → Task 2, Step 3 uses `widget.layout.bandOfElement` / `bandRect`.
- FR-006 (clamp shifts inward, never clips; degenerate-band note) → Task 2 `_clampAxis` + doc comment; preserves the fixed `hit`×`hit` box.
- FR-007 (no model/engine/command change) → Global Constraints; only `design_canvas.dart` + `selection_overlay.dart` touched.
- SC-001/SC-002 → Task 1 test (chrome tracks clamped element). SC-003 → Task 2 tests (top-left + bottom-right flush). SC-004 → existing `resize_clamp_teardown_test.dart` re-run in Task 1 Step 6 + full suite. SC-005 → Task 3 Steps 1–2.

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `rectFor(String) -> JetRect?` consistent across tasks; `_clampAxis(double, double, double) -> double`; `bandOfElement(String) -> String?` and `bandRect(String) -> JetRect?` match `DesignTimeLayout`. Handle/element finder keys match the harness conventions (`jet_print.designer.handle.<pos>`, `jet_print.designer.element.<id>`).
