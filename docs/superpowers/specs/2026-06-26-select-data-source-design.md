# Select Data Source — Design

> Status: DESIGN (approved to draft → plan). 2026-06-26.

## Problem

When the designer is opened with **no attached data source** (`dataSchema == null`),
the Data Source panel shows only a passive empty hint. An author has no in-designer way to
**attach** a data source and start binding. We want: when no data source is provided, the
Data Source panel offers a **"Select data source"** button; choosing a
`*.jetreport.datasource` file attaches its schema (and optional sample data), making the
empty designer usable. The playground's **Empty** demo adopts this flow.

## Decisions

| Topic | Decision |
|---|---|
| File extension | `*.jetreport.datasource` (sidecar to `*.jetreport`). |
| File contents | A versioned JSON document: the data **schema** (`JetDataSchema` = named dataset + `FieldDef` tree, nested collections to any depth) **plus optional sample rows**. |
| Where file I/O happens | In the **host** (playground), never in the library — same layered rule and `_guard` seam as Open/Save. The library exposes a notify callback only. |
| Schema ownership | Stays host-owned and immutable per attachment. The callback triggers the host's picker; the host decodes the file and updates its own `dataSchema`, which flows back through the existing `dataSchema` param. The library adds no mutable schema state. |
| Button gating | The "Select data source" button appears only when (a) no schema is attached **and** (b) `onSelectDataSchema` is wired — mirroring the Open/Save "shown only when wired" precedent. |
| Process | Spec → plan → TDD (Red→Green per task), per the repo constitution. |

## Architecture

Three units, dependencies pointing inward (data → designer → host):

### 1. `JetDataSourceFile` codec — new, public (`data` seam, pure Dart)

A versioned JSON codec for the `*.jetreport.datasource` document. Mirrors `JetReportFormat`'s
shape (a `final class` with static `encode`/`decode`, a `version` constant, and a typed
exception on malformed input).

- **Model:** decode yields a small value object carrying `JetDataSchema schema` and
  `List<Map<String, Object?>>? sample` (null when the file omits sample rows).
- **JSON shape:**
  ```json
  {
    "jetDataSource": 1,
    "schema": { "name": "Invoice", "fields": [ /* FieldDef tree */ ] },
    "sample": [ { "id": 1, "lines": [ /* ... */ ] } ]
  }
  ```
- **FieldDef (de)serialization:** encode/decode a `FieldDef` recursively — `name`, `type`
  (`JetFieldType`), and for `collection` its nested `fields`. (This FieldDef-tree codec does
  not exist yet; it is added here and is the reusable core.)
- **Round-trip lossless** over schema; sample rows pass through as plain JSON values.
- **Errors:** malformed JSON, wrong/absent `jetDataSource` version, or an unknown
  `JetFieldType` throw a typed `JetDataSourceFormatException` (parallel to
  `JetReportFormatException`), so hosts can show a clean message.
- **Public surface:** export `JetDataSourceFile` (codec) + its result type + exception from
  `jet_print.dart`. `FieldDef`, `JetDataSchema`, `JetFieldType` are already public.

> Pure, no Flutter import. Lives beside the other data-seam files
> (`lib/src/data/serialization/…` — new folder, or `lib/src/domain/serialization/` next to
> `report_format.dart`; chosen in the plan to match the existing codec home).

### 2. `onSelectDataSchema` host callback — new, on designer + workspace

- Add `final Future<void> Function()? onSelectDataSchema;` to **`JetReportDesigner`** and
  forward it from **`JetReportWorkspace`** (same forwarding pattern as `onOpenRequested`).
- Wrapped through the existing `_guard` so a throw / rejected Future is routed to `onError`,
  never escaping (library does no file I/O itself).
- Carried to the panel by **extending `DesignerSchemaScope`** with an
  `onSelectDataSource` field (it already sits exactly above the Data Source panel and the
  panel already reads it via `.of(context)`). `updateShouldNotify` compares both fields.
  A static `selectCallbackOf(context)` accessor returns the callback (null when unwired).

### 3. `DataSourcePanel` empty state — modified

- When `DesignerSchemaScope.of(context) == null`:
  - If a select-callback is wired → render a centered prompt with a **"Select data source"**
    button (icon `LucideIcons.database`/`filePlus`) that invokes the guarded callback; keep
    a short helper line.
  - If no callback is wired → keep the current `RegionEmptyHint` (unchanged behaviour, so
    existing hosts/goldens are untouched).
- New localized string `dataSourceSelect` (button label) added to
  `JetPrintLocalizations` (+ any locale ARBs present). Field names stay untranslated as today.

### 4. Playground — Empty demo

- Convert the Empty demo host to a `StatefulWidget` holding `JetDataSchema? _schema`
  (and optional `List<Map>? _sample`), passed to `JetReportWorkspace.dataSchema`.
- Wire `onSelectDataSchema` to a file picker:
  - **Desktop/IO:** `file_selector`/`XFile` open → read text.
  - **Web:** existing `XFile` read path (kIsWeb), consistent with current web file I/O.
  - Decode via `JetDataSourceFile.decode`; on success `setState` the schema (+ sample);
    on `JetDataSourceFormatException` surface through the workspace `onError`.
- Ship a sample `assets/invoice.jetreport.datasource` (schema + a few sample rows) so the
  flow is testable end-to-end by hand.

## Data flow

```
[empty designer] --(no schema)--> DataSourcePanel shows "Select data source"
   --tap--> onSelectDataSchema (guarded) --> host picker --> read file text
   --> JetDataSourceFile.decode --> {schema, sample?}
   --> host setState(schema) --> dataSchema param --> DesignerSchemaScope
   --> panel now renders the dataset tree; bindings resolve against it
```

## Error handling

- Decode failures throw `JetDataSourceFormatException`; the host catches and forwards to
  `onError` (designer surfaces it via the existing error sink). The picker being cancelled is
  a no-op (no schema change, no error).
- The guarded callback guarantees no host exception escapes the library.

## Testing (TDD)

- **Codec:** round-trip (schema-only and schema+sample), nested-collection fidelity, version
  rejection, unknown-field-type rejection, malformed-JSON rejection.
- **Callback forwarding:** `JetReportWorkspace` forwards `onSelectDataSchema` to
  `JetReportDesigner`; `_guard` routes a throwing callback to `onError`.
- **Scope:** `DesignerSchemaScope.selectCallbackOf` returns the wired callback / null;
  `updateShouldNotify` fires when the callback identity changes.
- **Panel widget tests:** no schema + wired callback → button present & tapping invokes it;
  no schema + no callback → unchanged empty hint; schema present → dataset tree (button
  absent). These are widget tests (no new goldens; gated to avoid canvas-golden drift).
- **Playground:** a widget/smoke test that decoding a sample file attaches the schema.

## Non-goals (this slice)

- Visual schema/sample editor (still backlog item F).
- Live data preview wiring from the sample rows (the sample is parsed and stored; consuming
  it in Preview is a follow-up — schema attachment is the deliverable here).
- Changing the report-definition format or any render/golden output.

## Constitution check

- **I. Library-first / clean API:** new codec is a pure public unit; callback mirrors existing
  host seams. PASS.
- **II. Layered architecture:** codec in `data` (pure); callback flows host→designer; no file
  I/O in the library. PASS.
- **III. Test-First:** every unit Red→Green. PASS.
- **IV. WYSIWYG / rendering fidelity:** author-time only; no render path; goldens unchanged.
  PASS.
- **V. Serialization:** new *additive* data-source file format, versioned with a typed
  exception; report format untouched. PASS.
- **VI. Docs/DX:** dartdoc on the codec + callback; clean analyzer/format gate. PASS.
