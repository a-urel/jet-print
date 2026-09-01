# Crosstab / Pivot Grid — Designer Authoring (Spec B)

**Date:** 2026-09-01
**Status:** Implemented — branch `045-crosstab-designer-authoring`, 14 commits. Reconciled with the
shipped code after review; the corrections are marked **(revised)** where the design changed during
implementation.
**Depends on:** `2026-08-30-crosstab-engine-design.md` (Spec A — shipped, `origin/main` `63a46ee`)
**Layer:** designer only. No domain-model field is added, no codec change, no engine change.

## Goal

Make a crosstab a first-class **authorable** object in the designer: add one, select it, edit its
axes, measures, layout metrics and visibility, reorder it among its siblings, and delete it — with
undo/redo, localization and tests, exactly as bands, groups and nested lists already work.

The six cosmetic text/box style slots are **not** in scope (see §4); "style" here means the layout
metrics.

Spec A deliberately shipped a read-only designer surface: the Outline row has no tap handler and no
actions, and the canvas placeholder is wrapped in `IgnorePointer`. The user-visible symptom is
"PivotGrid rapora elemanı eklenemiyor ve seçilemiyor" — this spec closes exactly that gap.

## What already exists (Spec A seams)

Spec A left the authoring hooks in place; Spec B mostly consumes them.

| Seam | State |
|---|---|
| `Crosstab`, `CrosstabGroup`, `CrosstabMeasure`, `CrosstabStyle` | Immutable, `ValueEquality`, full thunk-`copyWith` on every nullable slot |
| `validate()` crosstab rules | Complete (`_validateCrosstab`): empty axes, unparseable expressions, non-root placement, non-positive metrics, unknown fields, width overflow, `visible` misuse |
| `allIds(def)` | Already yields the crosstab id **and** its group/measure ids — Spec A's comment says "so authoring mints them"; `ElementIdFactory.seedFrom` therefore already keeps minted ids collision-free |
| `band_walker` traversals | Every `ScopeNode` switch already has an explicit, commented `CrosstabNode` arm |
| `DesignTimeLayout` | Computes each crosstab's page-absolute rect and exposes `List<PlacedCrosstab> crosstabs` |
| `crosstabDisplayLabel` + `crosstabLabel` ARB key | Present in all three locales |
| Codec | `kind: 'crosstab'` round-trips; `UnknownScopeNode` protects forward compatibility |

Nothing in Spec B requires a schema version bump: the model is unchanged, so a file authored in the
designer is byte-compatible with one hand-written for Spec A.

## Locked decisions

These are the four open design questions, answered.

### 1. A crosstab is added from the Outline "+" menu, not the canvas

The toolbox and canvas drop target create **elements inside a band**. A crosstab is not an element —
it is a `ScopeNode`, a sibling of bands, and it has no author-controlled position or size on the
page. It is added the way its actual siblings are added: from the scope's "+" menu, next to
"Add band", "Add list ▸" and "Add group ▸".

Only the **root scope's** menu offers it. Spec A decision 8 restricts crosstabs to the root scope
and `validate()` rejects them elsewhere; an affordance that mints an object the validator
immediately rejects is a bug, not a feature.

### 2. A crosstab is born valid and bound

`validate()` requires at least one row group, one column group and one measure. A crosstab created
empty would be born broken, and every "add empty then bind" flow in this repo has been replaced by a
born-bound one (spec 026 groups, spec 027 lists). So the "Add crosstab ▸" submenu picks the data
source — one entry per collection in scope, plus "(rows of this scope)" — and the created crosstab
is seeded from the schema of that source:

- **row group** = the first scalar field; **column group** = the second scalar field, or the first
  again when only one exists;
- **measure** = the first numeric field with `JetCalculation.sum`; when there is no numeric field,
  the first scalar field with `JetCalculation.count` (count needs no numeric input);
- names default to the field names; `showTotal` defaults to true, matching the model default.

**Each submenu option is independently disabled unless *its own* source offers at least one
non-collection field** — there is nothing to bucket by otherwise, and no seeding rule could produce a
valid crosstab. In particular a collection whose children are all themselves collections is offered
disabled, not enabled-and-inert: gating on "has any children" leaves a live-looking, dead menu item
whose only effect is `createCrosstab`'s own silent refusal.

### 3. Selection granularity is the whole crosstab

`Selection` gains a **sixth** mutually-exclusive target, `crosstabId` — element ids, `bandId`,
`groupId`, `scopeId` and `isReport` were the five. Axis levels and measures are **not** separately
selectable.

Making a group or a measure its own selection target would add two more mutually-exclusive fields to
`Selection` — a class whose invariant ("exactly one of six") is enforced by hand in its factories,
its `==`, its `toString` and every consumer switch — and would need canvas chrome for objects that
have no canvas rect of their own (a measure is a column that only exists once data is folded). The
cost lands in the selection, clipboard, undo and hit-test surfaces; the benefit is a selection ring
around a list row that is already directly editable in place.

Axis levels and measures are therefore edited as **lists inside the crosstab's Properties inspector**,
each row with its own inline fields and its own add / remove / reorder actions.

### 4. The canvas gets a schematic, not WYSIWYG

The crosstab's real geometry is data-driven: the row count is the distinct-key count of the row axis,
the column count is the leaf-column count times the measure count, and both are only known after a
fold over real rows. The designer holds a `JetDataSchema`, not a data source — it has no rows to fold.
Spec A's own note says pagination-aware sizing is render-time only.

So the canvas block stays a stand-in, but a **truthful and interactive** one: it becomes selectable,
and it draws what the model alone determines — the row-label column at its real `rowLabelWidth`, one
header row per column-group level, the measure column names at their real `measureColumnWidth`, and
one stub row per row-group level at its real `rowHeight` and indent. Data-driven column and row
*counts* are stood in with a single ellipsis column/row, so the block never implies a row count it
cannot know.

This is worth building only because the widths are real: the "wider than the page body" case becomes
visible on the canvas instead of only in a diagnostic string. Full WYSIWYG — running `planCrosstab`
against sample data — is deferred to Spec C, where it belongs with the fit/scale column mode.

## 1. Selection

`controller/selection.dart`:

```dart
factory Selection.crosstab(String crosstabId) =>
    Selection._(const <String>[], crosstabId: crosstabId);
```

plus the `crosstabId` field, its inclusion in `isEmpty`, `==`, `hashCode` and `toString`, and the
documented invariant extended to six targets, and `controller/api/selection.dart` gains
`void selectCrosstab(String crosstabId)` beside `selectBand` / `selectScope`.

**(revised) The consumers, enumerated** — phrasing the sweep as the idiom "everything that reads
`bandId ?? groupId ?? scopeId`" missed a consumer written in a different idiom, and that miss shipped
a dead rename. Every place that special-cases a non-element selection:

| Site | Crosstab arm |
|---|---|
| `properties_panel.dart` `inspectedKey` chain | `?? crosstabId` |
| `properties_panel.dart` inspector dispatch | a `_crosstabInspector` arm |
| `selection_overlay.dart:124` | outline chrome, no resize handle |
| `ruler_metrics.dart:39` | `layout.crosstabRect(id)` |
| `outline_panel.dart:131` stale-inline-editor guard | `selection.crosstabId == _editingId` — **this is the one the idiom missed**; it reads `bandId` alone, so a crosstab's rename editor was discarded on the next build |
| `jet_report_designer_controller.dart` `_pasteTargetBand` | none — it asks for a paste-target *band*, and a crosstab correctly is not one |
| `api/clipboard.dart` `delete` / `copy` / `cut`, `canCopy` | none — they act on `selection.ids`; see below |

**Delete/cut/copy no-op on a crosstab selection**, exactly as on a band, group, scope or report
selection: those commands act on elements, and a crosstab is removed from its Outline action. That
is a decision, not an oversight, and a test pins it so it cannot drift into one.

`canCopy` is unchanged: like a band, group or scope selection, a crosstab selection is not
clipboard-copyable in this spec. Deleting one goes through the Outline action, as it does for a
nested list.

## 2. Model-edit seam

### Walker helpers (`controller/band_walker.dart`)

```dart
Crosstab? findCrosstab(ReportDefinition def, String crosstabId);
DetailScope? findScopeOfCrosstab(ReportDefinition def, String crosstabId);
ReportDefinition mapCrosstabs(ReportDefinition def, Crosstab Function(Crosstab) transform);
ReportDefinition removeCrosstab(ReportDefinition def, String crosstabId);
```

`addScopeChild(def, scopeId, CrosstabNode(ct))` already accepts any `ScopeNode` and is reused as-is.

`reorderScopeChild` currently matches its target with `n is BandNode && n.band.id == bandId`, so it
cannot move a crosstab. It is generalized to match **any** node kind by id through an exhaustive
switch (`BandNode` → band id, `NestedScope` → scope id, `CrosstabNode` → crosstab id,
`UnknownScopeNode` → no id, never matches) and renamed `reorderScopeNode`. `moveBand` passes a band
id and behaves identically; a behaviour-preserving rename with the existing reorder tests unchanged.

### Commands (`controller/commands/crosstab_commands.dart`)

Three commands, not one per property — following `UpdateGroupCommand` and the DRY program's
`ElementEditCommand<E>`:

```dart
class CreateCrosstabCommand extends EditCommand { ... }   // append + select
class DeleteCrosstabCommand extends EditCommand { ... }   // remove + clear selection
class UpdateCrosstabCommand extends EditCommand {         // every property edit
  const UpdateCrosstabCommand({
    required this.crosstabId,
    required this.label,
    required this.update,   // Crosstab Function(Crosstab)
  });
}
```

Axis and measure edits are `UpdateCrosstabCommand`s whose thunk rebuilds the relevant list. A no-op
thunk leaves the definition value-equal and therefore records no history — the controller's existing
`_commit` guard already handles that.

### Controller API (`controller/api/crosstab.dart`, a new `part`)

```dart
extension CtrlCrosstab on JetReportDesignerController {
  // (revised) The controller holds no JetDataSchema — it arrives through
  // DesignerSchemaScope at the UI seam — so the caller resolves the source's
  // fields and only the seeding RULE lives here. It no-ops on a non-root scope:
  // root-only is a model rule validate() enforces, so gating the Outline menu
  // alone would leave this public API able to mint an invalid definition.
  void createCrosstab(String scopeId,
      {required List<FieldDef> fields, String? collectionField});
  void deleteCrosstab(String crosstabId);
  void moveCrosstab(String crosstabId, int delta);
  void renameCrosstab(String crosstabId, String? name);
  void setCrosstabCollection(String crosstabId, String? collectionField);
  void setCrosstabVisible(String crosstabId, BoolProperty visible);
  void setCrosstabStyle(String crosstabId, CrosstabStyle style);

  void addCrosstabGroup(String crosstabId, {required bool row, required String fieldName});
  void removeCrosstabGroup(String crosstabId, String groupId);
  void moveCrosstabGroup(String crosstabId, String groupId, int delta);
  void updateCrosstabGroup(String crosstabId, String groupId,
      CrosstabGroup Function(CrosstabGroup) update);

  void addCrosstabMeasure(String crosstabId, {required String fieldName});
  void removeCrosstabMeasure(String crosstabId, String measureId);
  void moveCrosstabMeasure(String crosstabId, String measureId, int delta);
  void updateCrosstabMeasure(String crosstabId, String measureId,
      CrosstabMeasure Function(CrosstabMeasure) update);
}
```

`remove*` is a no-op when it would leave the crosstab with zero row groups, zero column groups or
zero measures — the UI disables the button at that point, and the API refuses as well so the
invariant does not depend on the widget. New group and measure ids come from `_ids.next('ctgroup')`
/ `_ids.next('ctmeasure')`, which `allIds` already covers.

Because the extension is public API reached through the barrel, its name must appear in the barrel's
`export ... show` list — the god-file-split lesson: a public extension left out of `show` is
uncallable through the barrel and only `public_api_test` catches it.

## 3. Outline panel

`_addCrosstabRow` stops being a decorative `Padding` and becomes a real row:

- **selectable** — `selected: selection.crosstabId == ct.id`, `onSelect: controller.selectCrosstab`;
- **renameable** — the same double-tap `EditableLabel` path bands and elements use, committing
  through `renameCrosstab`;
- **actions** — move up, move down, remove. `_leafRow` gains an optional `actions` parameter
  (defaulting to none, so element rows are untouched) rather than forcing a crosstab through
  `_branchRow`, which would render a disclosure chevron for a node with no children.

The move actions carry the tooltip copy Spec A decision 7 promised: moving a crosstab above the first
band makes it print **once before** the row loop, and below it **once after** — the Outline order is
the only expression of that rule, so the tooltip states it.

The root scope's `_addMenu` gains an "Add crosstab ▸" option, listing the same collection choices as
"Add list ▸" plus a "(rows of this scope)" entry, gated as decision 2 describes. It is offered only
when `scope.id == definition.body.root.id`.

## 4. Properties inspector

New part file `layout/panels/properties/inspectors/crosstab_inspector.dart`. **(revised)** Only the
*element* inspector had been split out; the band, group and scope inspectors still live inside
`properties_panel.dart`. That makes a new file more necessary, not less — the panel is already the
largest file in the designer. Dispatch in
`properties_panel.dart` gains an arm before the group/scope arms:

```dart
} else if (selection.crosstabId case final String id
    when findCrosstab(controller.definition, id) != null) {
  children = _crosstabInspector(controller, id, theme, l10n, schema);
}
```

Sections, in order:

| Section | Contents |
|---|---|
| Identity | Display name (blank clears back to the localized fallback) |
| Data | Collection picker — the in-scope collections, plus a clear action meaning "the rows of this scope" |
| Row groups | Ordered list, one card per level |
| Column groups | Same, for the column axis |
| Measures | Ordered list, one card per measure |
| Layout | `rowLabelWidth`, `rowLabelIndent`, `measureColumnWidth`, `rowHeight`, `headerRowHeight` |
| Visibility | The existing `BoolProperty` editor, as bands and elements use |

**(revised) Rebinding the data source preserves the authored expressions.** It never reseeds or
resets the axes and measures. A rebind is usually one step of repointing a report at a renamed or
restructured source, and silently reseeding would discard authored names, sorts, total labels and
formats to save one re-pick. The cost is that a binding the new source cannot resolve is invisible in
the model, so the inspector flags each one in place, under the field that carries it, using the
element inspector's `_unresolved` rule (nothing is flagged with no schema attached — resolution waits
for a source, FR-019a).

**Deferred during implementation:** the six text/box style slots (`headerText`,
`headerBox`, `cellText`, `cellBox`, `totalText`, `totalBox`). `style_editors.dart` exposes
low-level pieces (colour field, family row, toggle group), not a composed text-style editor, so
surfacing three text styles and three box styles means reproducing most of the element inspector's
font section three times — against the god-file ceiling, for slots that are purely cosmetic, already
round-trip through the codec, and that no report has asked for. The metrics ship because they are
what makes the width warning actionable. Moved to Spec C.

An axis card carries: name, key expression (field picker plus the existing `fx` expression-editor
dialog), sort (`ascending` / `descending` / `dataOrder`), a show-total switch, and a total-label
override that is disabled while show-total is off. A measure card carries: name, value expression
(same picker + `fx`), aggregate (the `JetCalculation` values minus `none`, which `validate()`
rejects), and a format picker from the existing `format_presets.dart`.

**Diagnostics.** The Layout section shows a localized inline warning when the crosstab's minimum
width — `rowLabelWidth + measures.length * measureColumnWidth` — exceeds the page body width. This
mirrors `_columnDiagnostics` (spec 035): the panel re-derives the condition from the same geometry
rather than surfacing the engine's English `Diagnostic` string, because engine diagnostics are not
localized.

## 5. Canvas

- `DesignTimeLayout` gains `String? crosstabIdAt(JetOffset page)`, scanning `crosstabs` — the rects
  are already computed, only the lookup is new.
- `gestures.dart`'s empty-point classifier tries the crosstab hit **before** falling back to the band
  under the point, since a crosstab's rect is a flow block that no band overlaps.
- `_crosstabPlaceholders` loses its `IgnorePointer` wrapper and draws the schematic of decision 4.
- `selection_overlay.dart` gains a crosstab arm next to `_bandChrome`, drawing a selection outline
  around the block. No resize handles: the block's size is model-derived, not drag-authored.
- `ruler_metrics.dart` reads the crosstab rect for the selected-object ruler highlight, matching the
  band arm one line above it.

**Golden impact: none. (revised)** The prediction above was written without checking: no designer
canvas golden contains a crosstab (`test/designer/goldens/` has none; the only crosstab golden is the
render-layer `test/goldens/pivot_test.dart`, which the designer does not touch). The schematic
therefore moved **zero** goldens, and no regeneration step was needed. Adding a crosstab to a
designer golden is worth doing, but it is new coverage, not a consequence of this change — Spec C.

## 6. Localization

New ARB keys in `jet_print_en.arb`, `jet_print_tr.arb`, `jet_print_de.arb`, then `flutter gen-l10n`:
the add-menu entry and its "(rows of this scope)" option, the reorder tooltips (with the
before-loop / after-loop sentence), the eight section headings, the axis- and measure-card field
labels, the three sort-mode labels, and the width warning. Every key is added to **all three ARBs in
the same task** — the chart spec shipped 21 keys that existed only in generated Dart, and the ARBs
are the source of truth `gen-l10n` regenerates from.

German is the width-binding locale for designer chrome (spec 044): any new fixed-width control in
the inspector is checked against the German string.

## 7. Testing

| Area | Test |
|---|---|
| Commands | Black-box through the controller (`encapsulation_test` forbids reaching into command internals): create → definition contains a valid crosstab; delete → gone, selection cleared; every setter → one undo restores both model and selection |
| Born-valid | `validate(def)` returns **no error-severity diagnostic** for a crosstab created by `createCrosstab` against each playground schema — the check that would have caught both demo bugs, filtered to errors so a later info/warning does not break it |
| Invariants | `removeCrosstabGroup` / `removeCrosstabMeasure` refuse the last one, at the API level, not only in the widget |
| Outline | Selecting a crosstab row selects it; rename commits; move up/down reorders among siblings; remove deletes; the add-menu entry is absent on a nested scope and disabled without scalar fields |
| Properties | The inspector renders for a crosstab selection; editing each field commits exactly one history entry; the width warning appears exactly at the overflow threshold |
| Canvas | A tap inside the block selects the crosstab; the selection outline is drawn; a tap outside it still selects the band or report as before |
| Undo/redo | One end-to-end walk: create, edit an axis, add a measure, reorder, delete — then undo back to the original definition |
| Root-only | A direct `createCrosstab` call against a nested scope changes neither definition, history nor selection |
| Rename | A double-tap on the Outline row opens the inline editor **and it survives the next build**, then commits — the guard this spec's first draft missed |
| Menu gating | A collection with no scalar child is offered *disabled*; asserted on the option's `enabled` flag, not on "nothing happened" (`createCrosstab` refuses it anyway, so a tap-and-check would pass against a dead item) |
| Rebind | Expressions survive a rebind, and each one the new source cannot resolve is flagged |
| Clipboard | Delete/cut/copy no-op on a crosstab selection, and `canCopy` is false |
| Goldens | None move — see §5 |

## Out of scope (Spec C)

Crosstab text/box style editors (see the Properties section) · across-first slice order · fit/scale
column mode · derived measures · per-cell templates · crosstab
inside a `NestedScope` · full WYSIWYG canvas rendering through `planCrosstab` · drag-to-resize of
the row-label or measure columns on the canvas · crosstab clipboard (copy/paste/duplicate).

## Risks

- **`Selection`'s hand-enforced invariant.** A sixth target multiplies the mutual-exclusion surface.
  Mitigation: one test asserting each factory produces exactly one non-empty target, and that the
  five are pairwise unequal.
- **`reorderScopeChild` generalization.** It is used by `moveBand` today; the rename must be
  behaviour-preserving. Mitigation: the existing band-reorder tests run unchanged against the
  renamed function before any crosstab uses it.
- **Inspector size.** The crosstab inspector is the largest single inspector in the panel, so it goes
  into its own `part` file from the first line. There is no documented line limit in this repo;
  ~1,040 lines is simply the current size of `properties_panel.dart` after the god-file split
  program, and it is cited here as empirical pressure, not policy.
- **Seeding rule surprise.** Field order in a schema decides which field lands on which axis. It is
  deterministic and immediately editable, and no other rule avoids guessing without a modal wizard.
