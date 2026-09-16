# Binding data

What a row is, how an expression reaches one, and where an aggregate folds.

A report definition never holds data. It holds *names* — `$F{lineTotal}`, a
collection field called `orders` — and the fill pass is the only place those
names meet values. Everything after it works on text and numbers already
resolved: the layouter, the frame and the painters cannot reach a row, because by
then there is none to reach. Binding does not run alongside the other stages; it
ends, completely, before the next begins.

## A row

[`data/jet_data_source.dart`](../packages/jet_print/lib/src/data/jet_data_source.dart)
→ `JetDataSource` is the host's whole side of the contract: one method, `open`,
returning a cursor. That cursor, `data/data_set.dart` → `DataSet`, is four
members — `fields`, `moveNext`, `current`, `close` — synchronous, forward-only
and re-openable, each `open` positioned before the first row.

`data/data_row.dart` → `DataRow` copies both schema and values into unmodifiable
collections at construction, so a stashed row cannot change underneath its
holder — which is what lets the filler compare previous against current to detect
a group break. The schema is `data/field_def.dart` → `FieldDef`: a name, a coarse
`JetFieldType`, and — for a `collection` field — its own child `fields`,
recursively. Four implementations of `JetDataSource` reach the barrel.

## One language, two spellings

An element's binding is one string: `TextElement.expression`, when non-null,
replaces its literal `text`. `Expression.parse` in
[`expression/expression.dart`](../packages/jet_print/lib/src/expression/expression.dart)
is four stages in a line — `expression/lexer.dart` → `tokenize` (the lexer is
what knows a `$F{}` / `$P{}` / `$V{}` reference from any other sigil),
`expression/parser.dart` → `Parser` descending into the sealed `Expr` tree of
`expression/ast.dart`, and `expression/evaluator.dart` → `evaluate` walking it:

```dart
case FieldRefExpr(name: final String n):
  return context.resolveField(n);
case ParamRefExpr(name: final String n):
  return context.resolveParam(n);
case VariableRefExpr(name: final String n):
  return context.resolveVariable(n);
// ... literal, unary, binary, conditional, call
```

Three kinds of reference, three methods on `expression/eval_context.dart` →
`EvalContext`; `RowEvalContext` is the bridge, taking fields from a `DataRow`,
params from a map, variables from the calculator's snapshot, and yielding
`JetNull` — never an error — for anything it cannot resolve.

**Parsing throws; evaluation does not.** A malformed expression raises
`ExpressionException` at `parse`, but a failed *operation* — division by zero,
comparing a string to a date, calling an unregistered name — returns a `JetError`
value propagating up the tree like any other. `rendering/fill/element_resolver.dart`
→ `ElementResolver` catches the one and records the other, rendering `!ERR` with
a diagnostic either way: a bad expression costs a cell, not the document.

The `{ … }` and `[field]` form is the **designer's** display spelling, not a
second language: `designer/template/value_template_compiler.dart` →
`parseValueField` compiles `{SUM([lineTotal])}` down to the canonical
`SUM($F{lineTotal})` stored on the element, and `reverseCompile` turns it back
for display. Authoring-time presentation, then — unrelated to the fill-time
aggregate expansion below, and easy to conflate with it.

## Master and detail

A nested collection is a row value that is a `List` of maps, declared as a
`collection` `FieldDef` and named by a `DetailScope`'s `collectionField`.
`rendering/fill/report_filler.dart` → `emitNode` is the mechanism, entire:

```dart
case NestedScope(scope: final DetailScope s):
  final List<DataRow> childRows = childRowsOf(scopeRow, s.collectionField!);
  if (childRows.isEmpty) break; // empty collection → no bands, no footer
  // ... footer preparation
  for (final DataRow childRow in childRows) {
    for (final ScopeNode child in s.children) {
      emitNode(child, childRow);
    }
  }
```

It recurses, so depth is unbounded — a list inside a list is another
`NestedScope`. `data/collection_rows.dart` → `coerceCollectionRows` is the single
place raw values become child rows: declared child fields project, and without
them `inferFields` infers the child schema, typing nested `List<Map>` columns as
collections recursively. `apps/jet_print_playground/lib/nested_list_sample.dart`
builds the three-level Customer ▸ Order ▸ Line case, public API only.

## Where an aggregate folds

Four routes, chosen by where the aggregate is *authored* and where its operand
*lives*.

1. **A declared `ReportVariable`** folds in
   `expression/aggregate/variable_calculator.dart` → `VariableCalculator`, whose
   `advance` the filler calls once per **master** row and nowhere else. Two reset
   scopes, `report` and `group`; child rows of a nested scope never reach it.
2. **An inline aggregate in the summary or a root group footer, over a master
   field.** `expression/aggregate/aggregate_synthesizer.dart` → `expandAggregates`
   rewrites the call to `$V{__agg<n>}` and appends a hidden `ReportVariable`:
   route 1, no second accumulator, and a pure no-op when nothing lifts.
3. **The same bands, operand deeper.** `liftDescendantAggregates` (same file) runs
   *before* `expandAggregates`, resolving the operand against the source's schema
   through `data/aggregate_path.dart` → `resolveAggregatePath`. A unique
   `DescendPath` becomes `$V{__dagg<n>}`, folded by `foldDescendantLeaves`
   **flatly** over every descendant leaf — so AVG is a true average over leaves,
   not a mean of subtotals. Same-scope wins over deeper; two distinct paths are
   `Ambiguous`, and the engine refuses to guess.
4. **Inside the nested scope itself.** A `DetailScope.footer` goes through
   `expression/aggregate/nested_footer.dart` → `prepareNestedFooter`, folding
   `$V{__nagg<n>}` over that scope instance's own child rows with a fresh
   accumulator per instance. A `DetailScope.totals` entry — a `ScopeTotal` — has
   no band at all: `rendering/fill/report_filler.dart` → `augmentForScope` folds
   it and injects the result **as a field on the parent row**, so an enclosing
   scope, a group footer or the summary reads it as plain `$F{name}`.

The order in `fillDefinition` is fixed: open the cursor (route 3 wants its
schema), lift, expand, then per master row run `augmentForScope` *before*
`calc.advance`, so a grand total over a published total sums it live. Outside
those sinks an aggregate is an error, not a silent zero —
`domain/report_validation.dart` → `validate` reports invariant I8.

## Why it is like this, and the alternative rejected

The tempting alternative is folding aggregates while painting: the painter
already visits every band in order, and a running total is one accumulator. It
fails three ways.

**The answer would depend on how often you paint.** Preview, thumbnail rail and
export all draw the same page, and a scroll or resize draws it again; an
accumulator folded during paint double-counts every repaint.

**And on what order.** Pagination is lazy per page (→ page 03), so nothing
guarantees page 3 is built before page 7; a subtotal folded at paint would print
a different number depending on which page the reader opened first.

**And there would be nowhere to put it.** By paint time there is no row and no
`EvalContext` to evaluate against; page 04 is the argument for why the painted
thing is a flat list of primitives and nothing more.

The costs are real. **Fill is eager over rows** even when the source is not: the
`while (ds.moveNext())` loop runs to completion and materializes every band
before layout begins, so `JetPagedDataSource` streams into a fill that does not.
**The sinks are a closed set**, and **the `__agg` prefix is reserved** — a user
variable of that name is silently shadowed.

## Run it

```bash
flutter test packages/jet_print/test/expression/ packages/jet_print/test/data/
flutter test packages/jet_print/test/rendering/fill/
```

The first proves the halves in isolation: the language against hand-built
contexts, the cursor contract against every source. The second proves they meet
real rows, and `descendant_summary_fill_test.dart` is the one to read —
customers A and B plus a customer with no orders, one authored
`SUM($F{lineTotal})` in the customer group footer and the *same* string in the
summary, asserting 35, 300, 0 and a grand total of 335 — then the identical
numbers with **no declared schema**, proving `inferFields` types the nested chain
well enough for `resolveAggregatePath` to descend it. `AVG` there is 67 — 335
over five leaves, not the mean of three subtotals — so the flat-fold property
above is an assertion.

## Trap

**Every number the engine prints must leave through `expression/value.dart` →
`jetStringify`.** `JetNumber` always holds a `double`, and `_doubleToString`
reproduces the Dart VM's representation by hand: a finite integer-valued double
below the scientific-notation threshold is emitted as `toStringAsFixed(0)` with
`.0` appended. Skip it and `35.0` prints as `35` on the
web and `35.0` on the VM — one report, two documents. A new display path reaching
for `double.toString()` reintroduces that split, and only the chrome leg can see
it. `AGENTS.md` carries the repository rule this mechanism upholds.

## Next

Page 03, [pagination](03-pagination.md), turns the filled band stream into pages.
The hand-off is already visible here: `$V{PAGE_NUMBER}` and `$V{PAGE_COUNT}`, the
reserved names in `rendering/fill/page_variables.dart` → `kPageScopedVariables`,
are rejected by the filler wherever it can reach them — how many pages there are
is the one question this pass cannot answer.
