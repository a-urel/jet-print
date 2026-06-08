# Spec 008c — Page-scoped late substitution

**Status**: Approved design (slice 008c of the 008 Layout & Pagination feature).
**Depends on**: 008a (layout engine) + 008b (group-aware pagination), both merged to `main`.
**Builds the seam**: the post-pagination chrome pass that 008a deliberately left open.

---

## 1. Purpose & scope

At layout time, **after** body pagination (so the page count is known), evaluate **page-scoped** expressions in page-chrome text and substitute the resulting text in place, at the element's **authored bounds**.

**In scope** — what a chrome text expression may reference:
- `$V{PAGE_NUMBER}` — the 1-based index of the page the chrome instance is emitted onto.
- `$V{PAGE_COUNT}` — the total number of pages (constant within a layout).
- `$P{name}` — report parameters (threaded into the layout via the IR — §3).

`PAGE_NUMBER`/`PAGE_COUNT` are the existing `kPageScopedVariables` authority (`rendering/fill/page_variables.dart`, spec 007b §2), which Fill reserves and rejects in body/data sites; 008c is the consumer that resolves their values.

**Out of scope** (unchanged from 008a/008b):
- `columnHeader`/`columnFooter` — not laid out yet (008b info-ignores them). Only `pageHeader`/`pageFooter` chrome is substituted.
- Chrome **images** — the 008a "not embedded; renders a placeholder" info stays.
- Body/detail text — already resolved by Fill (007b).
- The global number-formatting model and the expression evaluator — untouched (§4). The only expression-seam change is an additive, read-only reference-collector (§3).

**Known limitation (page comparisons).** Because page variables are `JetString` (§4), page **conditions** use string semantics: `$V{PAGE_NUMBER} == "1"` (first page) and `$V{PAGE_NUMBER} == $V{PAGE_COUNT}` (last page) work; numeric ordering/arithmetic on page vars does **not** (`> 1` errors or compares lexicographically). This is the unavoidable cost of the all-double model (§4); a numeric page-var variant is possible future work.

## 2. Architecture & the seam

008a emits page chrome in a **post-pagination pass**: after the body loop fixes the page count, it iterates every page and places the authored `template.bands` chrome (`pageHeader` at the top, `pageFooter` at the bottom) via `place(_authoredBoxes(band), …)`. Chrome bands **bypass Fill** — their `TextElement`s carry an unevaluated `expression`, and `TextElementRenderer` renders from `el.text` (the authored fallback), ignoring `el.expression`. 008a therefore emitted one **info** per chrome text expression ("not evaluated").

008c replaces that:
1. A **compile-and-classify pre-pass** (once per chrome text element, replacing the 008a chrome scan): parse the expression (cache the `Expression`); **statically** collect its references and emit page-independent diagnostics (parse errors, unavailable references) once per element.
2. A **page-aware post-pass**: for each page `i` (0-based), for each chrome `TextElement` with an expression, evaluate the cached `Expression` against a `PageEvalContext(pageNumber: i + 1, pageCount: pages.length, params: filled.params, functions)` and place a `TextElement(text: jetStringify(value))` at the **authored bounds**.

This is **Approach A** (page-scoped resolution owned by Layout): a dedicated `PageEvalContext` plus a static reference-collector reuse the `EvalContext`/`Expression` seams and keep the new concern self-contained. (Rejected: extending the row-scoped `ElementResolver` with a page mode; per-page band rewrites.)

**Static reference analysis (why, not probe evaluation).** The evaluator short-circuits — `?:` walks only the taken branch (`evaluator.dart:43`) and `&&`/`||` skip the right side (`evaluator.dart:65-79`). So evaluating an expression once to discover its references (the pattern `scanPageScoped` uses in `report_filler.dart:105`) misses refs in untaken/short-circuited branches and cannot deliver reliable once-per-element diagnostics. 008c instead walks the parsed AST (§3), which visits every branch/operand/argument and treats string literals as literals — complete and string-literal-safe.

**The fixed-bounds invariant.** Substitution does **not** repaginate, does **not** grow the chrome box, and **preserves the authored bounds**. (The text renderer still measures line breaks at emit time — unavoidable and unchanged; what is fixed is the box, not the measurement.) Substituted text that overflows its authored box overflows/clips exactly as any over-long authored text would — it never triggers a new page or reflows the body. The page count is final before substitution runs, so `PAGE_COUNT` is simply `pages.length`; no second pagination pass.

## 3. Data model

**Expression reference-collector** (new, additive, read-only — `rendering`/`layout` consumes it; lives in `expression/`):
- `Expression.references` → `({Set<String> fields, Set<String> params, Set<String> variables})`, computed by a recursive walk over the sealed `Expr` AST (`LiteralExpr`/`FieldRefExpr`/`ParamRefExpr`/`VariableRefExpr`/`UnaryExpr`/`BinaryExpr`/`ConditionalExpr`/`CallExpr`), visiting **all** branches, operands, and arguments. String literals are `LiteralExpr` nodes, so sigil-like text inside a quoted string is never mistaken for a reference. Purely additive; changes no evaluation behavior. (Bonus, out of scope: this primitive could later harden Fill's `scanPageScoped`, which shares the probe-eval blind spot.)

**`FilledReport.params`** (new field on the internal Fill→Layout IR, `rendering/fill/filled_report.dart`):
- Type **`Map<String, JetValue>`** (normalized), NOT raw `Map<String, Object?>`. `FilledReport` is a value-equal, hashable snapshot; raw `Object?` values (a list/map/custom object) compare by identity and hash unstably, so two semantically identical fills could compare unequal. `JetValue.from` normalizes the supported kinds and maps any unsupported type to a stable `JetError` **value** (never throws — `value.dart:20-27`), so the normalized map has clean value equality. Mirrors `FilledBand.variables` (already `Map<String, JetValue>`).
- Stored unmodifiable; participates in `==`/`hashCode` by value.
- `ReportFiller` normalizes the raw `Map<String, Object?> params` it already receives at `fill()` into `Map<String, JetValue>` when constructing the `FilledReport`. **Body resolution is unchanged** — it still uses the raw `params` during `fill()`; only the IR snapshot is normalized for Layout's chrome use.

**`PageEvalContext`** (new, `rendering/layout/page_eval_context.dart`) `implements EvalContext` — a pure **value** resolver (diagnostics come from the static pre-pass, so it carries no recording sinks):
- `resolveVariable(name)` → `PAGE_NUMBER`/`PAGE_COUNT` as `JetString` (§4); any other name → `JetNull`.
- `resolveParam(name)` → the stored `JetValue` from `filled.params` (already normalized), or `JetNull` if absent.
- `resolveField(name)` → `JetNull` (chrome has no data row).
- `functions` → the layouter's `JetFunctionRegistry`.

**`ReportLayouter`** (`rendering/layout/report_layouter.dart`) gains a `JetFunctionRegistry? functions` constructor parameter (default the built-in registry, mirroring `ReportFiller`); its library doc comment drops the "no expression engine" clause.

## 4. Page-scoped values (the all-double caveat)

The engine is **all-double**: `JetNumber` wraps a `double`, and `jetStringify(JetNumber(5))` is `'5.0'` (`value_test.dart:50`, asserted deliberately). Crucially, `+` does **not** coerce — it requires two numbers **or** two strings (`evaluator.dart:92-99`), so `"Page " + $V{PAGE_NUMBER}` with a *numeric* page var is a hard `JetError`. Changing the global model is out of 008c's scope.

Therefore **`PAGE_NUMBER` and `PAGE_COUNT` resolve to `JetString`** holding the integer's decimal text (`"1"`, `"3"`). Then:
- `$V{PAGE_NUMBER}` → `1`
- `"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}` → `Page 1 of 3`
- `$V{PAGE_NUMBER} == "1"` → first-page condition (string equality, `evaluator.dart:89`)
- `$V{PAGE_NUMBER} == $V{PAGE_COUNT}` → last-page condition

**Trade-off (decision §10, limitation §1):** page vars are textual counters. Numeric ordering/arithmetic on them is unsupported (`-`/`/` need two numbers, `evaluator.dart:128/134`; ordering needs same-type comparables, `:140-145`). Equality against a string literal works; lexicographic ordering is a footgun past 9 pages. This is acceptable for a display-focused slice and is documented. Report **parameters** keep their natural `JetValue` kind (a numeric `$P{}` stringifies per the all-double model, exactly as in body text — consistent, not 008c's concern).

## 5. Substitution mechanism

**Pre-pass (once per chrome `TextElement` with an `expression`)** — replaces the 008a chrome scan:
1. `Expression.parse(el.expression!)`. On `ExpressionException` → one `error` diagnostic (elementId `el.id`); mark the element parse-failed (renders `'!ERR'` on every page). Cache the parsed `Expression` otherwise.
2. `expr.references` (static, branch-complete). Classify and emit **once per element**:
   - `fields` non-empty → one `warning`: the `$F{…}` names referenced in chrome have no data row.
   - `variables` minus `kPageScopedVariables` non-empty → one `warning`: non-page `$V{…}` names are unavailable at page scope.
   - `params` and page vars → no diagnostic (an absent `$P{}` resolves to blank at eval, matching body — `fill_eval_context.dart:70`).

**Post-pass (per page, per chrome `TextElement`)**:
- No expression → place authored element unchanged (008a behavior).
- Parse-failed → place `TextElement(text: '!ERR', …)` at authored bounds (no repeat diagnostic).
- Else → `value = cachedExpression.evaluate(PageEvalContext(i + 1, pages.length, filled.params, functions))`; place `TextElement(text: jetStringify(value), bounds: el.bounds, style: el.style, id: el.id)`.
  - **Render follows null-propagation:** a bare unavailable ref resolves to `JetNull` → `''` (blank); an unavailable ref consumed by an operator/function poisons to `JetError` → `'!ERR'` (`evaluator.dart:83-85,156`). No special pre-substitution — chrome behaves exactly like body text w.r.t. nulls.
  - A `value is JetError` → render `'!ERR'` and emit a runtime diagnostic per §6 (suppressed if the element already carries a structural diagnostic, since its `'!ERR'` is already explained).

## 6. Diagnostics policy (diagnostic-rich)

`Diagnostic` carries only `(severity, message, elementId)` — no page field (`report_diagnostics.dart`).

**Structural — page-independent — once per element (pre-pass, via static reference analysis):**
- Parse error → `error`, render `'!ERR'`.
- `$F{}` reference in chrome → `warning`, render per null-propagation (§5).
- Non-page `$V{}` reference in chrome → `warning`, render per null-propagation.
- Absent `$P{}` → blank, **no** diagnostic (matches body).

**Runtime — post-pass:**
- A `JetError` result (e.g. a type error, unknown function, or division by zero) → render `'!ERR'`; emit one `error` **deduped per `(element id, message)`** — a deliberately **coarse** summary (the failing page renders `'!ERR'` regardless). With string page vars, page-*dependent* runtime errors are contrived, so per-page message detail is not worth the complexity. Suppressed for an element that already has a structural diagnostic (its `'!ERR'` is already explained).

This split is a **design decision** (the code only establishes that `Diagnostic` has no page field), and it keeps diagnostics deterministic: identical inputs → identical per-element classifications and per-`(element, message)` runtime errors.

## 7. Layer-boundary change

`test/architecture/layer_boundaries_test.dart` (the `layout/` case, ~lines 260-292) asserts `rendering/layout` is both (a) Flutter-free **and** (b) free of the expression engine, explicitly as a *"008a is pure geometry"* invariant. 008c **relaxes (b)** — page-scoped evaluation is intrinsically a layout responsibility, and `expression/` is inward of `rendering/` in the DAG (domain ← data ← expression ← rendering), so the import is legal. **(a) stays** — `layout/` remains headless. The test keeps the Flutter-free assertion and drops the expression-seam prohibition (updating its comment/reason).

## 8. Files

**Create / modify (`expression/`):**
- `lib/src/expression/expression.dart` — add the read-only `references` getter (backed by a small AST walk; the walk may live in a new `lib/src/expression/reference_collector.dart`).

**Modify (`rendering/fill/`):**
- `lib/src/rendering/fill/filled_report.dart` — add `FilledReport.params` (`Map<String, JetValue>`, unmodifiable; into `==`/`hashCode`).
- `lib/src/rendering/fill/report_filler.dart` — normalize the received `params` into `Map<String, JetValue>` and pass to the `FilledReport`.

**Create (`rendering/layout/`):**
- `lib/src/rendering/layout/page_eval_context.dart` — `PageEvalContext` (pure value resolver).

**Modify (`rendering/layout/`):**
- `lib/src/rendering/layout/report_layouter.dart` — `JetFunctionRegistry` dependency; compile-and-classify pre-pass (replacing the chrome scan); page-aware chrome post-pass; doc-comment + expression-engine imports.

**Tests:**
- `test/expression/` — the `references` collector (collects across all `?:`/`&&`/`||` branches and call args; distinguishes field/param/variable; ignores sigil-like text inside string literals).
- `test/rendering/fill/filled_report_test.dart` — `FilledReport.params` equality/normalization.
- `test/rendering/fill/report_filler_test.dart` — filler stores normalized params.
- `test/rendering/layout/report_layouter_test.dart` — substitution goldens; rewrite the two 008a tests at ~lines 207 and 229.
- `test/architecture/layer_boundaries_test.dart` — relax the layout/expression rule (keep Flutter-free).

## 9. Testing

`PageFrame` data goldens on the existing small-page harness:
- **Page N of M**: a `pageFooter` with `"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}` over a 3-page body → `Page 1 of 3`, `Page 2 of 3`, `Page 3 of 3`.
- **Bare `$V{PAGE_NUMBER}`**: renders `1`, `2`, … (not `1.0`) — the all-double guard.
- **First/last-page condition**: `$V{PAGE_NUMBER} == "1"` and `$V{PAGE_NUMBER} == $V{PAGE_COUNT}` select the right pages (string equality).
- **Param substitution**: chrome `$P{title}` resolves from `filled.params`; numeric `$P{}` stringifies per the all-double model.
- **Fixed-bounds**: substituted text longer than the authored width does **not** add a page (compare page count to the no-expression baseline); the chrome `TextRunPrimitive` sits at the authored bounds.
- **Parse error**: `'!ERR'` text + exactly one `error` across all pages.
- **Static-analysis completeness**: a ref hidden in a short-circuited/untaken branch — e.g. `$V{PAGE_NUMBER} == "9" ? $F{x} : "ok"` or `false && ...` — still produces the once-per-element `$F{}` **warning** (proving AST analysis, not probe eval). Two distinct elements each using `$F{x}` → two warnings (per-element granularity).
- **Render of illegal refs**: a bare `$F{x}` → blank; `"a" + $F{x}` → `'!ERR'` (null-propagation), each with one structural warning.
- **Absent `$P{}`**: blank, no diagnostic.
- **No-expression chrome**: unchanged from 008a.
- **Rewrite 008a ~:207** ("renders its literal + an info") → now asserts the evaluated value (`1`) and **no** info.
- **Rewrite 008a ~:229** ("diagnosed once, not once per page") → uses an illegal `$F{}` (or non-page `$V{}`) so a diagnostic actually fires, asserting one warning across a multi-page layout (not an absent `$P{}`, which is silent).
- **Determinism**: two layouts → equal `PageFrame`s + equal diagnostics projection.

Expression tests: `references` walks all branches and call args, classifies by kind, and excludes sigil-like text inside string literals. Fill tests: `FilledReport.params` normalizes (unsupported type → stable `JetError`, equal across two fills) and round-trips in equality; `ReportFiller` stores the normalized map; the no-params path is unchanged.

## 10. Decisions

1. **Approach A** (page-scoped resolver owned by Layout).
2. **Params threaded via `FilledReport`** (internal IR, no schema impact) — single source, normalized once.
3. **Params normalized to `Map<String, JetValue>`** — preserves the value-equal snapshot invariant.
4. **`PAGE_NUMBER`/`PAGE_COUNT` as `JetString`** of the integer — required because `+` won't mix a string literal with a number and the all-double model renders `1.0`. Trade-off: page conditions use string equality; numeric ordering/arithmetic on page vars is unsupported (limitation §1/§4).
5. **Static AST reference analysis** for unavailable-ref diagnostics — branch-complete and string-safe, unlike probe evaluation (which short-circuiting defeats). Adds a read-only `Expression.references` to the expression seam.
6. **Diagnostics**: structural once per element (pre-pass); runtime `JetError`s coarse-deduped per `(element, message)` (post-pass), suppressed when an element already carries a structural diagnostic.
7. **Render follows null-propagation** — no special pre-substitution; chrome behaves like body (bare unavailable ref → blank, in-operation → `'!ERR'`).
8. **Fixed-bounds** substitution — no repagination, no chrome box growth, authored bounds preserved.
9. **Layer boundary relaxed** — `layout/` may import `expression/` (legal in the DAG); stays Flutter-free.
10. **No schema bump** — `FilledReport.params` is internal IR; consistent with the 008b pre-1.0 additive carve-out.

## 11. Review history

- **R1 (design)** — High: raw `Map<String, Object?>` params would break `FilledReport` value equality → normalize to `Map<String, JetValue>`. Medium: "once per element" must dedupe per element, not by name → per-element granularity. Medium: page-scoped runtime-error policy underspecified → split structural vs runtime. Wording: "no re-measure" is false → "no repagination, no chrome box growth, authored bounds preserved."
- **R2 (design)** — Medium: `PAGE_NUMBER` as a number stringifies `1.0` (`value_test.dart:50`) → `JetString`. Medium: "all four verified" overreached on the runtime policy → reframed as a design decision. Low: the "diagnosed once" test must use an illegal `$F{}`/non-page `$V{}`, not an absent `$P{}` (silent, `fill_eval_context.dart:70`).
- **R3 (spec)** — High: the probe-evaluation pre-pass can't reliably find refs because the evaluator short-circuits (`evaluator.dart:43,65`) → **static AST reference analysis** (`Expression.references`); `PageEvalContext` drops its recording sinks. Medium: illegal refs resolve to `JetNull`, which poisons to `JetError` inside operators/functions (`evaluator.dart:83-85,156`) → spec no longer promises "render blank"; render follows null-propagation. Medium: `+` requires same-type operands and ordering/arithmetic need numbers (`evaluator.dart:92-99,128,134,140`), so the `JetString` decision breaks numeric page comparisons and the `100/($V{PAGE_NUMBER}-2)` example is invalid → removed the example, documented the comparison limitation (§1/§4), and simplified the runtime-diagnostic policy to a coarse per-`(element, message)` dedup.
