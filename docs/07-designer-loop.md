# The designer loop

How an edit becomes a new definition, and why every edit is a command object.

Pages 01–06 are a pipeline: a definition goes in, ink comes out, one pass. The designer is the
other shape — a pointer moves, the definition is replaced, the frame is re-recorded, and the
user may at any moment take the last step back. The loop's centre is one `ChangeNotifier` over
one immutable snapshot, and one private method that swaps it.

## One mutation point

[`designer/controller/jet_report_designer_controller.dart`](../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart)
→ `JetReportDesignerController` is a `ChangeNotifier` over three fields: the current
`DesignerDocument`, an `EditHistory`, and an `ElementIdFactory`. Its public surface is dozens of
mutators spread across thirteen `part` files under `controller/api/` as twelve named extensions
(`AGENTS.md`'s *Four god-files are split with `part` + `extension`* states what that costs).
Every mutator that changes the model ends at one private method — `_commit`, whole:

```dart
bool _commit(EditCommand command) {
  final DesignerDocument before = _document;
  final DesignerDocument after = command.apply(before);
  if (after.definition == before.definition &&
      after.selection == before.selection) {
    return false;
  }
  _document = after;
  _history.push(before);
  notifyListeners();
  return true;
}
```

There is no public `commit` and no second path: nothing outside `lib/src/designer/controller/`
constructs an `EditCommand`, and the barrel exports the controller, its extensions and
`Selection`, but no command class.

## The unit of history is a snapshot, not a command

`designer/controller/designer_document.dart` → `DesignerDocument` is what history stores: a
`ReportDefinition` paired with the `Selection` active for it, both immutable.
`designer/controller/edit_history.dart` → `EditHistory` is then two `List<DesignerDocument>`
stacks — `push` appends the *prior* document and clears the redo stack, `undo` pops one and
banks the current document for redo. No command is stored and none inverted: `EditCommand` has
`apply` and nothing else, so there is no `unapply` to get wrong.

That is affordable only because the model is immutable — a snapshot copies one reference, and
`designer/controller/band_walker.dart` → `updateBand` maps one band while preserving every other
referentially. History is unbounded per session and lives only in memory; `open` calls `clear`.
`EditHistory` also owns `revision`, bumped on every history change, which the canvas reads to
tell whether its cached recording of page 05's paint path is stale.

## Every edit is a command object

`designer/controller/edit_command.dart` → `EditCommand` declares a `label` and one pure method,
`DesignerDocument apply(DesignerDocument before)`; `DefinitionEditCommand` is literally a
definition transform plus a selection.

**Selection moves with the model**, because `apply` returns a whole document:
`CreateElementCommand` returns `Selection.of([placed.id])`, `DeleteCommand` `Selection.empty`.
No window exists where the definition has changed and the selection has not.

**Redo reproduces an edit, it never recomputes one.** Every derived value is resolved before the
command is built and baked in: `MoveCommand` takes final band-clamped bounds per id, not a
delta; `CreateElementCommand` a built element whose id `ElementIdFactory` already minted. A redo
cannot re-derive a different number, and an id cannot drift across undo/redo.

## `ElementEditCommand<E>`, and what cannot use it

Most element edits are one shape: find one element by id, rewrite a field, touch nothing else.
`designer/controller/element_edit_command.dart` → `ElementEditCommand<E extends ReportElement>`
factors out exactly that:

```dart
// ... the class dartdoc, the const constructor and `final String id` are cut
E edit(E element);
@override
DesignerDocument apply(DesignerDocument before) => before.withDefinition(
      updateElement(
          before.definition, id, (ReportElement e) => e is E ? edit(e) : e),
    );
```

A subclass supplies its fields, a `label` and the typed `edit` — `SetTextCommand`,
`SetShapeKindCommand`, the barcode setters. The type test is load-bearing: an absent id, or one
belonging to another element type, returns the element unchanged — a value-equal definition,
which the next section makes a clean no-op. No subclass needs a not-found branch.

What the base cannot express is visible in it — `withDefinition` with no selection argument, one
element addressed. A command sits outside the family when it targets a band, group, scope,
crosstab or the report; when it spans elements; or when it must set the selection.

## A no-op is decided by value, not by identity

`_commit`'s guard compares definitions with `==`. Every command rebuilds — `updateElement`
funnels through `mapBands`, which reconstructs the definition on every call — so `identical`
would report a change every time, and every keystroke would become a history entry. Value
equality is what makes the comparison mean anything, and it holds because the domain tree mixes
in `ValueEquality`, the mixin page 04 shows on `PageFrame`. So setting text that is already
there, or dragging into a border that clamps the move to nothing, records **no history entry and
fires no notification** — no mutator implementing that, none able to forget it.

`_commit` returns whether anything changed, and one caller needs the answer: one holding
transient state the commit was meant to tear down. `controller/api/move.dart` → `commitMove`
ends with `if (!committed) _notify();` — a clamped-to-nothing drag commits nothing, yet the snap
guide and drag ghost still have to leave the screen. `move_commit_teardown_test.dart` is the
regression: a guide once stayed frozen on a canvas with no drag in progress.

## Selection is in the snapshot; the view is not

`designer/controller/selection.dart` → `Selection` is an immutable value that is exactly one of:
a set of element ids, a single band, group, scope or crosstab, or the report, and the cases are
exclusive by construction. It names its target by the stable id page 01 describes — never an
index, never a model reference — so it survives the definition being replaced under it. It rides
inside `DesignerDocument`, which is why undo restores it, but changing it is not an edit:
`_setSelection` replaces the document and notifies without touching `_history`. Zoom, pan, view
toggles and live drag state sit outside the snapshot, so outside undo.

## Why it is like this, and the alternative rejected

The alternative is the ordinary one: let the widgets edit the definition. The canvas owns the
report, a drag writes an element's bounds, an inspector writes a style, a `setState` follows. It
fails here three ways.

**It is not expressible.** The domain types have `const` constructors, final fields and no
setters. A widget cannot write a band's height, only build a new definition — re-implementing
`band_walker.dart`'s descent at every call site, which is page 01's argument for having that
walker at all.

**Undo becomes inverse operations.** With no choke point there is no before-snapshot to bank, so
each edit must describe how to reverse itself: a second implementation per command, correct only
while it stays in step with the first. Notification and no-op suppression go the same way.

**The designer starts forming opinions.** One mutation point is also one model: canvas, preview,
thumbnails and exporters all read `definition`, through the single paint path of pages 04 and
05.

The costs are real: the controller is a god-object the `part`/`extension` split manages rather
than removes, and history never persists. And the pattern is only as good as its funnel — a
mutator skipping `_commit` would compile and be invisible to undo. What enforces the outcome is
that every command's contract is asserted through its public mutator.

## Run it

```bash
flutter test packages/jet_print/test/designer/controller/
```

Nearly every file there is black-box by necessity: the command classes are not exported, and
`test/encapsulation_test.dart`'s allowlist admits only the tree-walker and binding-resolution
tests here. A test does what the designer does — call the mutator.

`controller_history_test.dart` states the core contract: `open` seeds the id factory past the
largest existing numeric suffix; undo and redo restore **both** definition and selection
exactly; an edit after an undo discards the redo stack; undo and redo past the ends do nothing.
`undo_redo_sequence_test.dart` repeats that sixty edits deep. `set_shape_kind_command_test.dart`
states the no-op rule beside the case proving it is about values, not appearances: picking
*rectangle* on a shape whose serialized form was unrecognized (page 06's preserved unknowns)
**is** a real edit, because it clears the preserved form.

## Trap

**A field-by-field rebuild of a `Band` silently drops the next field added to `Band`.**
`AGENTS.md` carries the rule as *Rebuilders drop fields silently*; the mechanism is that
`domain/band.dart` → `Band.copyWith` is the old `value ?? this.value` form on every parameter,
including the nullable `columnLayout` and `name`. That form cannot tell "leave it" from "clear
it", so a command that must *clear* one of them cannot use `copyWith` at all — and two must,
`commands/rename_band_command.dart` → `RenameBandCommand` and
`commands/remove_column_layout_command.dart` → `RemoveColumnLayoutCommand`, both calling
`Band(...)` directly and enumerating every other field by hand. Add a field to `Band`: those two
calls still compile, still pass their own tests, and quietly reset it to its default on every
rename and layout removal.

`domain/copy_support.dart` is the fix the rest of the model already took: a `T Function()?`
thunk parameter makes `field: () => null` expressible, so clearing needs no rebuild.
`DetailScope`, `GroupLevel`, `ReportDefinition` and every element type import it; `Band` does
not. One more grep target: `commands/scope_commands.dart` → `SetScopeCollectionCommand` rebuilds
a `DetailScope` directly, on a justification that expired when `DetailScope` took the thunk.

## Next

Page 08, [the canvas](08-the-canvas.md), takes the loop outward: how the controller's display
definition becomes a design-time `PageFrame` through the *same* renderers the engine uses, how a
pointer becomes an element id, and how selection chrome draws over a picture it may not change.
