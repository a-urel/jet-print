# Phase 0 Research: Simplified Label Value & Format Properties

**Feature**: `013-label-value-format` | **Date**: 2026-06-11 | **Plan**: [plan.md](plan.md)

This document resolves the open design questions for the unified label value field, the
`{ … }` advanced-template syntax, the `format` property, and the localized `#ERROR` token,
grounding each decision in the existing codebase so the design honors the constitution
(minimal public surface, strict layering, WYSIWYG via a single render path, TDD).

---

## 1. Value-field model: one field, three forms

**Decision.** The single value input recognizes exactly three forms, decided by a
deterministic parse of the whole string:

| Input (whole value) | Meaning | Stored on `TextElement` |
|---|---|---|
| `[fieldName]` (one well-formed token, nothing else) | Simple field binding | `expression = "$F{fieldName}"`, `text` unchanged |
| `{ … }` (wrapped in braces) | Advanced template | `expression = <compiled expression string>` |
| anything else (incl. `Total: [x]`, `sample text`) | Literal | `text = <unescaped value>`, `expression = null` |
| empty | Empty literal | `text = ""`, `expression = null` |

- A bare `[field]` binds **only** when it spans the entire value (matches the existing
  `binding_token.dart` rule `^\$F\{([^}]*)\}$` in reverse). Brackets appearing inside literal
  text (`Total: [x] of [y]`) stay literal (spec Edge Cases).
- **Escape character**: a backslash `\` makes the next `[`, `]`, `{`, `}`, or `\` literal, so
  a designer can author literal `[draft]` as `\[draft]` and literal braces as `\{ \}`. Chosen
  because backslash is the conventional escape and appears in no field name or ICU pattern the
  value field accepts. (Exact rendering of a lone trailing `\` → literal backslash.)

**Rationale.** Keeps the common cases (`[customerName]`, `sample text`) friction-free while
giving advanced authoring a single unambiguous gate (`{ … }`). All three forms collapse onto
the **existing** `TextElement.text` / `TextElement.expression` fields — no new binding field,
no schema change for bindings, and the render pipeline (`ElementResolver._resolveText`) is
untouched: it still just parses and evaluates `expression`.

**Alternatives considered.**
- *Always-bind any `[token]` even mid-text* — rejected; breaks literal text containing
  brackets and contradicts the clarified "single token spanning the whole value" rule.
- *A visible binding/literal toggle* — rejected at `/speckit.clarify` (Option C); reintroduces
  the two-state UI the feature removes.

---

## 2. The `{ … }` advanced template: compile to an expression string

**Decision.** The template is a **designer-facing presentation** over the existing expression
language. A small bidirectional compiler lives in the designer layer:

- **Forward (commit): template → expression string**, then hand to the existing
  `Expression.parse`. The compiler never builds AST nodes itself — it emits canonical source
  text that the existing lexer/parser already accept (`lib/src/expression/`).
- **Reverse (display): expression string → template string**, for showing a stored binding in
  the value field and on the canvas.

**Template grammar** (resolving the deferred `[NEEDS CLARIFICATION]`):

```text
template      := part*
part          := literal | field | call
literal       := run of chars except [ ] { } \  (\ escapes the next char)
field         := '[' fieldName ']'                 fieldName: ident chars, trimmed
call          := funcName '[' fieldName ']'         e.g. upper[name]
              |  funcName '(' arglist? ')'          e.g. round[price] uses the [ ] sugar
arglist       := arg (',' arg)*
arg           := template | quotedString | number
```

Compilation rules (canonical output, chosen so reverse is a clean inverse):

| Template | Compiled expression string |
|---|---|
| `{[firstName] [lastName]}` | `CONCAT($F{firstName}, " ", $F{lastName})` |
| `{upper[name]}` | `UPPER($F{name})` |
| `{[a][b]}` (no separator text) | `CONCAT($F{a}, $F{b})` |
| `{Total: [qty]}` | `CONCAT("Total: ", $F{qty})` |
| `[customerName]` (simple form, no braces) | `$F{customerName}` |

- A template with a **single** `[field]` and no surrounding text/functions normalizes to the
  **simple** form `$F{field}` (so `{[name]}` and `[name]` store identically — one canonical
  representation, stable round-trip).
- Literal runs inside a template become quoted string args of `CONCAT`; embedded quotes/
  backslashes are escaped for the expression lexer (`lib/src/expression/lexer.dart` string
  rules).
- Function names are emitted upper-case (the registry is case-insensitive at lookup? — **No**;
  `function_registry.dart` keys are exact. The compiler upper-cases to match the registered
  built-ins `UPPER`/`CONCAT`/`FORMAT`/…; reverse lower-cases inside `{ … }` for readability,
  e.g. `{upper[name]}`).

**Reverse compiler** walks the parsed `Expr` AST (`ast.dart`: `FieldRefExpr`, `CallExpr`,
`LiteralExpr`, `BinaryExpr`) and emits template text:
- `FieldRefExpr(n)` → `[n]`
- `CallExpr("CONCAT", parts)` → concatenated template parts inside `{ … }`
- `CallExpr(fn, [FieldRefExpr(n)])` → `{fn[n]}` (lower-cased fn)
- `LiteralExpr(string)` → the raw text (escaped)
- **Anything outside this subset** (arbitrary `BinaryExpr`, params `$P{}`, variables `$V{}`,
  nested arithmetic, unsupported functions) → the value field shows the binding as
  `{ <raw expression> }` in a **read-only** state with a hint, and editing replaces it. This
  is the resolution of the second deferred clarification: legacy/exotic expressions are never
  silently lost — they render and display verbatim, but the simplified field does not pretend
  to round-trip them into the template grammar.

**Rationale.** Reusing `Expression.parse` (eager tokenize+parse, per
`expression.dart:24`) means **zero** new evaluation code and the render path stays a single
shared pipeline (Constitution IV). The compiler is pure string→string and unit-testable in
isolation (Constitution III). Round-trip stability is guaranteed for the supported subset by
canonical-form normalization and pinned with property/round-trip tests.

**Alternatives considered.**
- *Build `Expr` AST directly from the template* — rejected; duplicates parser knowledge and
  risks divergence from the canonical language; string emission reuses the one true parser.
- *Store the template source verbatim in a new `TextElement.template` field and compile at
  render time* — rejected; adds a serialized field and a render-time compile step, and forces
  a second source of truth alongside legacy `expression`. Storing the compiled `expression`
  (status quo field) keeps one source of truth and zero render changes; reverse-compile covers
  display.

---

## 3. The `format` property

**Decision.** Add an optional `String? format` to `TextElement` (ICU pattern; `null`/empty =
unformatted). It is applied at render time to the **resolved value**, reusing the exact logic
behind the existing `FORMAT(value, pattern)` function.

- **Refactor for DRY**: extract the core of `format_functions.dart` `_format` into a shared
  pure helper `applyJetFormat(JetValue value, String pattern) → JetValue` (number →
  `NumberFormat(pattern)`, date → `DateFormat(pattern)`, else unchanged; `FormatException` →
  fall back to the unformatted value). Both the `FORMAT` expression function and the new
  property call it, so they cannot drift.
- **Where applied**: in `ElementResolver._resolveText`, after `value` is computed and before
  `jetStringify`, if `el.format` is non-empty apply `applyJetFormat(value, el.format)`. A
  format that does not fit the value's type (e.g. number pattern on a string) or a malformed
  pattern returns the value unchanged → the label shows the unformatted value, never `!ERR`
  (spec FR-012).
- **Literal labels**: a literal `text` is a `JetString` at resolve time only when bound;
  literal (non-expression) labels skip the expression path entirely, so `format` has no visible
  effect on them (spec assumption) — no special-casing needed.
- **Locale**: `applyJetFormat` reads `Intl.getCurrentLocale()` exactly as `FORMAT` does today
  (set per render in 011), so formatting stays headless and deterministic.

**Format presets (resolved at `/speckit.clarify`): seven.** Preset → pattern mapping lives in
the **designer layer** (a UI concern; the rendering layer only sees the final pattern string):

| Preset | Pattern filled into the field |
|---|---|
| None | `""` (clears) |
| Integer | `#,##0` |
| Decimal | `#,##0.00` |
| Currency | `¤#,##0.00` (locale currency symbol via ICU `¤`) |
| Percent | `#,##0%` |
| Date | `yyyy-MM-dd` |
| Date & time | `yyyy-MM-dd HH:mm` |

Picking a preset fills the free-text field with its pattern (designer may then edit); the field
remains free-text so any ICU pattern is allowed (spec FR-009).

**Rationale.** One formatting code path (shared helper) satisfies WYSIWYG and avoids a second
formatter. No schema bump (see §5). Presets are a thin UI affordance, not a serialized concept.

---

## 4. Localized `#ERROR` for unresolved bindings

**Decision.** A binding whose field is **not present in the active data source** renders a
configurable token, defaulting to the literal `#ERROR`, threaded through the fill layer as a
string option; the designer canvas/preview supply the **localized** string from
`JetPrintLocalizations`.

- **Layering (Constitution II).** The headless rendering layer must not import Flutter l10n.
  So the token is a plain `String` on the fill/resolve entry point
  (`unresolvedFieldToken`, default `'#ERROR'`). Pure headless export uses the default (or a
  host-supplied override) — keeping the renderer Flutter-free and deterministic. The
  **designer preview**, which has a `BuildContext`, passes the localized
  `l10n.errorUnresolvedToken` value in. "Localized" is thus honored wherever a locale context
  exists (the designer/preview flow the spec scenario describes) and degrades gracefully to
  `#ERROR` headless.
- **When is a field "unresolved"?** Only when the referenced field name is **absent from the
  attached data source's declared schema** — not merely null in a given row. The designer
  already computes exactly this via `_unresolved(schema, …)` in `properties_panel.dart`. The
  fill pipeline gains an optional known-field set; when provided and a `$F{name}` references a
  name outside it, the resolved text becomes the token. **When no schema is provided
  (status-quo headless callers), behavior is unchanged** — a missing field stays empty — so no
  existing report regresses (spec FR-015 / SC-005). `FillEvalContext` already tracks
  `warnedFields`; this builds on that signal rather than adding a parallel one.
- **New ARB key** `errorUnresolvedToken` = `#ERROR` (en/de/tr — the token text itself is short
  and may be identical across locales, but the key exists so a translator can change it).

**Rationale.** Threading a string keeps the render core pure and deterministic, satisfies the
localized requirement where it is observable (designer/preview), and scopes the
missing-field → token change to schema-aware contexts so headless rendering of existing
templates is untouched.

**Alternatives considered.**
- *Import l10n into the renderer* — rejected; violates Constitution II layering and the
  headless/deterministic export contract from 012.
- *Always turn any missing field into `#ERROR`* — rejected; regresses reports that rely on
  optional fields rendering blank.

---

## 5. Serialization & schema version

**Decision.** Add `format` to `TextElementCodec` as an **optional** field written only when
non-null (mirroring the existing `expression`/`style` omission). **No `schemaVersion` bump**:
`report_codec.dart` documents the pre-1.0 carve-out (additive optional fields that default
when absent need no bump/migration while the library is undeployed). Bindings need no
serialization change at all — they already round-trip via `expression`.

**Rationale.** Smallest possible on-disk change; old templates load unchanged (absent
`format` ⇒ `null`), new templates stay readable by the same decoder. Constitution V satisfied
without a migration.

---

## 6. Editing surface & commands

**Decision.** Reuse the established command/controller pattern:
- Replace the panel's separate `_TextField` (Text) + `_BindingField` (Binding) for text
  elements with **one** `_ValueField` that parses its content into either a `setText`+
  `clearBinding` or a `setBinding(compiledExpression)` edit, as a single undoable commit.
- Add `controller.setFormat(id, pattern)` backed by a new `SetFormatCommand` (mirrors
  `SetTextCommand`'s no-op-aware `apply`), and extend `TextElement.copyWith` to carry `format`.
- Canvas display: extend `fieldTokenLabel`/`_designTimeDisplay` so a stored `expression` shows
  as its template/`[field]` form (reverse compiler from §2), keeping field and canvas identical
  (spec SC-002).

**Rationale.** No new dispatch infrastructure (the controller has no registry — commands are
instantiated directly), preserving the existing undo/redo and no-op semantics.

---

## 7. Testing strategy (Constitution III — tests precede implementation)

- **Template compiler (unit)**: forward template→expression and reverse expression→template,
  including canonical-form normalization, escaping, the simple-vs-template equivalence
  (`{[name]}` ≡ `[name]` ≡ `$F{name}`), and round-trip stability (compile∘reverse = identity on
  the supported subset). Legacy/exotic expression → read-only `{ … }` display.
- **Value-field parse (unit/widget)**: each of the three forms; escape character; empty;
  brackets-in-literal stays literal; single edit toggles bound↔literal.
- **Format (unit)**: `applyJetFormat` parity with `FORMAT`; number/date patterns; type
  mismatch and malformed pattern → unformatted fallback (FR-012); preset→pattern mapping.
- **Serialization (unit)**: round-trip with/without `format`; absent `format` ⇒ null; no
  schema bump; old fixture (no `format`) still decodes.
- **Render/resolve (unit)**: `format` applied to resolved value; unresolved field → token
  (schema provided) and unchanged-empty (no schema) — guarding SC-005.
- **Localization (widget, per-locale files)**: new `propertiesFormat`/`formatHint`/preset
  labels and `errorUnresolvedToken` present in en/de/tr with English fallback; no raw ARB keys
  leak (extend `localization_test.dart` + de/tr siblings).
- **Properties panel (widget)**: single value field present (no second binding field); format
  field present with presets; commits are undoable; canvas token matches field (SC-002).
- **Goldens**: invoice canvas/preview unchanged for existing bindings (WYSIWYG, Constitution
  IV); a formatted-number preview golden.

---

## Resolved unknowns summary

| Item | Resolution |
|---|---|
| Literal-vs-binding rule | Whole-value `[field]` binds; else literal; backslash escape (§1) |
| `{ … }` template grammar | Defined; compiles to canonical expression string via existing parser (§2) |
| Legacy/exotic expression display | Read-only `{ raw }` with hint; never lost (§2) |
| `format` storage & application | Optional `TextElement.format`; shared `applyJetFormat`; render-time (§3) |
| Format presets | Seven; designer-layer preset→pattern map (§3) |
| Localized `#ERROR` | Threaded string option, default `#ERROR`; designer supplies localized; schema-scoped (§4) |
| Schema version | No bump; optional additive field (pre-1.0 carve-out) (§5) |
