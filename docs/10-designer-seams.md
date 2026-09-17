# Designer seams

The plumbing the canvas and the panels both stand on — and what the barrel charges for it.

The designer's plumbing is inherited scopes and stateless lookups: cheap, and almost none of it
reaching the model. It costs something in exactly one place — the package's single door, where a name
left out of an `export … show` deletes methods from the public surface without breaking a build.

## Three scopes, three answers to "what if it is absent"

[`designer/designer_scope.dart`](../packages/jet_print/lib/src/designer/designer_scope.dart) →
`DesignerScope.of`, less its doc comment and signature:

```dart
// designer/designer_scope.dart → DesignerScope.of
final DesignerScope? scope = listen
    ? context.dependOnInheritedWidgetOfExactType<DesignerScope>()
    : context.getInheritedWidgetOfExactType<DesignerScope>();
assert(scope != null, 'No DesignerScope found above this widget.');
return scope!.notifier!;
```

Two decisions are visible there. `listen` separates a widget that *renders* controller state, which
subscribes, from a button callback that merely needs the controller, which reads it without
registering a dependency. The assert is the other: there is no fallback controller, since a designer
without one is not a state the library models.

The other two scopes answer that question differently, and what each carries is the reason.
`designer/designer_font_scope.dart` → `DesignerFontScope` is a plain `InheritedWidget`, not an
`InheritedNotifier`: the registry is hoisted once and never changes under the tree, so there is
nothing to notify. Its `of` falls back to a fresh default-only `FontRegistry`, the same set the
engine and exporter construct on their own, so a panel pumped in isolation gets a real answer rather
than an empty one. `designer/designer_schema_scope.dart` → `DesignerSchemaScope` is nullable on
purpose: `of` returning null means no data source is attached, a legal displayable state — the Data
Source panel's empty state — not a missing dependency.

All three are built at one site, `designer/jet_report_designer.dart` →
`_JetReportDesignerState.build`. So the rule is not "use an `InheritedWidget` for designer state":
mutability picks the widget type, and whether *absent* is a legal state picks the missing-scope policy.

## Lookups that never reach the model

`designer/paper_presets.dart` and `designer/margin_presets.dart` are catalogs with no state, and the
interesting property is what they refuse to store. Only the resulting `PageFormat` or `JetEdgeInsets`
reaches the definition; the preset identity — "A4", "Narrow" — is *re-derived* for display each time
by `recognizePaper` and `recognizeMargin`. So a report authored elsewhere still reads as A4 rather
than Custom, and one saved from here carries no preset field a later build could disagree with.

Derivation needs slack, and both allow half a point per side, so a page rounded to whole points still
names its size — safe only because the entries are far apart, which `paper_presets_test.dart`'s *a
size near but beyond tolerance is Custom, not the neighbour* holds. `recognizePaper` sorts the page's
sides first, so one portrait entry recognizes both orientations, and `applyPaper` leaves the current
margins alone. Neither catalog imports from `l10n/`: a paper name is an international standard, like
a unit symbol, and a margin preset is an enum the panel labels.

The glyph lookups sit one layer out. `designer/element_glyph.dart` → `elementGlyph` maps a
`ReportElement` through a chain of type tests ending in a square; `designer/field_type_glyph.dart` →
`fieldTypeGlyph` maps a `JetFieldType` through an exhaustive `switch`. The asymmetry is forced: a
field type is a closed enum, so the switch makes a new variant a compile error, while the element
hierarchy is deliberately open — `UnknownElement` exists so an element this build never heard of
survives a round trip (page 06), and it has to be drawable rather than fatal. The square is the cost
of that openness. `element_glyph.dart`'s dartdoc claims three consumers — outline, properties header,
palette — and two are real: `designer/layout/designer_toolbox.dart` keys on `DesignerToolType`, never
holds a `ReportElement`, and carries a parallel list of the same icons. So the same dartdoc's promise
that a new element type gets its icon "in exactly one place" is wrong by one: it takes two.

## The compiler writes expressions and never runs them

`designer/template/value_template_compiler.dart` projects one text field onto
`TextElement.expression` and back. Forward, `parseValueField` recognizes three forms — literal text
with a `\` escape, a whole-value `[field]` token, and a `{ … }` template — and the last two compile
to a canonical expression *string*:

```dart
// designer/template/value_template_compiler.dart → parseValueField, inside the `{ … }` branch
final String expr = _compileTemplate(raw.substring(1, raw.length - 1));
Parser(tokenize(expr))
    .parseExpression(); // validate (malformed → literal)
return BindingValue(expr);
```

The parser is the arbiter throughout. `_compileTemplate` first offers the whole body as a single
expression — unless a `\` escape marks it literal — so `{SUM([t]) + 500}` compiles to arithmetic
rather than a concatenation of literal runs, and only a parse failure falls back to the part-by-part
scan producing `CONCAT`. The compiled string is then parsed again before it is accepted, so a
template that would not evaluate degrades to literal text rather than to a stored expression that
fails at render.

`reverseCompile` is the inverse, and the projection both the value field and the canvas token read
(page 08), which is why the two cannot disagree. Its `editable` flag is the honest part: an
expression outside the template grammar is shown verbatim in braces and read-only, so one the
designer cannot round-trip is never silently rewritten by the field displaying it.

The alternative — storing the template and teaching the render chain to expand it — was rejected, at
the cost of one directional scan and one reverse renderer. What it buys is that **no file under
`lib/src/designer/` ever evaluates an expression — `evaluate` appears nowhere under that
directory.** The seam type is imported there, for parsing and inspection, but never run, so the
designer has no evaluation path that could drift from the engine's. Nothing in `test/architecture/`
pins that yet: today it is a grep.

## Four files split with `part`, and what that costs at the barrel

`AGENTS.md` lists the four split files and their consequences under *Traps*; this is the mechanism
underneath. Each — controller, design canvas, properties panel, outline panel — grew method clusters
with no seam between them: every method reached the same private state, so extracting one into its
own *library* meant making that state non-private. `part of` avoids the trade, because a part file is
the same library as its parent — an `extension` declared there keeps full access to `_document`,
`_history`, `_editingId` and the rest, and the split changes file layout, not API. Two consequences
follow.

The first is that same-library is not same-*class*. `setState` and `notifyListeners` are `@protected`
— available to a subclass, flagged through an extension, which is not an instance member of the class
it extends — so each parent declares a proxy its extensions call instead: `_rebuild(fn)` wrapping
`setState` in the three widget files, `_notify()` wrapping `notifyListeners` in the controller. An
extension body does not see the class's static scope either — `C._s()` resolves, bare `_s()` does not
— which is spelling rather than access, and why the controller's pure helpers sit at top level in
`controller/api/statics.dart`.

The second reaches a consumer. An extension's methods are callable only where the extension is in
scope, and an extension is in scope by **name** — so exporting the class is not enough:

```dart
// lib/jet_print.dart — with ten more command families elided
export 'src/designer/controller/jet_report_designer_controller.dart'
    show
        JetReportDesignerController,
        // Command families split across `part` files as extensions; exported so
        // the controller's methods stay callable through the package barrel.
        CtrlSelection,
        CtrlElementEdit,
```

Among the four split files only the controller reaches a consumer this way; the other three extend
private `State` classes, so their extensions are private too and stop at the library edge. But the
requirement is about visibility, not about those files: it reaches any public extension a consumer is
meant to call, wherever in `lib/src/` it is written. `public` is the weaker word here — Dart has no
package-private, so an extension written only to be reachable from a sibling library is public too, and
correctly absent from the barrel. Omit the name of one a consumer needs and the package still analyzes,
the class still exports, and its methods silently vanish from the public surface. What catches that is
a consumer-shaped test — `public_api_test.dart` imports only the entry point and calls `setShapeKind`,
`setTextStyle` and `setBarcodeColor`, all extension members — and nothing catches it for an extension
no such test exercises.

The stakes are that high because the entry point is singular, and exactly so:
**`packages/jet_print/lib/` holds exactly one library file at its root, `jet_print.dart`, and every
other Dart file under `lib/` lives in `lib/src/`.** Everything a consumer can name is in that file's
`export … show` clauses — which is what makes an omitted extension a real risk, not a theoretical one.

## Localization is a contract here, a procedure elsewhere

`AGENTS.md` carries the ARB-editing rules under *Traps*, and the procedure is
`docs/recipes/add-localized-string.md`. What belongs here is the seam: `l10n.yaml` pins two
guarantees that answer different questions. `preferred-supported-locales: [en]` puts English first in
the generated `supportedLocales`, which governs *locale resolution* — an active locale the library
does not support resolves to English, not to whichever locale sorts first. A key missing from one ARB
is a different mechanism: `gen-l10n` fills it from the template at generation time, so that gap
closes before any locale is resolved. `nullable-getter: false` is the second, making `of(context)`
total because the library reads strings unconditionally. Both reach consumers through the barrel as
`JetPrintLocalizations`, whose `delegate` and `supportedLocales` are statics on it.

Each non-English locale is verified in its own test file, which reads like duplication and is not.
The observable rule is one isolate per non-English locale; the cause, as those files' own note
explains it, is a framework quirk — CLDR data loading through process-global async state, so two such
locales in one isolate leave the later tree unbuilt.

## Run it

```bash
flutter test packages/jet_print/test/public_api_test.dart \
  packages/jet_print/test/designer/template/ \
  packages/jet_print/test/designer/paper_presets_test.dart \
  packages/jet_print/test/designer/margin_presets_test.dart \
  packages/jet_print/test/designer/localization_de_test.dart
```

`public_api_test.dart` is the consumer standing in for a host, and the extension methods it calls pin
the barrel's `show` list. `value_template_compiler_test.dart` states the three forms, the literal
fallback, and round-trip stability on the supported subset; the preset files pin recognition and
tolerance.

## Trap

**One thirteen-arm operator table is written twice, and only a comment links the copies.**
`expression/ast.dart` and `value_template_compiler.dart` each declare a private `_binarySymbol`
mapping `BinaryOp` to its source symbol — the first for `toString`, the second so a reversed token
re-parses to the same tree. The duplication is a choice, not a wall: the compiler already imports
`expression/ast.dart`, so dropping one underscore would single-source the table with no new
dependency.

The failure mode is narrow and so easy to miss. A *new* `BinaryOp` breaks the build in both places,
since both are exhaustive switch expressions — that direction is safe. A *changed* arm is not: spell
one operator differently and `toString` and the round trip disagree, with no compile error and no
failing test until an expression using it is reverse-compiled. Grep `_binarySymbol`.

## Next

The narrative ends here. What follows are the recipes in `docs/recipes/` — short procedural pages for
the tasks this walk kept deferring: adding an element type, an expression function or a localized
string, regenerating goldens, adding a playground demo. `docs/README.md` routes between them.
