# Data-Field `description` — Design

**Date:** 2026-06-27
**Status:** Approved (brainstorming) — pending implementation plan
**Branch:** `feat-field-description`

## Goal

Give each data field an optional, human-friendly `description` (a label),
displayed beside the field's technical `name` in the designer's **Data Source**
view. Decouples the readable label from the binding key: authors keep stable
machine names (`customerTotal`) while seeing friendly text ("Total spend per
customer").

This is **author-facing display sugar only**. It does not affect binding,
expression resolution, fill, or render. No golden changes.

### Why this is the right shape (best practice)

Reporting tools universally split the binding key from the display label —
JasperReports (`name` vs `fieldDescription`), SSRS/Power BI (field name vs
alias), Crystal Reports (field name vs caption). The value:

- A label can be renamed/localized without breaking any expression that binds
  by `name`.
- Database columns are often terse (`cust_tot_amt`); the label can be readable.

The chosen term is **`description`** (matching JasperReports' `fieldDescription`).

## Scope

| In scope | Out of scope (YAGNI) |
|---|---|
| Optional `String? description` on `FieldDef` | GUI editor for `description` |
| Round-trip in the data-source file codec | Use as a rendered/printed column header |
| Display in the Data Source tree (two-line) | Any engine / fill / render / golden change |
| Fallback to name-only when null | Schema-version bump (schema is host-attached, not in the report template) |

The author supplies `description` either by constructing `FieldDef` explicitly
or by loading a data-source file that carries it. Inferred schemas
(`inferFields`/`inferColumn`) have no source for it → it stays null and the view
shows the name alone (no behavior change for inferred schemas).

## Components

### 1. Model — `lib/src/data/field_def.dart`

Add `final String? description;`, default `null`.

- Constructor: new optional named param `this.description`.
- `==`: include `other.description == description`.
- `hashCode`: add `description` to `Object.hash(...)`.
- `toString`: append when non-null (keep existing terse form when null).
- `inferType` / `inferColumn` / `inferFields`: unchanged — they construct
  `FieldDef`s without a description, so it defaults null.

Pure sugar: never read by binding, resolution, or the fill/render path.

### 2. Serialization — `lib/src/data/serialization/data_source_file.dart`

- `_encodeField`: `if (field.description != null) 'description': field.description`
  (omit-when-null → files without descriptions stay byte-identical).
- `_decodeField`: read optional `description`; if the key is present it must be a
  `String`, else throw `JetDataSourceFormatException` (mirror the `name`/`type`
  validation style). Absent key → null.

### 3. Data Source view — `lib/src/designer/layout/panels/data_source_panel.dart`

Display `description` as a **second line** under the field name (muted, smaller),
for both leaf rows (`_FieldRow`) and collection branches. Null/empty description
→ render exactly as today (name only, no empty second line).

```
🔤 customerTotal            Decimal
   Total spend per customer
🔤 orderDate                DateTime
   Date the order was placed
```

Leaf rows stay draggable (the drag chip still carries `field.name`, not the
description — the binding key is what gets dropped). The trailing type token is
unchanged.

For collection branches: the tree branch shows the description under its name
where the shared `TreeBranch` widget allows it; if `TreeBranch` cannot host a
subtitle without a broader change, scope the two-line treatment to leaf rows for
this slice and note the gap (collections are rarer and already visually distinct
as expandable branches). Decide during implementation after reading
`TreeBranch`.

## Data flow

```
host schema (explicit FieldDef.description OR data-source file)
        │
        ▼
JetDataSchema  ──►  DesignerSchemaScope  ──►  DataSourcePanel
                                                  │
                                                  ├─ leaf:   name + description (2-line) + type token
                                                  └─ branch: name + description + type token
```

No new state, controller, command, or undo entry — read-only display.

## Error handling

- Decode: a non-string `description` value → `JetDataSourceFormatException`
  (consistent with existing field validation).
- Null/empty `description` everywhere → graceful fallback to name-only.
- Inference never produces a description; no path can crash on its absence.

## Testing

- **Model** (`test/data/field_def_test.dart` or sibling): equality/hashCode
  distinguish two fields differing only by `description`; `toString` includes it
  when set, omits when null; default is null.
- **Serialization** (`test/data/serialization/data_source_file_test.dart`):
  round-trip a field with a `description`; omit-when-null keeps prior JSON
  byte-identical; a non-string `description` throws.
- **View** (`test/designer/data_source_tree_test.dart`): a field with a
  `description` renders both name and description text; a field without one
  renders only the name (no stray empty subtitle); drag data still carries the
  `name`.
- **Regression:** full `flutter test` green; goldens unchanged (author-time-only
  change, no render path touched).
