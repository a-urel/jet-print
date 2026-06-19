# Image-placeholder icon — design

**Date:** 2026-06-19
**Status:** Approved (brainstorming) — ready for implementation plan
**Area:** `packages/jet_print` (engine rendering); affects the design canvas and exported PDF/PNG

## Purpose

When an `ImageElement` has no resolvable bytes — on the designer canvas (no live
data row), a `FieldImageSource` whose field is absent, or a `UrlImageSource`
(the library does no network I/O) — the renderer currently draws the element
outline plus the muted text **"image"**. Replace that text with a **centered
picture-frame glyph** so the placeholder reads as an image at a glance, the way
a designer expects an empty image box to look.

This is approach **A** from brainstorming: an image-only glyph composed from the
existing primitive vocabulary, scoped so that barcode and unknown-element
placeholders are untouched.

## Engine facts this design relies on (already built)

- The source-less branch of `ImageElementRenderer.emit`
  (`packages/jet_print/lib/src/rendering/elements/renderers/image_element_renderer.dart`)
  calls the shared `emitPlaceholder(out, bounds, 'image', ctx, elementId: el.id)`.
- `emitPlaceholder` (`rendering/elements/placeholder.dart`) emits a full-bounds
  outline `RectPrimitive` + a measured `TextRunPrimitive` label. It also backs
  the barcode-fallback and unknown-element placeholders — so it must stay as-is.
- The frame primitive vocabulary already includes `RectPrimitive`,
  `LinePrimitive`, and `PathPrimitive` (with `MoveTo` / `LineTo` / `ClosePath`,
  plus optional `fill` and `stroke`). **There is no circle/ellipse primitive** —
  paths are straight-segment only.
- Both paint backends already render all three: `rendering/paint/canvas_painter.dart`
  (live canvas + PNG raster) and `rendering/export/pdf_painter.dart` (PDF export).
  So a glyph built from these primitives is WYSIWYG across screen and PDF with no
  new backend code and no new primitive type.
- The muted placeholder grey is `JetColor(0xFF999999)` (`_placeholderColor` in
  `placeholder.dart`).

## Glyph geometry & scaling

All strokes and fills use the placeholder grey `0xFF999999`. The element's
**full-bounds outline `RectPrimitive` is retained** (unchanged — it shows the
element's extent); only the text label is replaced by a centered glyph.

- **Icon size:** `side = (min(bounds.width, bounds.height) * 0.55).clamp(0, 28)`
  points. The proportion shrinks the glyph in small elements; the 28-pt cap keeps
  it from ballooning in large ones.
- **Legibility floor:** if `side < 8`, emit **only** the element outline (no
  glyph) — too small to render legibly.
- **Glyph = three parts**, laid out inside a centered `side × side` square
  (let `s = side`, square top-left at `(cx - s/2, cy - s/2)` where `(cx, cy)` is
  the bounds center):
  1. **Frame** — a `RectPrimitive` (stroke only) covering the square. The picture
     border.
  2. **Sun** — a small **filled regular octagon** `PathPrimitive`, radius
     `≈ s * 0.12`, centered in the upper-left quadrant of the frame
     (`≈ (square.left + 0.30*s, square.top + 0.30*s)`). Eight `LineTo`s + a
     `ClosePath` approximate the circle the primitive set lacks.
  3. **Mountain** — a **filled triangle** `PathPrimitive`
     (`MoveTo` → `LineTo` → `LineTo` → `ClosePath`) sitting on the frame's lower
     edge: base from `≈ (square.left + 0.15*s, square.bottom - 0.15*s)` to
     `≈ (square.right - 0.15*s, square.bottom - 0.15*s)`, apex near
     `≈ (square.left + 0.55*s, square.top + 0.45*s)`.

(The exact fractional constants are tuning values; the implementation plan fixes
them and the golden is the visual source of truth. The invariant the tests pin is
the *set* of primitives and that the glyph is centered and bounded by `side`.)

## Components & files (engine only)

- **`rendering/elements/placeholder.dart`** — add
  `void emitImagePlaceholder(FrameBuilder out, JetRect bounds, {String? elementId})`.
  It emits the full-bounds outline rect, and — when `side >= 8` — the frame, sun,
  and mountain primitives, all tagged with `elementId`. No `RenderContext`
  parameter (no text measuring). The existing `emitPlaceholder` is **left
  untouched**.
- **`rendering/elements/renderers/image_element_renderer.dart`** — the source-less
  `else` branch calls `emitImagePlaceholder(out, bounds, elementId: el.id)`
  instead of `emitPlaceholder(out, bounds, 'image', ctx, elementId: el.id)`.

No new primitive type, no backend change, no public-API change, no new exports.

## Testing & goldens

- **New unit test** for `emitImagePlaceholder` (sibling of `placeholder_test.dart`):
  - For a normal box (e.g. 50×40): asserts the emitted primitives are the
    full-bounds outline `RectPrimitive` + a frame `RectPrimitive` + two
    `PathPrimitive`s (sun + mountain), each tagged with the `elementId`, each
    grey, with the glyph centered within `bounds` and bounded by `side`.
  - For a tiny box (e.g. 6×6, `side < 8`): asserts **only** the outline rect is
    emitted (no glyph primitives).
- **Update `rendering/elements/image_element_renderer_test.dart`**: the two
  source-less cases (`UrlImageSource` at line 45, `FieldImageSource` at line 55)
  currently assert `prims[1]` is `TextRunPrimitive('image')`. They now assert the
  glyph primitives (outline rect first, then frame rect + paths) and that no
  `TextRunPrimitive` is emitted.
- **Regenerate goldens** that rasterize a **source-less** image element:
  - The PDF-export golden whose fixture uses `UrlImageSource`
    (`test/rendering/export/support/export_fixtures.dart:300`).
  - Any additional golden whose fixture contains a source-less image element —
    enumerated in the implementation plan via grep, regenerated with
    `--update-goldens`, and each regenerated image eyeballed.
- **Guards (must stay byte-identical):**
  - `rendering/elements/placeholder_test.dart` (the text `emitPlaceholder` path)
    is unchanged.
  - Barcode-fallback and unknown-element placeholders (still text) — their
    goldens unchanged.
  - The unrelated `JetPrintPlaceholder` designer-widget golden
    (`test/goldens/jet_print_placeholder.png`) is unchanged.
  - Goldens whose image fixtures use real `BytesImageSource`
    (e.g. `export_fixtures.dart:230`) are unchanged.

## Non-goals

- No new primitive type (no circle/ellipse); the sun is a polygon approximation.
- No change to `emitPlaceholder` or to the barcode/unknown placeholders.
- No public-API or serialization change.
- No change to how resolvable images render (`BytesImageSource` → `ImagePrimitive`).

## Success criteria

1. A source-less image element on the design canvas shows a centered
   picture-frame glyph (frame + mountain + sun) instead of the word "image",
   scaled to the element and capped at 28 pt, and the same glyph appears in
   exported PDF/PNG.
2. Very small image elements (`side < 8`) show just the outline, no garbled glyph.
3. Barcode, unknown-element, and text placeholders are visually unchanged
   (goldens byte-identical).
4. `flutter analyze` clean; the new unit test and the updated renderer test pass;
   the full `packages/jet_print` suite is green with only the intended
   image-placeholder goldens regenerated.
