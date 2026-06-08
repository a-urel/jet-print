# Spec 008c — Page-scoped late substitution

**Status**: Approved design (slice 008c of the 008 Layout & Pagination feature).
**Depends on**: 008a (layout engine) + 008b (group-aware pagination), both merged to `main`.
**Builds the seam**: the post-pagination chrome pass that 008a deliberately left open.

---

## 1. Purpose & scope

At layout time, **after** body pagination (so the page count is known), evaluate **page-scoped** expressions in page-chrome text and substitute the resulting text in place, at the element's **authored bounds**.

**In scope** — what a chrome text expression may reference:
- `$V{PAGE_NUMBER}` — the 1-based index of the page the chrome instance is being emitted onto.
- `$V{PAGE_COUNT}` — the total number of pages (constant within a layout).
- `$P{name}` — report parameters (threaded into the layout via the IR — §3).

`PAGE_NUMBER`/`PAGE_COUNT` are the existing `kPageScopedVariables` authority (`rendering/fill/page_variables.dart`, spec 007b §2), which Fill already reserves and rejects in body/data sites; 008c is the consumer that finally resolves their values.

**Out of scope** (unchanged from 008a/008b):
- `columnHeader`/`columnFooter` — not laid out yet (008b still info-ignores them). Only `pageHeader`/`pageFooter` chrome is substituted.
- Chrome **images** — the 008a "not embedded; renders a placeholder" info stays.
- Body/detail text — already resolved by Fill (007b).
- The global number-formatting model and the expression engine — untouched (§4).

## 2. Architecture & the seam

008a emits page chrome in a **post-pagination pass**: after the body loop fixes the page count, it iterates every page and places the authored `template.bands` chrome (`pageHeader` at the top, `pageFooter` at the bottom) via `place(_authoredBoxes(band), …)`. Chrome bands **bypass Fill** — their `TextElement`s still carry an unevaluated `expression`, and `TextElementRenderer` renders from `el.text` (the authored fallback), ignoring `el.expression`. 008a therefore emitted one **info** per chrome text expression ("not evaluated in the static layout pass").

008c replaces that with real evaluation:
1. A **compile-and-validate pre-pass** (once per chrome text element, replacing the 008a chrome scan): parse the expression (cache the `Expression`); emit page-independent diagnostics (parse errors, unavailable references) **once per element**.
2. A **page-aware post-pass**: for each page `i` (0-based), for each chrome `TextElement` with an expression, evaluate the cached `Expression` against a `PageEvalContext(pageNumber: i + 1, pageCount: pages.length, params: filled.params, functions)` and place a `TextElement(text: jetStringify(value))` at the **authored bounds**.

This is **Approach A** (page-scoped resolution owned by Layout): a dedicated `PageEvalContext` reuses the `EvalContext`/`Expression`/function-registry seams, parallels the Fill structure, and keeps the new concern self-contained. (Rejected: extending the row-scoped `ElementResolver` with a page mode — muddies its single responsibility and `FillEvalContext` *rejects* page vars; a per-page band-rewrite — allocates N chrome-band copies for no gain.)

**The fixed-bounds invariant.** Substitution does **not** repaginate, does **not** grow the chrome box, and **preserves the authored bounds**. (The text renderer still measures line breaks at emit time — that is unavoidable and unchanged; what is fixed is the box, not the measurement.) Substituted text that overflows its authored box overflows/clips exactly as any over-long authored text would — it never triggers a new page or reflows the body. The page count is final before substitution runs, so `PAGE_COUNT` is simply `pages.length` and no second pagination pass is needed.

## 3. Data model

**`FilledReport.params`** (new field on the internal Fill→Layout IR, `rendering/fill/filled_report.dart`):
- Type **`Map<String, JetValue>`** (normalized), NOT raw `Map<String, Object?>`. `FilledReport` is a value-equal, hashable snapshot; raw `Object?` values (a list/map/custom object) would compare by identity and hash unstably, so two semantically identical fills could compare unequal. `JetValue.from` normalizes the supported kinds and maps any unsupported type to a stable `JetError` **value** (it never throws — `value.dart:20-27`), so the normalized map has clean value equality. This mirrors `FilledBand.variables` (already `Map<String, JetValue>`).
- Stored unmodifiable; participates in `==`/`hashCode` by value (same pattern as `FilledBand.variables`' unordered hash).
- `ReportFiller` normalizes the raw `Map<String, Object?> params` it already receives at `fill()` into `Map<String, JetValue>` when constructing the `FilledReport`. **Body resolution is unchanged** — it still uses the raw `params` during `fill()`; only the IR snapshot is normalized for Layout's chrome use.

**`PageEvalContext`** (new, `rendering/layout/page_eval_context.dart`) `implements EvalContext`:
- `resolveVariable(name)` → `PAGE_NUMBER`/`PAGE_COUNT` as `JetString` (§4); any other name → record as an unavailable non-page variable, return `JetNull`.
- `resolveParam(name)` → the stored `JetValue` from `filled.params` (returned directly — already normalized), or `JetNull` if absent (silent — matches `FillEvalContext.resolveParam`, `fill_eval_context.dart:70`).
- `resolveField(name)` → record as an unavailable field reference (chrome has no data row), return `JetNull`.
- `functions` → the layouter's `JetFunctionRegistry`.
- The unavailable-reference recording uses **per-element** sinks owned by the pre-pass (§6) — not a shared by-name set.

**`ReportLayouter`** (`rendering/layout/report_layouter.dart`) gains a `JetFunctionRegistry? functions` constructor parameter (default the built-in registry, mirroring `ReportFiller`). Its library doc comment drops the "no expression engine" clause.

## 4. Page-scoped values (the all-double caveat)

The engine is an **all-double** numeric model: `JetNumber` wraps a `double`, and `jetStringify(JetNumber(5))` is `'5.0'` (`value_test.dart:50`, asserted deliberately). Number→string coercion bakes the `.0` in **during** evaluation (so a final integer-aware stringify could not undo it inside a concatenation), and changing the global stringify model is out of 008c's scope.

Therefore **`PAGE_NUMBER` and `PAGE_COUNT` resolve to `JetString`** holding the integer's decimal text (`"1"`, `"3"`). Then both forms render correctly:
- `$V{PAGE_NUMBER}` → `1`
- `"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}` → `Page 1 of 3`

**Trade-off (decision §10):** page variables are textual counters; arithmetic on them concatenates as strings. This is acceptable for display counters, and a numeric variant or coercion function can be added later if a real need appears. Report **parameters** keep their natural `JetValue` kind (a numeric `$P{}` stringifies per the all-double model, exactly as in body text — consistent, not 008c's concern).

## 5. Substitution mechanism

**Pre-pass (once per chrome `TextElement` with an `expression`)** — replaces the 008a chrome unresolved-binding scan:
1. `Expression.parse(el.expression!)`. On `ExpressionException` → one `error` diagnostic (elementId `el.id`); the element is marked failed and renders `'!ERR'` on every page (mirrors `ElementResolver`'s `'!ERR'`).
2. Surface **unavailable references** — `$F{}` (no row) and non-page `$V{}` — once per element: a fresh per-element recording `PageEvalContext` collects them into element-local sinks, and a single `warning` per element names them (mirrors `ElementResolver`'s `pageRefs.join(', ')`). The parsed `Expression` is cached for the post-pass. (Runtime `JetError` from this probe is ignored here — runtime failures are page-dependent and handled in the post-pass.)

**Post-pass (per page, per chrome `TextElement`)**:
- No expression → place authored element unchanged (008a behavior).
- Parse-failed → place `TextElement(text: '!ERR', …)` at authored bounds (no repeat diagnostic).
- Otherwise → `value = cachedExpression.evaluate(PageEvalContext(i + 1, pages.length, filled.params, functions))`; place `TextElement(text: jetStringify(value), bounds: el.bounds, style: el.style, id: el.id)`. A `value is JetError` → §6 runtime policy.

## 6. Diagnostics policy (diagnostic-rich)

`Diagnostic` carries only `(severity, message, elementId)` — no page field (`report_diagnostics.dart`). 008c splits by failure kind:

**Structural — page-independent — once per element (pre-pass):**
- Parse error → `error`, render `'!ERR'`.
- `$F{}` reference in chrome → `warning`, render blank.
- Non-page `$V{}` reference in chrome → `warning`, render blank.
- Absent `$P{}` → blank, **no** diagnostic (matches body, `fill_eval_context.dart:70`).

**Runtime — page-dependent — per failing (element, page) (post-pass):**
- A `JetError` result (e.g. `100 / ($V{PAGE_NUMBER} - 2)` divides by zero on page 2 only) → one `error` per failing (element, page), **with the page number embedded in the message** (the only way to preserve page detail given the flat `Diagnostic` shape). Each (element, page) evaluates exactly once, so this is one diagnostic per actually-failing page; that page renders `jetStringify(JetError)` = `'!ERR'`. This is a **design decision** (page-dependence is real; the code only establishes that `Diagnostic` has no page field), not a code-derived rule.

Determinism holds: identical inputs produce identical per-page evaluations and therefore identical diagnostics (including the page numbers in messages).

## 7. Layer-boundary change

`test/architecture/layer_boundaries_test.dart` (the `layout/` case, currently lines ~260-292) asserts `rendering/layout` is both (a) Flutter-free **and** (b) free of the expression engine, explicitly as a *"008a is pure geometry"* invariant. 008c **relaxes (b)** — page-scoped evaluation is intrinsically a layout responsibility, and `expression/` is inward of `rendering/` in the dependency DAG (domain ← data ← expression ← rendering), so the import is architecturally legal. **(a) stays** — `layout/` remains headless. The test is amended to keep the Flutter-free assertion and drop the expression-seam prohibition (updating its comment/reason).

## 8. Files

**Modify (`rendering/fill/`):**
- `lib/src/rendering/fill/filled_report.dart` — add `FilledReport.params` (`Map<String, JetValue>`, unmodifiable; into `==`/`hashCode`).
- `lib/src/rendering/fill/report_filler.dart` — normalize the received `params` into `Map<String, JetValue>` and pass to the `FilledReport`.

**Create (`rendering/layout/`):**
- `lib/src/rendering/layout/page_eval_context.dart` — `PageEvalContext`.

**Modify (`rendering/layout/`):**
- `lib/src/rendering/layout/report_layouter.dart` — `JetFunctionRegistry` dependency; compile-and-validate pre-pass (replacing the chrome scan); page-aware chrome post-pass; doc-comment update; expression-engine imports.

**Tests:**
- `test/rendering/fill/filled_report_test.dart` — `FilledReport.params` equality/normalization.
- `test/rendering/fill/report_filler_test.dart` — filler stores normalized params.
- `test/rendering/layout/report_layouter_test.dart` — substitution goldens; rewrite the two 008a tests at lines ~207 and ~229.
- `test/architecture/layer_boundaries_test.dart` — relax the layout/expression rule (keep Flutter-free).

## 9. Testing

`PageFrame` data goldens on the existing small-page harness:
- **Page N of M**: a `pageFooter` with `"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}` over a 3-page body → pages render `Page 1 of 3`, `Page 2 of 3`, `Page 3 of 3`.
- **Bare `$V{PAGE_NUMBER}`**: renders `1`, `2`, … (not `1.0`) — the explicit all-double guard.
- **Param substitution**: a chrome `$P{title}` resolves from `filled.params`; numeric `$P{}` stringifies per the all-double model.
- **Fixed-bounds**: substituted text longer than the authored width does **not** add a page or change page count (compare page count to the no-expression baseline); the chrome `TextRunPrimitive` sits at the authored bounds.
- **Parse error**: `'!ERR'` text + exactly one `error` diagnostic across all pages.
- **Unavailable refs**: a chrome `$F{x}` (and a non-page `$V{total}`) → one `warning` per element (not per page); two distinct elements each using `$F{x}` → two warnings (per-element granularity).
- **Absent `$P{}`**: blank, no diagnostic.
- **No-expression chrome**: unchanged from 008a.
- **Rewrite 008a :207** ("renders its literal + an info") → now asserts the evaluated value (`1`) and **no** info.
- **Rewrite 008a :229** ("diagnosed once, not once per page") → uses an illegal `$F{}` (or non-page `$V{}`) so a diagnostic actually fires, asserting one warning across a multi-page layout. (Not an absent `$P{}` — that is silent.)
- **Determinism**: two layouts → equal `PageFrame`s + equal diagnostics projection.

Fill tests: `FilledReport.params` round-trips/normalizes (an unsupported type → stable `JetError`, equal across two fills); `ReportFiller` stores the normalized map; the no-params path is unchanged.

## 10. Decisions

1. **Approach A** (page-scoped resolver owned by Layout) over extending `ElementResolver` or per-page band rewrites.
2. **Params threaded via `FilledReport`** (internal IR, no schema impact) — single source, normalized once.
3. **Params normalized to `Map<String, JetValue>`** in the IR — preserves the value-equal snapshot invariant (raw `Object?` would break equality/hash).
4. **`PAGE_NUMBER`/`PAGE_COUNT` as `JetString`** of the integer — the all-double model would otherwise render `1.0`; this avoids changing global stringify semantics. Trade-off: textual counters, string arithmetic.
5. **Diagnostic-rich** error handling; structural diagnostics once per element, runtime `JetError`s per failing (element, page) with the page in the message (a design choice, given the flat `Diagnostic` shape).
6. **Fixed-bounds** substitution — no repagination, no chrome box growth, authored bounds preserved.
7. **Layer boundary relaxed** — `layout/` may import `expression/` (legal in the DAG); stays Flutter-free.
8. **No schema bump** — `FilledReport.params` is internal IR; consistent with the 008b pre-1.0 additive carve-out.

## 11. Review history

- **R1 (design)** — High: raw `Map<String, Object?>` params would break `FilledReport` value equality → normalize to `Map<String, JetValue>`. Medium: "once per element" must dedupe per element id + ref, not by name like `FillEvalContext` → per-element sinks in the pre-pass. Medium: page-scoped runtime-error policy underspecified → split structural (once/element) vs runtime (per failing page, page in message). Wording: "no re-measure" is false (renderer measures at emit) → invariant is "no repagination, no chrome box growth, authored bounds preserved."
- **R2 (design)** — Medium: `PAGE_NUMBER` as a number stringifies `1.0` (all-double model, `value_test.dart:50`) → resolve page vars as `JetString`. Medium: the "all four verified" claim overreached on the runtime-error policy → reframed as a design decision (the code only proves `Diagnostic` has no page field). Low: the rewritten "diagnosed once" test must use an illegal `$F{}`/non-page `$V{}` (absent `$P{}` is silent, `fill_eval_context.dart:70`).
