# Payroll sample (playground) — design

**Date:** 2026-06-19
**Status:** Approved (brainstorming) — ready for implementation plan
**Scope:** Add a new "Payroll" report sample to `apps/jet_print_playground`, between
the Packing slip and List tabs. Public API only (`package:jet_print/jet_print.dart`);
**no engine changes**.

## Goal

A comprehensive, real-world-like **multi-employee payroll run** rendered as one
document: employees grouped by **department**, each employee getting a full US-style
**pay stub** with parallel Earnings and Deductions line-item tables (with year-to-date
columns), a highlighted Net Pay box, and a verification QR. Department subtotals and a
company grand total close the run.

The sample doubles as an engine showcase. It is the first playground sample to use
**two parallel nested collections** (earnings *and* deductions) under one master row —
distinct from the single linear nesting (Box ▸ Item) the packing slip shows.

## Why this shape

A pay stub is the most recognizable payroll artifact. Department grouping plus per-employee
stubs exercises multi-level `GroupLevel` breaks, master-scope inline aggregates, nested
single-fold aggregates, field arithmetic, `ShapeElement` layering, a QR `BarcodeElement`,
and `PageFurniture` — a broad, realistic slice of the band model.

## Engine constraints that shape the layout (verified on `main`)

From `packages/jet_print/lib/src/domain/report_validation.dart`:

1. **One renderable per-row band per scope.** A `DetailScope` may *structurally* hold 2+
   `BandNode`s, but `validate()` emits info `"…has N per-row bands; multiple per-row bands
   are not yet rendered"` ([report_validation.dart:295](../../../packages/jet_print/lib/src/domain/report_validation.dart)).
   So a scope can show only **one** per-row band. We cannot put an "Earnings header band"
   and a "Deductions header band" as siblings under one employee scope.
2. **Multiple `NestedScope` children are fully legal** (no per-row-band penalty). Earnings
   and Deductions both nest under the employee scope.
3. **`GroupLevel` headers/footers are separate slots** — they do not count toward the
   per-row-band limit, and multi-level grouping on the **root** scope renders (per-scope
   grouping on nested scopes is deferred).
4. **Aggregates** are supported in summary bands, root group footers, and nested-scope
   footers: `SUM($F{master})` over master rows in a group footer (spec 028), and
   `SUM($F{leaf})` folding a nested scope's own rows (spec 029). Field arithmetic
   `$F{a} - $F{b}` works in the expression evaluator
   ([evaluator.dart:100](../../../packages/jet_print/lib/src/expression/evaluator.dart)).
   We deliberately avoid `SUM(a) - SUM(b)` top-level arithmetic over aggregates (an
   unmerged fx-editor / spec 032 feature).

## Data model

`Employee` master rows, each with two parallel nested collections.

**Employee (master, `JetDataSchema payrollSchema`):**
`empNo, empName, jobTitle, department, payPeriod, payDate, payMethod, grossPay,
totalDeductions, netPay, verifyToken`

**earnings[]** (collection): `type, hours, rate, earnAmount, earnYtd`
**deductions[]** (collection): `type, dedAmount, dedYtd`

`grossPay / totalDeductions / netPay` are stored as the authoritative employee-level
figures (as a real payroll system computes them) **and** reconciled live on the page:
the Earnings footer shows `SUM($F{earnAmount})` (= gross), the Deductions footer shows
`SUM($F{dedAmount})` (= total deductions), and Net is derived live via
`$F{grossPay} - $F{totalDeductions}`. Storing the totals lets department subtotals and the
grand total use master-scope `SUM($F{grossPay})` / `SUM($F{netPay})` without cross-collection
aggregation.

Field names are distinct across the two collections (`earnAmount`/`dedAmount`,
`earnYtd`/`dedYtd`) for readability. Sample data is **ordered by department** so grouping
breaks correctly (the engine groups pre-sorted rows, like the existing samples).

## Band structure

Each scope has **≤1 per-row band** — engine-legal.

```
root DetailScope (iterates employees, pre-sorted by department)
├─ groups:
│   ├─ GroupLevel "department"  key=$F{department}
│   │     header → dept banner ("DEPARTMENT — Engineering")
│   │     footer → dept subtotals: SUM(grossPay) / SUM(totalDeductions) / SUM(netPay)
│   └─ GroupLevel "employee"  key=$F{empNo}  keepTogether:true
│         header → identity card (name, empNo, jobTitle, payPeriod, payDate, payMethod)
│                  + verification QR (BarcodeElement, dataField: verifyToken)
│                  + "EARNINGS" heading + earnings column titles
│         footer → NET PAY highlight box (filled ShapeElement behind
│                  $F{grossPay} - $F{totalDeductions}) + employer/confidentiality note
└─ children:
    ├─ NestedScope "earnings" (collectionField: earnings)
    │     row    → type | hours | rate | earnAmount | earnYtd
    │     footer → "Gross pay" SUM(earnAmount)
    │              + "DEDUCTIONS" heading + deduction column titles
    └─ NestedScope "deductions" (collectionField: deductions)
          row    → type | dedAmount | dedYtd
          footer → "Total deductions" SUM(dedAmount)
```

**Structural compromise (engine-forced):** the "DEDUCTIONS" section heading and its column
titles ride at the **bottom of the Earnings footer band**, because a scope cannot hold two
per-row header bands. This matches how payslips read visually — Earnings block, then
Deductions block.

**Page furniture:** running header `"PAYROLL"`; footer
`"Page " + PAGE_NUMBER + " of " + PAGE_COUNT + "  ·  Confidential"`.

## Extras (all confirmed in scope)

- **YTD columns** on every earnings and deductions line (bound to `earnYtd` / `dedYtd`).
- **Net-pay highlight box** — a filled `ShapeElement` rectangle behind the NET PAY figure.
- **Verification QR** — `BarcodeElement` (`BarcodeSymbology.qrCode`) bound to `verifyToken`
  in the employee header, with a literal fallback for the headless/no-row canvas.
- **Page footer** via `PageFurniture` ("Page X of Y · Confidential").

## Sample data

4 employees across 2 departments (Engineering ×2, Sales ×2). Each has 2–4 earnings and
3–5 deductions. Amounts are deterministic and self-consistent: `grossPay − totalDeductions
= netPay`, and the stored `grossPay` / `totalDeductions` equal the live `SUM` folds of the
line items. US-style deduction types (Federal Tax, Social Security, Medicare, 401(k),
Health Insurance). USD / `en` locale, `#,##0.00` currency formatting.

`kSamplePayroll` is the single source of truth for both the data source and the test, so
the rendered totals and expected sums cannot drift (mirrors the packing slip's
`kSampleShipment`).

## Files

| File | Contents |
|------|----------|
| `apps/jet_print_playground/lib/payroll_sample.dart` | `payrollSchema` (JetDataSchema) + `payrollDefinition()` (ReportDefinition) |
| `apps/jet_print_playground/lib/rendered_payroll_example.dart` | `kSamplePayroll` data + `payrollDataSource()` + `renderPayrollDefinition(...)` |
| `apps/jet_print_playground/lib/main.dart` | imports + new `ShadTab` (value `'bordro'`, payroll/wallet icon) after `makbuz` |
| `apps/jet_print_playground/lib/l10n/app_en.arb` / `app_de.arb` / `app_tr.arb` | new `tabPayroll` key ("Payroll" / "Gehaltsabrechnung" / "Bordro"); regenerate the committed `app_localizations*.dart` via `flutter gen-l10n` |
| `apps/jet_print_playground/test/…` | a test mirroring the packing-slip sample test: render `payrollDefinition()` over `payrollDataSource()`, assert the live `SUM` folds equal the stored gross/deductions/net |

## Render entry point

`renderPayrollDefinition({ReportDefinition? definition, JetDataSource? source,
List<JetFontFamily> fonts})` → `JetReportEngine().renderDefinition(...)` with
`RenderOptions(locale: Locale('en'), knownFields: <all schema field names>, fonts: fonts)`
— identical wiring to `renderPackingSlipDefinition`. `definition` defaults to the bundled
sample so the designer tab can pass live edits; `source` defaults to the sample data.

## Out of scope (YAGNI)

- No engine changes; no new domain types; no reliance on unmerged fx-editor (032) features.
- No per-scope grouping (deferred in the engine).
- No additional locales beyond the existing en/de/tr.
- No employer-logo image; the QR is the only graphic flourish beyond the highlight box.

## Risks / verification

- **Multiple per-row bands.** Mitigated by the structure above (each scope ≤1 per-row band;
  section headings ride in group/scope-footer slots). Will confirm `validate()` returns no
  errors (info diagnostics acceptable) on the finished definition.
- **Total reconciliation.** The test asserts stored totals equal the live folds, and that
  department subtotals + grand total equal the sum of member employees.
- **Manual GUI walk.** Render the tab, confirm stubs paginate with `keepTogether`, the QR
  scans, the net box highlights, and YTD columns align.
