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
no pagination, no rendering. 008 (Layout) consumes `FilledReport`; 007a's renderers draw the
resolved elements it contains.

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
**all page-scoped-expression handling** — page variables (`$V{PAGE_NUMBER}`, `$V{PAGE_COUNT}`),
the fixed-bounds validation rule (blueprint §5), and late substitution into reserved bounds. These
require pagination and page-scoped bands that do not exist in 007b. In 007b a reference to an
undeclared variable (including a page-variable name) resolves to `JetNull` → blank (§5), with no
special handling — Fill has no notion of "deferred" slots.

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
| `$F{name}` to a field **absent from the current row's schema** (`!row.hasField(name)`) | blank + **warning** (deduped per field name — the schema-drift / typo signal) |
| `$F{name}` to a **declared-but-null** field | blank, **no** diagnostic (legitimate null data) |
| `$F{}` / undeclared `$V{}` in title/summary (no row) | blank, **no** diagnostic (no row is expected; page vars legitimately absent) |
| Unresolvable `FieldImageSource` (field missing or not byte-like) | renderer placeholders it + **warning** |
| Variable/group expression **parse** failure | **fail fast** — typed structural exception (report-definition error) |

The missing-field warning is implemented by a `fill/` `EvalContext` that wraps the data row and
records a warning when `resolveField` is asked for a name the row's schema does not declare; a
declared-but-null field and a no-row context stay silent. Missing **variables** (e.g. a
not-yet-existing page variable) resolve to `JetNull` silently — 007b is not noisy about names 008
will introduce.

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
class FilledBand  { final BandType type; final double height; final List<ReportElement> elements; /* value == */ }
```

Pure data with value equality (the resolved `ReportElement`s are already value-equal), so a fill is
a **data golden**: assert the band stream's types + resolved element values, and that identical
inputs yield an identical `FilledReport` (determinism). `FilledBand` carries only `type`, `height`,
and the resolved `elements` — the geometry-free output 008 measures and paginates.

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
- **Fail-fast** — a malformed *variable* expression → the fill throws a typed structural exception.
- **Band context** — `$F{}` in `summary` resolves to blank (no row), while `$V{}` grand total resolves.
- **Determinism** — re-filling identical inputs yields an equal `FilledReport`.

## 9. Public API & exports

Nothing is exported from `jet_print.dart` in 007b. `ReportFiller`, `FilledReport`, `FillResult`,
`ReportDiagnostics`, and the `fill/` eval context are `src/`-internal and exercised white-box
(`package:jet_print/src/...`; `/test/rendering/` is allowlisted). The 011 `JetReportEngine` is the
eventual public door; `FilledReport` is intentionally incomplete until 007c.

## 10. Design decisions & deviations (auditable)

1. **Page-scoped handling deferred to 008** (§2) — its legal carriers are page-scoped bands Fill
   does not process, and it requires pagination; 007b treats page-variable names as ordinary
   undeclared variables (→ blank).
2. **Split parse-failure policy** (§5) — content (text) expressions caught → `!ERR` + diagnostic;
   structural (variable/group) expressions fail fast.
3. **Barcode passthrough is an explicit 007a §3 amendment** (§4), not an implicit omission.
4. **Missing-field warning honored** per the blueprint + `EvalContext` doc (§5), distinguishing
   undeclared (warn) from declared-null (silent).
5. **Title/summary have no row context** (§6) — summary is order-stable.
6. **Internal, intentionally-incomplete IR** (§3, §9) — not frozen public; 007c extends it.

## 11. File plan

- **Modify:** `domain/elements/text_element.dart` (+`expression`); `domain/serialization/text_element_codec.dart`
  (optional `expression` field); `CHANGELOG.md`; `test/architecture/layer_boundaries_test.dart`
  (assert `rendering/fill/` is headless and imports no `rendering/elements`/`rendering/frame`/`rendering/paint`).
- **Create:** `rendering/fill/{report_diagnostics, filled_report, fill_eval_context, element_resolver, report_filler}.dart`
  (`FillResult` lives with `report_filler.dart`); `test/rendering/fill/*`.

## 12. Review history

Pre-write review (GitHub Copilot), folded in: page-scoped placeholder rule was inconsistent with
the blueprint's fixed-bounds carriers and 007b's own band scope → **removed from 007b, deferred to
008** (§2). "Render-don't-crash" omitted parse-time throws → **explicit split policy** (§5).
Barcode passthrough contradicted the 007a seam → **explicit 007a §3 amendment** (§4). Missing-field
silent-blanking diverged from the blueprint → **warning honored** (§5). Entry point read as public
→ **internal, intentionally-incomplete IR** (§3, §9). Open question on summary order-sensitivity →
**title/summary carry no row context** (§6).
