# Report Engine — Architecture Design

**Date**: 2026-06-07 (rev. 3 — incorporates two rounds of external design review; see §15)
**Status**: Approved blueprint (reference design; implementation split into specs 003–009)
**Topic**: The `jet_print` report engine — the functional core that turns a report model + data into laid-out, printable output across screen, PDF, and print.
**Relates to**: Constitution v1.0.0 (Principles I–VI); builds on 001 (scaffold) and 002 (designer layout shell).

---

## 1. Goal & Scope

Design the **complete component architecture** for the report engine as a reference
blueprint, answering "which components do we need and how do they fit." This document is
the architectural source of truth; the engine is **built incrementally** through a sequence
of dependency-ordered Spec Kit features (003–009, see §11), each independently testable and
shippable, culminating in the constitution's data-aware **invoice MVP**.

**In scope (blueprint)**: report model, serialization, data layer, expression engine,
rendering pipeline (fill → layout/paginate → paint), paint backends, the extension points,
error/diagnostics, versioning, public API, and testing strategy.

**Out of scope (this blueprint)**: the full designer UI behavior (canvas editing,
property editors, drag-drop) — a separate track that *consumes* the engine after 009; async/
streaming data sources; built-in SQL/REST connectors; charts/cross-tabs/subreports (the
extension points are designed to admit them later without core changes); **complex-script
text shaping** (bidi, ligatures, combining marks) — see the text-scope note below.

**v1 text scope (affects the WYSIWYG guarantee)**: text handling targets **Latin and simple
left-to-right scripts**. The cross-backend parity guarantee (§3) and its golden tests (§10) are
scoped to that set. Complex-script shaping is deferred (§14) and extends the same `TextMeasurer`
mechanism without redesign. If a future milestone needs RTL/CJK, it is an additive enhancement,
not a re-architecture.

## 2. Decisions (the constraints this design satisfies)

| Decision | Choice | Consequence |
|---|---|---|
| Output of this exercise | **Full architecture blueprint** | Reference design; implementation via specs 003–009 |
| Layout paradigm | **Banded + absolute-in-band** positioning | Deterministic band-arranger; no general flow/reflow solver |
| Output targets | **Screen canvas (given) + PDF + native print + PNG**; *not* widget-tree reuse | Headless layout pass → display list → swappable paint backends |
| Expression richness | **Arithmetic + conditionals + aggregates/grouping**, pluggable function registry | A first-class expression engine (lexer/parser/evaluator + variable calculator) |
| Data sources | **In-memory + abstract `JetDataSource`**, synchronous | Library stays dependency-light & host-agnostic; consumers plug their own backends |
| Element types | **Text/field, image, line/rect, barcode/QR** behind a registry | Table/subreport/chart addable later without touching core |
| Pipeline shape | **Staged pipeline with explicit IRs** | Each stage pure & unit-testable; WYSIWYG by construction; headless & golden-friendly |

## 3. Architectural Principles Applied

- **Inward dependencies (Principle II)**: every seam depends only on seams closer to the
  pure domain model. Dependency DAG:
  `domain → (nothing)` · `data → domain` · `expression → domain, data` ·
  `rendering → domain, data, expression` · `designer → all`. Nothing points outward; the
  layer-boundary test enforces this.
- **Single shared layout, many outputs (Principle IV / WYSIWYG)**: one headless layout pass
  produces a `PageFrame` display list; every paint backend renders the *same* frame, so
  canvas, PDF, PNG, and print cannot diverge. For text, the mechanism is precise: the
  **`TextMeasurer`** emits a *positioned glyph run* (which glyphs, at which advances) using the
  **registered fonts**, and backends **paint exactly those positions rather than re-shaping** —
  so wrapping and band heights match exactly across screen/PDF/PNG for whatever the measurer
  supports. **v1 supported text scope: Latin and simple left-to-right scripts** (no bidi,
  ligature, or combining-mark shaping). The cross-backend guarantee is scoped to that set;
  complex-script shaping (§14) extends the *same* mechanism to more scripts later. Within scope,
  parity is a property of shared metrics, not an aspiration.
- **Extensible without core edits (Principle II)**: four extension points (element *types* =
  codec + renderer, expression functions, data sources, paint backends) absorb new capability.
  An element *type* is a registered bundle so it is both *persistable* and *renderable* with
  zero core edits (see §6, §8).
- **Test-first & deterministic (Principle III)**: the two intermediate representations are
  also the test seams — most of the engine is verified as pure data transforms.
- **Platform-agnostic, headless core** — two distinct dependency boundaries, not one:
  - **(a) Flutter / `dart:ui` is confined to `CanvasPainter`** (the on-screen paint backend) —
    the boundary that actually matters for headlessness. `domain`, `data`, `expression`, and the
    `fill`/`layout`/`frame`/`text` parts of `rendering` never import Flutter; they use the
    domain's own geometry value types, never `dart:ui`'s `Size`/`Rect`/`Offset` or Flutter's
    `BoxConstraints`. So the measure→layout→frame path runs headless (server/CI/test) with no
    Flutter binding.
  - **(b) Pure-Dart third-party libs may live in rendering *infrastructure***, because they are
    themselves headless and deterministic: the `pdf`/`printing` backends (paint), the `barcode`
    package inside the **barcode renderer** (`rendering/elements/`), and the TTF/OTF parser
    behind the default `TextMeasurer` (`rendering/text/`). None pull in Flutter, so they don't
    compromise (a). The `domain`/`data`/`expression` seams take **no** rendering third-party
    deps at all (`intl` for formatting aside).

  (Barcode generation stays in its renderer, not "behind paint," on purpose: paint backends are
  element-agnostic — they know only primitives — so a barcode emits rect/image primitives like
  any other element. Pushing it into paint would re-couple backends to element types.)

## 4. Seam Map & Component Inventory

```
Designer UI            src/designer/        (exists; consumer; out of scope here)
  ▲ consumes
Public Facade          lib/jet_print.dart   JetReportEngine + minimal exports (single entry point)
  ▼
Rendering pipeline     src/rendering/
  • elements/   ElementRendererRegistry + ElementRenderer + built-ins (text/field, image, line/rect, barcode⊕)   ★ extension point
  • text/       TextMeasurer + FontRegistry (pure-Dart glyph metrics via TTF/OTF parsing⊕)   ◆ injected seam
  • fill/       Fill stage → FilledReport
  • layout/     Layout & pagination (measures via TextMeasurer) → List<PageFrame>
  • frame/      PageFrame primitive display list + FrameBuilder   (WYSIWYG contract; pure-Dart geometry types)
  • paint/      ReportPainter + CanvasPainter🔌, PdfPainter⊕, ImagePainter (paint with the same FontRegistry)   ★ extension point
  ▼
Expression engine      src/expression/      lexer · parser · AST · evaluator + function registry ★ · variable/aggregate calculator
  ▼
Data layer             src/data/            JetDataSource ★ + DataSet/DataRow + in-memory implementations
  ▼
Domain / Report Model  src/domain/          template · bands · element defs (+ UnknownElement) · styles · geometry value types ·
                                            params/variables/groups/bindings ·
                                            serialization/ (versioned JSON + migration + ElementCodecRegistry ★)
```

★ = extension point   ◆ = injected infrastructure seam (default impl shipped)   🔌 = imports Flutter / `dart:ui` (CanvasPainter only — the headless boundary)   ⊕ = uses a pure-Dart third-party lib (headless, no Flutter)

**Component responsibilities**

1. **Report Model** (`domain/`) — pure-Dart, serializable definition: `ReportTemplate`,
   `ReportBand` (title, page header/footer, column header/footer, group header/footer,
   detail, summary, background, no-data), element *definitions*, **pure-Dart geometry value
   types** (`JetSize`/`JetOffset`/`JetRect`/`JetEdgeInsets`/`JetConstraints` — never `dart:ui`),
   styles, `ReportParameter` / `ReportVariable` / `ReportGroup`, field & expression bindings.
   Includes **`UnknownElement`** — preserves the raw JSON of any element type not registered
   locally so templates round-trip losslessly (Principle V) and render a visible placeholder.
2. **Serialization** (`domain/serialization/`) — versioned JSON read/write, `schemaVersion`
   field, ordered migration framework. Consults an **`ElementCodecRegistry`** (pure-Dart,
   type-key → `toJson`/`fromJson`) so custom element *definitions* persist with zero core
   edits; unregistered types deserialize to `UnknownElement` and re-serialize unchanged.
3. **Data layer** (`data/`) — abstract `JetDataSource` → `DataSet` (row cursor) → `DataRow`,
   field metadata; in-memory implementations (`List<Map>`, JSON, object-list). Synchronous;
   fully resolved before layout.
4. **Expression engine** (`expression/`) — lexer/parser/AST compiling expressions like
   `$F{qty} * $F{price}`; evaluator resolving field/param/variable refs against a row;
   pluggable function registry (math/string/date/logic/format); variable & aggregate
   calculator (SUM/COUNT/AVG, running totals, group resets).
5. **Element renderers + registry** (`rendering/elements/`) — `ElementRenderer` interface
   (measure + emit primitives) and built-in renderers; `ElementRendererRegistry` maps element
   type-key → renderer. Paired with the domain-side `ElementCodecRegistry` (#2) through one
   public `registerElementType(...)` call so a custom element is both persistable *and*
   renderable.
6. **Text metrics & font seam** (`rendering/text/`) — `TextMeasurer` (interface, pure Dart)
   computing glyph advances, line breaking, ascent/descent, and wrapped-block size; default
   implementation parses TTF/OTF glyph metrics for **deterministic, platform-independent**
   measurement. `FontRegistry` holds the embedded font bytes. The layout stage measures text
   through this seam (as a positioned glyph run); **every paint backend draws those same
   positions with the same `FontRegistry`**, which is what makes cross-backend line breaks and
   heights identical within the **v1 Latin/LTR text scope** (§1, §3).
7. **Fill stage** (`rendering/fill/`) — single data pass: routes rows to band instances,
   evaluates element expressions, feeds the variable calculator → `FilledReport`.
8. **Layout / paginate** (`rendering/layout/`) — measures band instances (delegating element
   sizing to renderers, which measure text via the `TextMeasurer` seam), grows/stacks bands,
   applies keep-together & print-when, repeats page/group headers+footers, breaks pages,
   resolves deferred page-scoped expressions into pre-reserved fixed bounds (§5) →
   `List<PageFrame>`. Pure Dart (no `dart:ui`).
9. **Frame** (`rendering/frame/`) — `PageFrame` = a flat list of positioned **primitives**
   (text run, image, line, rect, path) using pure-Dart geometry types; `FrameBuilder` is the
   write-side used by renderers. The WYSIWYG contract between layout and paint. Each primitive
   carries the originating element id (for designer hit-testing).
10. **Paint backends** (`rendering/paint/`) — `ReportPainter` abstraction + `CanvasPainter`
    (`dart:ui`), `PdfPainter` (`pdf`), `ImagePainter` (PNG), each drawing with the shared
    `FontRegistry`. Native printing = `PdfPainter` + `printing`.
11. **Public facade** (`jet_print.dart`) — `JetReportEngine` orchestrating fill→layout→paint
    (injecting the `TextMeasurer`/`FontRegistry`), plus the minimal public exports.

## 5. Data-Flow Pipeline

```
Inputs: ReportTemplate (model) + JetDataSource + parameters map
   ▼
① Fill        open dataset; per row → route to band, evaluate expressions,
              feed variable/aggregate calculator (group resets, running totals). One data pass.
   ▼ produces
   ▶ FilledReport — ordered band INSTANCES with resolved values + frozen variable values.
                    No geometry. Pure data → snapshot-testable.
   ▼
② Layout/     measure each band instance (element sizing via renderers; text via TextMeasurer),
   Paginate   grow/stack bands, keep-together & print-when, repeat page/group headers+footers,
              break pages, then substitute deferred page-scoped exprs into pre-reserved bounds.
   ▼ produces
   ▶ List<PageFrame> — each page = flat list of positioned PRIMITIVES. Headless, deterministic.
   ▼
③ Paint       chosen ReportPainter walks primitives → Canvas (screen) · PDF · PNG · printer.
```

**Why two IRs.** `FilledReport` separates *data resolution* from *geometry*;
`PageFrame` separates *geometry* from *pixels*. This makes each stage a pure function with
inspectable inputs/outputs, and it is what makes WYSIWYG automatic — there is exactly one
`PageFrame` per page, and every backend paints it identically.

**Deferred (late-bound) evaluation — and why it stays layout-safe.** Page-scoped values
("Page 3 of 12", per-page running totals) are unknown during Fill because pagination has not
happened. Fill marks such expressions as unresolved placeholders in the `FilledReport`; the
layout stage substitutes them once page boundaries exist, immediately before emitting
primitives.

The hazard the naive version misses: if a late-bound value's *formatted text* could change an
element's width/height (e.g. "Page 1 of 9" → "Page 1 of 10" widening the run), substituting it
after measurement would feed back into pagination — a circular dependency that can oscillate.
The design closes this with an explicit **fixed-bounds rule**: deferred page-scoped expressions
are permitted **only in fixed-size (non-growing) elements within fixed-height bands** (page /
column header & footer). Such an element's box is sized *before* substitution, so the resolved
text is rendered within already-reserved bounds and **never reflows or repaginates**. If the
text overflows its reserved box, the element's overflow policy (auto-shrink / clip) applies plus
a diagnostic — pagination is never revisited. Model validation **rejects** a page-scoped
expression placed in an auto-growing element (error diagnostic), making the rule enforceable
rather than a convention. No second pass, no oscillation.

## 6. Extension Points (the four contracts)

Illustrative signatures (formalized per spec):

```dart
// 1 · Add an element TYPE = codec (persist) + renderer (draw), under one type-key.
//     Pure-Dart geometry types only (JetSize/JetRect/JetConstraints — never dart:ui).
abstract class ElementCodec<E extends ReportElement> {        // domain-side · pure Dart
  E fromJson(Map<String, Object?> json);
  Map<String, Object?> toJson(E element);
}
abstract class ElementRenderer<E extends ReportElement> {     // rendering-side
  JetSize measure(E el, MeasureContext ctx, JetConstraints c); // ctx exposes the TextMeasurer
  void emit(E el, FillContext ctx, JetRect bounds, FrameBuilder out);
}
registerElementType<QrElement>('qr', QrCodec(), QrRenderer()); // persistable AND renderable
// Unregistered type on load → UnknownElement{typeKey, rawJson} → re-serializes unchanged.

// 2 · Add outputs — implement over the same primitives; no element knows it exists.
abstract class ReportPainter {
  void beginPage(PageFormat f);
  void drawText(TextPrimitive p);
  void drawImage(ImagePrimitive p);
  void drawLine(LinePrimitive p);
  void drawRect(RectPrimitive p);
  void drawPath(PathPrimitive p);
  void endPage();
}

// 3 · Add data backends — implement a synchronous row cursor.
abstract class JetDataSource { DataSet open(Map<String, Object?> params); }
abstract class DataSet { bool moveNext(); Object? field(String name); List<FieldDef> get fields; }

// 4 · Add expression functions.
typedef ExprFn = Value Function(List<Value> args, EvalContext ctx);
functions.register('FORMAT', formatFn);
```

**Why this is cheap to extend.** `PageFrame` holds *primitives, not elements*. Layout turns
elements → primitives; paint turns primitives → pixels/PDF. A new element type (e.g. QR)
registers a `{codec, renderer}` pair: the codec lets it **persist and migrate** through JSON
(consulted by serialization), the renderer emits existing primitives — and the three paint
backends are untouched. A new output (e.g. SVG) just implements `ReportPainter` over the same
primitives — no element is touched. Two independent axes of growth, and an element added this
way is a *first-class persisted citizen*, not a code-only object. Templates authored with a
type this build doesn't know about survive round-trip via `UnknownElement` rather than being
dropped — the forward-compatibility Principle V requires.

## 7. Error Handling & Diagnostics

**Philosophy: render-don't-crash.** The engine collects non-fatal issues into a
`ReportDiagnostics` (info / warning / error) returned *alongside* output and renders visible
placeholders, so a report always produces something paintable (critical for a live designer
canvas). Only structural faults fail fast.

| Case | Behavior |
|---|---|
| Expression eval error | Paint `!ERR` token in element bounds + error diagnostic; continue |
| Missing / null field | Render blank (configurable default) + warning |
| Band / page overflow | Grow band → clip per element policy (`stretch`/`truncate`) → page break |
| Unknown element type on load | Deserialize to `UnknownElement` (raw JSON kept) → renders placeholder, re-serializes unchanged + warning |
| Page-scoped expr in an auto-growing element | **Rejected** at model validation (error diagnostic) — enforces the fixed-bounds rule (§5) |
| Late-bound value overflows reserved bounds | Auto-shrink / clip per element policy + warning; pagination never revisited |
| Missing font in `FontRegistry` / PDF backend | Substitute fallback font + warning (same fallback across backends to preserve parity) |
| Malformed JSON / bad schema | Throw typed `ReportFormatException` (structural — fail fast) |

## 8. Serialization & Versioning (Principle V)

- Human-inspectable **JSON** with an explicit `schemaVersion`.
- **`ElementCodecRegistry`** (pure-Dart, in `domain`): each element type registers a
  `type-key → {fromJson, toJson}` codec, so the serializer encodes/decodes built-in *and*
  custom element definitions with **zero core edits**. Registered jointly with the renderer
  via the single public `registerElementType(...)` (the renderer lives in `rendering`; the
  codec stays domain-pure, preserving the dependency direction).
- **`UnknownElement`** representation: an element whose `type-key` is not registered locally
  deserializes into `UnknownElement{typeKey, rawJson}`, which **re-serializes byte-for-byte**
  and renders a visible placeholder. This is what makes "preserve unknown content" real rather
  than aspirational — a template authored in a newer build (or by a plugin) is never silently
  truncated when opened in an older one.
- **Migration framework**: ordered `vN → vN+1` steps; older files load → migrate → current
  in-memory model.
- **SemVer** for the package *and* the report schema; a breaking schema change is a MAJOR
  event documented in `CHANGELOG.md` with a migration path.

## 9. Public API Surface (Principle I — minimal)

**Exported** (via `jet_print.dart`): model types (incl. pure-Dart geometry value types and
`UnknownElement`); `JetReportEngine` facade
(`fill`/`layout`/`paintPage`/`exportPdf`/`exportPng`/`printDocument`); `registerElementType(...)`
(binds an `ElementCodec` + `ElementRenderer` under a type-key) and the expression function
registry; `JetDataSource` + in-memory implementations; `FontRegistry` (register custom fonts);
`ReportPainter` + primitive types (read-side, so custom painters can consume frames); load/save
+ `ReportDiagnostics`.

**Private** (`src/`, never exported): lexer/parser internals, fill/layout internals, the default
`TextMeasurer` TTF-parsing implementation, `FrameBuilder` write internals.

## 10. Testing Strategy (Principles III + IV)

- **Unit (base)** — model invariants; serialization round-trip + version migration;
  `UnknownElement` byte-for-byte round-trip; page-scoped-expr-in-growing-element validation
  rejection; `TextMeasurer` glyph-advance / line-break / wrapped-size correctness against font
  fixtures; expression lexer/parser/evaluator incl. aggregates over fixtures; data-source
  iteration; per-element measure/emit; pagination rules (incl. fixed-bounds late substitution).
- **IR snapshot (middle)** — `FilledReport` and `PageFrame` snapshotted as data ("logic
  goldens"): fast, deterministic, the bulk of engine coverage.
- **Pixel goldens (top)** — the *same* model + data painted to Canvas / PDF / PNG asserted for
  **parity**; the data-aware **invoice** is the flagship golden. A dedicated **text-fidelity
  parity** golden uses **Latin/LTR (v1-scope)** prose long enough to wrap, asserting identical
  line breaks across backends — the direct check that the shared-metrics design holds.
  Complex-script parity is explicitly **not** covered in v1 (out of scope, §1); a failing
  placeholder/skipped test documents the boundary rather than implying coverage.
- **Contract / architecture** — extend the layer-boundary test (domain pure; `layout/`, `fill/`,
  `frame/`, `text/` have **no `dart:ui` / Flutter import**); a **persisted-extension test** adds
  a custom element type (`{codec, renderer}`) + custom function + custom data source entirely
  from test code, then asserts it **round-trips through JSON *and* renders** with **zero core
  edits**, proving Principle II for both persistence and rendering; determinism test (identical
  inputs → identical `PageFrame`).

## 11. Decomposition into Implementation Specs

Dependency-ordered; each independently testable and demonstrable. Note **006 depends only on
003**, so the paint/golden harness can come up early (painting hand-authored `PageFrame`
fixtures) and de-risk the visual path before Layout exists.

| Spec | Title | Seam(s) | Depends on | Key deliverable & tests |
|---|---|---|---|---|
| **003** | Report Model & Serialization | `domain/` | — | Full model + pure-Dart geometry value types + versioned JSON + migration + **`ElementCodecRegistry`** + **`UnknownElement`**; replaces `ReportDocument` stub. Tests: invariants, round-trip, migration, unknown-element round-trip |
| **004** | Data Layer | `data/` | 003 | `JetDataSource`/`DataSet`/`DataRow` + in-memory impls. Tests: iteration, field access |
| **005** | Expression Engine | `expression/` | 003, 004 | Lexer/parser/AST/evaluator + function registry + aggregate calculator. Tests: parse/eval tables, aggregates |
| **006** | Frame, Text-metrics & Paint backends | `rendering/frame`, `text/`, `paint/` | 003 | `PageFrame` + `FrameBuilder` + **`TextMeasurer`/`FontRegistry`** (default TTF parser) + `ReportPainter` + `CanvasPainter` (shared fonts). Tests: measurer metrics correctness, paint fixture frame → golden, text-parity golden |
| **007** | Element Types + Fill | `rendering/elements`, `fill/` | 003,004,005,006 | `ElementRenderer` + `registerElementType` (codec+renderer) + built-ins; Fill → `FilledReport`. Tests: measure/emit, fill snapshots, **persisted-extension test** (round-trip + render, zero core edits) |
| **008** | Layout & Pagination | `rendering/layout/` | 006, 007 | Band arrange/grow, page breaks, repeating headers, **fixed-bounds late substitution** of page-scoped exprs → `List<PageFrame>`. Tests: pagination snapshots, late-bound safety, determinism |
| **009** | Engine Facade + Export + Invoice (**MVP**) | `jet_print.dart`, `paint/` | 003–008 | `JetReportEngine` + PdfPainter/ImagePainter/printing (shared `FontRegistry`) + invoice end-to-end. Tests: cross-backend WYSIWYG parity |

**After 009 (separate track)**: wire the engine into the 002 designer shell — canvas paints
live `PageFrame`s, property editors mutate the model, drag-drop element creation.

## 12. New Dependencies (justified, minimal, permissive — Constitution Tech Standards)

- **`pdf`** — `PdfPainter` backend (PDF document generation). Maintained, permissive license.
- **`printing`** — native/OS printing built on the PDF output. Same ecosystem.
- **`barcode`** — barcode/QR geometry for the barcode element **renderer** (`rendering/elements/`,
  emits primitives or an image). Pure Dart (no Flutter), permissive. Lives in the renderer, not
  paint, so backends stay element-agnostic (§3 boundary b).
- **TTF/OTF metric parser** — behind the default `TextMeasurer` (`rendering/text/`). Pure Dart
  (no Flutter); may reuse the `pdf` package's font parser or a small dedicated reader.
- **`intl`** — already present; reused for number/date `FORMAT` functions.
- PNG export uses `dart:ui` (`Picture.toImage`) from the Canvas path; no extra dependency.

**Dependency boundary (precise):** Flutter / `dart:ui` is confined to `CanvasPainter` (§3
boundary a). The pure-Dart third-party libs above (`pdf`, `printing`, `barcode`, the TTF parser)
are headless and isolated behind their backend/renderer/measurer abstractions, so the
measure→layout→frame path stays platform-agnostic and every dependency is swappable. The
`domain`/`data`/`expression` seams carry no rendering third-party deps.

## 13. Constitution Alignment

| Principle | How this design complies |
|---|---|
| I — Library-First & Clean Public API | Minimal exports via single entry point; internals under `src/`; facade is the only orchestration surface |
| II — Layered & Extensible | Strict inward DAG (layer-boundary test); element types are persistable+renderable bundles (codec+renderer), unknown types survive via `UnknownElement` — extension covers both persistence and rendering with zero core edits |
| III — Test-First | Two IRs make most of the engine pure-data testable; TDD per stage; extension & determinism tests |
| IV — WYSIWYG | One headless layout → one `PageFrame` → many backends; cross-backend pixel goldens; invoice flagship |
| V — Versioned Serialization | JSON + `schemaVersion` + ordered migrations + SemVer for package and schema |
| VI — Documentation & DX | Public symbols carry dartdoc; runnable tester app; CHANGELOG per spec; zero-warning analyzer gate |

## 14. Open Questions / Future Work

- **Table/list element** vs detail-band repetition: invoices use the detail band; a dedicated
  in-band table element is deferred (extension point accommodates it).
- **Subreports & charts**: deferred; admitted by the element registry later.
- **Async/streaming data**: the `JetDataSource` contract is synchronous now; an async variant
  can be added without disturbing the synchronous path.
- **Font handling**: measurement strategy is settled (pure-Dart TTF/OTF metric parsing via the
  `TextMeasurer` seam; one shared `FontRegistry` across measure + all backends). The remaining
  open detail is PDF **subsetting** (embed only used glyphs to shrink output) — a 006/009
  optimization, not an architecture question.
- **Default-font provenance**: whether the library ships a bundled default font (predictable,
  license-checked, deterministic goldens) or requires the consumer to register one. Leaning
  bundled-default for first-run/test determinism; settle in 006.
- **Hit-testing / selection** for the designer canvas: resolved at the data level — each
  `PageFrame` primitive carries its originating element id (§4 #9), so the designer track can
  map a canvas point to a model element without a parallel structure. The interaction layer
  itself is built in the designer track.
- **CJK / complex-script shaping**: v1 is scoped to Latin / simple LTR text (§1 text-scope, §3
  parity guarantee). Full shaping (bidi, ligatures, combining marks, CJK) is a later enhancement
  that **extends** the same `TextMeasurer`/positioned-glyph-run mechanism to more scripts — and
  with it broadens the cross-backend parity guarantee — without re-architecting the pipeline.

## 15. Design-Review Resolutions

### Round 1 (rev. 2) — three findings, all accepted and folded into the sections above

1. **Flutter types in the "pure-Dart" core + missing text-metrics seam** *(blocker)*.
   `Size`/`Rect`/`Offset` (`dart:ui`) and `BoxConstraints` (Flutter) cannot live in a pure-Dart
   core, and text measurement was unspecified — which would make cross-backend parity
   unimplementable. **Resolution**: the core uses its own pure-Dart geometry value types; a new
   **`TextMeasurer` / `FontRegistry` seam** (§4 #6, deterministic TTF/OTF metric parsing) drives
   measurement, and **every paint backend draws with the same `FontRegistry`** so line breaks
   and heights match across screen/PDF/PNG (§3, §6, §10 text-parity golden).

2. **Deferred page-scoped expressions resolved too late** *(high)*. A late-bound value whose
   text affects element size (e.g. "Page 1 of 10") creates a circular layout dependency.
   **Resolution**: the **fixed-bounds rule** (§5) — page-scoped expressions are allowed only in
   fixed-size elements within fixed-height bands, substituted into pre-reserved bounds, never
   triggering reflow/repagination; model validation rejects violations (§7).

3. **Extensibility covered rendering but not persisted round-tripping** *(high)*. "Register a
   renderer" did not explain how custom element *definitions* load/save/migrate, contradicting
   the unknown-content-preservation and zero-core-edit claims. **Resolution**: an element *type*
   is now a **`{codec, renderer}` bundle** registered via `registerElementType` — the codec
   (domain-pure) persists it; an explicit **`UnknownElement`** preserves unregistered types
   byte-for-byte on round-trip (§2 model, §6, §8). Custom elements are first-class persisted
   content, confirming the reviewer's assumption rather than narrowing scope to code-only.

### Round 2 (rev. 3) — two "overclaim" findings (round-1 blockers confirmed resolved), both accepted

4. **Dependency-boundary claim internally inconsistent** *(medium)*. "Only paint backends import
   third-party libs" conflicted with the `barcode` package living in the barcode renderer (and
   the TTF parser in the text seam). **Resolution**: split the claim into two precise boundaries
   (§3, §4 legend, §12) — **Flutter/`dart:ui` confined to `CanvasPainter`** (the headless
   guarantee) vs. **pure-Dart third-party libs permitted in rendering infrastructure** (barcode
   renderer, TTF parser, pdf/printing) since they stay headless. Chose this over moving barcode
   "behind paint," which would re-couple element-agnostic paint backends to element types.

5. **Text-parity guarantee broader than supported script scope** *(medium)*. The blanket
   "identical wrapping across backends" claim held only for Latin while complex-script shaping
   was deferred. **Resolution**: scope the v1 guarantee explicitly to **Latin / simple LTR**
   text (§1 text-scope, §3, §10), and state the exact mechanism (backends paint the measurer's
   positioned glyph run, no re-shape). Complex-script shaping (§14) extends the same mechanism
   and broadens the guarantee later — additive, not a re-architecture.
