# Crosstab / Pivot Grid — Designer Authoring (Spec B)

**Date:** 2026-09-01
**Status:** Draft for review
**Depends on:** `2026-08-30-crosstab-engine-design.md` (Spec A — shipped, `origin/main` `63a46ee`)
**Layer:** designer only. No domain-model field is added, no codec change, no engine change.

## Goal

Make a crosstab a first-class **authorable** object in the designer: add one, select it, edit its
axes, measures, metrics and style, reorder it among its siblings, and delete it — with undo/redo,
localization and tests, exactly as bands, groups and nested lists already work.

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

The submenu entry is disabled when the source has no scalar field at all — there is nothing to bucket
by, and no seeding rule could produce a valid crosstab.

### 3. Selection granularity is the whole crosstab

`Selection` gains a fifth mutually-exclusive target, `crosstabId`. Axis levels and measures are **not**
separately selectable.

Making a group or a measure its own selection target would add two more mutually-exclusive fields to
`Selection` — a class whose invariant ("exactly one of five") is enforced by hand in its factories,
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
documented invariant extended to five targets. Every existing consumer that reads `bandId ?? groupId
?? scopeId` for its "inspected key" gains `?? crosstabId`, and `controller/api/selection.dart` gains
`void selectCrosstab(String crosstabId)` beside `selectBand` / `selectScope`.

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
  void createCrosstab(String scopeId, {String? collectionField});
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

New part file `layout/panels/properties/inspectors/crosstab_inspector.dart` — the panel is already
split into `part` files by inspector, and this follows that structure. Dispatch in
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
| Style | Header / cell / total text and box styles, via the existing `style_editors.dart` widgets |
| Visibility | The existing `BoolProperty` editor, as bands and elements use |

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

**Golden impact.** The schematic changes the pixels inside the placeholder rect, so the designer
canvas goldens that contain a crosstab move. Those are regenerated deliberately, in the task that
introduces the schematic, and reviewed as an intentional diff. No other golden should move — a
diff anywhere else is a bug in that task.

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
| Undo/redo | One end-to-end walk: create, edit an axis, add a measure, reorder, delete — then undo five times back to the original definition |
| Goldens | Regenerated once, in the schematic task |

## Out of scope (Spec C)

Across-first slice order · fit/scale column mode · derived measures · per-cell templates · crosstab
inside a `NestedScope` · full WYSIWYG canvas rendering through `planCrosstab` · drag-to-resize of
the row-label or measure columns on the canvas · crosstab clipboard (copy/paste/duplicate).

## Risks

- **`Selection`'s hand-enforced invariant.** A fifth target multiplies the mutual-exclusion surface.
  Mitigation: one test asserting each factory produces exactly one non-empty target, and that the
  five are pairwise unequal.
- **`reorderScopeChild` generalization.** It is used by `moveBand` today; the rename must be
  behaviour-preserving. Mitigation: the existing band-reorder tests run unchanged against the
  renamed function before any crosstab uses it.
- **Inspector size.** The crosstab inspector is the largest single inspector in the panel. It goes
  into its own `part` file from the first line; the god-file program's ceiling (~1,040 lines) applies.
- **Seeding rule surprise.** Field order in a schema decides which field lands on which axis. It is
  deterministic and immediately editable, and no other rule avoids guessing without a modal wizard.
