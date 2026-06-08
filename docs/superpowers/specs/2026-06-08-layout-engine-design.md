# Spec 008a — Layout engine (measure, grow, paginate; repeating page chrome → `List<PageFrame>`)

**Status:** design approved (forks settled; one pre-write review round folded in, §12).
**Depends on:** 006 (`PageFrame`/`FrameBuilder` + `TextMeasurer`/`FontRegistry`) and 007a
(`ElementRenderer` measure/emit), both merged to `main`; consumes the 007b/007c `FilledReport`
stream. Drives existing seams — introduces no new extension point.
**Layer:** `rendering/layout/` (a new headless directory: `domain` + `rendering` only; no `dart:ui`,
no Flutter, no expression engine).

---

## §1 — Purpose & the 008 decomposition

008 (Layout) transforms a resolved report into a paintable display list:
`(ReportTemplate, FilledReport) → List<PageFrame>`. The blueprint's 008 bundles band measurement,
band growth, vertical stacking, page-breaking, repeating page **and** group/column chrome,
keep-together, print-when, background watermarks, and "Page N of M" late-binding — too much for one
plan. Following the 007 → 007a/007b/007c precedent, 008 is sliced into three independently-shippable
specs, each producing a testable `PageFrame` golden on its own:

| Spec | Scope | Unit |
|---|---|---|
| **008a (this spec)** | Measure body bands, grow them to fit, stack vertically, break pages, repeat `pageHeader`/`pageFooter` on every page, emit one `PageFrame` per page. | The core layout algorithm for the linear case — the invoice spine. |
| **008b** | `groupHeader` repeat-on-page-break, `keep-together`, `print-when`, `background`, columns, title-on-own-page. | Flow directives layered on the spine. |
| **008c** | "Page N of M" / per-page values: late substitution of page-scoped exprs within fixed bounds (two-phase `PAGE_COUNT`). | Self-contained late-binding with its own fixed-bounds invariant. |

008a is the consumer the 006/007a seams were built for: `PageFrame`/`FrameBuilder` (006) is the
output IR, `ElementRenderer.measure/emit` (007a) is the per-element contract whose `measure`
docstring already reserves `JetConstraints` *"for 008."* This spec drives those contracts; it does
not invent new ones.

## §2 — Scope

**In scope:**
- A pure `ReportLayouter.layout(template, filled) → LayoutResult{ List<PageFrame> pages; ReportDiagnostics diagnostics }`.
- **Band measurement + grow-only growth** of body bands via `ElementRenderer.measure`.
- **Vertical stacking** of body bands in the per-page body region; **page break** on overflow.
- **Repeating page chrome:** `pageHeader` at the top, `pageFooter` anchored to the bottom, on every page.
- **Primitive emission** via `ElementRenderer.emit` into one `FrameBuilder` per page.

**Out of scope (later specs):**
- `groupHeader` repeat after a page break, `keep-together`/orphan control, `print-when`,
  `background` watermark, multi-column flow (`columnHeader`/`columnFooter`), title-on-own-page — all
  **008b**.
- **Page-scoped substitution** ("Page N of M", per-page running totals) within fixed bounds —
  **008c**. This is the *only* late chrome resolution the `(template, filled)` input can support
  unaided: `PAGE_NUMBER`/`PAGE_COUNT` are derivable from layout state (loop position, page count).
  **Broader chrome expression evaluation** — `$P{}` params, `NOW()`, field refs — is **not promised
  by 008c**: it needs a params/eval channel the current API does not carry (the runtime `params` map
  lives only in the Fill call and is absent from `FilledReport`), so it is an **explicit open
  question for 008c's own design** (§10 #2), not a commitment of this spec.
- Any domain/serialization change. 008a adds **no** element overflow-policy field, **no** band
  directive fields (see §10 #1).

**The input split (the crux).** Body band *instances* come from `filled.bands` — already resolved by
Fill (`title`/`groupHeader`/`detail`/`groupFooter`/`summary`/`noData`), each carrying resolved
elements + a frozen variable snapshot. Page-chrome band *definitions* come from `template.bands`
(`pageHeader`/`pageFooter`) — **not** in the `FilledReport` stream, because they repeat per page,
which is a layout-time decision. So **Layout owns chrome element handling**, and `template.page` is
authoritative for the page format (fill-design §10.7: *"the template for page chrome + page format,
the FilledReport for resolved content + frozen variable snapshots"*).

## §3 — Architecture & data flow

```
ReportTemplate ─┐                                  ┌─► List<PageFrame>    (one per page)
                ├─► ReportLayouter.layout(...) ─────┤
FilledReport   ─┘                                  └─► ReportDiagnostics  (non-fatal issues)
```

Pure and deterministic: identical `(template, filled)` → identical `List<PageFrame>` and the same
diagnostics (Constitution III/IV; pinned by a determinism test that compares frames by value and
diagnostics by a normalized projection, §9). All measurement is a side-effect-free function of
`(element, TextMeasurer)`; pagination is a deterministic walk over pre-measured band heights.

## §4 — Public API & renderer wiring

`ReportLayouter` mirrors `ReportFiller`: a small class with injectable dependencies that default to
the built-ins, and a single `layout(...)` entry point returning output + diagnostics. `LayoutResult`
co-locates in `report_layouter.dart` exactly as `FillResult` co-locates in `report_filler.dart`.

```dart
class LayoutResult {
  const LayoutResult({required this.pages, required this.diagnostics});
  final List<PageFrame> pages;
  final ReportDiagnostics diagnostics;
}

class ReportLayouter {
  ReportLayouter({ElementRendererRegistry? renderers, TextMeasurer? measurer})
      : _renderers = renderers ?? _defaultRenderers(),
        _measurer = measurer ?? MetricsTextMeasurer(FontRegistry()..registerDefault());

  LayoutResult layout(ReportTemplate template, FilledReport filled);

  // Built-ins flow through the canonical PAIRED registration path, then expose the
  // renderer half — the layouter's dependency stays renderer-only (like ReportFiller's
  // JetFunctionRegistry), but default registration is not re-implemented.
  static ElementRendererRegistry _defaultRenderers() {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    return reg.renderers;
  }
}
```

- **Renderer dispatch** is `_renderers.rendererFor(element)` → the registered `ElementRenderer`, or
  the built-in Unknown-placeholder renderer when none is registered (007a; no new code for unknown
  types).
- **`RenderContext`** is built once (`RenderContext(measurer: _measurer)`) and reused for every
  `measure`/`emit` call in the pass.
- The 011 facade injects its shared instances later (`typeRegistry.renderers`, the shared measurer);
  the narrow renderer-only param keeps that wiring honest.

## §5 — Band measurement & grow-only growth

Body-band measurement is a **pure** unit, `BandMeasurer`, separate from pagination — the measurement
rule (the part most worth scrutinizing) earns its own test file, the way 007c isolated
`group_band_index.dart`. It is computed **once per body band**, independent of page position, and its
result feeds both the break decision (band height) and emission (element boxes), so nothing is
measured twice.

```dart
/// One band measured to its grown height, with each element's grown, band-local box.
class MeasuredBand {
  const MeasuredBand(this.height, this.elements);
  final double height;                                          // >= band.height
  final List<({ReportElement element, JetRect bounds})> elements; // band-local boxes
}

class BandMeasurer {
  BandMeasurer(this._renderers, this._ctx);
  MeasuredBand measure(FilledBand band); // body bands are FilledBands (designed height + resolved elements)
}
```

**The rule (grow-only, height-only):**
- For each element `el`: `natural = rendererFor(el).measure(el, ctx, JetConstraints(maxWidth: el.bounds.width))`.
  The renderer wraps at `el.bounds.width` and grows in height only (the text renderer's documented
  invariant), so `natural.width` is ignored — the element's **width stays authored**.
- Each element's grown band-local box: `JetRect(el.bounds.x, el.bounds.y, el.bounds.width,
  max(el.bounds.height, natural.height))` — **grow-only**: an element never shrinks below its
  authored height, only stretches when its content needs more room.
- Band height: `max(band.height, maxₑ (el.bounds.y + grownHeight(el)))`. A band with no elements is
  its designed height.

**No intra-band reflow.** A growing element does **not** push its siblings down — they stay at their
authored `y`. Per the blueprint's *"banded + absolute-in-band, no flow/reflow solver,"* band growth
is a pure `max()` over element bottoms, not a constraint solver. This is what keeps layout
deterministic and headless.

## §6 — The pagination algorithm

### Geometry setup (`page = template.page`)

```
left=margins.left   top=margins.top   bottom=page.height-margins.bottom
headers = template.bands where type==pageHeader   (document order)
footers = template.bands where type==pageFooter
headerHeight = Σ header.height        footerHeight = Σ footer.height   (chrome is FIXED height — §7)
bodyTop = top + headerHeight          bodyBottom = bottom - footerHeight
bodyCapacity = bodyBottom - bodyTop
```

**Chrome-overcommit guard (computed before any band is measured).** `bodyCapacity` can be ≤ 0 when
the page chrome alone meets or exceeds the printable height (`headerHeight + footerHeight ≥
contentHeight`). That is a **root-cause** condition, not a per-band one: the header and footer
regions overlap and there is no body room at all. The layouter detects it up front and emits **one
warning** naming the cause —

```
if bodyCapacity <= 0:
    diagnostics.warning('page chrome (header ${headerHeight} + footer ${footerHeight}) '
        'leaves no room for body on a ${contentHeight}-pt printable height; chrome overlaps and '
        'body bands overflow')
```

— then proceeds (render-don't-crash): chrome is still emitted (and may overlap), and each body band
is placed at `bodyTop` overflowing downward. When `bodyCapacity ≤ 0` the **per-band** capacity
warning below is **suppressed** (it would just restate the symptom with a misleading negative number;
the upfront warning is the real signal).

### Held builders + body loop + chrome post-pass (the 008c seam)

The layouter accumulates **one `FrameBuilder` per page**, places **body** bands during the
pagination loop, and emits **chrome** in a **post-pagination pass** once the full page set exists —
building `PageFrame`s only at the very end. This ordering is deliberate: it is the insertion point
008c needs (see §10 #3).

```
measured  = [BandMeasurer.measure(b) for b in filled.bands]     // pure, once
pages     = [FrameBuilder(page)]                                // always >= 1 page
cursorY   = bodyTop

for mb in measured:                                             // 1. body pagination
    if cursorY + mb.height > bodyBottom && cursorY > bodyTop:
        pages.add(FrameBuilder(page)); cursorY = bodyTop        //    page break
    if bodyCapacity > 0 && mb.height > bodyCapacity:           //    suppressed when chrome overcommits
        diagnostics.warning('band height ${mb.height} exceeds body capacity ${bodyCapacity}; content overflows')
    for e in mb.elements:                                       //    translate band-local -> page
        rendererFor(e.element).emit(e.element, ctx,
            JetRect(left + e.bounds.x, cursorY + e.bounds.y, e.bounds.width, e.bounds.height), pages.last)
    cursorY += mb.height

for fb in pages:                                                // 2. chrome post-pass
    y = top;        for h in headers: placeChrome(h, y, fb); y += h.height
    y = bodyBottom; for f in footers: placeChrome(f, y, fb); y += f.height

return LayoutResult(pages: [fb.build() for fb in pages], diagnostics)
```

- **`placeChrome(band, topY, fb)`** emits each element at its **authored** band-local box translated
  to the page (`left+x`, `topY+y`, authored width/height) — **no growth** (chrome is fixed-height,
  §7). It does **not** re-run the unresolved-binding scan; that scan runs once during setup (§7).
- **Break rule:** a band that does not fit the remaining body height moves to a fresh page — *unless*
  the current page is already empty (`cursorY == bodyTop`), in which case it stays to avoid an
  infinite blank-page loop.
- **Atomic bands (no flow solver):** a band taller than `bodyCapacity` is placed at `bodyTop` and
  overflows past `bodyBottom` (into the footer region / bottom margin) with a **warning**; pagination
  is never revisited. Splitting a band across pages is explicitly out of scope (blueprint:
  *"deterministic band-arranger; no general flow/reflow solver"*).
- **≥1 page invariant:** the first builder is created before the loop, so even an empty body (e.g. a
  zero-band stream) yields one chrome-decorated page; the chrome post-pass always has a target, and
  008c's `PAGE_COUNT = pages.length` is always ≥ 1.

### Z-order via emission order

Body primitives land in each builder **before** chrome primitives, so chrome paints on top. That is
correct here because the header/footer regions never overlap the body region — and it is exactly the
hook 008b's `background` needs: a watermark must paint *first*, so it will prepend at page-open while
header/footer keep appending in this post-pass. **Emission order encodes z-order.**

## §7 — Page-chrome resolution (008a behavior, explicit)

008a emits chrome through the **same renderers** as body, but against the **authored** template
elements — **no expression engine enters Layout**, **no image byte-resolution**. To keep this
behavior *specified* rather than emergent, the layouter **scans chrome elements once during setup**
(a single pass over `headers`+`footers`, not inside `placeChrome`, so each is flagged **once**, never
per-page) and records one **info** diagnostic per element that carries a binding it cannot render
dynamically. The diagnostic names the element id and states the binding was **not evaluated in the
static layout pass** — it deliberately does **not** promise a specific later stage, because the
owners differ by binding kind and that ownership is cross-spec (below), not 008a's to assert
per-element:

| Chrome element form | 008a render | Diagnostic | Who could resolve it later |
|---|---|---|---|
| Static `TextElement` (no `expression`) | its literal `text` | — | — |
| `TextElement` with `expression != null` | its **authored literal `text`** (not evaluated) | **info** | **page-scoped** refs (`PAGE_NUMBER`/`PAGE_COUNT`) → 008c; other exprs (`$P{}`/`NOW()`/fields) → open (needs a params channel, §2/§10 #2) |
| `ImageElement` with `BytesImageSource` | the image | — | — |
| `ImageElement` with `FieldImageSource` | the **placeholder** (`emit` → `emitPlaceholder`) | **info** | field images are row-bound (007b Fill); page chrome has **no row**, so this is effectively unresolvable in chrome — *not* an 008c concern |
| `ImageElement` with `UrlImageSource` | the **placeholder** | **info** | a later **async paint-prep** step (its own future spec), per the 007a renderer-design — *not* 008c |
| Shape / barcode / other static | rendered normally | — | — |

So text shows its literal and a non-bytes image shows the placeholder — both flagged identically and
once. The key correction over the first draft: the diagnostic no longer claims "resolved in 008c."
Only **page-scoped text** is 008c's to substitute (within the fixed bounds §6 reserves); URL images
belong to async paint-prep, field images to Fill (and are meaningless without a row), and arbitrary
param/date text is an open question (§2). 008a promises none of these per-element — it renders
deterministically and flags the gap.

## §8 — Diagnostics & error policy (render-don't-crash; reuses `ReportDiagnostics`)

| Condition | Severity | Behavior |
|---|---|---|
| Page chrome ≥ printable height (`bodyCapacity ≤ 0`) | **warning** | **one** upfront root-cause warning (§6); proceed — chrome may overlap, body bands overflow; per-band capacity warnings suppressed |
| Body band taller than `bodyCapacity` (when `bodyCapacity > 0`) | **warning** | place at `bodyTop`, overflow, continue (no flow solver) |
| Unresolved chrome binding (expr / non-bytes image) | **info** | render renderer's natural output (literal / placeholder); one per element (§7); does **not** name a later owner |
| `filled.page != template.page` | **warning** | use `template.page` (authoritative, §2); continue |
| `columnHeader`/`columnFooter`/`background` present in `template.bands` | **info** | ignored in 008a (arrives in 008b); one per type |
| Unknown element type | (none) | `rendererFor` → Unknown placeholder renderer (007a; no new code) |

There is **no** 008a-specific structural fail-fast: a malformed template already threw
`ReportFormatException` at decode (serialization) or fill (007c duplicate-group-name). 008a is a pure
geometry pass over an already-validated, already-resolved input — every issue it can encounter is
recoverable and produces something paintable.

## §9 — Testing (TDD; data goldens)

**`band_measurer_test.dart`** (heights — the growth rule in isolation):
- No elements → designed height.
- Element shorter than its box → designed height (grow-only never shrinks).
- Tall wrapped text → band grows to that element's bottom; element box height = measured height,
  width = authored width.
- Multiple elements → band height = max element bottom.
- Element below others grows → band grows; siblings keep their authored `y` (no reflow).

**`report_layouter_test.dart`** (`PageFrame` goldens — breaks & coordinates):
- Single page: all bands fit → one `PageFrame`; element page-coords = `(left+x, cursorY+y)`.
- Overflow → two pages; the band that doesn't fit starts page 2 at `bodyTop`.
- `pageHeader` repeated at `top` on every page; `pageFooter` anchored at `bodyBottom` on every page.
- Multiple header/footer bands stack in document order.
- Band taller than `bodyCapacity` → placed at `bodyTop`, overflows, **warning** emitted.
- **Chrome overcommit** (`headerHeight + footerHeight ≥ contentHeight`) → **one** upfront warning;
  per-band capacity warnings suppressed; frames still produced.
- `noData` stream → one page (header + noData + footer).
- **Determinism:** two `layout(...)` runs on identical inputs produce equal `List<PageFrame>`
  (`PageFrame`/`FramePrimitive` have value equality) **and** equal diagnostics compared as a
  **normalized projection** — `diagnostics.entries.map((d) => (d.severity, d.message, d.elementId))`
  — because `Diagnostic`/`ReportDiagnostics` are plain mutable classes with **no** value equality, so
  a direct `==` would compare by identity and always fail (the comparison is on the projected tuples,
  not the objects).
- Chrome authored content: a chrome `TextElement` with an `expression` emits its **literal** + an
  **info** diagnostic; an unresolved chrome image (`Field`/`Url` source) emits the **placeholder** +
  an **info** diagnostic (one each, not per page); the diagnostic text does **not** name a later
  resolver stage.
- `columnHeader`/`columnFooter`/`background` present → ignored + **info**.
- Empty stream (zero bands) → exactly one chrome-only page (the ≥1-page invariant).
- `filled.page != template.page` → **warning**; the produced frames use `template.page`.

**Architecture:** extend the layer-boundary test so `rendering/layout/` imports stay within `domain`
+ `rendering` (no `dart:ui`, no `package:flutter`, no `expression/`).

## §10 — Design decisions

1. **Uniform grow-only growth; no domain change.** Every body element grows in height to its natural
   measured size; the band grows to the tallest element bottom. A per-element fixed/clip opt-out (an
   overflow-policy enum) and band directives (`keep-together`/`print-when`) are **not** added in 008a
   — they are 008b's domain surface. 008a stays entirely within `rendering/layout/` with zero
   domain/serialization churn. *Rationale:* the safe default is "never clip data"; the opt-out is a
   refinement, and adding the enum (field + codec + schema + `==`/`hashCode`) now would widen 008a
   into the domain layer for a feature 008b owns.

2. **008a is a pure geometry engine — no expression engine.** Chrome elements emit as authored; 008a
   depends only on the renderer + measurer seams, not on `expression/`. The interim cost (a
   `$P{title}` header shows its authored literal) is transient and explicitly diagnosed (§7).
   **Scope of later chrome resolution (corrected from the first draft, which over-promised "all
   dynamic chrome → 008c"):** the `(template, filled)` input supports only **page-scoped**
   substitution unaided — `PAGE_NUMBER`/`PAGE_COUNT` come from layout state — and that is 008c's
   charter. **Broader chrome expression evaluation is an open question, not a commitment:** `$P{}`
   needs the runtime `params` map, which lives only in the `ReportFiller.fill(...)` call and is
   **absent from `FilledReport`**; `NOW()`/field refs likewise have no carrier in the current API.
   Supporting them would require **widening the layout API** (e.g. `layout(template, filled, {params})`)
   or the IR — a decision deferred to 008c's own design so 008a carries no unused channel (YAGNI).
   (Image bindings are a *different* axis again: `UrlImageSource` → async paint-prep, `FieldImageSource`
   → Fill and meaningless without a row — see §7.)

3. **Held builders + post-pagination chrome pass is the 008c substitution seam.** `PageFrame`/
   `FramePrimitive` carry only resolved primitives — no authored elements, no placeholders — so if
   008a collapsed pagination and frame-emission into one incremental step, 008c would have **no clean
   place** to substitute `PAGE_COUNT` (unknown until every page exists) without re-running layout or
   rewriting primitives. By holding one `FrameBuilder` per page and emitting chrome in a post-pass
   that runs *after* pagination but *before* `fb.build()`, 008a already has the seam: in 008a that
   pass emits authored chrome; in 008c the **same** pass evaluates page-scoped exprs (`PAGE_COUNT =
   pages.length`, now known) and emits resolved chrome. No new intermediate IR, no second layout
   pass, no primitive post-processing — substitution stays "inside layout, before `List<PageFrame>`"
   exactly as the blueprint requires. *(Rejected alternative: stop 008a at a pre-frame pagination IR.
   It also gives 008c a hook, but invents a whole intermediate type and its tests — YAGNI when the
   held-builders post-pass already provides the seam.)*

4. **Chrome is fixed-height (no growth).** `headerHeight`/`footerHeight` use the bands' designed
   heights and chrome elements emit at authored bounds. This both keeps the body region a stable
   rectangle per page **and** preserves the fixed-bounds invariant 008c's late substitution depends
   on (a page-scoped value must land in a box sized *before* substitution, so it can never reflow or
   repaginate).

5. **`template.page` is authoritative for the page format** (fill-design §10.7). `filled.page` is a
   by-construction copy from `ReportFiller`; if a hand-built `FilledReport` disagrees, the layouter
   warns and proceeds with `template.page` rather than silently trusting the derived copy.

6. **Atomic bands; no flow solver.** A band taller than a whole page body overflows with a warning
   rather than being split. Band-splitting (and the keep-together/orphan controls that make splitting
   tolerable) is deliberately deferred — 008a establishes the deterministic band-arranger the
   blueprint specifies.

7. **`BandMeasurer` is a separate pure unit.** Mirrors 007c's `group_band_index.dart` split: the
   height rule is unit-tested on its own (heights), while pagination goldens test breaks and
   coordinates. Two concerns, two test files. Measuring once and reusing the boxes also avoids a
   double-measure at emission.

## §11 — File plan

| File | Change |
|---|---|
| `lib/src/rendering/layout/band_measurer.dart` | **new** — `MeasuredBand` + `BandMeasurer` (pure grow-only band measurement) |
| `lib/src/rendering/layout/report_layouter.dart` | **new** — `LayoutResult` + `ReportLayouter` (geometry, body loop, chrome post-pass, emission) |
| `test/rendering/layout/band_measurer_test.dart` | **new** — growth-rule heights |
| `test/rendering/layout/report_layouter_test.dart` | **new** — pagination/coordinate/chrome/determinism goldens |
| `test/architecture/layer_boundaries_test.dart` | extend — `rendering/layout/` stays headless (domain + rendering only) |
| `CHANGELOG.md` | 008a entry |

No `lib/jet_print.dart` export in 008a — the public surface is the 011 `JetReportEngine`; the
layouter is `src/`-internal, consumed via white-box `package:jet_print/src/...` imports in tests
(the existing test convention).

## §12 — Review history

**Pre-write review (R1), folded in:**

1. *Substitution seam is one slice too late (High).* Reviewer: `PageFrame`/`FramePrimitive` carry
   only resolved primitives, so if 008a emits final frames, 008c has no clean way to late-bind
   page-scoped chrome without re-running layout or inventing an intermediate IR; the blueprint places
   substitution inside layout before `List<PageFrame>` (lines 180, 342). **Verified and folded in:**
   confirmed primitives keep no authored element/placeholder (`primitive.dart`), and `PAGE_COUNT`
   genuinely can't be known mid-loop. Resolution chosen is the reviewer's *"keep late chrome
   substitution inside the layouter"* option, realized as **held builders + a post-pagination chrome
   pass** (§6, §10 #3) — the seam now exists without a new IR (the reviewer's second option, rejected
   as YAGNI).

2. *Default renderer wiring doesn't match the built-in API (Medium).* Reviewer: built-ins register
   through `registerBuiltInElementTypes(ElementTypeRegistry)`, not directly into an
   `ElementRendererRegistry`. **Verified and fixed:** the injected param stays renderer-only (narrow,
   `ReportFiller`-analogous), but the default routes through the paired
   `ElementTypeRegistry`→`registerBuiltInElementTypes`→`.renderers` path (§4).

3. *`PageFormat` source conflicts with the documented contract (Medium).* Reviewer: fill-design says
   the template supplies page chrome + page format; mixing `template.bands` with `filled.page` leaves
   mismatched pairs underspecified. **Verified and fixed:** fill-design §10.7 confirms it;
   `template.page` is now authoritative, with a warning on mismatch (§2, §8, §10 #5).

4. *Unresolved chrome binding rule left implicit (open question).* Reviewer: unresolved chrome text
   would render its authored literal while an unresolved image field falls through to a placeholder —
   too accidental to leave unspecified. **Verified and specified:** confirmed `ImageElementRenderer`
   sends a non-`BytesImageSource` to `emitPlaceholder`. 008a now scans chrome once for unresolved
   bindings and emits one **info** diagnostic per element, with the per-type behavior tabulated
   (§7) and tested (§9).

**Second review (R2), folded in:**

1. *008a over-promises 008c's chrome evaluation (High).* Reviewer: the spec defers "all chrome
   expression evaluation" to 008c (params, dates, a `$P{title}` example), but `layout(template,
   filled)` carries no runtime `params` map — `FilledReport` has only page + band snapshots — so 008c
   can derive page numbers but cannot evaluate `$P{}`/`NOW()`/field chrome from that input.
   **Verified and narrowed (the reviewer's "narrow the wording" option, YAGNI over widening the API
   now):** confirmed `params` lives only in the `ReportFiller.fill(...)` call and is absent from the
   IR. 008c's charter is **page-scoped substitution only**; broader chrome eval is flagged an explicit
   **open question** needing a params channel, not a commitment (§2, §7, §10 #2).

2. *Header/footer overcommit makes the geometry invalid before any band is measured (Medium).*
   Reviewer: `bodyCapacity` can go negative when chrome ≥ printable height, silently overlapping
   chrome and emitting misleading negative-capacity per-band warnings. **Verified and fixed:** added
   an **upfront root-cause warning** when `bodyCapacity ≤ 0`, with explicit proceed-behavior (chrome
   may overlap, bands overflow) and **suppression** of the now-misleading per-band capacity warnings
   (§6, §8, §9).

3. *Chrome-image rule assigns `UrlImageSource` to the wrong stage (Medium).* Reviewer: the 007a
   renderer-design already owns `UrlImageSource` resolution in a later **async paint-prep** step, not
   layout/008c — so "deferred to 008c" for URL chrome would strand it forever. **Verified and fixed:**
   confirmed the renderer-design split (`FieldImageSource`→Fill, `UrlImageSource`→paint-prep). §7's
   table now separates the rows and the diagnostic **no longer names 008c** for images — field images
   are row-bound (meaningless in chrome), URL images belong to async paint-prep, only page-scoped
   *text* is 008c's.

4. *Determinism test would fail if implemented literally (Low).* Reviewer: `Diagnostic`/
   `ReportDiagnostics` have no value equality, so an equality assertion compares by identity.
   **Verified and fixed:** confirmed neither defines `==`. §9 now compares frames by value
   (`PageFrame` has `==`) and diagnostics by a **normalized projection** of `(severity, message,
   elementId)` tuples — no new `==` added to the 007b diagnostics types (out of 008a's scope).
