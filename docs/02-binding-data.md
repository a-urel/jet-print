# Binding data

What a row is, how an expression reaches one, and where an aggregate folds.

A report definition never holds data. It holds *names* — `$F{lineTotal}`, a
collection field called `orders` — and the fill pass is the only place those
names meet values. The layouter, the frame and the painters work on text and
numbers already resolved, because by then there is no row left to reach.

## A row

[`data/jet_data_source.dart`](../packages/jet_print/lib/src/data/jet_data_source.dart)
→ `JetDataSource` is the host's whole side of the contract: one method, `open`,
returning a cursor. That cursor, `data/data_set.dart` → `DataSet`, is
synchronous, forward-only, and re-opened fresh before the first row each time.

`data/data_row.dart` → `DataRow` copies schema and values into unmodifiable
collections, so a stashed row cannot change underneath its holder. The schema is
`data/field_def.dart` → `FieldDef`: a name, a coarse `JetFieldType`, and — for a
`collection` field — its own child `fields`, recursively.

## One language, two spellings

An element's binding is one string: `TextElement.expression`, when non-null,
replaces its literal `text`. `Expression.parse` in
[`expression/expression.dart`](../packages/jet_print/lib/src/expression/expression.dart)
is three stages in one line — `expression/lexer.dart` → `tokenize` (the lexer
knows a `$F{}` / `$P{}` / `$V{}` reference from any other sigil), then
`expression/parser.dart` → `Parser` descending into the sealed `Expr` tree of
`expression/ast.dart`. Walking it is a separate call,
`expression/evaluator.dart` → `evaluate`:

```dart
case LiteralExpr(value: final JetValue v):
  return v;
case FieldRefExpr(name: final String n):
  return context.resolveField(n);
case ParamRefExpr(name: final String n):
  return context.resolveParam(n);
case VariableRefExpr(name: final String n):
  return context.resolveVariable(n);
// ... unary, binary, conditional, call
```

Three kinds of reference, three methods on `expression/eval_context.dart` →
`EvalContext`. The fill pass always supplies its own,
`rendering/fill/fill_eval_context.dart` → `FillEvalContext`: fields from a
`DataRow`, params from a map, variables from the calculator's snapshot,
`JetNull` for whatever it cannot resolve, and two signals recorded on the way
out — a missing-field warning from `resolveField`, a reserved page-scoped name
from `resolveVariable`. `RowEvalContext` is the diagnostics-free default,
reached only via `VariableCalculator`'s optional factory.

**Parsing throws; evaluation does not.** A malformed expression raises
`ExpressionException` at `parse`, but a failed *operation* — division by zero,
an unregistered name — returns a `JetError` value propagating up like any other.
`rendering/fill/element_resolver.dart` → `ElementResolver` catches the one and
records the other, rendering `!ERR` either way: a bad expression costs a cell,
not the document.

The `{ … }` and `[field]` form is the **designer's** display spelling, not a
second language: `designer/template/value_template_compiler.dart` →
`parseValueField` compiles `{SUM([lineTotal])}` to the canonical
`SUM($F{lineTotal})` stored on the element. Authoring-time presentation,
unrelated to the fill-time aggregate expansion below and easy to confuse.

## Master and detail

A nested collection is a row value that is a `List` of maps, declared as a
`collection` `FieldDef` and named by a `DetailScope`'s `collectionField`.
`rendering/fill/report_filler.dart` → `emitNode` carries it:

```dart
case NestedScope(scope: final DetailScope s):
  final List<DataRow> childRows = childRowsOf(scopeRow, s.collectionField!);
  for (final DataRow childRow in childRows) {
    for (final ScopeNode child in s.children) {
      emitNode(child, childRow);
    }
  }
// ... the empty-collection guard and all footer handling
```

It recurses, so depth is unbounded — a list inside a list is another
`NestedScope`. `data/collection_rows.dart` → `coerceCollectionRows` is the
single place raw values become child rows: declared child fields project, and
without them `inferFields` infers the child schema, typing nested `List<Map>`
columns as collections recursively.
`apps/jet_print_playground/lib/nested_list_sample.dart` →
`nestedListsDefinition` is the three-level Customer ▸ Order ▸ Line case.

## Where an aggregate folds

Four routes, by where the aggregate is *authored* and where its operand *lives*.

1. **A declared `ReportVariable`** folds in
   `expression/aggregate/variable_calculator.dart` → `VariableCalculator`, whose
   `advance` the filler calls once per **master** row and nowhere else. Two
   reset scopes, `report` and `group`; nested-scope child rows never reach it.
2. **An inline aggregate in the summary or a root group footer, over a master
   field.** `expression/aggregate/aggregate_synthesizer.dart` →
   `expandAggregates` rewrites the call to `$V{__agg<n>}` plus a hidden
   `ReportVariable`: route 1, no second accumulator, a no-op when nothing lifts.
3. **The same bands, operand deeper.** `liftDescendantAggregates` (same file)
   runs *before* `expandAggregates`, resolving the operand against the source's
   schema through `data/aggregate_path.dart` → `resolveAggregatePath`. A unique
   `DescendPath` becomes `$V{__dagg<n>}`, folded by `foldDescendantLeaves`
   **flatly** over every descendant leaf — so AVG is a true average over leaves,
   not a mean of subtotals. Same-scope wins over deeper, and two paths are
   `Ambiguous`: the engine refuses to guess.
4. **Inside the nested scope itself.** A `DetailScope.footer` goes through
   `expression/aggregate/nested_footer.dart` → `prepareNestedFooter`, one fresh
   `$V{__nagg<n>}` accumulator per scope instance — and `emitNode` classifies
   its operands with `resolveAggregatePath` just as route 3 does: same-scope
   folds per child row inside the loop, a `DescendPath` folds once over the
   subtree after it, `Ambiguous` renders the fallback. A `ScopeTotal` in
   `DetailScope.totals` has no band at all: `augmentForScope` folds it and
   injects the result **as a field on the parent row**, read upstream as
   `$F{name}`.

The order in `fillDefinition` is fixed: open the cursor (route 3 wants its
schema), lift, expand, then per master row run `augmentForScope` *before*
`calc.advance`, so a grand total over a published total sums it live. Outside
those sinks an aggregate is flagged — but only a *top-level* one:
`domain/report_validation.dart` → `aggregateBand` tests `topLevelAggregate`
against the expression root, so I8 catches a bare `SUM($F{x})` in a page header
and misses `SUM($F{x}) + 500` wherever it is misplaced — the same shape route 2
legitimately expands when it *is* in a summary or root group footer, the only
slots `expandAggregates` rewrites.

## Why it is like this, and the alternative rejected

The tempting alternative is folding aggregates while painting — the painter
already walks every band in order. Three things break.

**The answer would depend on how often you paint.** Preview, thumbnail rail and
export all draw the same page, and a scroll redraws it; an accumulator folded at
paint double-counts every repaint.

**And on what order.** Pagination is lazy per page (→ page 03), so nothing
guarantees page 3 is built before page 7; a subtotal folded at paint would
change with reading order.

**And there would be nowhere to put it.** By paint time there is no row and no
`EvalContext`; page 04 argues why the painted thing is a flat primitive list.

The costs are real. **Fill is eager over rows** even when the source is not: the
`while (ds.moveNext())` loop runs to completion and materializes every band
before layout begins, so `JetPagedDataSource` streams into a fill that does not.
**The sinks are a closed set**, and **the `__agg` prefix is reserved**.

## Run it

```bash
flutter test packages/jet_print/test/expression/ packages/jet_print/test/data/
flutter test packages/jet_print/test/rendering/fill/
```

The first proves the halves in isolation. The second proves they meet real rows,
and `descendant_summary_fill_test.dart` is the one to read — customers A and B
plus one with no orders, one authored `SUM($F{lineTotal})` in the customer group
footer and the *same* string in the summary, asserting 35, 300, 0 and a grand
total of 335, then the same numbers with **no declared schema**: route 3
descending a chain nobody declared. `AVG` there is 67 — 335 over five leaves,
not the mean of three subtotals — making the flat-fold property an assertion.

## Trap

**Every number the engine prints must leave through `expression/value.dart` →
`jetStringify`.** `JetNumber` always holds a `double`, and `_doubleToString`
reproduces the Dart VM's representation by hand: a finite integer-valued double
below the scientific-notation threshold is emitted as `toStringAsFixed(0)` with
`.0` appended. This neutralizes the platform difference `AGENTS.md` records
under *Traps*, whose entry also names the one CI leg that catches a regression
here. A new display path reaching for `double.toString()` puts that difference
straight back into rendered output.

## Next

Page 03, [pagination](03-pagination.md), turns the filled band stream into
pages. The hand-off is visible here: `$V{PAGE_NUMBER}` and `$V{PAGE_COUNT}`, the
reserved names in `rendering/fill/page_variables.dart` → `kPageScopedVariables`,
resolve to `JetNull` in `FillEvalContext.resolveVariable`, which records them
for the filler to reject. How many pages there are is the one question this pass
cannot answer.
