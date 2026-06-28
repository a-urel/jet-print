# Watermark Support — Design

**Date:** 2026-06-28
**Branch:** `043-watermark-support`
**Status:** Approved design, pending implementation plan.

## Goal

Let a report carry a **watermark** — a faint **text** (e.g. "DRAFT", "CONFIDENTIAL") or **image** (e.g. a logo/stamp) drawn behind the content of **every page**, rotated and semi-transparent. The watermark renders identically across preview, PDF export, PNG raster, and system print (Constitution IV — WYSIWYG, single paint path).

Out of scope for v1: designer-UI authoring, tiled/repeated patterns, per-page-number gating, drawing over (in front of) content. The model is built so these are additive later.

## Decisions (locked)

- **Form:** one watermark per report, holding **either** text **or** image (not both).
- **Z-order:** drawn **behind** all content (bottom of the page's primitive list), so content stays readable.
- **Placement:** centered on the **full page rect** (including margins).
- **Rotation:** real rotation in the paint layer (not pre-baked geometry), about the primitive's bounds-center. Default **−45°**.
- **Opacity:** default **0.15**, clamped 0–1.
- **Scope:** model + render + serialization. No designer UI in v1.
- **Reserved `background` band:** stays separate and untouched. The watermark is its own purpose-built object — the band cannot express rotation/centering. (Memory: `BandType.background` / `PageFurniture.background` exist but are "modelled-not-rendered".)

## Architecture

```
PageFurniture.watermark: Watermark?            ← new domain value object
        │ (read at page assembly)
LazyLayout.buildPage()  ── emits watermark primitives FIRST (bottom z) ──► FrameBuilder
        │
PageFrame.primitives    (watermark text/image carry rotation + opacity)
        │
paintFrame()  ── wraps each primitive draw in painter.pushTransform/popTransform when rotation ≠ 0 ──► ReportPainter
        │
   CanvasPainter / PdfPainter / PageRasterizer(Canvas)   (3 backends, same loop → shows everywhere)
```

No new engine, no new fill pass, **no schema-version bump** (additive optional field).

### Why this approach (vs alternatives)

Three ways to get diagonal text were considered:

- **(A — chosen) `rotation` field on the primitive base + centralized transform in `paintFrame`.** Small, uniform, reusable for any future rotated element. Each backend adds one save/rotate/restore pair.
- **(B) A dedicated fat `WatermarkPrimitive`.** Self-contained but re-implements text/image painting in every backend and bloats the exhaustive primitive switch. More code, less reuse. Rejected.
- **(C) Pre-rotate geometry at frame-build (text → outline paths).** No painter change, but loses real text (no font hinting, huge paths). Rejected.

## Components

### Domain

**`Watermark`** — new `lib/src/domain/watermark.dart`. Immutable value object, `==`/`hashCode`/`copyWith`.

| Field | Type | Notes |
|---|---|---|
| `text` | `String?` | Watermark caption. Mutually exclusive with `imageBytes`. |
| `textStyle` | `JetTextStyle` | Reuse existing text-style model (font family/size/color). Color alpha is honored alongside `opacity`. |
| `imageBytes` | `Uint8List?` | Encoded image. Mutually exclusive with `text`. |
| `imageFit` | `JetBoxFit` | Reuse the fit enum (`lib/src/domain/elements/image_source.dart`) already carried by `ImagePrimitive.fit`. |
| `opacity` | `double` | 0–1, default `0.15`. Clamped. |
| `angleDegrees` | `double` | Default `-45`. Any value (normalized at paint). |

Both-set is a documented "either/or"; debug-asserts, and **text wins** at emit if both are non-null.

**`PageFurniture.watermark: Watermark?`** — new nullable field beside the reserved `background` slot in `lib/src/domain/report_definition.dart`. Watermark is per-page chrome → it belongs in furniture.

### Rendering — frame primitives

- **`FramePrimitive.rotation: double`** (radians, about `bounds` center). Default `0` → every existing primitive is byte-for-byte unchanged. Added on the sealed base in `lib/src/rendering/frame/primitive.dart`.
- **`ImagePrimitive.opacity: double`** (default `1.0`) — needed because image pixels carry their own color (text opacity is already expressible via `JetColor` alpha).

### Rendering — paint layer

- **`ReportPainter`** gains `pushTransform(Offset center, double radians)` and `popTransform()` (`lib/src/rendering/paint/report_painter.dart`).
- **`paintFrame()`** wraps the existing exhaustive switch: when `primitive.rotation != 0`, call `pushTransform(center, rotation)` before the draw and `popTransform()` after. When `0`, unchanged path.
- Backends implement push/pop once each as native save+translate+rotate+restore:
  - `CanvasPainter` — `dart:ui.Canvas` save/restore.
  - `PdfPainter` — `package:pdf` graphics save/transform/restore.
  - `PageRasterizer` — records the same `CanvasPainter` path, so it inherits rotation for free.
- Image opacity: `drawImage` applies `opacity` (e.g. paint alpha / pdf graphics alpha).

### Rendering — page assembly

- **`LazyLayout.buildPage()`** (`lib/src/rendering/layout/report_layouter.dart`): a new private `_emitWatermark(FrameBuilder fb, PageFormat page, Watermark wm)` runs **first**, before body and chrome, so watermark primitives sit at the bottom of `frame.primitives` (painted first = behind).
  - Text: lay out the caption via the existing text layout into one `TextRunPrimitive`, bounds centered on the full page rect, `rotation = wm.angleDegrees * π/180`, color alpha combined with `wm.opacity`.
  - Image: one `ImagePrimitive`, centered, `imageFit` applied, `rotation` set, `opacity = wm.opacity`.
  - Empty text or `opacity == 0` → emit nothing (no-op).

## Data flow

Author sets `PageFurniture.watermark` (via API or decoded JSON) → fill + layout run unchanged → `buildPage` injects watermark primitives at index 0 → `paintFrame` rotates and draws them first → identical output on preview, PDF, PNG, and print (all converge on `paintFrame`).

## Serialization

`lib/src/domain/serialization/report_definition_codec.dart`:

- `_encodeFurniture`: add `if (f.watermark != null) 'watermark': _encodeWatermark(f.watermark!)`.
- `_decodeFurniture`: decode the optional `'watermark'` key.
- New `_encodeWatermark`/`_decodeWatermark` (or a small `watermark_codec.dart`): omit-when-null fields; image bytes base64; reuse the existing text-style codec.
- **No `schemaVersion` bump.** Additive optional field — old files decode with `watermark == null` (nothing drawn); new files with a watermark are still version 2.

## Error handling

- Both `text` and `imageBytes` set → debug-assert; text wins at emit. Documented either/or.
- Empty text or `opacity == 0` → emit nothing (no-op, not an error).
- Undecodable image bytes → reuse the existing `ImageElement`/`ImagePrimitive` decode-failure path; watermark is skipped, the rest of the page still renders.
- `opacity` clamped to 0–1; `angleDegrees` accepted as any value, normalized at paint.

## Testing

- **Domain:** `Watermark` `==`/`copyWith`; `PageFurniture` holds and round-trips it.
- **Codec:** round-trip for the text variant, the image variant, and the null/absent case; confirm no schema-version change.
- **Primitive defaults:** `rotation` defaults `0`, `ImagePrimitive.opacity` defaults `1.0` → existing primitives unchanged.
- **Paint:** a rotated primitive calls `pushTransform`/`popTransform` exactly once around its draw (fake painter records calls).
- **Golden (new):** a report with a diagonal "DRAFT" text watermark → preview golden; an image-watermark golden. Verify watermark sits behind content.
- **Golden (regression — key guard):** all existing goldens **unchanged** — with `watermark == null` everywhere, output is byte-identical. If any existing golden diffs, STOP and inspect.

## Constitution Check

| Principle | Status |
|---|---|
| I. Library-first / clean API | PASS — `Watermark` value object + `PageFurniture.watermark`; no leaky internals. |
| II. Layered architecture | PASS — domain (`Watermark`) → rendering (primitive/paint/assembly); dependencies point inward; codec in serialization layer. |
| III. Test-First | PASS — every unit Red→Green; goldens gate fidelity. |
| IV. Rendering fidelity / WYSIWYG | PASS — single `paintFrame` path → preview/PDF/PNG/print identical by construction. |
| V. Serialization | PASS — additive omit-when-null field; no schema bump; old files decode. |
| VI. Docs/DX | PASS — dartdoc on `Watermark`, `rotation`, `opacity`, push/popTransform; `dart format` + clean analyzer gate. |

No violations.

## Follow-ups (not in v1)

- Designer-UI authoring panel (text/image/opacity/angle + live preview).
- Tiled/repeated watermark.
- Draw-over (front) option and per-page-number gating.
- Generalize the new `rotation` primitive field to author-rotated elements.
