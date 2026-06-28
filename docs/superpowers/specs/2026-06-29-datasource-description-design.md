# Data Source Description — Design

**Date:** 2026-06-29
**Status:** Approved

## Summary

Add an optional `String? description` to `JetDataSchema` (the host-attached data
source root), shown as a muted second line under the dataset name in the
designer's **Data Source** view. An exact mirror of the existing
`FieldDef.description` feature — pure author-facing display sugar, never read by
binding, type, expression resolution, fill, or render.

## Motivation

Fields already carry an optional human-friendly `description` rendered two-line
under the technical name. The dataset root has no such affordance, so a host
cannot annotate *what the data source itself is*. This closes that gap with the
identical, already-validated pattern.

## Scope

**Display-only**, matching field descriptions: set via the schema object / file
codec, rendered under the dataset name. No in-panel edit affordance, no command,
no undo wiring.

## Changes

1. **`data/data_schema.dart`** — add `final String? description` (optional,
   default null) to `JetDataSchema`; thread through the constructor; update
   `==`, `hashCode`, and `toString`. The `fields` list and all inference paths
   are untouched.

2. **`data/serialization/data_source_file.dart`** — `_encodeSchema` emits
   `description` only when non-null (omit-when-null); `_decodeSchema` reads it as
   optional and throws `JetDataSourceFormatException` on a non-String value.
   **No `jetDataSource` version bump** — the addition is additive and optional,
   so legacy files round-trip byte-identical (same precedent as
   `FieldDef.description`, which also did not bump).

3. **`designer/layout/panels/data_source_panel.dart`** — the root `TreeBranch`
   built by `_datasetNode` gets `description: schema.description`. `TreeBranch`
   already renders the `LabelWithDescription` two-line layout, so no widget
   change is needed.

4. **Playground (`apps/jet_print_playground/lib/invoice_sample.dart`)** — seed
   `invoiceSchema` with a description so the feature is visible in the demo.
   (Field-description lesson: the second line renders only when set; an unseeded
   demo shows nothing.)

5. **Tests** — mirror the field-description suite:
   - `JetDataSchema` equality distinguishes by `description`.
   - Codec round-trip preserves a set description.
   - Omit-when-null: a null-description schema encodes with no `description` key
     and is byte-identical to the pre-feature output.
   - A non-String `description` in a decoded document throws
     `JetDataSourceFormatException`.

## Non-goals

- Editing the description in the designer UI.
- Any change to binding, fill, render, or report-template serialization.
- Touching schema inference (inferred schemas get a null description).

## Risk

Lowest-risk class: optional field on an immutable value type. The one recurring
trap (per the field-description lesson) is a field-by-field rebuild of
`JetDataSchema` somewhere that silently drops the new field — grep every
`JetDataSchema(` construction/copy site. There is no `copyWith`; construction
sites are the playground samples and the codec decoder, all covered above.
