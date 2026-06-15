# Feature Specification: Gate "Add list" to Bindable Collections

**Feature Branch**: `027-add-list-gating`
**Created**: 2026-06-15
**Status**: Draft
**Input**: The Outline "+" menu's "Add list" becomes a submenu of the collections
available at that scope's level; picking one creates a list already bound to it.
Disabled where no collection is bindable. Mirrors the 026 "Add group" gating.

## Problem

The Outline "+" menu offers "Add list" on every scope unconditionally, creating
an **unbound** nested list (`createListWithBand(scope.id)` with no
`collectionField`). When invoked on a scope that has no sub-collection to bind to
— e.g. inside the `lines` list, whose items are all scalars — the resulting list
can *never* be validly bound: it is permanent, unbindable clutter. Repeated
invocations stack several `List (unbound)` nodes (observed: a `lines` list
containing three nested unbound lists).

This is the same gap [[spec-026-group-bind-status]] closed for groups, one level
up: 026 made "Add group" a field submenu (born bound) and disabled it where no
scalar field is in scope. "Add list" has no such gate yet — which is exactly why
it lets you pile up unbindable lists. This feature makes the Outline "Add list"
symmetric with "Add group".

## Clarifications

### Session 2026-06-15

- Q: Gate "Add list" by binding at creation (a collection submenu, full
  symmetry with 026 groups) or keep it structure-first unbound but disabled when
  empty? → A: **Bind at creation** — "Add list ▸ collection" submenu; picking a
  collection creates a bound list. The Outline unbound-list path is removed.
- Q: Scope — only the Outline "Add list", or also de-duplicate the Data Source
  "＋Add list"? → A: **Outline only.** The Data Source "＋Add list" already binds
  data-first and is left untouched.

## Scope

**In scope**: the Outline "+" menu "Add list" option (submenu + disabled-empty),
and one shared helper for resolving a scope's bindable collections.

**Out of scope** (intentional, consistent with the 026 decisions):
- **No de-duplication.** "Add list ▸ lines" under root stays available even if a
  `lines` list already exists — two lists over one collection is a *valid* bound
  structure (e.g. summary + detail), unlike the unbindable unbound ones.
- **Existing unbound lists are not auto-migrated** — the author deletes them
  manually (026 likewise left existing placeholder groups alone).
- **Data Source "＋Add list" is untouched.**

## User Scenarios & Testing *(mandatory)*

The user is a **report author** designing in the visual designer.

### User Story 1 - Add a bound list from the Outline (Priority: P1)

An author opens the Outline "+" menu on a scope and chooses **Add list**, which
expands to the collection fields available at that scope's level. Picking `lines`
creates a nested list bound to `lines`, with a detail band, selected.

**Why this priority**: This is the entry point that produced the unbound clutter;
binding at creation is the fix.

**Independent Test**: Open the add menu on the root scope with a schema attached;
assert the "Add list" submenu lists exactly the collection fields resolvable at
that scope (`lines`); pick one; assert a `NestedScope` exists with
`collectionField == 'lines'` and a detail band, selected, in one undoable step.

**Acceptance Scenarios**:

1. **Given** the root scope with a `lines` collection in scope, **When** the
   author opens "Add list", **Then** the submenu lists `lines` (and no scalar
   fields).
2. **Given** the submenu open, **When** the author picks `lines`, **Then** a
   nested list bound to `lines` (with its detail band) is added in one undoable
   step and that band is selected.
3. **Given** a scope with no bindable collection (e.g. inside `lines`, whose
   items are all scalars), **When** the author opens the "+" menu, **Then** "Add
   list" is disabled — no unbound list can be created there.

## Requirements *(mandatory)*

- **FR-001**: A shared helper `collectionFieldsForScope(schema, def, scopeId)`
  returns the collection-typed fields resolvable at `scopeId`'s level — the exact
  mirror of the existing `scalarFieldsForScope`, filtering `type == collection`.
  The `scopePathToScope` + `fieldsInScopeForChain` resolution shared by the two
  is extracted so it is written once.
- **FR-002**: The Outline "+" menu replaces the flat "Add list" option with a
  nested submenu whose children are `collectionFieldsForScope(...)` for that
  scope. Picking collection `C` invokes
  `controller.createListWithBand(scope.id, collectionField: C)` (which already
  creates the bound nested scope + its detail band and selects it). Child option
  key: `'$scopeBase.add.list.field.<C>'`.
- **FR-003**: When a scope has no bindable collection, the "Add list" entry is
  disabled (matching the "Add group" empty-state). It MUST NOT create an unbound
  list.
- **FR-004**: No new controller method is required — `createListWithBand`'s
  existing `collectionField` parameter is used. The Data Source "＋Add list" and
  the unbound `createListWithBand(scope.id)` controller call (still used by tests
  / programmatic callers) are unchanged.

## Design Notes

### Bindable-collection resolution

The collections a *new child list* of scope `S` may iterate are the
collection-typed fields in `S`'s own field-scope:
`fieldsInScopeForChain(schema, scopePathToScope(def, S))` filtered to
`JetFieldType.collection`. For the root scope that yields the top-level
collections (`lines`); for the `lines` scope it yields nothing (its items are
scalars), so "Add list" is disabled there. This is the collection-typed
counterpart of 026's `scalarFieldsForScope`.

### Menu mechanics

`_MenuOption` and `_TypeMenu` already support nested `children` and `enabled`
(added in 026 for "Add group ▸"). "Add list" reuses them unchanged; only the
option construction in `_addMenu` changes from a flat option to a submenu. The
shadcn submenu opens on hover (same as "Add group").

## Testing Strategy

- **Outline widget test**: the "Add list" submenu lists the scope's collections;
  picking `lines` creates a bound nested list + detail band; a collections-less
  scope (inside `lines`) shows "Add list" disabled and creates nothing. Update
  the existing flat-"Add list" assertion (it now taps the submenu parent → hover
  → pick `lines`).
- **Helper**: `collectionFieldsForScope` covered via the Outline widget tests
  (the 026 `scalarFieldsForScope` is likewise covered through widget tests).
- **Regression**: `datasource_add_list_test` (Data Source path) and
  `createListWithBand` unbound usage stay green — they are untouched.
- **Goldens**: authoring-only change; expect 0 golden changes.

## Success Criteria

- **SC-001**: The Outline "+" menu cannot create an unbound list — every list it
  creates is bound to a collection chosen at creation.
- **SC-002**: "Add list" is unavailable on a scope with no bindable collection
  (no more unbindable nested lists under `lines`).
- **SC-003**: Lists and groups now have symmetric Outline creation: both are
  field/collection submenus, both disabled when there is nothing to bind.
