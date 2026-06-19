# Image-placeholder Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render a centered picture-frame glyph (frame + mountain + sun) instead of the text "image" when an `ImageElement` has no resolvable bytes, on the design canvas and in exported PDF/PNG.

**Architecture:** Add one engine helper, `emitImagePlaceholder`, that composes the glyph from the existing primitive vocabulary (`RectPrimitive` + `PathPrimitive`), and switch the source-less branch of `ImageElementRenderer` to call it. The shared text `emitPlaceholder` (used by barcode/unknown) is untouched, so the visual change is scoped to image elements. No new primitive type, no backend change, no public-API change.

**Tech Stack:** Dart, `package:jet_print` engine, `flutter_test`, golden image tests (`--update-goldens`).

## Global Constraints

- Engine-only change under `packages/jet_print`. No public-API change, no new exports, no serialization change, no new primitive type.
- Glyph color is the existing placeholder grey `JetColor(0xFF999999)` (`_placeholderColor` in `placeholder.dart`).
- Icon size: `side = (min(bounds.width, bounds.height) * 0.55).clamp(0.0, 28.0)`; if `side < 8.0`, emit only the full-bounds outline rect (no glyph).
- The full-bounds element outline `RectPrimitive` is **retained** (unchanged affordance); only the text label is replaced.
- `emitPlaceholder` (text) and the barcode/unknown placeholders are **not** modified.
- Only goldens that rasterize a **source-less** image element may change; barcode/unknown/text goldens, the `JetPrintPlaceholder` designer-widget golden, and `BytesImageSource` goldens must stay byte-identical.
- Run `flutter` from `packages/jet_print`; run `git` from the repo root (`/Users/ahmeturel/Projects/oss/jet-print`) — `flutter` leaves the cwd inside the package.
- Work on branch `image-placeholder-icon` (already created off `main`, holds the design doc).

---

### Task 1: `emitImagePlaceholder` helper + unit test

A pure, focused helper that emits the glyph primitives. It is added but not yet wired (Task 2 switches the renderer), so the full suite stays green at this commit.

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/elements/placeholder.dart`
- Test: `packages/jet_print/test/rendering/elements/image_placeholder_test.dart`

**Interfaces:**
- Consumes: `FrameBuilder.add`, `RectPrimitive`, `PathPrimitive`, `MoveTo`/`LineTo`/`ClosePath`, `JetOffset(dx, dy)`, `JetRect(x:,y:,width:,height:)`, `JetColor`, and the file-private `_placeholderColor` (`JetColor(0xFF999999)`) already defined in `placeholder.dart`.
- Produces: `void emitImagePlaceholder(FrameBuilder out, JetRect bounds, {String? elementId})` — appends a full-bounds outline `RectPrimitive`, and (when `side >= 8`) a frame `RectPrimitive`, a filled-octagon "sun" `PathPrimitive`, and a filled-triangle "mountain" `PathPrimitive`, all tagged with `elementId`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/rendering/elements/image_placeholder_test.dart`:

```dart
// emitImagePlaceholder: an image-glyph (frame + mountain + sun) for the
// source-less image placeholder — no text label.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/placeholder.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

void main() {
  const JetColor grey = JetColor(0xFF999999);

  test('normal box: outline + frame rects and sun + mountain paths, no text',
      () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    emitImagePlaceholder(
        out, const JetRect(x: 0, y: 0, width: 50, height: 40),
        elementId: 'img1');
    final List<FramePrimitive> prims = out.build().primitives;

    // No text label any more.
    expect(prims.whereType<TextRunPrimitive>(), isEmpty);

    final List<RectPrimitive> rects = prims.whereType<RectPrimitive>().toList();
    final List<PathPrimitive> paths = prims.whereType<PathPrimitive>().toList();
    expect(rects, hasLength(2)); // full-bounds outline + glyph frame
    expect(paths, hasLength(2)); // sun + mountain

    // Everything is tagged with the element id.
    for (final FramePrimitive p in prims) {
      expect(p.elementId, 'img1');
    }

    // Outline covers the full element bounds, stroke-only, grey.
    final RectPrimitive outline = rects[0];
    expect(outline.bounds, const JetRect(x: 0, y: 0, width: 50, height: 40));
    expect(outline.stroke, grey);
    expect(outline.fill, isNull);

    // Glyph frame is a centered square sized by `side = min(50,40)*0.55 = 22`.
    final RectPrimitive frame = rects[1];
    expect(frame.bounds.width, closeTo(22, 0.001));
    expect(frame.bounds.height, closeTo(22, 0.001));
    expect(frame.bounds.x + frame.bounds.width / 2, closeTo(25, 0.001));
    expect(frame.bounds.y + frame.bounds.height / 2, closeTo(20, 0.001));
    expect(frame.stroke, grey);

    // Sun + mountain are filled grey.
    for (final PathPrimitive p in paths) {
      expect(p.fill, grey);
    }
  });

  test('tiny box (side < 8): only the full-bounds outline is emitted', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    emitImagePlaceholder(
        out, const JetRect(x: 1, y: 1, width: 6, height: 6),
        elementId: 'i');
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims, hasLength(1));
    expect(prims.single, isA<RectPrimitive>());
    expect(prims.single.bounds, const JetRect(x: 1, y: 1, width: 6, height: 6));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/rendering/elements/image_placeholder_test.dart`
Expected: FAIL — `emitImagePlaceholder` is not defined (compile error).

- [ ] **Step 3: Write minimal implementation**

In `packages/jet_print/lib/src/rendering/elements/placeholder.dart`, add `import 'dart:math' as math;` at the top of the imports, and append this function at the end of the file (after `emitPlaceholder`):

```dart
/// Appends an image-glyph placeholder over [bounds]: the full-bounds outline
/// [RectPrimitive] (the element's extent), plus — when the element is large
/// enough to be legible — a centered picture-frame glyph (frame rect + a filled
/// "mountain" triangle + a small filled "sun" octagon), all in [_placeholderColor]
/// and tagged with [elementId].
///
/// Used for the source-less image case (designer canvas, unresolved field, or
/// URL — the library does no network I/O), in place of the text [emitPlaceholder].
/// Composed from existing primitives so it paints identically on canvas and PDF.
void emitImagePlaceholder(
  FrameBuilder out,
  JetRect bounds, {
  String? elementId,
}) {
  // Full-bounds element outline — the same affordance the text placeholder gave.
  out.add(RectPrimitive(
    bounds: bounds,
    stroke: _placeholderColor,
    elementId: elementId,
  ));

  final double side =
      (math.min(bounds.width, bounds.height) * 0.55).clamp(0.0, 28.0);
  if (side < 8.0) return; // too small for a legible glyph

  final double cx = bounds.x + bounds.width / 2;
  final double cy = bounds.y + bounds.height / 2;
  final double left = cx - side / 2;
  final double top = cy - side / 2;
  final double right = cx + side / 2;
  final double bottom = cy + side / 2;
  final JetRect square =
      JetRect(x: left, y: top, width: side, height: side);

  // Picture frame.
  out.add(RectPrimitive(
    bounds: square,
    stroke: _placeholderColor,
    elementId: elementId,
  ));

  // Sun: a small filled octagon in the upper-left quadrant (the primitive set
  // has no circle, so approximate with an 8-gon).
  final double sunR = side * 0.12;
  final double sunCx = left + side * 0.30;
  final double sunCy = top + side * 0.30;
  final List<PathCommand> sun = <PathCommand>[];
  for (int i = 0; i < 8; i++) {
    final double a = i * math.pi / 4;
    final JetOffset p =
        JetOffset(sunCx + sunR * math.cos(a), sunCy + sunR * math.sin(a));
    sun.add(i == 0 ? MoveTo(p) : LineTo(p));
  }
  sun.add(const ClosePath());
  out.add(PathPrimitive(
    bounds: square,
    commands: sun,
    fill: _placeholderColor,
    elementId: elementId,
  ));

  // Mountain: a filled triangle resting on the frame's lower edge.
  out.add(PathPrimitive(
    bounds: square,
    commands: <PathCommand>[
      MoveTo(JetOffset(left + side * 0.15, bottom - side * 0.15)),
      LineTo(JetOffset(left + side * 0.55, top + side * 0.45)),
      LineTo(JetOffset(right - side * 0.15, bottom - side * 0.15)),
      const ClosePath(),
    ],
    fill: _placeholderColor,
    elementId: elementId,
  ));
}
```

Note: `placeholder.dart` already imports `geometry.dart` (for `JetRect`), `color.dart`, `frame_builder.dart`, and `primitive.dart` (for `RectPrimitive`) — `PathPrimitive`, `PathCommand`, `MoveTo`, `LineTo`, `ClosePath`, and `JetOffset` come from those same files, so the only new import is `dart:math`.

- [ ] **Step 4: Run test to verify it passes**

Run (from `packages/jet_print`): `flutter test test/rendering/elements/image_placeholder_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Verify the helper did not disturb the existing text placeholder**

Run (from `packages/jet_print`): `flutter test test/rendering/elements/placeholder_test.dart`
Expected: PASS (the text `emitPlaceholder` is unchanged).

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/elements/placeholder.dart \
        packages/jet_print/test/rendering/elements/image_placeholder_test.dart
git commit -m "feat(rendering): add emitImagePlaceholder image-glyph helper"
```

---

### Task 2: Wire the renderer to the glyph + regenerate affected goldens

Switch the source-less image branch to the new glyph, update its unit assertions, and regenerate exactly the goldens that rasterize a source-less image.

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/elements/renderers/image_element_renderer.dart`
- Modify (test): `packages/jet_print/test/rendering/elements/image_element_renderer_test.dart`
- Regenerate (goldens): the export golden(s) that render the `export_fixtures.dart` invoice (its logo uses `UrlImageSource`) — identified empirically below.

**Interfaces:**
- Consumes: `emitImagePlaceholder(out, bounds, elementId:)` from Task 1.

- [ ] **Step 1: Update the renderer's two source-less unit tests (failing first)**

In `packages/jet_print/test/rendering/elements/image_element_renderer_test.dart`, replace the two placeholder tests (the `UrlImageSource` test at ~line 45 and the `FieldImageSource` test at ~line 55) with:

```dart
  test('a url source (unresolved) emits an image-glyph placeholder', () {
    const ImageElement el = ImageElement(
        id: 'i', bounds: bounds, source: UrlImageSource('https://x/y.png'));
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    // Outline rect first, glyph paths present, and no text label.
    expect(prims.first, isA<RectPrimitive>());
    expect(prims.whereType<PathPrimitive>(), isNotEmpty);
    expect(prims.whereType<TextRunPrimitive>(), isEmpty);
  });

  test('a field source (unresolved) also emits an image-glyph placeholder', () {
    // FieldImageSource is a distinct source kind; the placeholder branch must
    // cover it too, not just UrlImageSource.
    const ImageElement el = ImageElement(
        id: 'i', bounds: bounds, source: FieldImageSource('photo'));
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims.first, isA<RectPrimitive>());
    expect(prims.whereType<PathPrimitive>(), isNotEmpty);
    expect(prims.whereType<TextRunPrimitive>(), isEmpty);
  });
```

(`bounds` is the file's existing `JetRect(x: 0, y: 0, width: 50, height: 40)`, so `side = 22` and the glyph is emitted.)

- [ ] **Step 2: Run the renderer test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/rendering/elements/image_element_renderer_test.dart`
Expected: FAIL — the renderer still calls the text `emitPlaceholder`, so a `TextRunPrimitive('image')` is emitted and `whereType<TextRunPrimitive>()` is not empty (and `PathPrimitive` is empty).

- [ ] **Step 3: Switch the renderer to the glyph**

In `packages/jet_print/lib/src/rendering/elements/renderers/image_element_renderer.dart`, change the `else` branch of `emit`:

```dart
    } else {
      emitPlaceholder(out, bounds, 'image', ctx, elementId: el.id);
    }
```

to:

```dart
    } else {
      emitImagePlaceholder(out, bounds, elementId: el.id);
    }
```

`emitImagePlaceholder` is exported from the same `placeholder.dart` the renderer already imports (`import '../placeholder.dart';`), so no import change is needed. The `ctx` parameter remains used elsewhere in `emit` (the `BytesImageSource` branch and `measure`), so leave the method signature as-is.

- [ ] **Step 4: Run the renderer + helper unit tests**

Run (from `packages/jet_print`):
`flutter test test/rendering/elements/image_element_renderer_test.dart test/rendering/elements/image_placeholder_test.dart`
Expected: PASS (both files).

- [ ] **Step 5: Run the full package suite to find the goldens that changed**

Run (from `packages/jet_print`): `flutter test`
Expected: PASS everywhere **except** golden tests that rasterize a source-less image element. The anticipated failing golden(s) are the export goldens that render the `export_fixtures.dart` invoice — whose logo is `UrlImageSource('https://example.com/logo.png')` (`test/rendering/export/support/export_fixtures.dart:303`). Likely: `test/rendering/export/png_export_test.dart` (golden PNG) and any export test pinning the rendered invoice's pixels/bytes.

Record the exact list of failing golden tests from the output.

**Guard — STOP and investigate (do not regenerate) if any of these fail**, because their fixtures contain NO source-less image:
- `test/goldens/rendered_invoice_test.dart` (preview invoice — text/shape only)
- `test/goldens/label_sheet_test.dart`, `test/goldens/formatted_value_test.dart`
- any `test/designer/goldens/*` (designer surfaces — no source-less image)
- `test/jet_print_placeholder_test.dart` (unrelated `JetPrintPlaceholder` widget)
- `test/designer/goldens/barcode_symbologies_golden_test.dart` (barcode, not image)

If a guard golden fails, the change leaked beyond image placeholders — stop and report, do not `--update-goldens`.

- [ ] **Step 6: Regenerate only the affected goldens and eyeball them**

For the failing golden test files identified in Step 5 (expected: the export PNG golden(s)), regenerate:

Run (from `packages/jet_print`, substituting the actual failing paths):
`flutter test --update-goldens test/rendering/export/png_export_test.dart`

Then open each regenerated golden PNG under `packages/jet_print/test/goldens/` (or the test's golden directory) and confirm the image element now shows the picture-frame glyph (frame + mountain + sun) rather than the word "image", and nothing else changed.

- [ ] **Step 7: Run the full suite again to confirm green**

Run (from `packages/jet_print`): `flutter test`
Expected: all tests pass.

- [ ] **Step 8: Analyze**

Run (from `packages/jet_print`): `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 9: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/elements/renderers/image_element_renderer.dart \
        packages/jet_print/test/rendering/elements/image_element_renderer_test.dart \
        packages/jet_print/test/
git commit -m "feat(rendering): render image-glyph placeholder for source-less images

Source-less ImageElements (designer canvas, unresolved field, URL) now show a
centered picture-frame glyph instead of the text 'image'. Regenerates the
export golden(s) whose fixture uses a URL image source. Barcode/unknown/text
placeholders are unchanged."
```

(The `git add packages/jet_print/test/` line stages the regenerated golden PNGs alongside the test edits.)

---

## Self-Review

**Spec coverage:**
- "Replace text with a centered picture-frame glyph" → Task 1 (`emitImagePlaceholder`) + Task 2 (renderer switch).
- "Frame + mountain + sun, octagon approximates the circle" → Task 1 implementation.
- "Icon size `min*0.55` clamped to 28; `<8` → outline only" → Task 1 code + both unit tests.
- "Retain full-bounds outline" → Task 1 (first `RectPrimitive`) + test asserting outline bounds.
- "`emitPlaceholder` untouched; barcode/unknown unchanged" → Task 1 Step 5 guard + Task 2 Step 5 guards.
- "Update the two renderer assertions" → Task 2 Step 1.
- "Regenerate only source-less-image goldens; guards byte-identical" → Task 2 Steps 5–7.
- "flutter analyze clean; suite green" → Task 2 Steps 7–8.

**Placeholder scan:** No TBD/TODO. The golden list in Task 2 is empirical-with-expectation (run suite → failing set is the affected set), with an explicit guard list of goldens that must NOT change — this is deliberate, not a vague requirement.

**Type consistency:** `emitImagePlaceholder(FrameBuilder, JetRect, {String? elementId})` is defined in Task 1 and called identically in Task 2. `_placeholderColor` (grey `0xFF999999`) reused from `placeholder.dart`. Primitive types (`RectPrimitive`, `PathPrimitive`, `MoveTo`/`LineTo`/`ClosePath`, `JetOffset`, `JetRect`) match the verified `primitive.dart`/`geometry.dart` signatures.
