# Feature Specification: fx Expression Editor for the Value Field

**Feature Branch**: `032-fx-expression-editor`
**Created**: 2026-06-16
**Status**: Draft
**Input**: The Value field's only authoring affordance is the field-picker
(database glyph) that inserts a single `[field]` reference. Authors who want to
compose a complex expression — `{SUM([customerTotal])}`, `{IF([qty] > 0, [a],
[b])}`, `{ROUND([total], 2)}` — must type the friendly template syntax by hand,
with no discoverable list of functions and no validation feedback until they
blur the field. Add an **fx** button beside the existing picker that opens a
centered modal **expression editor**: a roomier editor seeded with the current
value, a clickable palette of in-scope fields and built-in functions, and live
syntax/unresolved-field validation. Composing in the editor uses the same
friendly template syntax shown everywhere else and commits through the same
single-undo path as the inline field. This is a **designer-only** feature — no
engine, domain, or serialization change; goldens unchanged.

## Problem

Two gaps, one user-facing and one structural:

1. **No discoverable way to author complex expressions.** The inline field
   exposes only `[field]` insertion. Everything richer — aggregates, string/math
   functions, conditionals — must be typed from memory in a single-line input,
   with errors surfaced only as a post-blur red hint. There is no function list,
   no field/function palette, and no room to read a long expression.

2. **The friendly template grammar is narrower than the engine.** Today
   `value_template_compiler.dart` only round-trips `[field]` references, literal
   text, **single-field** function sugar (`{upper[name]}`), **aggregate** calls
   with a full inner expression (`{SUM([qty] * [price])}`), and `CONCAT` of those
   parts. General N-ary calls to registered functions —
   `IF([qty] > 0, [a], [b])`, `ROUND([t], 2)`, `COALESCE([a], [b])`,
   `SUBSTRING([c], 0, 3)`, `FORMAT([t], "#,##0")` — are **not** recognized by
   `_compileTemplate` (only aggregate names pass the call gate) and reverse to
   `null` in `_exprToToken` (shown read-only). So an author who types one of
   these into the value field has it silently treated as **literal text**. An fx
   editor offering these functions would be unable to actually save them.

The engine already *evaluates* all of these functions (they are registered in
`string_functions`/`math_functions`/`logic_functions`/`format_functions`). The
gap is purely in the friendly↔expression **projection**, so closing it is a
designer/presentation change, not an engine change — consistent with how specs
028–031 stayed designer-only.

## Clarifications

### Session 2026-06-16

- Q: What should the fx button do — an insert-function menu, an expression
  editor, or both? → A: **A centered modal expression editor** with a multi-line
  editor, field + function palettes, and live validation.
- Q: Which syntax should authors edit inside the editor — the friendly template
  syntax or the raw engine expression? → A: **Friendly template syntax**
  (`[field]` tokens, `{FN([field]) * 2}`), round-tripped through the existing
  `value_template_compiler`, so authors see one consistent language everywhere.
- Q: How should the editor surface relative to the field — anchored popover or
  centered modal dialog? → A: **Centered modal dialog** (dimmed backdrop), for
  room to compose longer expressions.
- Q: What live feedback should the editor show — syntax valid/error,
  unresolved-field warning, live result preview? → A: **Syntax valid/error +
  unresolved-field warning.** Live result preview is out of scope (no sample data
  is plumbed into the designer).
- Q: The friendly grammar can't author IF/ROUND(x,2)/COALESCE/SUBSTRING/FORMAT
  today (they revert to literal text). Extend the grammar, or limit the palette
  to what round-trips? → A: **Extend the grammar** — generalize
  `value_template_compiler` to support N-ary `FN(arg, arg, …)` calls in both
  directions, so the palette can offer and save the full function set. The
  generalization also benefits the inline Value field.

## Scope

**In scope**:

- **Grammar generalization** (`value_template_compiler.dart`):
  - **Forward** (`_compileTemplate`): any identifier followed by `(` compiles to
    `IDENT(_compileArg(body))` (not only aggregate names). The existing
    `_scanBalancedParens` + `_compileArg` already substitute `[field]` → `$F{...}`
    inside the argument list and pass operators, commas, nested calls, and string
    literals through.
  - **Reverse** (`_exprToToken`): a general `CallExpr` renders as `{fn(args)}` via
    the existing recursive `_argToToken`. The existing single-field sugar
    (`{upper[name]}`), aggregate, and `CONCAT` reverse forms are **kept unchanged**
    so current round-trips, canvas tokens, and tests stay byte-identical.
- **fx button**: a second affordance in `_ValueField`'s `trailing:` slot, beside
  the existing field-picker glyph, shown whenever the value is **editable**.
  Tapping opens the editor dialog.
- **Expression editor dialog** (`_ExpressionEditorDialog`, centered modal): a
  multi-line editor seeded with the field's current display token; a **field
  palette** (the same in-scope `FieldDef`s the inline picker offers) inserting
  `[name]`; a **function palette** grouped String / Math / Logic / Aggregate
  inserting a caret-positioned snippet; a live **status line** (valid/error +
  unresolved-field); **Cancel** (discard) and **Insert** (commit) actions.
- **Function catalog** (`expression_function_catalog.dart`, designer-side pure
  metadata): per-function `name`, `group`, `insertSnippet`, caret offset, and a
  short `signature` label. Aggregate entries derive their names from
  `aggregateFunctionsByName` to avoid drift; the rest are curated to match the
  registered built-ins.
- **Validation & commit**: syntax via `parseValueField`; unresolved-field via the
  spec-031 `resolvableNamesForBand` + `expressionResolvesNames`; Insert commits
  the editor text through the field's existing `onCommit` → `controller.setValue`
  (one undoable edit).

**Out of scope (intentional)**:

- Any engine, domain, or serialization change — all functions are already
  registered and evaluated; this only widens the friendly↔expression projection
  and adds author-time UI.
- A **live result preview** (evaluating against sample data) — no sample data is
  plumbed into the designer; the status line shows syntax + resolution only.
- Editing the **raw** engine syntax (`$F{}`, `$P{}`, `$V{}`) directly — the
  editor speaks the friendly template syntax. Params/variables that fall outside
  the template grammar continue to show read-only in the inline field, unchanged.
- Authoring `ScopeTotal`s or other Outline/Data-Source affordances — unrelated.
- New evaluation semantics, operator precedence changes, or function additions.

## User Scenarios & Testing *(mandatory)*

The user is a **report author** editing a text element's Value in the designer.

### User Story 1 - Open the editor and compose an expression (P1)

Selecting a text element, the author sees an **fx** button beside the field
picker. Tapping it opens a centered modal seeded with the current value (e.g.
`{SUM([customerTotal])}` or empty). The author clicks `ROUND` from the Math
group and `total` from the field palette to build `{ROUND([total], 2)}`, sees a
green **valid** status, and clicks **Insert**; the element's expression updates
in one undoable step and the canvas reflects it.

**Acceptance**: fx opens the dialog seeded with the current display token;
palette clicks insert caret-positioned tokens; Insert commits via `setValue`
(undo restores the prior value); Cancel discards edits.

### User Story 2 - Author a complex expression the inline field couldn't save (P1)

The author composes `{IF([qty] > 0, [unitPrice] * [qty], 0)}` in the editor and
Inserts it. The stored `TextElement.expression` is the compiled
`IF($F{qty} > 0, $F{unitPrice} * $F{qty}, 0)`, and re-opening the field shows the
same friendly token (round-trips) rather than read-only literal text.

**Acceptance**: a general N-ary call composed in the editor compiles forward and
reverse-compiles back to the same friendly token; it is **not** treated as
literal text.

### User Story 3 - Live validation as you type (P1)

While editing, an incomplete expression (`{SUM([x]) *}`) shows a red **error**
status; a reference to a name not in scope (`{SUM([bogus])}`) shows an
**unresolved-field** warning naming `bogus`; a well-formed in-scope expression
shows **valid**. The same resolution logic as the inline field is used, so the
two agree.

**Acceptance**: the status line reflects `parseValueField` (syntax) and
`resolvableNamesForBand`/`expressionResolvesNames` (resolution) on each change.

### User Story 4 - Inline field gains the generalized grammar (P2)

Typing `{ROUND([total], 2)}` directly into the **inline** Value field (without
opening fx) now saves and round-trips, where before it reverted to literal text.

**Acceptance**: the grammar generalization is in the shared compiler, so the
inline field benefits without fx-specific code.

### User Story 5 - Existing tokens are unchanged (P2)

Existing simple bindings and sugar (`[name]`, `{upper[name]}`, `{SUM([qty])}`,
CONCAT templates) display and round-trip exactly as before; no canvas token,
golden, or stored expression changes for them.

## Requirements *(mandatory)*

### Functional

- **FR-001**: `_compileTemplate` MUST compile any identifier immediately followed
  by `(` as a function call `IDENT(arg-list)`, where the argument list is
  compiled by the existing `_compileArg` (substituting `[field]` → `$F{field}`
  and passing operators, commas, nested calls, and string literals through).
  The aggregate-only gate is removed.
- **FR-002**: `_exprToToken` MUST reverse-compile a general `CallExpr` to a
  `{fn(args)}` friendly token via the recursive `_argToToken`, for calls not
  already covered by the single-field-sugar, aggregate, or `CONCAT` branches.
- **FR-003**: The single-field sugar (`{upper[name]}`), aggregate, and `CONCAT`
  forward/reverse forms MUST remain byte-identical to today (no regression in
  existing round-trip tests, canvas tokens, or goldens).
- **FR-004**: The `_ValueField` `trailing:` slot MUST present an **fx** button
  beside the existing field-picker glyph, with a stable key
  (`'<p>.field.value.fx'`), shown whenever the value is editable.
- **FR-005**: Tapping fx MUST open a centered modal expression editor seeded with
  the field's current display token (empty when the value is empty/literal).
- **FR-006**: The editor MUST provide a **field palette** of the same in-scope
  `FieldDef`s the inline picker offers (`_valueFieldChoices`, including spec-031
  synthetic published-total fields); selecting one inserts `[name]` at the caret.
- **FR-007**: The editor MUST provide a **function palette** grouped String /
  Math / Logic / Aggregate from the designer-side catalog; selecting one inserts
  the function's snippet with the caret positioned at its first argument.
- **FR-008**: The editor MUST show a live **status**: `valid` for a well-formed
  binding/literal, an **error** state for an uncompilable `{…}` body
  (`parseValueField` does not return a `BindingValue`), and an
  **unresolved-field** warning when a `$F{}` reference is absent from the band's
  resolvable name set (`resolvableNamesForBand` + `expressionResolvesNames`,
  spec 031) — identical logic to the inline `_unresolved`.
- **FR-009**: **Insert** MUST commit the editor text through the field's existing
  `onCommit` path (→ `controller.setValue`) as a single undoable edit; **Cancel**
  MUST discard all edits and leave the value unchanged.
- **FR-010**: A designer-side `expression_function_catalog.dart` MUST list each
  offered function with its group, insert snippet, caret offset, and signature
  label. Every catalog name MUST correspond to a function registered in the
  engine (a test guards drift); aggregate names MUST derive from
  `aggregateFunctionsByName`.
- **FR-011**: No engine, domain, or serialization behavior changes; no new
  evaluation code or render path; goldens unchanged. New localized strings are
  added only for the new UI affordances (fx tooltip, dialog labels/actions,
  status messages).

### Key Entities

- **Generalized template call** — a friendly `{fn(arg, …)}` token that compiles
  to / from an engine `CallExpr` of any registered function, not only aggregates.
- **Expression editor dialog** — the centered modal authoring surface: editor +
  field palette + function palette + status line + Cancel/Insert.
- **Function catalog entry** — designer-side presentation metadata (name, group,
  snippet, caret offset, signature) for one built-in function.
- **Editor status** — the live verdict shown to the author: valid / syntax error
  / unresolved-field (with the offending name).

## Success Criteria *(mandatory)*

- **SC-001**: The fx button appears beside the field picker for an editable Value
  and opens the dialog seeded with the current display token.
- **SC-002**: A general N-ary call composed in the editor
  (`{IF([qty] > 0, [a], [b])}`, `{ROUND([t], 2)}`, `{COALESCE([a], [b])}`,
  `{SUBSTRING([c], 0, 3)}`) compiles forward to the expected engine expression
  and reverse-compiles back to the same friendly token (not literal text).
- **SC-003**: The inline Value field saves and round-trips the same general calls
  (the generalization lives in the shared compiler).
- **SC-004**: Every existing simple/sugar/aggregate/CONCAT token compiles and
  reverse-compiles byte-identically to before; no golden changes.
- **SC-005**: Field-palette and function-palette selections insert the expected
  caret-positioned tokens; the status line shows valid / error / unresolved for
  the corresponding inputs; Insert commits via `setValue` (one undo) and Cancel
  discards.
- **SC-006**: Every function-catalog name resolves to a registered engine
  function (drift guard), and every catalog snippet parses to a `BindingValue`.
- **SC-007**: `flutter analyze` + `dart format` clean; the full `jet_print` test
  suite and the playground analyze/test are green; all goldens unchanged.
