# Phase 1 Data Model: Simplified Label Value & Format Properties

**Feature**: `013-label-value-format` | **Date**: 2026-06-11 | **Plan**: [plan.md](plan.md)

This feature adds **one** persisted field and otherwise reuses existing model state. The
"value field" forms and the `{ … }` template are *editing/presentation* concepts that map onto
the existing `text` / `expression` fields — they are not new persisted entities.

---

## Entity: `TextElement` (modified)

Location: `packages/jet_print/lib/src/domain/elements/text_element.dart`

| Field | Type | New? | Notes |
|---|---|---|---|
| `id` | `String` | — | unchanged |
| `bounds` | `JetRect` | — | unchanged |
| `text` | `String` | — | literal content (or the resolved value after Fill) |
| `style` | `JetTextStyle` | — | unchanged; default `JetTextStyle.fallback` |
| `expression` | `String?` | — | binding as an **expression string** (`$F{…}`, `CONCAT(…)`, …); `null` = literal. Unchanged shape — the value field/template compile **into** this field |
| `format` | `String?` | **NEW** | optional ICU pattern applied to the resolved value at render time; `null`/empty = unformatted |

**Rules**
- `copyWith` MUST accept and preserve `format` (today it preserves `expression`; extend it to
  carry `format` and to allow setting it).
- Equality / `hashCode` / `toString` MUST include `format`.
- A label is **bound** iff `expression != null`; otherwise **literal**.
- `format` is independent of bound/literal but only has a visible effect on bound (expression)
  values (literal text bypasses the expression+format path).

**State / derived presentation (not persisted)**

The designer derives the value-field string and canvas token from `text`/`expression`:

```text
display(textElement):
  if expression == null      → text                       (literal; escape brackets/braces)
  else                       → reverseCompile(expression)  → "[field]"  or  "{ … }"  or  "{ raw }"(read-only)
```

```text
parseValueField(input):
  if input is "\…escaped…"   → literal text(unescaped),  expression = null
  if input matches ^\[ident\]$ → expression = "$F{ident}", keep text
  if input is "{ … }"        → expression = compileTemplate(inner), keep text
  else                       → literal text = input,      expression = null
```

---

## Entity: `FormatPreset` (designer-layer, not persisted)

Location: designer layer (e.g. `packages/jet_print/lib/src/designer/.../format_presets.dart`)

A fixed list of seven `(labelKey, pattern)` pairs surfaced as quick-picks. Only the resulting
**pattern string** ever reaches the model (`TextElement.format`); the preset identity is not
stored.

| Preset | `format` pattern written |
|---|---|
| None | `""` (clears `format` → `null`) |
| Integer | `#,##0` |
| Decimal | `#,##0.00` |
| Currency | `¤#,##0.00` |
| Percent | `#,##0%` |
| Date | `yyyy-MM-dd` |
| Date & time | `yyyy-MM-dd HH:mm` |

---

## Serialization (modified)

Location: `packages/jet_print/lib/src/domain/serialization/text_element_codec.dart`

```text
toJson(el):
  { id, bounds, text,
    style?      (only if != fallback),
    expression? (only if != null),
    format?     (only if != null)   ← NEW, additive, optional
  }

fromJson(json):
  TextElement(
    …,
    expression: json['expression'] as String?,
    format:     json['format']     as String?,   ← NEW; absent ⇒ null
  )
```

- **Schema version**: stays `kReportSchemaVersion = 1` (pre-1.0 additive-optional carve-out in
  `report_codec.dart`). No migration.
- **Backward compatibility**: templates saved before this change have no `format` key ⇒ decode
  to `format: null` ⇒ identical render (spec FR-013/FR-015, SC-005).

---

## Rendering inputs (modified, non-persisted)

Location: `packages/jet_print/lib/src/rendering/fill/` (`element_resolver.dart`,
`fill_eval_context.dart`, and the fill entry point)

| Input | Type | New? | Notes |
|---|---|---|---|
| resolved value | `JetValue` | — | from `Expression.parse(expression).evaluate(ctx)` |
| `format` pattern | `String?` | (from model) | applied via shared `applyJetFormat` before `jetStringify` |
| `unresolvedFieldToken` | `String` | **NEW** | fill option; default `'#ERROR'`; designer/preview pass localized value |
| known-field set / schema | `Set<String>?` | **NEW (optional)** | when present, a `$F{name}` outside it resolves to `unresolvedFieldToken`; when absent, behavior unchanged (missing ⇒ empty) |

---

## Relationships & invariants

- `TextElement.expression` remains the **single source of truth** for a binding. The value
  field and `{ … }` template are bidirectional projections of it (compile ↔ reverse-compile).
- Canonical normalization guarantees `{[name]}` ≡ `[name]` ≡ `expression "$F{name}"`, so a
  binding round-trips through the value field without drifting (SC-002, SC-004).
- `format` and `expression` are orthogonal: changing one never alters the other.
- WYSIWYG invariant (Constitution IV): the same `expression` + `format` produce the same output
  in canvas-preview, preview, and export, because all share `ElementResolver` →
  `applyJetFormat` → the existing paint/export pipeline.
