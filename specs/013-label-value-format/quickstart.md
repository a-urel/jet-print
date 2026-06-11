# Quickstart: Simplified Label Value & Format Properties

**Feature**: `013-label-value-format` | **Date**: 2026-06-11 | **Plan**: [plan.md](plan.md)

This feature changes the **designer's Properties panel** for labels; it requires no new setup
or API calls from a host application. Below is how a report designer (end user) experiences it,
plus the one public-API touchpoint for code that constructs labels directly.

## For the report designer (UI)

Select a label. The Properties panel now shows **one Value field** (instead of separate Text
and Binding fields) plus a **Format field**.

**Bind to a field** — type the field name in brackets:

```text
Value:  [customerName]
```

The canvas and the field both show `[customerName]`; at report time it shows the field's value.

**Literal text** — type anything else:

```text
Value:  Paid in full
```

To make literal text that contains brackets, escape them:

```text
Value:  \[draft]          → renders the literal text  [draft]
```

**Advanced template** — wrap in braces to combine fields or apply functions:

```text
Value:  {[firstName] [lastName]}    → John Smith
Value:  {upper[name]}               → JOHN
Value:  {Total: [qty]}              → Total: 3
```

**Format** — pick a preset or type an ICU pattern; empty = unformatted:

```text
Format:  #,##0.00     → 1234.5  shows as  1,234.50
Format:  yyyy-MM-dd   → a date shows as   2026-06-11
Format:  (presets)    → None · Integer · Decimal · Currency · Percent · Date · Date & time
```

A binding to a field that is not in the data source shows a "field not found" hint while
editing and renders `#ERROR` in preview.

## For code that builds labels (public API)

`TextElement` gains an optional `format`:

```dart
const TextElement(
  id: 'amount',
  bounds: JetRect(x: 0, y: 0, width: 120, height: 18),
  text: 'amount',
  expression: r'$F{amount}',   // a binding (as today)
  format: '#,##0.00',          // NEW: ICU pattern applied to the resolved value
);
```

- `format` is optional; omitting it (or `null`) renders the value unformatted — existing
  templates are unaffected.
- A pattern that does not fit the value's type, or is malformed, falls back to the unformatted
  value (never an error token).
- No schema-version change: templates saved before this feature load unchanged.

## Verifying

```bash
# from repo root
flutter test packages/jet_print
```

Key checks: one value field appears for a selected label (no second binding field); typing
`[field]`, `{ … }`, and literal text each produce the right model edit as a single undoable
step; the Format field + presets format a bound numeric/date value; an existing template (no
`format`) renders identically (goldens).
