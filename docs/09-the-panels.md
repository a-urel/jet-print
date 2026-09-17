# The panels

The surfaces beside the canvas: what the outline shows, how the properties panel picks an
inspector, and the one path from a widget callback to an undoable step.

Page 08 turned a pointer on paper into a call on the controller. The panels do the same without
the paper, and they are where most of the model is authored — a crosstab's measures, a group's key
and a page's margins have no gesture on the canvas at all. The right-hand surface is
`designer/layout/designer_right_panel.dart` → `DesignerRightPanel`, a `ShadTabs` over Data Source,
Outline and Properties whose tabs are declared `maintainState: false`: an inactive body leaves the
tree rather than being hidden, which is why panel view state below resets when you leave the tab.

## An editor is a value and a callback

No widget under `designer/layout/` writes to a `ReportDefinition`. An editor is handed the value
it should display and a callback it hands a value back to, and that callback is always a
controller mutator. `designer/layout/panels/properties/fields/text_input.dart` → `_NumberField`
is the smallest complete case — the X/Y/W/H fields, the band height, the margins and the crosstab
metrics are all this one widget. It owns a `TextEditingController` for the in-progress string and a
`FocusNode` (its own, unless the panel hands it one of its focus targets), and no model state at
all. Its whole commit:

```dart
void _commit() {
  final double? parsed = double.tryParse(_controller.text.trim());
  if (parsed == null) {
    _controller.text = _format(widget.value); // reject unparseable input
    return;
  }
  // Ignore a re-commit that only reflects display rounding — e.g. blurring a
  // field showing the rounded "28.4" form of a 28.35 model value would
  // otherwise drift it to 28.4. Below display precision, there is no edit.
  if (_format(parsed) == _format(widget.value)) {
    _controller.text = _format(widget.value);
    return;
  }
  widget.onCommit(parsed);
}
```

What it gives back is one parsed `double` — not a rect, not a delta, not the element. The rest of
the path is page 07's: the element inspector passes `onCommit: (double v) =>
controller.setGeometry(id, x: v)`, and `designer/controller/api/element_edit.dart` → `setGeometry`
reads the element's current bounds, substitutes the one named axis, applies `clampToBand`, and hands
a `ResizeCommand` to `_commit`, which banks the prior document and notifies. One keystroke, one
history entry — **unless the clamp absorbs the edit entirely**, because `setGeometry` returns on
`if (clamped == b)` before reaching `_commit`: typing `-20` into the X of an element already at 0
records nothing, notifies nothing, and leaves the field showing `-20` (page 07's value-equal no-op,
one step earlier). Otherwise the editor learns the clamped value the way every observer does, since
`designer/designer_scope.dart` → `DesignerScope` is an `InheritedNotifier` and the rebuild hands
the field a new `value` — which `didUpdateWidget` copies into the text controller **only while the
field is unfocused**, so typing is never overwritten but an undo or a canvas drag lands at once.

Every other editor is that shape with a different payload: `_ValueField` in
`properties/fields/value_field.dart` is given a `ValueDisplay` and returns raw token text for
`setValue` to parse, its field picker and its fx dialog routing through that same `onCommit`, so the
three ways to author a binding are one path. That `ValueDisplay` is `reverseCompile` from
`designer/template/value_template_compiler.dart`, the projection page 08 describes — and where the
canvas takes only `.text`, the panel reads `.editable` too and renders the input `readOnly` when it
is false, so a binding outside the grammar cannot be typed over.

## The panel dispatches on the selection

`designer/layout/panels/properties_panel.dart` → `PropertiesPanel` is one `State` whose `build`
is a chain over the `Selection` page 07 defines:

```dart
final List<Widget> children;
if (selection.isReport) {
  children = _reportInspector(controller, theme, l10n);
} else if (selection.bandId case final String bandId) {
  children = _bandInspector(controller, bandId, theme, l10n, schema);
// ... here, the crosstab, group and scope arms, each guarded exactly like the
// element arm below — and, above this block, the pending-focus request, the
// theme/schema/l10n lookups and the inspected-key bookkeeping
} else if (selection.singleOrNull case final String id
    when _find(controller, id) != null) {
  children = _elementInspector(
      controller, _find(controller, id)!, theme, l10n, schema);
} else {
  return KeyedSubtree(
    key: const ValueKey<String>('$_p.empty'),
    child: _EmptyState(count: selection.length),
  );
}
```

Each inspector is a method returning a flat `List<Widget>` the panel scrolls, the two largest living
in their own `part` files under `panels/properties/inspectors/` for the reason `AGENTS.md` gives
under *Four god-files are split with `part` + `extension`*. **A selection with no inspector falls to
the empty state** — `_EmptyState`, showing the localized multi-selection message above one element
and the "select something" hint otherwise. The `when` clauses route into it: a selection naming a
node the definition no longer holds skips its arm rather than building half an inspector. One arm is
a signpost rather than an editor: `_groupInspector` renders a header and a sentence, because a
group's name, key and start-new-page flag are edited on its carrier band — `_bandInspector`
appends `_groupSection` on the group's header, or its footer when there is no header — and
`selectGroup` has no caller in `lib/` at all, so that arm is reached only by a host.

The panel is not remounted when the selection changes. It is one `State`, so a `_NumberField` at the
same position survives from element to element and takes the new value through `didUpdateWidget` —
deliberate for the numeric fields, wrong for anything holding a draft, which is why every section
that holds one (font, barcode, chart, appearance, and any later addition) sits inside a
`KeyedSubtree` keyed by the element's id: switching elements destroys those editors and a half-typed
hex colour with them.

## The outline is the tree made navigable

`designer/layout/panels/outline_panel.dart` → `OutlinePanel` walks the definition in visual order:
the report root, the record-blind furniture and once-bands above the body, the master scope, then
the ones below. Under a scope, `panels/outline_panel/rows.dart` → `_addScopeRows` emits the group
headers outer-to-inner, the scope's ordered `children` — a `BandNode`, a `NestedScope` recursed
into, a `CrosstabNode` as a leaf — then the group footers inner-to-outer. `UnknownScopeNode` emits
nothing: page 06's preserved-verbatim node has nothing to author. Groups get no row of their own
but surface as their header and footer bands, which is why the scope's "+" menu is where a missing
group band is added.

Selection goes through the controller in both directions. Tapping a row calls `selectBand` /
`select` / `selectScope` / `selectCrosstab` / `selectReport`; the row's `selected` flag is read
back from `controller.selection` on the next build and exposed to the semantics tree, which is how
`outline_tree_test.dart` asserts it. Nothing listens to the canvas — both read one notifier.
Expansion is the outline's own state: a `Set<String>` of collapsed ids, keyed by id so it survives
an add, a remove or a reorder, and reset when the tab is left. The rows carry the structural
affordances too — reorder, retype, remove, and the "+" menus in `outline_panel/add_menus.dart`,
whose `_retypeTargets` omits the furniture the layouter cannot yet lay out.

## One pair of style editors, two inspectors

`panels/properties/fields/style_section.dart` → `_TextStyleEditor` and `_BoxStyleEditor` are the
composed editors shared across inspectors: family, size, colour, B/I/U and alignment in the first;
fill, outline and outline width in the second. Both are stateless, both take the style to display
and return a whole new style, and both build every child key as `'$keyBase.<name>'` — the element
inspector passing `keyBase: '$_p.field'`, which is what those keys were before the extraction, the
crosstab inspector one namespace per appearance role.

Nullable slots are the interesting part. A crosstab role whose style is unset displays the
*effective* value it would inherit rather than a blank control, and any edit commits a concrete
style — a one-way door, which is why each role carries a reset writing `null` back through
`copyWith`'s thunk form (`AGENTS.md`, *`copyWith` uses thunks*). Those inherited values are mirrored
constants, not imports — the render layer is not a designer dependency — so the doc comment
names the test pinning each copy separately. That is the divergence the shared editors exist to
prevent, here unprevented: private to different libraries, the two copies can be compared by no
test, and a planner default changed on one side leaves the panel showing the other.

## Why it is like this, and the alternative rejected

The alternative is per-inspector editors — the crosstab inspector composing its own font row out
of the same primitives the element inspector composes its own out of. That is what the tree looked
like before `a8254c2` and `6998750`, and those commit messages say why it changed: the element
inspector had assembled family/size/colour/B-I-U/align inline, each crosstab appearance slot needed
the same controls, and composing them per slot meant repeating that block once per slot. The
duplication is why the crosstab style editors were deferred in the first place.

The failure mode is not the repetition. It is that two copies of a font row diverge — one gains a
preset, one starts preserving stored alpha on a hex edit — and **nothing catches it**, because
each copy passes its own tests. The extraction's own check was built to be exactly that: the element
inspector was moved onto the shared editor first, with key composition chosen so every shipped key
survived verbatim, so the existing element tests validated the new widget unedited. The cost is that
one editor must then serve slots with different rules — `_BoxStyleEditor` carries a `showFill`
flag for the line shape, which has no interior, a path no crosstab slot exercises and which
therefore got a test of its own.

## Run it

```bash
flutter test packages/jet_print/test/designer/
```

The root of that directory is the largest single group in the repo's test tree, and nearly all of it
drives the public `JetReportDesigner` — `properties_editor_test.dart` reaches the inspector by
tapping its tab, as a user would. Three of its cases state the binding path end to end: *editing X
commits to the model as one undoable step* types, submits, asserts the model and undoes it; *the
width stepper bumps the size by one* proves the stepper is that same commit; *the fields reflect a
model change made elsewhere* calls `setGeometry` and watches the field follow.

## Trap

**A new selection kind must be added to three chains written in two idioms, and only one of them is
the dispatch.** The `??` chain computing the inspected key in `properties_panel.dart` →
`_PropertiesPanelState.build` and the `||` chain in `outline_panel.dart` →
`_OutlinePanelState.build` both decide whether an inline rename editor survives the next frame, and
neither resembles it. Miss the panel's and the key stays `null` across a selection change, so a
rename field opened on one object persists onto the next; miss the outline's and the editor is torn
down on the very next build, so double-tapping a row appears to do nothing. The second is not
hypothetical — it is how crosstab rename shipped, which is why `crosstab_outline_test.dart`'s
*double-tapping the row opens an editor that commits a rename* carries the reason "the inline
rename editor must survive the next build", and `properties_rename_test.dart`'s *header edit resets
when selection changes* pins the other. Grep for `_editingId` and `_lastInspectedKey`.

## Next

Page 10, [designer seams](10-designer-seams.md), takes what the panels and the canvas both depend
on and treats it directly: the scopes carrying the controller, fonts and schema down the tree, the
preset and glyph lookups, the value-template compiler, localization, and what the `part` +
`extension` splits cost at the barrel.
