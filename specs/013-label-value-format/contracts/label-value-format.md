# Contracts: Simplified Label Value & Format Properties

**Feature**: `013-label-value-format` | **Date**: 2026-06-11 | **Plan**: [plan.md](plan.md)

These are behavioral contracts (with the test groups that pin them) for the editing surface,
the template compiler, formatting, and rendering. The library is consumed only through
`package:jet_print/jet_print.dart`; the only public-surface change is the additive
`TextElement.format` field.

---

## C1 — Value-field parsing (designer)

A single value input replaces the Text + Binding pair for text elements. Given the committed
string `v`:

| `v` | Resulting model edit |
|---|---|
| `""` | literal: `text=""`, binding cleared |
| `sample text` | literal: `text="sample text"`, binding cleared |
| `[customerName]` (whole value, well-formed) | binding: `expression="$F{customerName}"` |
| `{[firstName] [lastName]}` | binding: `expression=CONCAT($F{firstName}, " ", $F{lastName})` |
| `{upper[name]}` | binding: `expression=UPPER($F{name})` |
| `Total: [qty]` (brackets mid-text, no braces) | literal: `text="Total: [qty]"` |
| `\[draft]` | literal: `text="[draft]"` (escape consumed) |

- Changing the value between bound and literal is **one undoable commit** (FR-005, SC-004).
- A bound element's value field **displays** the binding via reverse-compile: `$F{x}` → `[x]`,
  template expressions → `{ … }`; an out-of-grammar expression → read-only `{ raw }` + hint.
- **Tests**: `value_field_parse_test.dart` (widget), `properties_editor_test.dart` (extend).

---

## C2 — Template compiler (designer, pure)

`compileTemplate(String inner) → String` (expression source) and
`reverseCompile(String expression) → String` (template/`[field]` form).

Contract:
- `compileTemplate` output MUST parse under the existing `Expression.parse` without error for
  all valid templates.
- Canonical normalization: a single-field template normalizes to the simple binding —
  `compileTemplate("[name]") == "$F{name}"`; the panel stores `[name]` and `{[name]}`
  identically.
- Round-trip on the supported subset: `reverseCompile(compileTemplate(t))` is `t` in canonical
  form (idempotent), and `compileTemplate(reverseCompile(e))` is `e` in canonical form.
- Escaping: literal `[`,`]`,`{`,`}`,`\` round-trip via backslash; quotes/backslashes inside
  literal runs are escaped into expression string literals.
- Out-of-grammar expression (params `$P{}`, variables `$V{}`, arithmetic, unknown funcs):
  `reverseCompile` returns the raw expression wrapped for read-only display; the panel marks it
  non-editable-as-template.
- **Tests**: `template_compiler_test.dart` (unit) — forward, reverse, round-trip, escaping,
  normalization, legacy fallback.

---

## C3 — Format application (rendering, pure)

`applyJetFormat(JetValue value, String pattern) → JetValue` — extracted shared helper.

Contract:
- `JetNumber` + numeric pattern → `JetString` via `NumberFormat(pattern)` (locale from
  `Intl.getCurrentLocale()`).
- `JetDate` + date pattern → `JetString` via `DateFormat(pattern)`.
- Type mismatch (e.g. number pattern on `JetString`) → returns `value` **unchanged**.
- Malformed pattern (`FormatException`) → returns `value` unchanged (never `!ERR`) (FR-012).
- Empty pattern → returns `value` unchanged.
- The existing `FORMAT(value, pattern)` function MUST delegate to this helper (no behavior
  change to `FORMAT`; parity test).
- In `ElementResolver._resolveText`, when `el.format` is non-empty, the resolved value passes
  through `applyJetFormat` before `jetStringify`.
- **Tests**: `apply_jet_format_test.dart` (unit), `format_functions_test.dart` (parity, extend),
  `element_resolver_format_test.dart` (render integration).

---

## C4 — Unresolved-binding token (rendering)

- Fill entry point gains `String unresolvedFieldToken = '#ERROR'` and an optional known-field
  set.
- With a known-field set provided: a `$F{name}` whose `name` is absent from it resolves to
  `unresolvedFieldToken` (whole resolved value), not empty.
- Without a known-field set: **unchanged** — missing field → empty (no regression; SC-005).
- Determinism preserved: same inputs + token → same bytes (no clock/locale ambient reads beyond
  the already-set render locale).
- Designer preview passes the localized `errorUnresolvedToken` string; headless export uses the
  default `#ERROR` (or host override).
- **Tests**: `unresolved_token_test.dart` (unit) — token-with-schema, empty-without-schema,
  determinism.

---

## C5 — Serialization

- `TextElementCodec.toJson` writes `format` only when non-null; `fromJson` reads it as optional
  (absent ⇒ `null`).
- `kReportSchemaVersion` unchanged (1); no migration added.
- Old fixtures (no `format`) decode unchanged; new templates round-trip byte-stably.
- **Tests**: `text_element_codec_test.dart` / `element_codec_test.dart` (extend),
  `report_codec_test.dart` (round-trip with `format`).

---

## C6 — Localization

New ARB keys in `jet_print_en.arb` (+ de/tr): `propertiesValue`, `valueFieldHint`,
`propertiesFormat`, `formatHint`, the seven preset labels (`formatPresetNone`,
`formatPresetInteger`, `formatPresetDecimal`, `formatPresetCurrency`, `formatPresetPercent`,
`formatPresetDate`, `formatPresetDateTime`), and `errorUnresolvedToken` (`#ERROR`). English
fallback for unsupported locales; no raw keys leak.
- **Tests**: `localization_test.dart` (+ `_de`/`_tr` siblings) extended.

---

## C7 — Public API surface

- **Added**: `TextElement.format` (constructor named param + getter + `copyWith` support).
  `TextElement` is already public via `package:jet_print/jet_print.dart`.
- **Removed/Changed**: none of the public render/export API. The template compiler, value
  field, format presets, and `applyJetFormat` live under `src/` (not exported) unless a test or
  the playground needs them — default is **internal**.
- The encapsulation / architecture test pins that nothing new leaks from `src/` and that the
  rendering layer gains no Flutter/l10n import (the `#ERROR` token stays a `String` parameter).
- **Tests**: existing `architecture/`/encapsulation tests (extend assertions for the new field
  and the no-l10n-in-rendering rule).
