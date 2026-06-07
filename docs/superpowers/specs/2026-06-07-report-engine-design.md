# Report Engine — Architecture Design

**Date**: 2026-06-07
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
extension points are designed to admit them later without core changes).

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
  canvas, PDF, PNG, and print cannot diverge.
- **Extensible without core edits (Principle II)**: four extension points (element renderers,
  expression functions, data sources, paint backends) absorb new capability.
- **Test-first & deterministic (Principle III)**: the two intermediate representations are
  also the test seams — most of the engine is verified as pure data transforms.
- **Platform-agnostic core**: only the paint backends import Flutter (`dart:ui`) or
  third-party libs (`pdf`, `printing`, `barcode`); `domain`, `data`, `expression`, and the
  `fill`/`layout`/`frame` parts of `rendering` are pure Dart.

## 4. Seam Map & Component Inventory

```
Designer UI            src/designer/        (exists; consumer; out of scope here)
  ▲ consumes
Public Facade          lib/jet_print.dart   JetReportEngine + minimal exports (single entry point)
  ▼
Rendering pipeline     src/rendering/
  • elements/   ElementRegistry + ElementRenderer + built-ins (text/field, image, line/rect, barcode)   ★ extension point
  • fill/       Fill stage → FilledReport
  • layout/     Layout & pagination → List<PageFrame>
  • frame/      PageFrame primitive display list + FrameBuilder   (WYSIWYG contract)
  • paint/      ReportPainter + CanvasPainter, PdfPainter, ImagePainter   ★ extension point · 🔌 Flutter/3rd-party
  ▼
Expression engine      src/expression/      lexer · parser · AST · evaluator + function registry ★ · variable/aggregate calculator
  ▼
Data layer             src/data/            JetDataSource ★ + DataSet/DataRow + in-memory implementations
  ▼
Domain / Report Model  src/domain/          template · bands · element defs · styles · geometry/page model ·
                                            params/variables/groups/bindings · serialization/ (versioned JSON + migration)
```

★ = extension point   🔌 = only place importing Flutter / third-party libraries

**Component responsibilities**

1. **Report Model** (`domain/`) — pure-Dart, serializable definition: `ReportTemplate`,
   `ReportBand` (title, page header/footer, column header/footer, group header/footer,
   detail, summary, background, no-data), element *definitions*, styles, geometry/page model,
   `ReportParameter` / `ReportVariable` / `ReportGroup`, field & expression bindings.
2. **Serialization** (`domain/serialization/`) — versioned JSON read/write, `schemaVersion`
   field, ordered migration framework, round-trip preservation of unknown content.
3. **Data layer** (`data/`) — abstract `JetDataSource` → `DataSet` (row cursor) → `DataRow`,
   field metadata; in-memory implementations (`List<Map>`, JSON, object-list). Synchronous;
   fully resolved before layout.
4. **Expression engine** (`expression/`) — lexer/parser/AST compiling expressions like
   `$F{qty} * $F{price}`; evaluator resolving field/param/variable refs against a row;
   pluggable function registry (math/string/date/logic/format); variable & aggregate
   calculator (SUM/COUNT/AVG, running totals, group resets).
5. **Element registry + renderers** (`rendering/elements/`) — `ElementRenderer` interface
   (measure + emit primitives) and built-in renderers; `ElementRegistry` maps element type →
   renderer.
6. **Fill stage** (`rendering/fill/`) — single data pass: routes rows to band instances,
   evaluates element expressions, feeds the variable calculator → `FilledReport`.
7. **Layout / paginate** (`rendering/layout/`) — measures band instances (delegating element
   sizing to renderers), grows/stacks bands, applies keep-together & print-when, repeats
   page/group headers+footers, breaks pages, resolves deferred page-scoped expressions →
   `List<PageFrame>`.
8. **Frame** (`rendering/frame/`) — `PageFrame` = a flat list of positioned **primitives**
   (text run, image, line, rect, path); `FrameBuilder` is the write-side used by renderers.
   This is the WYSIWYG contract between layout and paint.
9. **Paint backends** (`rendering/paint/`) — `ReportPainter` abstraction + `CanvasPainter`
   (`dart:ui`), `PdfPainter` (`pdf`), `ImagePainter` (PNG). Native printing = `PdfPainter` +
   `printing`.
10. **Public facade** (`jet_print.dart`) — `JetReportEngine` orchestrating fill→layout→paint,
    plus the minimal public exports.

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
② Layout/     measure each band instance (element sizing via renderers), grow/stack bands,
   Paginate   keep-together & print-when, repeat page/group headers+footers, break pages,
              resolve deferred page-scoped exprs (page N of M, page totals).
   ▼ produces
   ▶ List<PageFrame> — each page = flat list of positioned PRIMITIVES. Headless, deterministic.
   ▼
③ Paint       chosen ReportPainter walks primitives → Canvas (screen) · PDF · PNG · printer.
```

**Why two IRs.** `FilledReport` separates *data resolution* from *geometry*;
`PageFrame` separates *geometry* from *pixels*. This makes each stage a pure function with
inspectable inputs/outputs, and it is what makes WYSIWYG automatic — there is exactly one
`PageFrame` per page, and every backend paints it identically.

**Deferred (late-bound) evaluation.** Page-scoped values ("Page 3 of 12", per-page running
totals) are unknown during Fill because pagination has not happened. Fill marks such
expressions as unresolved placeholders in the `FilledReport`; the layout stage resolves them
once page boundaries exist, immediately before emitting primitives. This is a designed-in
capability, not a second-pass retrofit.

## 6. Extension Points (the four contracts)

Illustrative signatures (formalized per spec):

```dart
// 1 · Add element types — register a renderer; paint backends never change.
abstract class ElementRenderer<E extends ReportElement> {
  Size measure(E el, FillContext ctx, BoxConstraints c);
  void emit(E el, FillContext ctx, Rect bounds, FrameBuilder out);
}
registry.register<QrElement>(QrRenderer());

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
elements → primitives; paint turns primitives → pixels/PDF. A new element type (e.g. QR) just
registers a renderer that emits existing primitives — the three paint backends are untouched.
A new output (e.g. SVG) just implements `ReportPainter` over the same primitives — no element
is touched. Two independent axes of growth.

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
| Unknown element type on load | Preserve raw JSON + warning (forward-compatible round-trip) |
| Missing font in PDF backend | Substitute fallback font + warning |
| Malformed JSON / bad schema | Throw typed `ReportFormatException` (structural — fail fast) |

## 8. Serialization & Versioning (Principle V)

- Human-inspectable **JSON** with an explicit `schemaVersion`.
- **Migration framework**: ordered `vN → vN+1` steps; older files load → migrate → current
  in-memory model.
- Unknown fields/elements **preserved** on round-trip where possible.
- **SemVer** for the package *and* the report schema; a breaking schema change is a MAJOR
  event documented in `CHANGELOG.md` with a migration path.

## 9. Public API Surface (Principle I — minimal)

**Exported** (via `jet_print.dart`): model types; `JetReportEngine` facade
(`fill`/`layout`/`paintPage`/`exportPdf`/`exportPng`/`printDocument`); `ElementRegistry` and
the function registry (to register custom element types/functions); `JetDataSource` +
in-memory implementations; `ReportPainter` + primitive types (read-side, so custom painters
can consume frames); load/save + `ReportDiagnostics`.

**Private** (`src/`, never exported): lexer/parser internals, fill/layout internals,
`FrameBuilder` write internals.

## 10. Testing Strategy (Principles III + IV)

- **Unit (base)** — model invariants; serialization round-trip + version migration; expression
  lexer/parser/evaluator incl. aggregates over fixtures; data-source iteration; per-element
  measure/emit; pagination rules.
- **IR snapshot (middle)** — `FilledReport` and `PageFrame` snapshotted as data ("logic
  goldens"): fast, deterministic, the bulk of engine coverage.
- **Pixel goldens (top)** — the *same* model + data painted to Canvas / PDF / PNG asserted for
  **parity**; the data-aware **invoice** is the flagship golden.
- **Contract / architecture** — extend the layer-boundary test (domain pure; `layout/` has no
  Flutter import); an **extension test** adds a custom element + custom function + custom
  data source entirely from test code with **zero core edits**, proving Principle II;
  determinism test (identical inputs → identical `PageFrame`).

## 11. Decomposition into Implementation Specs

Dependency-ordered; each independently testable and demonstrable. Note **006 depends only on
003**, so the paint/golden harness can come up early (painting hand-authored `PageFrame`
fixtures) and de-risk the visual path before Layout exists.

| Spec | Title | Seam(s) | Depends on | Key deliverable & tests |
|---|---|---|---|---|
| **003** | Report Model & Serialization | `domain/` | — | Full model + versioned JSON + migration; replaces `ReportDocument` stub. Tests: invariants, round-trip, migration |
| **004** | Data Layer | `data/` | 003 | `JetDataSource`/`DataSet`/`DataRow` + in-memory impls. Tests: iteration, field access |
| **005** | Expression Engine | `expression/` | 003, 004 | Lexer/parser/AST/evaluator + function registry + aggregate calculator. Tests: parse/eval tables, aggregates |
| **006** | Frame & Paint backends | `rendering/frame`, `paint/` | 003 | `PageFrame` + `FrameBuilder` + `ReportPainter` + `CanvasPainter`. Tests: paint fixture frame → golden |
| **007** | Element Renderers + Fill | `rendering/elements`, `fill/` | 003,004,005,006 | `ElementRenderer`/registry + built-ins; Fill → `FilledReport`. Tests: measure/emit, fill snapshots |
| **008** | Layout & Pagination | `rendering/layout/` | 006, 007 | Band arrange/grow, page breaks, repeating headers, deferred page exprs → `List<PageFrame>`. Tests: pagination snapshots, determinism |
| **009** | Engine Facade + Export + Invoice (**MVP**) | `jet_print.dart`, `paint/` | 003–008 | `JetReportEngine` + PdfPainter/ImagePainter/printing + invoice end-to-end. Tests: cross-backend WYSIWYG parity |

**After 009 (separate track)**: wire the engine into the 002 designer shell — canvas paints
live `PageFrame`s, property editors mutate the model, drag-drop element creation.

## 12. New Dependencies (justified, minimal, permissive — Constitution Tech Standards)

- **`pdf`** — `PdfPainter` backend (PDF document generation). Maintained, permissive license.
- **`printing`** — native/OS printing built on the PDF output. Same ecosystem.
- **`barcode`** — barcode/QR generation for the barcode element renderer (emits primitives or
  an image). Permissive.
- **`intl`** — already present; reused for number/date `FORMAT` functions.
- PNG export uses `dart:ui` (`Picture.toImage`) from the Canvas path; no extra dependency.

Each is isolated behind the relevant backend/renderer abstraction so the engine core stays
platform-agnostic and the dependencies are swappable.

## 13. Constitution Alignment

| Principle | How this design complies |
|---|---|
| I — Library-First & Clean Public API | Minimal exports via single entry point; internals under `src/`; facade is the only orchestration surface |
| II — Layered & Extensible | Strict inward DAG (layer-boundary test); four extension points add capability without core edits |
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
- **Font embedding/subsetting** strategy for the PDF backend: detail to settle in 006/009.
- **Hit-testing / selection** on `PageFrame` for the designer canvas: defined in the designer
  track, but `PageFrame` should carry element-id back-references to enable it.
