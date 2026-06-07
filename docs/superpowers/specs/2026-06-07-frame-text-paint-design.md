# Spec 006 — Frame, Text-metrics & Paint backends — Design

**Date**: 2026-06-07
**Status**: Design (awaiting review) — implements spec **006** of the report-engine blueprint
  (`docs/superpowers/specs/2026-06-07-report-engine-design.md`, §11).
**Depends on**: 003 (Report Model & geometry value types) only. Not 004/005.
**Seams introduced**: `rendering/frame/`, `rendering/text/`, `rendering/paint/`.
**Constitution**: v1.0.0 — Principle II (Layered & Extensible), Principle III (Test-First),
  Principle IV (WYSIWYG, NON-NEGOTIABLE), Principle VI (Documentation/DX).

---

## 1. Goal & Scope

Build the **visual de-risking layer** of the engine: a headless display-list IR (`PageFrame`),
a headless text-measurement seam (`TextMeasurer`/`FontRegistry` over an in-house font-metrics
parser), and the first paint backend (`CanvasPainter`, `dart:ui`) — all exercised by painting
**hand-authored `PageFrame` fixtures**, so the whole paint/golden path is proven *before* Fill
(007) or Layout (008) exist.

**In scope**
- `rendering/frame/`: sealed `FramePrimitive` (text/image/line/rect/path) + `PageFrame` + `FrameBuilder`.
- `rendering/text/`: in-house TTF/OTF **metrics** parser → `FontMetrics`; `FontRegistry` (byte-keyed,
  with an embedded bundled default); `TextMeasurer` interface + default `MetricsTextMeasurer`
  (advances, greedy word-wrap line-breaking, ascent/descent, wrapped-block size).
- `rendering/paint/`: `ReportPainter` abstraction (with async `prepare`) + backend-agnostic
  `paintFrame` walk + `CanvasPainter` (`dart:ui`).
- Architecture-test extension for the new `rendering` seam; retirement of the scaffold placeholders.

**Out of scope (later specs)**
- Fill → `FilledReport` (007); element renderers + `registerElementType` (007).
- Layout/pagination → `List<PageFrame>` (008).
- `PdfPainter`/`ImagePainter`/`printing` and the **cross-backend pixel-parity** golden (009).
- Public exports via `jet_print.dart` (deferred-export convention; committed with the facade in 009).
- Complex-script shaping (bidi/ligatures/combining/CJK) — blueprint §1/§14.

**Text-fidelity guarantee (explicit, narrowed for v1).** 006 guarantees **deterministic
line-breaking**: a single headless `TextMeasurer` owns line-breaking and bakes the result into
`TextRunPrimitive.lines`, so every backend reproduces the *same* line breaks. Page-break and
band-height parity are realized by Layout (008), which consumes these breaks; cross-backend
*pixel* parity becomes provable only once a second backend exists (009, §8) — 006 alone stands up
one Canvas backend and the parity *mechanism*, not parity itself. *Within* a line, each backend
rasterizes the **same registered font** (visually consistent) but is **not guaranteed glyph-exact**
where it applies kerning/hinting the v1 hmtx-only metrics do not model.
This is the line-break slice of the blueprint's §3 positioned-glyph-run vision — recorded as a
justified deviation in blueprint **§15.6**; glyph-exact positioning is a deferred, additive
tightening (§13) that extends the same line IR without re-architecture. Scope: **Latin / simple
LTR** text.

---

## 2. Decisions

| # | Decision | Choice | Consequence |
|---|---|---|---|
| 1 | Text IR granularity | **Line-level laid-out runs** | Measurer owns breaks; painter draws a line as one run, no re-wrap. Guarantees line-break parity. |
| 2 | Font-metrics source | **In-house minimal TTF/OTF reader** | Parse only metric tables; pure Dart; **zero new package deps**; `pdf` stays out of 006. |
| 3 | Default font | **Bundled, embedded as generated Dart bytes** | One headless byte-source for both measure + paint; deterministic goldens; first-run rendering. |
| 4 | Test backbone | **Data goldens primary + Canvas pixel smoke** | Platform-independent data snapshots are the real guard; cross-backend parity test is a deferred placeholder. |
| 5 | Text guarantee | **Line-break parity (not glyph-exact) for v1** | Honest WYSIWYG claim; IR forward-compatible to per-glyph advances later. |
| 6 | Painter lifecycle | **Async `prepare(frame)` in the abstraction** | Backend async (font load / image decode) is enforced by the contract, not leaked. |
| 7 | Font provenance | **Noto Sans Regular, OFL, Latin-subset** | Broad Latin-Extended coverage (Western European + Turkish); `OFL.txt` committed. |
| 8 | Scaffold placeholders | **Retired in 006** | `ReportDocument`/`ReportLayout` quartet removed (verified zero real importers). |
| 9 | Public exports | **Deferred** (established convention) | New types stay in `src/`; white-box tests use `package:jet_print/src/...`; exports land in 009. |

---

## 3. Seam layout & the headless boundary

```
lib/src/rendering/
  frame/
    primitive.dart            sealed FramePrimitive + 5 variants + PathCommand
    page_frame.dart           PageFrame (immutable primitives + PageFormat)
    frame_builder.dart        FrameBuilder (write-side → PageFrame)
  text/
    font_metrics.dart         FontMetrics (unitsPerEm, ascent/descent/lineGap, cmap, advances)
    ttf/ttf_metrics.dart      parseTtfMetrics(Uint8List) → FontMetrics  (head·hhea·hmtx·cmap·OS/2)
    font_registry.dart        FontRegistry (byte-keyed; registerDefault())
    text_measurer.dart        TextMeasurer interface + MeasuredText + TextLine
    metrics_text_measurer.dart  MetricsTextMeasurer (default impl)
    fonts/
      NotoSans-subset.ttf     committed bundled font (binary)
      OFL.txt                 the font license (provenance)
      default_font_data.dart  generated: final Uint8List kDefaultFontBytes = base64Decode(...)
  paint/
    report_painter.dart       ReportPainter (async prepare) + paintFrame() walk
    canvas_painter.dart       CanvasPainter (dart:ui) — THE ONLY file importing Flutter/dart:ui
```

**The boundary (blueprint §3a).** `frame/` and `text/` are pure Dart — they import only
`dart:typed_data`/`dart:convert`/`dart:math` and the domain seam. They MUST NOT import
`dart:ui` or any Flutter library, so the measure→frame path runs headless in CI with no Flutter
binding. **Only `paint/canvas_painter.dart`** imports `dart:ui`. `report_painter.dart` (the
abstraction + walk) stays Flutter-free — it knows only primitives. The layer-boundary test (§10)
makes this executable.

Dependency direction: `rendering → domain` (and later `data`, `expression`). In 006 the rendering
seam imports **only** `domain` (geometry, styles, `PageFormat`). It must not import `designer`.

---

## 4. Component: `frame/` — the WYSIWYG contract

Pure-Dart geometry only (`JetRect`/`JetOffset`/`JetSize`/`JetColor` from `domain`). Each primitive
carries its originating `elementId` (nullable) for designer hit-testing later. All primitives have
value equality + a deterministic `toString` (for data goldens).

```dart
sealed class FramePrimitive {
  const FramePrimitive({required this.bounds, this.elementId});
  final JetRect bounds;       // position + size in page points
  final String? elementId;
}

final class TextRunPrimitive extends FramePrimitive {
  const TextRunPrimitive({
    required super.bounds, required this.lines, required this.style,
    required this.fontFamily, super.elementId,
  });
  final List<TextLine> lines;   // pre-broken by the measurer; painter never re-wraps
  final JetTextStyle style;     // color/size/weight/italic/align
  final String fontFamily;      // resolved family the painter must render with
}

final class ImagePrimitive extends FramePrimitive {
  const ImagePrimitive({
    required super.bounds, required this.bytes,
    this.fit = JetBoxFit.contain, super.elementId,
  });
  final Uint8List bytes;        // ENCODED (PNG/JPEG); decoded by the painter (keeps frame headless)
  final JetBoxFit fit;
}

final class LinePrimitive extends FramePrimitive {
  const LinePrimitive({
    required super.bounds, required this.start, required this.end,
    required this.color, this.strokeWidth = 1.0, super.elementId,
  });
  final JetOffset start; final JetOffset end; final JetColor color; final double strokeWidth;
}

final class RectPrimitive extends FramePrimitive {
  const RectPrimitive({
    required super.bounds, this.fill, this.stroke, this.strokeWidth = 1.0, super.elementId,
  });
  final JetColor? fill; final JetColor? stroke; final double strokeWidth;
}

final class PathPrimitive extends FramePrimitive {
  const PathPrimitive({
    required super.bounds, required this.commands, this.fill, this.stroke,
    this.strokeWidth = 1.0, super.elementId,
  });
  final List<PathCommand> commands; final JetColor? fill; final JetColor? stroke; final double strokeWidth;
}

sealed class PathCommand { const PathCommand(); }
final class MoveTo extends PathCommand { const MoveTo(this.to); final JetOffset to; }
final class LineTo extends PathCommand { const LineTo(this.to); final JetOffset to; }
final class ClosePath extends PathCommand { const ClosePath(); }
```

```dart
class PageFrame {
  PageFrame({required this.page, required List<FramePrimitive> primitives})
      : primitives = List<FramePrimitive>.unmodifiable(primitives);
  final PageFormat page;
  final List<FramePrimitive> primitives;     // value equality over (page, primitives) + toString
}

class FrameBuilder {
  FrameBuilder(this.page);
  final PageFormat page;
  void add(FramePrimitive primitive);
  PageFrame build();                          // snapshots into an immutable PageFrame
}
```

`JetBoxFit` is the existing domain enum (`domain/elements/image_source.dart`: `contain`/`cover`/
`fill`/`none`). `PageFrame` is an **in-memory IR**, not persisted to disk in v1 — no `toJson`. Data goldens compare
constructed `PageFrame`s by value (or by `toString`).

---

## 5. Component: `text/` — the parity engine (headless)

### 5.1 `FontMetrics` + the TTF reader

```dart
class FontMetrics {
  const FontMetrics({
    required this.unitsPerEm, required this.ascent, required this.descent,
    required this.lineGap, required Map<int,int> cmap, required List<int> advanceWidths,
    required this.defaultAdvance,
  });
  final int unitsPerEm;                 // from `head`
  final double ascent, descent, lineGap;// from `hhea`, font units
  int glyphForCodepoint(int cp);        // `cmap` (Unicode BMP format-4); missing → 0 (.notdef)
  double advanceForGlyph(int glyphId);  // `hmtx`; out of range → defaultAdvance
  final double defaultAdvance;
}

/// Parses the metric tables of a TTF/OTF font. Pure Dart (ByteData).
/// Throws FontFormatException on a malformed/unsupported font.
FontMetrics parseTtfMetrics(Uint8List bytes);
```

The reader walks the table directory and reads `head` (unitsPerEm), `hhea` (ascender/descender/
lineGap, numberOfHMetrics), `maxp` (numGlyphs), `hmtx` (advance widths), and `cmap` (a Unicode BMP
format-4 subtable). It ignores `glyf`/outlines entirely — metrics only. (`OS/2` typo-metric
fallback for a degenerate `hhea` is deferred — the bundled font and target fonts carry valid
`hhea`.) `FontFormatException` is a new typed error in `text/`.

### 5.2 `FontRegistry` (one contract: byte-keyed; default is a pre-registered entry)

```dart
class FontRegistry {
  void register(String family, Uint8List bytes,
      {JetFontWeight weight = JetFontWeight.normal, bool italic = false});

  /// Registers the bundled default under [defaultFamily]. Uses [bytes] if given
  /// (tests may inject); otherwise the embedded kDefaultFontBytes.
  void registerDefault({Uint8List? bytes});
  static const String defaultFamily = 'JetSans';
  bool get hasDefault;

  /// Parsed metrics for the requested variant; falls back to the default.
  /// Throws StateError only if nothing matches and no default is registered.
  FontMetrics metricsFor(String? family,
      {JetFontWeight weight = JetFontWeight.normal, bool italic = false});

  /// Raw bytes for the resolved variant — backends embed/load these
  /// (CanvasPainter via loadFontFromList; PdfPainter embeds later).
  Uint8List bytesFor(String? family,
      {JetFontWeight weight = JetFontWeight.normal, bool italic = false});

  /// The family name a backend must render with after fallback resolution.
  String resolveFamily(String? family,
      {JetFontWeight weight = JetFontWeight.normal, bool italic = false});
}
```

**The single source of truth.** Measurement parses `bytesFor(...)` → `FontMetrics`; painting loads
those *same* bytes into the backend. Same bytes ⇒ same glyph shapes everywhere; same metrics ⇒ same
line breaks. The bundled default's bytes live in `fonts/default_font_data.dart`
(`final Uint8List kDefaultFontBytes = base64Decode('…')`), generated from `NotoSans-subset.ttf`. No
`rootBundle`, no asset declaration — fully headless and identical in pure-Dart tests, CI, and apps.

### 5.3 `TextMeasurer` + default impl

```dart
abstract class TextMeasurer {
  MeasuredText measure(String text, JetTextStyle style, {double? maxWidth});
}

class MeasuredText {
  const MeasuredText({required this.lines, required this.size, required this.firstAscent});
  final List<TextLine> lines;
  final JetSize size;          // wrapped block: (max line width, lines×lineHeight)
  final double firstAscent;    // ascent of line 0 (for baseline alignment by callers)
}

class TextLine {
  const TextLine({required this.text, required this.width, required this.top,
      required this.baseline, required this.height});
  final String text;           // literal line content — whitespace preserved (no collapse/trim)
  final double width;          // measured advance width, points
  final double top;            // y of the line-box TOP from block top — paragraph-origin backends (Canvas)
  final double baseline;       // y of the BASELINE from block top = top + lineAscent — baseline-origin backends (PDF)
  final double height;         // line-box height, points  (value equality + toString)
}

class MetricsTextMeasurer implements TextMeasurer {
  MetricsTextMeasurer(this._registry);
}
```

**Algorithm (`MetricsTextMeasurer.measure`).**
1. Resolve `FontMetrics` via `_registry.metricsFor(style.fontFamily, weight, italic)`.
2. Scale: `pt(u) = u / unitsPerEm * style.fontSize`. With `hhea.descender` negative,
   `lineHeight = pt(ascent) + pt(−descent) + pt(lineGap)` and `lineAscent = pt(ascent)`.
3. **Segment on hard breaks**: `text.split('\n')` — always ≥1 segment, and **empty segments are
   kept**, so a blank middle line (consecutive `\n`) and a trailing `\n` produce empty `TextLine`s
   of height `lineHeight`. Literal whitespace is **never collapsed or trimmed**.
4. **Wrap each segment** (when `maxWidth != null`): greedy word-wrap at whitespace boundaries,
   **preserving the literal characters** — internal runs of spaces and leading/trailing spaces stay
   in the line text. Accumulate until the running advance would exceed `maxWidth`, then break before
   the overflowing token; a single token wider than `maxWidth` is its own overflowing line (no
   character-level breaking in v1). A tab is measured and treated as a single space (documented v1
   limitation). `maxWidth == null` ⇒ no wrapping (hard `\n` breaks only).
5. **Per-line geometry**: `width` = Σ scaled advances of the line's literal characters, spaces
   included (`cmap`→glyphId→`hmtx`); `top = index × lineHeight`; `baseline = top + lineAscent`;
   `height = lineHeight`.
6. `size = JetSize(maxLineWidth, lines.length × lineHeight)`; `firstAscent = lineAscent`. An empty
   input string `''` yields one empty line: `size = JetSize(0, lineHeight)`.

Deterministic and platform-independent: identical inputs + identical font bytes ⇒ identical output.

---

## 6. Component: `paint/` — backends

```dart
abstract class ReportPainter {
  Future<void> prepare(PageFrame frame) async {}   // async asset resolution; default no-op
  void beginPage(PageFormat format);
  void drawTextRun(TextRunPrimitive p);
  void drawImage(ImagePrimitive p);
  void drawLine(LinePrimitive p);
  void drawRect(RectPrimitive p);
  void drawPath(PathPrimitive p);
  void endPage();
}

/// Backend-agnostic walk. Exhaustive switch over the sealed primitive — no `default`,
/// so adding a variant is a compile error until every backend handles it.
Future<void> paintFrame(PageFrame frame, ReportPainter painter) async {
  await painter.prepare(frame);
  painter.beginPage(frame.page);
  for (final FramePrimitive p in frame.primitives) {
    switch (p) {
      case TextRunPrimitive(): painter.drawTextRun(p);
      case ImagePrimitive():   painter.drawImage(p);
      case LinePrimitive():    painter.drawLine(p);
      case RectPrimitive():    painter.drawRect(p);
      case PathPrimitive():    painter.drawPath(p);
    }
  }
  painter.endPage();
}
```

**`CanvasPainter` (`dart:ui`, the only Flutter-touching file).**
```dart
class CanvasPainter implements ReportPainter {
  CanvasPainter(this._canvas, this._registry);
  // prepare(): (1) loadFontFromList(_registry.bytesFor(family), fontFamily: resolveFamily(...))
  //               once per resolved family; (2) decode each ImagePrimitive.bytes →
  //               ui.Image into a per-frame cache.
  // drawTextRun(): for each TextLine, build a ui.Paragraph with the resolved font and a width
  //               wide enough that it NEVER re-wraps; position it horizontally within bounds.width
  //               per style.align (left/center/right honored; justify ⇒ left in v1). A ui.Paragraph
  //               paints from its TOP-LEFT, so the vertical origin is bounds.y + line.top (NOT
  //               line.baseline — that field is for baseline-origin backends like PDF). The
  //               measurer owns breaks; the painter only rasterizes.
  // drawLine/drawRect/drawPath(): map Jet geometry/color → dart:ui and stroke/fill on _canvas.
  // drawImage(): draw the cached ui.Image into bounds per JetBoxFit.
}
```

Golden tests paint into a `PictureRecorder` → `Picture.toImage` → `matchesGoldenFile` under
`flutter_test`. Pixel goldens are **smoke-level** (Skia/Impeller rasterization is platform-sensitive)
and may be platform-pinned; the determinism guarantee rests on the §7 data goldens.

---

## 7. Error handling (render-don't-crash; full `ReportDiagnostics` is 009)

| Case | 006 behavior |
|---|---|
| Unknown / unregistered font family | Fall back to the bundled default (same fallback in measure + paint ⇒ parity preserved) |
| Codepoint absent from `cmap` | Use glyph 0 (`.notdef`) advance |
| Empty string `''` | One empty line (`size = 0 × lineHeight`); the element layer (007) may choose not to render it |
| Blank line / repeated `\n` | Preserved as empty `TextLine`(s) of height `lineHeight` |
| Runs of spaces, leading/trailing whitespace | Preserved literally (never collapsed or trimmed) |
| Tab character | Measured and treated as a single space in v1 (documented limitation) |
| `maxWidth ≤ 0` or a word wider than `maxWidth` | One overflowing line — never an infinite loop |
| Malformed font bytes | `parseTtfMetrics` throws typed `FontFormatException` (structural, fail-fast) |
| `metricsFor`/`bytesFor` with no match and no default | `StateError` (engine misconfiguration — a default is always registered in practice) |

Diagnostics objects (warnings surfaced to callers) arrive with the engine facade in 009; 006’s
fallbacks are silent-but-deterministic.

---

## 8. Testing strategy (Principles III + IV)

All test files live under `test/rendering/` (already on the encapsulation white-box allowlist) and
may import `package:jet_print/src/...`.

- **`text/ttf_metrics_test.dart`** — parse the bundled font; assert known table values
  (unitsPerEm, ascent/descent, a few glyph advances, a few cmap mappings); malformed bytes →
  `FontFormatException`.
- **`text/measurer_metrics_test.dart`** — advances, ascent/descent, wrapped size, per-line
  `top`/`baseline` geometry (distinct origins), and **line-break correctness**: greedy wrap, hard
  `\n`, **blank middle line preserved**, **runs of spaces and leading/trailing whitespace
  preserved**, single overlong word, tab-as-space, empty string ⇒ one empty line. Pure data;
  platform-independent.
- **`frame/frame_snapshot_test.dart`** — `FrameBuilder`/`PageFrame` construct the expected
  primitives; value-equality + `toString` data golden. Immutability of `PageFrame.primitives`.
- **`paint/paint_frame_test.dart`** — `paintFrame` dispatches each primitive to the right method
  and calls `prepare`/`beginPage`/`endPage` in order, verified with a recording fake
  `ReportPainter` (no `dart:ui`). Headless.
- **`paint/canvas_painter_golden_test.dart`** — a hand-authored fixture `PageFrame` (text + rect +
  line + image) → `CanvasPainter` → `matchesGoldenFile`. Smoke-level; under `flutter_test`.
- **`parity_test.dart`** — `skip('cross-backend pixel parity lands with PDF/PNG in 009')`,
  documenting the boundary rather than implying coverage.
- **`architecture/layer_boundaries_test.dart`** — extended per §10.

---

## 9. Scaffold retirement

Remove the self-contained scaffold quartet (verified zero importers from real model code, the
facade, the designer, or `public_api_test`):
- `lib/src/domain/domain.dart` (the `ReportDocument` stub)
- `lib/src/rendering/rendering.dart` (the `ReportLayout` placeholder)
- `test/domain/domain_test.dart`
- `test/rendering/rendering_test.dart`

This completes the replacement 003 began (003 added the real model in new files but left the stub).
After removal, `flutter analyze` + the full suite must stay green, confirming nothing depended on them.

---

## 10. Architecture-test extension (the `rendering` seam)

Add a `rendering` group to `test/architecture/layer_boundaries_test.dart`:
- **has-source guard** — `rendering/` exists and has `.dart` files (no false green).
- **no designer reach** — no rendering file imports a `designer` URI.
- **headless except CanvasPainter** — for every rendering file, an import of `dart:ui` or a
  forbidden Flutter UI library is a violation **unless** the file path ends with
  `paint/canvas_painter.dart` (the sole whitelisted exception). This simultaneously proves
  `frame/`, `text/`, and `report_painter.dart` are Flutter-free.

The existing domain/data/expression groups are unchanged; their `_reachesOtherSeam` rule (which
forbids them from importing anything containing `rendering`) already covers the new seam from the
inside-out direction.

---

## 11. Build order (TDD phases → the plan)

1. **Frame** — `primitive.dart` (sealed + variants + `PathCommand`), `page_frame.dart`,
   `frame_builder.dart`; value equality, `toString`, immutability. Data goldens.
2. **TTF metrics** — `font_metrics.dart` + `ttf/ttf_metrics.dart`; commit `NotoSans-subset.ttf`
   + `OFL.txt`; generate `default_font_data.dart`. Parser unit tests vs. the bundled font.
3. **FontRegistry** — byte-keyed register + `registerDefault()` + fallback resolution.
4. **TextMeasurer** — interface + `MetricsTextMeasurer` (advances, word-wrap, ascent/descent,
   size). Metrics + line-break data goldens.
5. **ReportPainter + walk** — abstraction (async `prepare`) + `paintFrame`; recording-fake test.
6. **CanvasPainter** — `dart:ui`, `loadFontFromList`, async image decode; Canvas pixel smoke golden.
7. **Architecture test + housekeeping** — rendering-seam boundary group; deferred-parity
   placeholder; `CHANGELOG.md` (spec 006) bullet.
8. **Scaffold retirement** — delete the quartet (§9); confirm green.

---

## 12. Dependencies

**006 adds no new package dependencies.** In-house TTF parser (pure Dart), embedded default font
(generated Dart bytes), and `dart:ui` (already in the Flutter SDK). `pdf`/`printing`/`barcode`
arrive in 007/009. The committed `NotoSans-subset.ttf` + `OFL.txt` are repo artifacts, not pub deps.

---

## 13. Open questions / deferred (additive, not re-architecture)

- **Glyph-exact parity** — `TextLine` can gain an optional per-glyph advance/position list so PDF
  (009) and a future shaping engine paint exact positions, tightening line-break parity toward
  glyph-exact. The line IR does not foreclose it.
- **Font subsetting for PDF** — embed only used glyphs (009 size optimization, blueprint §14).
- **Justify alignment** — real inter-word stretching deferred; v1 renders `justify` as `left`.
- **Bold/italic synthesis** — v1 resolves registered variants or falls back; synthetic emboldening
  is out of scope.
- **`ReportDiagnostics`** — warning surfacing lands with the engine facade (009).

---

## 14. Constitution alignment

| Principle | How 006 complies |
|---|---|
| I — Library-First / Clean API | New types stay in `src/`; deferred public export until the 009 facade. |
| II — Layered & Extensible | `rendering → domain` only; the boundary test enforces the headless rule and the single `dart:ui` exception. |
| III — Test-First | TDD per phase; data goldens are the deterministic backbone; a recording fake tests the paint walk headless. |
| IV — WYSIWYG | One headless `TextMeasurer` owns line breaks → identical wrapping/heights across backends; claim explicitly scoped to line-break parity for v1. |
| VI — Documentation / DX | Dartdoc on public symbols; embedded default ⇒ zero-config first-run rendering; CHANGELOG per spec; zero-warning analyzer gate. |
