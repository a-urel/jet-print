# Add an expression function

A new `{NAME(…)}` the engine evaluates and the fx editor offers — and why those are two separate edits.

The language itself is [page 02](../02-binding-data.md); the fx editor's
projection of it is [page 10](../10-designer-seams.md). This page is the
sequence, and it is a library-internal one: `JetFunctionRegistry` is not
exported and no public entry point accepts one, so this recipe is for work
inside `packages/jet_print`, not for a host.

## The sequence

1. **Pick the family.** `lib/src/expression/functions/` holds one file per
   family — math, string, logic, format — each exposing a `register…Functions`
   entry point. Add your function to the family it belongs to. A genuinely new
   family means a new file, its own `register…Functions`, and a call added to
   `registerBuiltInFunctions` in `functions/built_in_functions.dart`; nothing
   else discovers it.
2. **Implement it** as a `JetExprFn` — `(List<JetValue> args, EvalContext ctx)`
   returning a `JetValue`. Check arity first, then each argument's type, and
   **return a `JetError` rather than throwing** — [page 02](../02-binding-data.md)
   draws that line. You never have to check for an error argument; the evaluator
   propagates one before it calls you.
3. **Register it** in that family's `register…Functions`, beside its
   neighbours' `register('NAME', _name)` calls. Built-in names are uppercase by
   convention and lookup is case-sensitive, so `Name` and `NAME` are two
   different functions and only one of them exists.
4. **Test it** in `test/expression/functions/<family>_functions_test.dart`,
   beside its neighbours: the happy path, both arity boundaries, and a
   wrong-typed argument returning `JetError`. If the function returns or accepts
   a number, read `AGENTS.md`'s trap on web numbers before you write the
   expectation, and run the chrome command it names.
5. **Offer it in the fx editor** by adding an entry to
   `expressionFunctionCatalog` in
   `designer/template/expression_function_catalog.dart`: the registry name, its
   group, and a signature label. The catalog is presentation-only metadata; the
   engine does not read it and the designer does not read the registry.
6. **Document it** — dartdoc on the implementation, and a `CHANGELOG.md` entry,
   since a new function is user-visible.

## Where the two halves come apart

Steps 3 and 5 are independent edits, and neither reads the other. Register
without cataloguing and the function works for anyone who types it but is not
discoverable. Catalogue without registering and it is offered, inserted, and
evaluates to `Unknown function "NAME"` at render time.

Neither direction survives the suite.
`test/architecture/expression_function_catalog_registration_test.dart` builds
both and asserts the scalar catalog names *equal* the registered ones, so a
name missing on either side fails it, and so does one spelled differently.
`expression_function_catalog_test.dart` cannot catch this on its own: it checks
that every offered name compiles as a call, and the parser knows nothing of the
registry. A function that should be registered but never offered goes in that
guard's `_deliberatelyUnpaletted`, with a comment saying why.

## Verify

```bash
flutter test packages/jet_print/test/expression/ \
  packages/jet_print/test/designer/template/expression_function_catalog_test.dart \
  packages/jet_print/test/architecture/expression_function_catalog_registration_test.dart
```

The first path covers the lexer, parser, evaluator and every function family;
the second covers the catalog, and the third that the two agree. Then the full
gate from the repository root, as `AGENTS.md` specifies it. Nothing here should
move a golden — a golden that moves means a fixture used your function's name
already.

## Next

[`add-localized-string.md`](add-localized-string.md) if the function needs a
label anywhere in the designer. [Page 02](../02-binding-data.md) for where an
expression is evaluated and what a `JetError` looks like once it reaches a
band.
