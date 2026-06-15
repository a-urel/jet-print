# Group Source Affordances + Field-Format Consistency — Design

**Date**: 2026-06-15
**Status**: Approved (brainstorm) — ready for implementation plan
**Branch**: continues on `025-designer-authoring-affordances` (a follow-on to the designer authoring-affordances feature; the branch is finished after this lands).
**Scope tier**: Focused enhancement, symmetric to the list-binding work in the 025 feature.

## Problem

The 025 feature made a list's data source (`collectionField`) selectable from a schema-aware
picker on the detail band. A **group's** data source has no equivalent affordance:

1. **No schema picker for the group key.** The group section (`_groupSection` in
   `properties_panel.dart`) renders the group key (`GRUP ANAHTARI`) as a plain free-text
   `_TextInput` wired to `setGroupKey`. Unlike the list collection field (which uses the
   schema-aware `_BindingField` + `_FieldPicker`), there is no way to **select** the grouping
   field from the schema — the author must type the expression by hand. (The manual edit path
   *works*; this is a discoverability gap, not a bug — confirmed by investigation and by the user.)
2. **The group name is not editable.** `GroupLevel.name` is a display label (groups are referenced
   by `id`, not `name`), and there is no `setGroupName` controller method or UI field. A group
   created via the 025 "Add group" action gets an auto-generated id as its name (e.g. `group_2`)
   with no way to rename it.
3. **Field-reference format is inconsistent across the designer.** Canvas placeholders and the
   element value field show the `[fieldName]` shorthand (e.g. `[description]`), but the list
   collection binding shows a **bare** field name (`lines`). The same picked-field concept reads
   two different ways depending on where you are.

Groups are reached via their header band (the deliberate "edit the structural entity from its band"
pattern, commit 9401f8c) — not as a selectable Outline node. This design keeps that.

## Goals

- Give the group key a **schema-aware field-picker** offering the scalar fields in scope, the
  symmetric counterpart of the list collection-field picker.
- Make a group **renameable** (a name field + a new `setGroupName` controller method).
- Standardize **all** binding/picker inputs on the `[fieldName]` display format, so the inspector
  speaks the same field language as the canvas placeholders.

## Non-goals (deferred)

- Making the group a first-class selectable Outline node (would partially revert 9401f8c).
- Surfacing keepTogether / reprintHeaderOnEachPage flags (intentionally hidden per the 2026-06-14
  design note).
- Cursor-position *insertion* of a field into a composite expression (the picker **replaces** the
  key; composite expressions like `YEAR($F{date})` are typed by hand).
- Any rendering, codec, or schema-version change.

## Constraints & invariants preserved

- **UI-only.** All work lands in `packages/jet_print/lib/src/designer/**` and the `l10n` `.arb`/
  generated `.dart`. No domain/codec/schema change. `GroupLevel.name`/`.key` and `copyWith` already
  exist; `setGroupName` is a new **designer-layer** controller method (mirrors `setGroupKey`).
- **Stored model values are unchanged by the format pass.** The `[fieldName]` work is a
  *display/input* contract only: a group key still stores a 005a expression (`$F{invoiceNo}`), a
  collection binding still stores a bare field name (`lines`), an element value still stores
  `$F{...}`. Only what the inspector *shows* and *accepts* changes.
- **Rendering fidelity.** Render goldens stay byte-identical (binding fields render only when a
  band/scope/group is selected; default-state goldens are unaffected).
- **Layered / minimal surface / localized**, as in 025.

## Design

### A. Group source affordances (in `_groupSection`, edited from the group header band)

**A1 — Group key schema picker.** The `GRUP ANAHTARI` field gains the same database-icon
`_FieldPicker` affordance the element value and list bindings carry. The offered fields are the
**scalar** (non-collection) fields in scope at the group's owning scope level — you group by a
scalar (e.g. `invoiceNo`), which is the scalar counterpart of the list picker's collection filter.
Picking a field sets the key to the `[fieldName]` shorthand (see B); free-text is retained for
composite expressions.

**A2 — Group name field.** An editable name field is added above the key, wired to a new
`setGroupName(groupId, name)` controller method (an `UpdateGroupCommand` mirroring `setGroupKey`).
Authoring stays permissive: a rename commits even if it collides with a sibling group's name; the
per-scope unique-name invariant (I2) is already a `validate()` diagnostic. (Inline surfacing of that
diagnostic is out of scope here, consistent with 025's deferral.)

### B. `[fieldName]` format consistency pass

All field-binding inputs **display and accept** the `[fieldName]` shorthand. Two classes, by the
underlying stored type:

- **Expression-typed bindings** — the group key and the element value field. These reuse the
  existing compile / `reverseCompile` machinery: the field **displays** a stored `$F{invoiceNo}` as
  `[invoiceNo]` (via `reverseCompile`) and **commits** `[invoiceNo]` back to `$F{invoiceNo}` (via the
  compile step) before storing. A composite expression (`YEAR($F{date})`) round-trips with its
  `$F{...}` parts shown as `[...]` and the rest verbatim. The element value field already behaves
  this way; the group key is switched onto the same path. `setGroupKey` continues to receive a valid
  005a string — compilation happens before it (so its existing contract and tests are unchanged).
- **Name-typed binding** — the list/scope `collectionField`. This is a bare field name, not an
  expression, so it gets a simple bracket **wrap on display / strip on commit**: the field shows
  `[lines]`, the picker inserts `[lines]`, and either form commits to the stored bare name `lines`.
  This updates the display in both the detail-band "List" section (`_bandListSection`) and the scope
  inspector (`_scopeInspector`) added in 025 — the stored value is untouched.
- **Image binding** (the same `_BindingField`, if a field source) follows the name-typed rule too.

The net effect: every place you pick or show a data field reads `[fieldName]`, matching the canvas.

## Key touchpoints (all existing except `setGroupName`)

| Need | Mechanism |
|------|-----------|
| Group key edit | existing `setGroupKey` (receives compiled 005a) |
| Group rename | **new** `setGroupName(groupId, name)` — designer-layer `UpdateGroupCommand` |
| `[field]` ⇄ `$F{field}` for expression bindings | existing compile / `reverseCompile` / `ValueDisplay` (element value field) |
| Field picker dropdown | existing `_FieldPicker` |
| Scalar fields in scope for a group | existing `fieldsInScopeForChain` + the group's scope chain, filtered to non-collection |
| Bracket wrap/strip for the collection binding | small display/commit transform at the `_BindingField` call sites |

## Testing (TDD)

- `setGroupName` controller unit test (renames; one undo; no-op for unknown group).
- Widget: the group key picker offers the in-scope scalar fields; picking one yields a `[field]`
  display and stores the compiled `$F{field}` key.
- Widget: the manual group-key edit path commits through the UI (closes the gap the investigation
  found — not a bug, but currently untested).
- Widget: the list/collection binding displays `[lines]` while the stored `collectionField` stays
  `lines`; the picker and free-text both commit the bare name.
- Widget: the group name field edits the model via `setGroupName`.
- Localization: a group-name label string in en/tr/de; reuse the existing picker tooltip.
- Regression: full `flutter test packages/jet_print` green, render goldens byte-identical.

## Out of scope / deferred

- Group-as-selectable-Outline-node; inline group diagnostics; the hidden pagination flags; composite-
  expression cursor insertion; any rendering/codec/schema change.

## Resolved decisions (from brainstorm)

- The reported "can't update the group source" is the **missing picker**, not a commit bug.
- Scope: group key picker **+** group rename (not the Outline-node change).
- Picker **replaces** the key with the `[field]` shorthand; composite expressions typed by hand.
- The `[fieldName]` format applies to **all** pickers/bindings (including retrofitting the 025 list
  binding's display from bare `lines` to `[lines]`); stored values are unchanged.
