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
   no field/function palette, and no room to read a long expression. This applies
   even to forms the grammar *already* round-trips (aggregates like `SUM`/`AVG`/
   `COUNT`, single-field sugar like `{upper[name]}`): they save fine but are
   undiscoverable. This is the discoverability gap, distinct from the grammar gap
   below.

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

3. **Top-level operators outside a call are silently swallowed.** *(amendment —
   see Clarifications 2026-06-16 #2)* Even after gap 2 is closed, a `{…}` body
   whose root is a binary/unary expression rather than a single call or token —
   `{SUM([customerTotal]) + 500}`, `{[price] * [qty]}`, `{-[balance]}` — is not
   recognized. `_compileTemplate` scans the body as a **concatenation template**,
   so the `+ 500` becomes a literal string run and the whole value compiles to
   `CONCAT(SUM($F{customerTotal}), "+500")` — *string* concatenation, not the
   intended *numeric* `SUM(...) + 500`. The status line still reports **valid**,
   so the meaning change is invisible. Symmetrically, `_exprToToken` has no
   branch for a top-level `BinaryExpr`/`UnaryExpr`, so such an expression
   reverse-compiles **read-only** showing raw `$F{}` syntax
   (`{SUM($F{customerTotal}) + 500}`) instead of the friendly editable token. The
   engine already evaluates these operators; the projection is the only gap.

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

### Session 2026-06-16 (amendment #2: top-level expressions)

- Q: `{SUM([customerTotal]) + 500}` compiles to `CONCAT(SUM(...), "+500")` (string
  concat, not numeric add) because top-level operators outside a call are treated
  as literal template text. Extend the grammar to support a full top-level
  expression, or leave it? → A: **Extend the grammar.** A `{…}` body is first
  attempted as a *single expression* (the existing `Parser` is the arbiter); only
  if it does not parse does it fall back to today's concatenation-template scan.
  This reuses the existing expression engine rather than adding a parallel one.
- Q: This flips ambiguous forms like `{[a] * [b]}` from string-concat (today) to
  numeric (`$F{a} * $F{b}`). Preserve the old string meaning for legacy stored
  `CONCAT($F{a}, " * ", $F{b})` via escaping, or accept reinterpretation? → A:
  **Accept reinterpretation.** No escaping. A legacy operator-joined CONCAT now
  reverse-displays as the numeric form and, on re-save, becomes the numeric
  expression. The round-trip property fixtures are relaxed accordingly. Rationale:
  the string `"5 * 3"` is almost never the author's intent, and the simpler rule
  avoids a backslash-escaping surface in displayed tokens.
- Q: Should `SUM` keep its uppercase display inside a top-level expression? → A:
  **No — accept the existing `_argToToken` lowercasing.** `{SUM([t]) + 500}`
  reverse-displays as `{sum([t]) + 500}` (re-uppercased to `SUM` on parse, so it
  round-trips). This matches how function names already render inside argument
  positions; preserving per-name casing is out of scope.

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
- **Top-level expressions** (`value_template_compiler.dart`, amendment #2):
  - **Forward** (`_compileTemplate`): before the concat-template scan, attempt the
    whole `{…}` body as a single expression — run it through the existing
    `_compileArg` (`[field]` → `$F{…}`, call-name uppercasing, operators/commas/
    string literals passed through) and `Parser`-validate the result. On success,
    that compiled expression is the binding. On any parse failure — or when the
    body contains a `\` escape — fall through to the **unchanged** concatenation
    scan. Concatenation forms (`{[first] [last]}`, `{Total: [qty]}`) fail the
    whole-body parse (juxtaposition / stray text) and are preserved automatically.
  - **Reverse** (`_exprToToken`): a top-level `BinaryExpr` or `UnaryExpr` renders
    as a `{…}` editable token via the existing recursive `_argToToken`, instead of
    falling through to the read-only raw-expression display.
- **Inline-aggregate lifting inside an expression** (`aggregate_synthesizer.dart`,
  amendment #2 — a **narrow engine/fill-time change**): `expandAggregates` must
  lift an aggregate that is a *sub-term* of a larger expression, not only one that
  is the whole expression. `rewriteExpression` scans the expression source for
  every aggregate call (`SUM(…)`, `AVG(…)`, …) anywhere in the tree — skipping
  quoted string literals and validating each candidate is a single-arg aggregate
  via the existing `topLevelAggregate` — synthesizes a hidden `__agg<n>` variable
  for each, and substitutes `$V{__agg<n>}` in place. So `SUM($F{customerTotal}) +
  50000` becomes `$V{__agg0} + 50000` (one report-scoped SUM variable + the
  literal add) instead of an un-expanded `SUM` that renders `!ERR`. This reuses
  the unchanged variable/accumulator pipeline (spec 028); it adds no new
  aggregation engine and no new render path.
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
  and adds author-time UI. *(Amendment #2 narrows this to ONE exception: the
  fill-time `expandAggregates` transform is extended to lift sub-term aggregates,
  reusing the spec-028 variable pipeline — see FR-015. No new evaluation engine,
  render path, or golden change.)*
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
golden, or stored expression changes for them. *(Exception: operator-joined field
forms `{[a] op [b]}` are reinterpreted as numeric — see User Story 6.)*

### User Story 6 - Top-level arithmetic around a call (P1, amendment #2)

The author types `{SUM([customerTotal]) + 500}` into the value field (or the fx
editor). Before, it silently compiled to `CONCAT(SUM(...), "+500")` — the `+ 500`
was string-concatenated and the result re-displayed as `{sum[customerTotal]+500}`.
Now it compiles to the numeric expression `SUM($F{customerTotal}) + 500` and
reverse-displays as the editable token `{sum([customerTotal]) + 500}`.

**Acceptance**: a `{…}` body that is a valid top-level expression
(`{SUM([t]) + 500}`, `{[price] * [qty]}`, `{([a] + [b]) * 2}`) compiles to that
expression (not a `CONCAT` of literal runs) and reverse-compiles to an **editable**
friendly token; concatenation forms (`{[first] [last]}`, `{Total: [qty]}`) are
unaffected.

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
- **FR-003**: The single-field sugar (`{upper[name]}`), aggregate, and **literal-run**
  `CONCAT` forms (`{[first] [last]}`, `{Total: [qty]}`) MUST remain byte-identical
  to today (no regression in existing round-trip tests, canvas tokens, or goldens).
  *(Operator-joined field forms `{[a] op [b]}` are the deliberate exception — see
  FR-014.)*
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
  status messages). *(Amendment #2 adds one narrow fill-time exception — FR-015 —
  that still introduces no new evaluation engine, render path, or golden change.)*
- **FR-012** *(amendment #2)*: `_compileTemplate` MUST first attempt the whole
  `{…}` body as a single expression (via `_compileArg` + `Parser` validation) and,
  on success, use it as the binding — so `{SUM([t]) + 500}` compiles to
  `SUM($F{t}) + 500` (numeric), not `CONCAT(...)`. The attempt MUST be skipped when
  the body contains a `\` escape, and MUST fall back to the existing
  concatenation-template scan on any parse failure, leaving concatenation forms
  (`{[first] [last]}`, `{Total: [qty]}`) byte-identical to today.
- **FR-013** *(amendment #2)*: `_exprToToken` MUST reverse-compile a top-level
  `BinaryExpr`/`UnaryExpr` to an editable `{…}` token via `_argToToken`, rather
  than the read-only raw-expression fallback.
- **FR-014** *(amendment #2)*: Ambiguous operator-joined field forms (`{[a] * [b]}`)
  now compile to the numeric expression; legacy stored `CONCAT($F{a}, " op ", $F{b})`
  is reinterpreted to the numeric form on reverse/re-save (no escaping). Round-trip
  fixtures that assumed string-concat for operator-joined fields are updated to the
  numeric meaning; all non-operator concat fixtures stay unchanged.
- **FR-016** *(amendment #2)*: `_compileArg` MUST expand function-of-field sugar
  (`fn[field]` → `FN($F{field})`) so the sugar composes inside an expression
  (`sum[total] + 50000`, `ROUND(sum[x], 2)`). This also heals a stale stored
  `CONCAT(SUM(…), "+n")` — whose value-field display is the sugar form
  `{sum[total]+n}` — into the numeric expression on the next commit, with no
  manual re-typing of parentheses.
- **FR-015** *(amendment #2)*: `expandAggregates` MUST lift an inline aggregate
  that appears as a **sub-term** of a larger expression (not only when it is the
  whole expression): every aggregate call in the source is replaced in place by a
  synthesized `$V{__agg<n>}` reference (skipping quoted strings; arity validated
  via `topLevelAggregate`), so `SUM([t]) + 500`, `SUM([a]) - SUM([b])`, and
  `ROUND(SUM([x]), 2)` compute through the existing variable/accumulator pipeline
  rather than rendering `!ERR`. Whole-expression aggregates, de-duplication, and
  scope inference are byte-for-byte unchanged. This is the one **engine/fill-time**
  change in amendment #2; it adds no new aggregation engine, render path, or
  golden change.

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
- **SC-004**: Every existing simple/sugar/aggregate/literal-run-CONCAT token
  compiles and reverse-compiles byte-identically to before; no golden changes.
  (Operator-joined field forms `{[a] op [b]}` are reinterpreted as numeric per
  FR-014 — they do not appear in goldens.)
- **SC-005**: Field-palette and function-palette selections insert the expected
  caret-positioned tokens; the status line shows valid / error / unresolved for
  the corresponding inputs; Insert commits via `setValue` (one undo) and Cancel
  discards.
- **SC-006**: Every function-catalog name resolves to a registered engine
  function (drift guard), and every catalog snippet parses to a `BindingValue`.
- **SC-007**: `flutter analyze` + `dart format` clean; the full `jet_print` test
  suite and the playground analyze/test are green; all goldens unchanged.
- **SC-008** *(amendment #2)*: A `{…}` body that is a valid top-level expression
  (`{SUM([t]) + 500}`, `{[price] * [qty]}`, `{([a] + [b]) * 2}`) compiles to the
  corresponding numeric engine expression (not a `CONCAT` of literal runs) and
  reverse-compiles to an editable friendly token; `{[first] [last]}` and
  `{Total: [qty]}` still compile to `CONCAT` unchanged.
