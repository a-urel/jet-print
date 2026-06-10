# Research: Export Support (012)

Phase 0 decisions. Library facts below were source-verified against `DavBfr/dart_pdf` at
tag `pdf-3.12.0` / `printing-5.14.3` (HEAD `72d590e` is identical) and pub.dev/GitHub as
of 2026-06-10.

## 1. PDF backend: `package:pdf` (dart_pdf), low-level API

**Decision**: Generate PDFs with `pdf` **3.12.0** (Apache-2.0, verified publisher
`nfet.net`, actively maintained, pure Dart) using its **low-level**
`PdfDocument`/`PdfPage`/`PdfGraphics` API — *not* its widgets layer — behind a new
internal `PdfPainter implements ReportPainter`.

**Rationale**:
- The low-level API maps 1:1 onto our frame primitives, all verified in source:
  `PdfGraphics.drawString(font, size, s, x, y)` places text at an exact **baseline**
  origin (`BT … Td … TJ ET`), which is precisely what `TextRunPrimitive`'s pre-measured
  `TextLine.baseline` provides — no re-layout, no re-wrap (FR-003/004).
  `PdfTtfFont(doc, ByteData bytes)` embeds fonts from the same raw TTF bytes our
  `FontRegistry` already holds (FR-005). `drawLine/drawRect/moveTo/lineTo/fillPath/
  strokePath/fillAndStrokePath/clipPath/setFillColor/setStrokeColor/setLineWidth` cover
  `LinePrimitive`/`RectPrimitive`/`PathPrimitive`. `PdfPageFormat(width, height)` is in
  PostScript points — the same unit as our `PageFormat` (FR-008 is a pass-through).
- Using its **widgets layer would violate Constitution IV**: it is a parallel layout +
  paint pipeline. The low-level API keeps our shared `paintFrame` walk as the single
  source of drawing truth.
- Pure Dart: the rendering seam stays Flutter-free; `flutter test` is explicitly
  accommodated (dart_pdf's `save()` runs inline when `FLUTTER_TEST` is set).
- Font subsetting (Type0/Identity-H via `TtfWriter.withChars`) is deterministic: glyphs
  are collected in first-use order, no random subset-name tag. *Caveat pinned by test*:
  a TTF **without a PostScript name** (nameID 6) falls back to an identity-hash
  `/BaseFont` — nondeterministic. The bundled `JetSans` must (and does, as a normal
  TTF) carry one; the determinism test would catch a violating font immediately.

**Alternatives considered**:
- `syncfusion_flutter_pdf` — feature-comparable and very actively maintained, but
  **commercially licensed** (Community License has revenue/headcount thresholds);
  incompatible with an Apache-licensed pub.dev library's dependency policy
  (Tech-standards: permissive licensing). Rejected.
- Hand-rolled PDF writer — full control over determinism, but fonts (CMaps, subsetting,
  ToUnicode) alone are months of work; unjustifiable against a maintained Apache-2.0
  dependency that 011 explicitly anticipated. Rejected.
- Rasterized "PDF of pictures" (pages as embedded PNGs) — trivially WYSIWYG but violates
  FR-004 (real, selectable text). Rejected.
- `htmltopdfwidgets` etc. are wrappers over dart_pdf; `pdfrx`/`pdfx` are viewers, not
  generators. Not applicable.

## 2. Byte-determinism mechanics (FR-007, SC-004)

**Decision**: Achieve byte-identical output with four contained measures in `PdfPainter`:
1. **No `/Info` object** — at the low level the Info dictionary (and with it
   `/CreationDate`, which `PdfInfo` hardcodes to `DateTime.now()` with no override
   parameter) only exists if constructed. We construct none. (There is **no**
   `creationDate:` parameter in dart_pdf 3.12.0 — do not plan around one.)
2. **Fixed `/ID`** — `PdfDocument.documentID` is a lazy getter that mixes
   `DateTime.now()` + `Random.secure()`, is **always written**, and has **no
   constructor parameter or setter**. The getter is virtual and `_write` dispatches
   through it, so we use a minimal internal subclass
   (`class _FixedIdPdfDocument extends PdfDocument` overriding `documentID` to a
   constant) — verified workable in source. Fallback if an upgrade breaks it:
   post-process the fixed-width `/ID [<64 hex> <64 hex>]` in the saved bytes.
3. **`verbose: false`** (default) — verbose mode writes a wall-clock comment (debug-mode
   asserts only, but we pin the default anyway).
4. **Deterministic inputs** — already guaranteed: the render pipeline is deterministic
   (011 FR-010), object ordering in dart_pdf is insertion-ordered (LinkedHashSet +
   monotonic serial counter), and draw-call sequence equals primitive order.

**Compression caveat (recorded, accepted)**: dart_pdf deflates via the Dart SDK's `zlib`
on the VM. That is deterministic for a given SDK build — which satisfies FR-007's
"identical artifacts **across runs**" — but bytes may change across Dart SDK or
dart_pdf upgrades. Golden PDF pins are therefore *deliberate-update* artifacts exactly
like image goldens (Constitution IV's golden-update discipline applies). No GitHub issue
tracks reproducible output in dart_pdf; nothing upstream is about to change this under us.

**Alternatives considered**: post-processing bytes only (fragile offsets vs. clean
override — kept as fallback); `compress: false` (larger artifacts for no determinism gain
within an SDK); filing/waiting for an upstream `documentID` parameter (worth proposing,
but not a plan dependency).

## 3. Print: `package:printing`, isolated behind a presenter seam

**Decision**: Implement `JetReportPrinter` over `printing` **5.14.3** (Apache-2.0, same
repo/author as `pdf`; Android/iOS/macOS/Windows/Linux/web). Availability check via
`Printing.info()` → `PrintingInfo.canPrint`; dialog via
`Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: jobName, format: pageFormat)`
which returns `true` (printed) / `false` (user cancelled). The `printing` import lives
**only** in the new `src/print/` seam behind the injectable `PrintDialogPresenter`
typedef (Tech-standards: swappable abstraction; rendering core stays platform-agnostic).

**Rationale & verified behaviors**:
- `info()` **never throws** — on an unsupported platform it returns
  `PrintingInfo.unavailable` (all-false), giving us a clean, crash-free
  `PrintUnavailableException` path (FR-009a; US3 acceptance 4). `layoutPdf` throws on
  platform errors and would throw `MissingPluginException` in plain `flutter test` —
  which is why the default presenter checks `canPrint` first and why widget tests inject
  a fake presenter (no platform channels in tests). `printing` also exposes a standard
  `plugin_platform_interface` (`PrintingPlatform.instance` is settable) as a deeper
  mock seam if ever needed.
- `onLayout` is re-invoked when the user changes paper in the dialog; we return the same
  deterministic bytes regardless (the document *is* the artifact; reflowing to the
  dialog's paper would break WYSIWYG).
- **Playground (macOS) requirement**: printing from a sandboxed macOS app needs the
  `com.apple.security.print` entitlement in **both** `DebugProfile.entitlements` and
  `Release.entitlements` — a playground (consumer) change, not a library one.

**Alternatives considered**: platform channels written in-repo (re-implements six
platforms of `printing` for zero gain); host-implemented printing only (violates the
clarified FR-009a: the *library* ships the print helper); `directPrint` without a dialog
(out of scope — the spec wants the system dialog).

## 4. PNG export: rasterize the existing canvas pipeline via `dart:ui`

**Decision**: `pageToPng` records the page through the **unchanged**
`paintFrame` → `CanvasPainter` path (identical to the preview) into a
`ui.PictureRecorder` whose canvas is scaled by `scale`, then
`Picture.toImage(round(w×scale), round(h×scale))` → `toByteData(ImageByteFormat.png)`.
New file `src/rendering/paint/page_rasterizer.dart` joins `canvas_painter.dart` as the
second declared `dart:ui` file in the rendering seam (architecture test extended,
pinned).

**Rationale**: zero parallel paint code (Constitution IV); pixel parity with the preview
is by construction; exact pixel dimensions satisfy SC-006 trivially.

**Determinism scope (recorded)**: the engine's PNG encoder is deterministic for identical
pixels on a given machine + engine build (what SC-004's run-to-run hash test exercises),
but **not** guaranteed byte-stable across machines/engine versions
(flutter/flutter#30036). Consequence for tests: PNG goldens go through the standard
golden comparator (which falls back to decoded-pixel comparison), while *run-to-run*
byte equality is asserted in-process. PDF goldens may be raw byte pins (pure-Dart
pipeline, no engine encoder involved).

**Alternatives considered**: a pure-Dart software rasterizer (`package:image` drawing) —
engine-independent bytes, but it would be a **parallel paint implementation** of every
primitive (direct Constitution IV violation) and worse fidelity; rejected. JPEG/quality
options — explicitly out of scope (clarified: PNG only).

## 5. Image embedding path for PDF (pure Dart)

**Decision**: `ImagePrimitive.bytes` (host-resolved, encoded) are embedded as: JPEG →
`PdfImage.jpeg(doc, image: bytes)` passthrough; PNG (and anything else) → decode with
`package:image` to RGBA → raw `PdfImage(doc, image: rgba, width, height)` (alpha via
`/SMask`). `image` becomes a **direct** dependency (it is already a transitive dependency
of `pdf`; we import it ourselves, so we declare it — MIT, pub-compatible). Placement uses
the shared `computeImageFit` rects with a clip, mirroring `CanvasPainter.drawImage`.

**Rationale**: keeps the PDF path pure Dart (no `dart:ui` decode in the rendering seam);
`package:image` decoding is deterministic; identical geometry to the preview.

**Alternatives considered**: decoding via `dart:ui` codecs (drags Flutter into the
PDF path and into the architecture allowlist for no benefit); skipping JPEG passthrough
(needless re-encode, bigger files, lossy-on-lossy).

## 6. Coordinate mapping: top-left frames → bottom-left PDF

**Decision**: `PdfPainter` maps coordinates **per draw call** with a tiny helper
(`y' = pageHeight − y`, heights subtracted accordingly) instead of installing a global
`scale(1, −1)` CTM.

**Rationale**: a global negative-y transform mirrors glyph outlines (text would render
upside-down and would need a counter-flip per text object — the classic dart_pdf
footgun); explicit per-primitive mapping is a handful of lines, trivially unit-testable
(`pdf_painter_parity_test`), and keeps `drawString`'s baseline semantics aligned with
`TextLine.baseline`: PDF baseline y = `pageHeight − (bounds.y + line.top + line.baseline)`.

## 7. API shape: a dedicated exporter facade (not engine methods)

**Decision**: a separate `const JetReportExporter` (`toPdf`, `pageToPng`) plus
`const JetReportPrinter` — the engine stays a pure render facade.

**Rationale**: mirrors the spec's entity model (export capability = "the export-side
counterpart of the 011 preview" consuming `RenderedReport`); keeps `JetReportEngine`'s
contract untouched (011 tests unchanged); the single-awaitable shape leaves room for
additive `{onProgress, cancelToken}` named parameters later without breaking changes
(clarified deferral). Image options stay a `scale:` named parameter — no speculative
options classes (Constitution I: deliberately minimal surface).

**Alternatives considered**: `JetReportEngine.exportPdf(...)` (bloats the render facade;
couples slices); extension methods on `RenderedReport` (less discoverable in dartdoc;
harder to make `const`-injectable); a builder/options-object API (speculative
generality the spec explicitly deferred).

## Resolved unknowns

All Technical Context items are resolved; no NEEDS CLARIFICATION remain. New
dependencies: `pdf` (direct), `printing` (direct), `image` (direct, already transitive).
Playground-only change: macOS `com.apple.security.print` entitlements.
