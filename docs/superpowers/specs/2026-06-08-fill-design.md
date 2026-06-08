# Spec 007b — Fill (flat) · Design

**Status:** approved-pending-review · **Date:** 2026-06-08 · **Depends on:** 003 (domain model +
codecs), 004 (`JetDataSource`/`DataSet`), 005 (expressions + `VariableCalculator`), 007a
(resolved-element seam). · **Layer:** `rendering/fill/` (inward DAG: depends only on `domain`,
`data`, `expression`; never `rendering/elements`, `rendering/frame`, Flutter).

007b is the **second half** of blueprint spec 007 (Element Types + Fill), split — like 005a/005b
and 007a/007b — into **007b Fill (flat)** (this spec) and **007c Grouping** (group header/footer
band sequencing + the `ReportBand`↔`ReportGroup` link + group-scoped subtotals in the stream).

---

## 1. Purpose

Fill is the **data pass**: walk a `ReportTemplate` over a `JetDataSource`, evaluate expressions,
drive the variable calculator, and emit an ordered stream of **resolved band instances** —
`FilledReport` — alongside a `ReportDiagnostics`. It produces *data, not geometry*: no measuring,
no pagination, no rendering.

**008 (Layout) consumes both the `ReportTemplate` and the `FilledReport`** — the template supplies
the page/column/background chrome bands (which Fill does not process), the page format, and the
page-scoped variable definitions; the `FilledReport` supplies the resolved content stream **and the
frozen variable snapshot per band instance** (§7), which 008 needs for per-page late substitution.
This contract is stated here because 007b defines the IR 008 consumes; 008 implements layout. 007a's
renderers draw the resolved elements `FilledReport` contains.

## 2. Scope & boundary

**In scope:** title/detail/summary/noData band emission; per-type element resolution (text
`expression`, image `FieldImageSource`→bytes); report-scoped running totals & grand totals;
diagnostics; the `FilledReport`/`FilledBand` IR. **Domain footprint: one additive field** —
`TextElement.expression` (+ its codec).

**Deferred → 007c:** group header/footer band sequencing, the `ReportBand`↔`ReportGroup` link,
group-scoped subtotals in the stream. The calculator still performs group *resets* internally in
007b (so report-scoped totals are correct and a report *may* declare groups for variable resets),
but 007b emits **no** group bands — declared group-scoped subtotals simply aren't displayed until
007c adds group footers.

**Deferred → 008:** page/column header/footer/background bands (page-scoped chrome); pagination;
page-scoped value *resolution* — defining the page variables, the fixed-bounds validation for their
*legal* carriers (fixed elements in page/column header/footer, blueprint §5), and late substitution
into reserved bounds. These require pagination and page-scoped bands that do not exist in 007b.

007b does, however, **reserve the page-scoped variable names** — a documented constant set
(`PAGE_NUMBER`, `PAGE_COUNT` for v1; 008 owns the authoritative list) — so it can **reject their
*illegal* use** in the bands it processes. A `title`/`detail`/`summary` text expression that
references a reserved page-scoped variable is an illegal placement (page-scoped values are legal
only in page/column header/footer, which Fill does not process) → **error diagnostic** + the element
keeps its authored `text` (§5). This enforces the blueprint's validation intent for 007b's bands
instead of silently blanking the evidence. A reference to any *other* undeclared variable resolves
to `JetNull` → blank, silently — 007b has no page-scoped machinery and no "deferred" slots.

Fill processes **only** `title`, `detail`, `summary`, `noData` bands; it ignores
`pageHeader`/`pageFooter`/`columnHeader`/`columnFooter`/`background`/`groupHeader`/`groupFooter`.

## 3. Entry point & pipeline (internal)

```dart
/// INTERNAL (src/, not exported). The public surface is the 011 JetReportEngine.
class ReportFiller {
  ReportFiller({JetFunctionRegistry? functions}); // defaults to registerBuiltInFunctions(...)
  FillResult fill(ReportTemplate template, JetDataSource source,
      {Map<String, Object?> params = const <String, Object?>{}});
}
class FillResult { final FilledReport report; final ReportDiagnostics diagnostics; }
```

One data pass:

1. Build `VariableCalculator(template.variables, template.groups, functions)` and `start()`.
   A malformed variable/group expression throws here — **structural, fail-fast** (§5).
2. Emit **title** (once, **no row** — §6) for each `title` band.
3. `open(params)` the dataset; for each row: `calc.advance(row, params)`, then emit **detail**(s)
   resolved against `(row, params, calc.values)`. `close()` in a `finally`.
4. If the dataset was empty: emit **noData** (no row). Otherwise emit **summary** (once, **no row**
   — §6) resolved against `(params, calc.values)`.
5. Return `FillResult(FilledReport(page: template.page, bands), diagnostics)`.

`ReportFiller`/`FilledReport`/`FillResult`/`ReportDiagnostics` are **internal** and **intentionally
incomplete** — 007c extends the band stream with group instances, so the IR must not be frozen as
public now.

## 4. Element resolution (per-type, in `fill/`)

Resolution lives in `rendering/fill/` because it needs both the model *and* the expression engine
(the layer DAG forbids `domain → expression`, so it cannot be a method on `ReportElement`). It
honors the 007a §3 field-partition contract — **same concrete type, same `id`/`bounds`/style**;
only the data-bearing field changes:

| Element | Resolution | Result |
|---|---|---|
| `TextElement` with `expression` | parse + evaluate against `(row, params, variables)` | new `TextElement(text: jetStringify(value), expression: null, …)` |
| `TextElement` without expression | — | unchanged (static) |
| `ImageElement` with `FieldImageSource` | look up the field in the row → bytes (`Uint8List`, or base64 `String`) | `ImageElement(source: BytesImageSource(bytes), …)`; unresolved → unchanged + **warning** |
| `BarcodeElement`, `ShapeElement`, **custom types** | — | **passthrough** (resolved == authored) |

`jetStringify(JetError)` is `'!ERR'`, so a failed text expression renders the error token (plus an
error diagnostic, §5). The resolver reconstructs each resolved element directly (no `copyWith`
needed). Custom element types pass through unchanged — the per-type built-in resolver chosen for
v1; custom data-binding is a documented future extension.

**Amendment to 007a §3 (barcode).** The 007a field-partition table prospectively listed
`BarcodeElement.data` as a substituted data-bearing field. v1 ships **no** barcode binding
mechanism (the fork chose text-only `expression`), so barcode resolves to itself (passthrough).
This spec amends the 007a §3 table to mark `barcode.data` as *not bindable in v1 (no barcode
expression); resolved == authored*. Barcode data-binding is deferred to a later spec.

## 5. Diagnostics & error policy (render-don't-crash)

```dart
enum DiagnosticSeverity { info, warning, error }
class Diagnostic { final DiagnosticSeverity severity; final String message; final String? elementId; }
class ReportDiagnostics {
  final List<Diagnostic> entries;
  void info(String m, {String? elementId});
  void warning(String m, {String? elementId});
  void error(String m, {String? elementId});
  bool get hasErrors;
}
```

Fill never throws on **content** problems — it collects them and continues, so a report always
produces a paintable `FilledReport` (critical for a live designer canvas). Structural faults still
fail fast.

| Case | Policy |
|---|---|
| Text expression — **parse** failure (`ExpressionException`) | caught → element text `'!ERR'` + **error** diagnostic |
| Text expression — **eval** error (`JetError` result) | text `'!ERR'` (via `jetStringify`) + **error** diagnostic |
| Text expression references a **reserved page-scoped variable** in a `title`/`detail`/`summary` band | **error** diagnostic (illegal placement, §2) + element keeps its authored `text` (not blanked, not `!ERR`) |
| `$F{name}` to a field **absent from the current row's schema** (`!row.hasField(name)`) — element **or** variable/group expression | blank + **warning** (deduped per field name — the schema-drift / typo signal) |
| `$F{name}` to a **declared-but-null** field | blank, **no** diagnostic (legitimate null data) |
| `$F{}` / undeclared `$V{}` in title/summary (no row) | blank, **no** diagnostic (no row is expected; page vars legitimately absent) |
| Unresolvable `FieldImageSource` (field missing or not byte-like) | renderer placeholders it + **warning** |
| Variable/group expression **parse** failure | **fail fast** — typed structural exception (report-definition error) |

Both content signals come from a single `fill/` `EvalContext` that wraps the data row, params, and
the calculator's variable values:
- **Missing-field warnings** — it records a warning (deduped per field name) when `resolveField` is
  asked for a name the current row's schema does not declare; a declared-but-null field and a no-row
  context stay silent.
- **Page-scoped detection** — it records, **precisely via `resolveVariable`** (so a string literal
  containing `$V{PAGE_NUMBER}` cannot false-positive — only a real reference triggers it), that an
  expression referenced a reserved page-scoped name; the resolver then raises the illegal-placement
  error for text expressions. Any other missing variable resolves to `JetNull` silently.

To make the missing-field warning reach **variable and group expressions** too — not just element
expressions — `VariableCalculator` gains an **optional eval-context factory** (additive; the default
builds `RowEvalContext`, so 005b behavior is unchanged). Fill injects a factory that builds this
tracking context sharing the same diagnostics sink, so a typo'd field inside a `SUM` variable —
which the accumulator otherwise skips as `JetNull` silently (`variable_accumulator.dart`) and quietly
corrupts the total — now surfaces a warning. Dedup-by-field-name bounds the volume across element,
variable, and group evaluations.

## 6. Band context (no order-sensitivity)

`detail` bands resolve against their data row plus the calculator's current values (running totals).
`title` and `summary` resolve with **no row**: `$F{}` references blank, and the bands read
`$V{}` (grand totals — for `summary`, the final accumulated values) and `$P{}` params. This is a
deliberate contract: **summary output never depends on which row happened to be last**, so a fill
is order-stable with respect to row-field access in the summary. (Summary's *aggregate* values do
reflect all rows, via the calculator — that is the point of a grand total.)

## 7. `FilledReport` IR (value-equal, snapshot-testable)

```dart
class FilledReport { final PageFormat page; final List<FilledBand> bands; /* value == + hashCode */ }
class FilledBand  {
  final BandType type;
  final double height;
  final List<ReportElement> elements;    // resolved copies
  final Map<String, JetValue> variables; // frozen variable snapshot at this instance
  /* value == (incl. deep map equality on variables) */
}
```

Per the blueprint (`FilledReport` = "resolved values **+ frozen variable values**"), each
`FilledBand` carries a **frozen snapshot of the calculator's variable values** as of when it was
emitted — initial values for `title`/`noData`, the post-`advance` values for each `detail`, the
final values for `summary`. 008 uses these for **per-page late substitution** (e.g. a page footer's
running total at a page boundary) without re-running Fill. `calc.values` already returns a defensive
copy, so snapshotting is cheap.

Pure data with value equality (resolved `ReportElement`s and `JetValue`s are value-equal; the
`variables` map compares by deep map equality), so a fill is a **data golden**: assert the band
stream's types + resolved element values + frozen variables, and that identical inputs yield an
identical `FilledReport` (determinism). `FilledBand` is geometry-free — the output 008 measures and
paginates.

## 8. Testing (data goldens + behavior)

- **Flat data golden** — a title/detail/summary template over a `JetInMemoryDataSource`; assert the
  resolved band stream (types + resolved element text values).
- **Text-expression resolution** — `CONCAT($F{first}, " ", $F{last})` → resolved `text`.
- **Image field resolution** — `FieldImageSource('photo')` whose row value is bytes → `BytesImageSource`.
- **Running + grand totals** — a report-scoped `SUM($F{amount})` variable: detail shows the running
  total, summary shows the grand total.
- **noData** — empty source → one `noData` band, no detail/summary.
- **Diagnostics** — a bad-syntax text expression → `'!ERR'` + an **error** diagnostic (no throw); a
  `$F{}` to an undeclared field → blank + a **warning**; a declared-null field → blank, no diagnostic.
- **Page-scoped rejection** — a `detail` text expression referencing `$V{PAGE_NUMBER}` → an **error**
  diagnostic + the element keeps its authored `text` (not blanked); a *string literal* containing the
  characters `$V{PAGE_NUMBER}` does **not** trigger it (precise `resolveVariable` detection).
- **Variable schema-drift** — a `SUM($F{typo})` variable over a schema without `typo` → a **warning**
  (via the calculator's injected tracking context), not a silently wrong total.
- **Frozen variables** — each `FilledBand` carries the variable snapshot: detail bands show the
  running `$V{total}`, summary carries the grand total.
- **Fail-fast** — a malformed *variable* expression → the fill throws a typed structural exception.
- **Band context** — `$F{}` in `summary` resolves to blank (no row), while `$V{}` grand total resolves.
- **Determinism** — re-filling identical inputs yields an equal `FilledReport`.

## 9. Public API & exports

Nothing is exported from `jet_print.dart` in 007b. `ReportFiller`, `FilledReport`, `FillResult`,
`ReportDiagnostics`, and the `fill/` eval context are `src/`-internal and exercised white-box
(`package:jet_print/src/...`; `/test/rendering/` is allowlisted). The 011 `JetReportEngine` is the
eventual public door; `FilledReport` is intentionally incomplete until 007c.

## 10. Design decisions & deviations (auditable)

1. **Page-scoped *resolution* deferred to 008, but illegal placements rejected now** (§2, §5) —
   007b reserves the page-scoped names and raises an error diagnostic (precise `resolveVariable`
   detection) when a `title`/`detail`/`summary` expression references one, preserving the blueprint's
   validation intent instead of silently blanking; other undeclared variables → blank.
2. **Split parse-failure policy** (§5) — content (text) expressions caught → `!ERR` + diagnostic;
   structural (variable/group) expressions fail fast.
3. **Barcode passthrough is an explicit 007a §3 amendment** (§4), not an implicit omission.
4. **Missing-field warning honored across element AND variable/group expressions** (§5) — via an
   injected calculator eval-context factory, distinguishing undeclared (warn) from declared-null
   (silent).
5. **Title/summary have no row context** (§6) — summary is order-stable.
6. **Internal, intentionally-incomplete IR** (§3, §9) — not frozen public; 007c extends it.
7. **008 consumes `(ReportTemplate, FilledReport)`** (§1) — the template for page chrome + page
   variables, the FilledReport for resolved content + frozen variable snapshots.
8. **`FilledBand` carries a frozen variable snapshot** (§7) — the blueprint's "frozen variable
   values," for 008's per-page late substitution.
9. **`VariableCalculator` gains an optional eval-context factory** (§5) — additive, default
   `RowEvalContext`; lets Fill's diagnostics reach variable/group expressions.

## 11. File plan

- **Modify:** `domain/elements/text_element.dart` (+`expression`); `domain/serialization/text_element_codec.dart`
  (optional `expression` field); `expression/aggregate/variable_calculator.dart` (additive optional
  eval-context factory, default `RowEvalContext`); `CHANGELOG.md`;
  `test/architecture/layer_boundaries_test.dart` (assert `rendering/fill/` is headless and imports no
  `rendering/elements`/`rendering/frame`/`rendering/paint`).
- **Create:** `rendering/fill/{report_diagnostics, filled_report, fill_eval_context, element_resolver, report_filler}.dart`
  (`FillResult` lives with `report_filler.dart`; the reserved page-scoped-name constant lives in
  `fill/`, e.g. alongside the resolver); `test/rendering/fill/*`.

## 12. Review history

Pre-write review (GitHub Copilot), folded in: page-scoped placeholder rule was inconsistent with
the blueprint's fixed-bounds carriers and 007b's own band scope → **removed from 007b, deferred to
008** (§2). "Render-don't-crash" omitted parse-time throws → **explicit split policy** (§5).
Barcode passthrough contradicted the 007a seam → **explicit 007a §3 amendment** (§4). Missing-field
silent-blanking diverged from the blueprint → **warning honored** (§5). Entry point read as public
→ **internal, intentionally-incomplete IR** (§3, §9). Open question on summary order-sensitivity →
**title/summary carry no row context** (§6).

Second review round, folded in: deferring page chrome + all page-scoped handling left 008 without
enough input → **008's contract restated as `(ReportTemplate, FilledReport)`** and **`FilledBand`
now carries the frozen variable snapshot** the blueprint mandates (§1, §7). Treating page-variable
names as silently-blanked undeclared variables made the validation rule unenforceable and discarded
authored intent → **reserved page-scoped names + reject illegal placements with an error
diagnostic** (precise `resolveVariable` detection, §2, §5). The missing-field warning didn't reach
variable/group expressions (the calculator uses its own `RowEvalContext`, and the accumulator skips
`JetNull`/`JetError` silently) → **`VariableCalculator` gains an injected eval-context factory so the
warning covers all expressions** (§5).
