# Feature Specification: Bind Groups to a Field at Creation

**Feature Branch**: `026-group-bind-at-creation`
**Created**: 2026-06-15
**Status**: Draft
**Input**: Every group a report author creates is born keyed to a real scalar
field in scope (`$F{field}`) and named after it. Remove the unbound placeholder
(`key: '0'`) group path from the authoring surface.

## Problem

A group level only means something relative to data: it breaks when a key
expression changes between consecutive rows. Today the designer lets an author
create a group whose key is a constant placeholder `'0'` (see
`createGroupWithHeader` in `jet_report_designer_controller.dart`), with its
display name defaulting to its generated id (`group1`, `group4`, …). Such a
group:

- never breaks at runtime (a constant key yields a single instance), so it
  silently does nothing;
- is offered header/footer affordances in the Outline "+" menu exactly like a
  data-bound group, because that menu keys off band-presence
  (`g.header == null`), not key validity;
- is visually indistinguishable from a real, bound group (e.g. the sample's
  `invoice` group keyed on `$F{invoiceNo}`).

This is an asymmetry with **lists**, which already have *both* a data-first
bound entry (Data Source panel: each collection's "＋ Add list" binds to that
collection) *and* a structure-first unbound entry (Outline "Add list"). Groups
have only the structure-first, unbound half. This feature completes the missing
half so groups are born bound, and removes the placeholder authoring path.

## Clarifications

### Session 2026-06-15

- Q: Where should the "create a bound group" action live in the UI? → A:
  **Both** — an Outline "+" menu entry *and* a Data Source per-scalar-field
  affordance, both invoking one shared controller action.
- Q: When there is no bindable scalar field in scope (no data source attached,
  or the scope exposes only collection fields), how should "Add group" behave? →
  A: **Disabled / hidden** — the placeholder `'0'` creation path is removed from
  the authoring surface; no unbound group is ever created from these entries.
- Q: What is a newly created group's display name and key? → A: `name` = the
  picked field's name (the author can rename later via `setGroupName`); `key` =
  `$F{field}`. The group is created together with its header band, and that
  header is selected (preserving today's "Add group" landing behaviour).

## Scope

**In scope**: the two authoring entry points, one shared controller action,
removal of the placeholder authoring path, and the disabled/hidden empty-scope
behaviour.

**Out of scope** (explicitly): migrating or flagging groups that are *already*
unbound (the validation/warning approach was considered and not chosen). This
feature only governs how *new* groups are created; it does not retroactively
fix or annotate existing placeholder-keyed groups in a loaded document.

## User Scenarios & Testing *(mandatory)*

The user is a **report author** designing in the visual designer.

### User Story 1 - Create a bound group from the Outline (Priority: P1)

An author opens the Outline "+" menu on a scope and chooses **Add group ▸**,
which expands to the scalar fields available in that scope. Picking `customer`
creates a group keyed on `$F{customer}`, named `customer`, with a header band
that becomes selected.

**Why this priority**: This is the primary entry point named in the request
("Add group tıklanınca …") and the one that replaces the placeholder path.

**Independent Test**: Open the add menu on a scope with a schema attached;
assert the submenu lists exactly the scope's scalar (non-collection) fields;
pick one; assert a `GroupLevel` exists with `key == r'$F{customer}'`,
`name == 'customer'`, a header band, the header selected, and exactly one undo
entry.

**Acceptance Scenarios**:

1. **Given** a scope with scalar fields `invoiceNo, customer, orderDate` in
   scope, **When** the author opens "Add group ▸", **Then** the submenu lists
   those three fields and no collection fields.
2. **Given** the submenu open, **When** the author picks `customer`, **Then** a
   group `name: customer, key: $F{customer}` plus header band is added in one
   undoable step and the header is selected.
3. **Given** a scope with no bindable scalar field (no schema, or only
   collections), **When** the author opens the "+" menu, **Then** "Add group" is
   disabled (with an explanatory tooltip) or absent — never creating a
   placeholder group.

### User Story 2 - Create a bound group from the Data Source (Priority: P2)

An author sees the Data Source tree. Each **scalar** field carries a trailing
"＋ group" affordance (mirroring the "＋ Add list" on collections). Activating it
on `customer` creates the same bound group, attached to the scope bound to that
field's parent collection (the root scope for a top-level scalar).

**Why this priority**: The data-first counterpart; most discoverable and
consistent with how lists already work, but secondary to the Outline entry.

**Independent Test**: Activate "＋ group" on a top-level scalar field; assert a
group is added to the root scope keyed on that field. Activate it on a scalar
nested under a collection that already has a bound scope; assert the group lands
on that nested scope.

**Acceptance Scenarios**:

1. **Given** a top-level scalar field `invoiceNo`, **When** the author activates
   "＋ group", **Then** a group `name: invoiceNo, key: $F{invoiceNo}` is added to
   the root scope.
2. **Given** a scalar field whose parent collection has **no** bound scope yet,
   **When** the author looks at that field, **Then** the "＋ group" affordance is
   absent (there is no scope to attach the group to).

## Requirements *(mandatory)*

- **FR-001**: A single controller action — `createGroupBoundToField(scopeId,
  fieldName)` — creates a `GroupLevel` with `name = fieldName`,
  `key = $F{fieldName}`, and a header band, selects the header, and records
  exactly one undoable step. No-op for an unknown scope or an empty/unknown
  field.
- **FR-002**: The Outline "+" menu replaces the single flat "Add group" option
  with a nested **"Add group ▸"** submenu whose children are the scope's scalar
  (non-collection) fields resolvable in that scope. Picking field `X` invokes
  `createGroupBoundToField(scope.id, X)`.
- **FR-003**: When a scope exposes no bindable scalar field, the "Add group"
  entry is shown disabled with an explanatory tooltip (preferred) or hidden. It
  MUST NOT create a placeholder-keyed group.
- **FR-004**: The Data Source panel gives each **scalar** field a trailing
  "＋ group" affordance that invokes `createGroupBoundToField(targetScope,
  field.name)`, where `targetScope` is the scope bound to the field's parent
  collection (root for a top-level scalar), reusing the existing scope-resolution
  used by "＋ Add list". The affordance is absent when no target scope exists.
- **FR-005**: The placeholder authoring path is removed: `createGroupWithHeader`
  (which hardcodes `key: '0'`) is no longer reachable from the UI and is removed
  (or repurposed) once it has no callers. The lower-level
  `createGroup(scopeId, {name, key})` primitive is retained.
- **FR-006**: The group key is stored as the canonical 005a expression
  `$F{field}`, consistent with the existing group-key picker's `[field]` ↔
  `$F{field}` mapping.

## Design Notes

### Field resolution

The set of bindable fields for a *new* group on scope `S` is the scalar
(non-`collection`) fields resolvable in `S`'s scope chain — the scope-level
counterpart of `_groupKeyChoices`, which today resolves at a group's existing
header/footer band. Extract a shared helper that resolves scalar fields for a
scope (via `scopePathTo(scope)` + `fieldsInScopeForChain`), used by both the
Outline submenu and the Data Source affordance.

### Outline menu mechanics

`_TypeMenu` renders `ShadContextMenu` / `ShadContextMenuItem`, which support
nested submenus via `items:`. Extend `_MenuOption` with an optional `children`
list so "Add group" can carry the per-field options without flattening N fields
into the top-level menu (the original "too many items" complaint). The existing
flat options (Add band, Add list, Add header · group, Add footer · group) are
unchanged.

### Data Source mechanics

Today only collection fields carry a trailing affordance ("＋ Add list", under
`_scopeForCollection` resolution). Add a parallel scalar-field affordance that
resolves the target scope the same way (parent collection's bound scope, or root
for a top-level scalar) and is omitted when no such scope exists.

## Testing Strategy

- **Controller**: `createGroupBoundToField` produces a bound group + header,
  selects the header, one history entry; unknown scope / empty field no-ops.
- **Outline**: submenu lists exactly the scope's scalar fields; pick → bound
  group; empty scope → disabled/hidden, never a placeholder group.
- **Data Source**: scalar "＋ group" → bound group under the correct scope;
  absent when no target scope.
- **Regression**: update or remove tests that depended on the old placeholder
  `createGroupWithHeader` / `key: '0'`.
- **Goldens**: authoring-only change. An already-bound group's rendered output
  is unchanged. Any golden that captured a placeholder-key group is regenerated
  to its `$F{field}` form.

## Success Criteria

- **SC-001**: No authoring action can produce a group with the constant
  placeholder key `'0'`.
- **SC-002**: A group created from either entry point is immediately data-bound:
  its key resolves in scope and it breaks correctly at render time.
- **SC-003**: Lists and groups now have a symmetric creation story (data-first +
  structure-first, both binding to a field/collection).
