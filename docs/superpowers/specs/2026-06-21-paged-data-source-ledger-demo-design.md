# Paged Data Source + Sales-Ledger Big-List Demo — Design

**Date:** 2026-06-21
**Status:** Approved (design); pending implementation plan.

## Problem

The user wants a "big list" playground demo to exercise the engine's data-source
capabilities. A review of the data-source layer first asked: does the structure
need architectural improvement to support this well?

### Data-source review findings

- **The contract is already right.** `JetDataSource.open() → DataSet{ moveNext /
  current / close }` is the JasperReports `JRDataSource` cursor pattern —
  forward-only and **count-free at the contract level**. A custom `DataSet`
  *can* produce rows lazily.
- **Eagerness lives in the implementations, not the contract.** All three public
  sources (`JetInMemoryDataSource`, `JetJsonDataSource`, `JetObjectDataSource`)
  materialize the full `List` up front, and the only cursor helper,
  `RowCursorDataSet`, is **index-based** (`rowCount` + `rowAt(i)`) — it requires
  the total row count up front and never surfaces lazy/generative iteration to a
  public source.
- **The engine already scales.** Per the E2 resilience/stress work the fill+render
  engine scales linearly to 1M rows with no cliff; E2b streaming was *deliberately
  deferred* because nested collections buffer anyway and the final
  `RenderedReport` is held fully in memory regardless of how input arrives.

### Conclusion of the review

No structural change to the contract is needed. The one genuine, low-cost
capability gap worth closing — and the one that makes a "big list / data-source
capabilities" demo meaningful — is a **public, lazily-paged source that does not
require the total row count up front and never holds the whole dataset in
memory.** This is the chosen scope.

## Decision

Add a **synchronous, lazily-paged** data source: `JetPagedDataSource`. Rows are
pulled one page at a time and discarded after each page; the total is unknown
until a short/empty final page ends the feed.

**Async/remote paging is explicitly deferred** (see Non-Goals). The synchronous
`fetchPage(pageIndex, pageSize)` signature maps 1:1 onto a future async sibling,
so nothing is thrown away when a real remote backend (e.g. Supabase
`.range(from, to)`) needs streaming.

### Why synchronous now, not async

- The fill pass is fully synchronous and single-pass: `DataSet.moveNext()`
  returns `bool` (not `Future`), the filler loops `while (ds.moveNext())`, and
  `renderDefinition` returns a `RenderedReport` synchronously. A source that
  fetches *during* iteration can therefore only do so synchronously.
- Going async is **breaking** (`render → Future`, `moveNext → Future<bool>`, the
  whole filler async) and was already weighed and deferred in E2.
- No remote consumer exists in jet-print today → building async fill
  speculatively is YAGNI.
- The payoff of async is capped today: the engine holds the entire
  `RenderedReport` in memory post-fill, so streaming the *input* only pays off
  against a remote bottleneck that does not yet exist.

## Architecture

### `JetPagedDataSource` (new public source)

Fourth sibling to in-memory / JSON / object. Lazily paged, unknown total,
synchronous fetch.

```dart
class JetPagedDataSource implements JetDataSource {
  JetPagedDataSource({
    required List<FieldDef> fields,   // explicit — see "schema required"
    required int pageSize,            // rows per page (demo default: 250)
    required List<Map<String, Object?>> Function(int pageIndex) fetchPage,
  });

  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      PagedCursorDataSet(fields: ..., pageSize: ..., fetchPage: ...);
}
```

- **Schema required (explicit `fields`).** A paged source cannot infer a schema
  from data it never fully loads. Unlike `JetInMemoryDataSource`, `fields` is
  required, not optional. (A first-page-inference convenience is intentionally
  out of scope — it risks mistyping all-null-on-page-0 columns and muddies the
  honest "you declare the schema" contract.)
- **`open()` ignores `params`** (consistent with the other built-in sources).
- Exported from `lib/jet_print.dart`.

### `PagedCursorDataSet` (new internal cursor)

A second `DataSet` implementation alongside `RowCursorDataSet`. Justification for
a new cursor rather than reusing `RowCursorDataSet`: the latter requires
`rowCount` up front (`rowAt(i)`) — precisely the assumption a paged feed of
unknown total breaks.

Behaviour:

- Lazily fetches page 0 on first `moveNext()`, serves its rows in order, fetches
  the next page when the current one is exhausted.
- **End of feed = a fetched page returns fewer than `pageSize` rows** (short or
  empty final page). When the total is an exact multiple of `pageSize`, the last
  full page is followed by an empty page → that empty page ends iteration.
- Holds **one page at a time**; total never known up front.
- `current` before a successful `moveNext()` throws `StateError` (mirrors
  `RowCursorDataSet`). `close()` stops the feed and releases the current page.
- Re-`open()` on the source yields a **fresh, independent** cursor positioned
  before the first row.

### Shared projection

The raw-map → `DataRow`-over-`fields` projection (each declared field reads its
value from the raw row; missing key → `null`; unknown keys dropped) is currently
private to `RowCursorDataSet`. `RowCursorDataSet`'s own doc claims the
forward-only/projection semantics "live in exactly one place." To preserve that,
extract the projection into a small shared helper that both cursors call, rather
than duplicating it.

### No engine change

`renderDefinition`, the `ReportFiller`, and the calculator are untouched.
Aggregation (`COUNT`, `SUM`) folds across the paged feed because the calculator
advances per row regardless of how the row arrived. **No golden changes.**

## The demo — sales-transaction ledger

New playground tab (label: "Defter" / ledger), following the existing demo
pattern (`*SampleDefinition()` + `*Schema` + `rendered_*_example.dart`, wired into
the `IndexedStack` / `ShadTabs` shell in `main.dart`).

### Files

- **`apps/jet_print_playground/lib/rendered_ledger_example.dart`** —
  - `ledgerDataSource()` returns a `JetPagedDataSource` whose `fetchPage(i)`
    **deterministically generates** ~20,000 transactions in 250-row pages
    (timestamp / receiptNo / item / qty / unitPrice / amount / status all derived
    from the row index — deterministic, no `Random` / `DateTime.now`, so the
    render is testable).
  - `ledgerSchema` (explicit `FieldDef`s for the transaction columns).
  - `renderLedgerDefinition({...})` mirroring the other `rendered_*_example.dart`
    render helpers (passes `knownFields` from the schema for schema-aware render).
- **`apps/jet_print_playground/lib/ledger_sample.dart`** —
  `ledgerSampleDefinition()`: a page-header band (column titles, repeats per
  page), a repeating **detail band** (one transaction row), a **page footer**
  ("Page X"), and a **summary band** with grand totals `{COUNT(...)}` +
  `{SUM([amount])}`.
- **`apps/jet_print_playground/lib/main.dart`** — import + one tab entry + a label
  in the labels list.

### What it proves

A paged source that **never holds all 20k rows** drives the full pipeline: many
pages, repeating bands, page breaks, page header/footer, and grand-total
aggregation across the whole feed.

## Testing

- **Lib unit tests** (`test/data/paged_data_source_test.dart`):
  - cursor walks all pages in order;
  - **unknown-total end on a short final page**;
  - exact-multiple total ends on the empty trailing page;
  - `current` before `moveNext()` throws;
  - `close()` mid-feed stops iteration;
  - projection drops unknown keys and nulls missing keys;
  - re-`open()` yields a fresh independent cursor.
- **Parity test (SC-006 style):** a `JetPagedDataSource` and a
  `JetInMemoryDataSource` over the **same small logical fixture** render
  **byte-identical** output — proves paging changes only *how* rows arrive, not
  the result.
- **Playground test:** the ledger renders the expected **page count** and the
  summary band shows the correct **COUNT + SUM** — asserted as values. (Rendered
  page count is layout-driven — rows-per-printed-page, not `pageSize` — so assert
  it as a `> 1` sanity bound or an exact value computed from the layout, not as
  "20000 / pageSize".) **No pixel golden** for the large multi-page render (too
  large/slow); existing goldens stay unchanged.

## Non-goals (deferred, documented)

- **Async / remote paging** — `JetAsyncPagedDataSource` + a `renderDefinitionAsync`
  entry point. The seam is named here so it drops in later; `fetchPage(pageIndex,
  pageSize)` maps 1:1 onto Supabase `.range(from, to)` and similar offset/limit
  APIs. Requires making the fill pipeline async; out of scope now.
- **JSON / object paged variants** — only the map-based paged source ships.
- **First-page schema inference** — paged sources require an explicit schema.
- **Reducing peak memory for huge renders** — out of reach regardless, because the
  `RenderedReport` is held fully in memory after fill; paging only bounds *input*
  memory.

## Success criteria

- **SC-001** `JetPagedDataSource` iterates an unknown-total feed to completion via
  the synchronous `DataSet` contract, holding one page at a time.
- **SC-002** Iteration ends correctly on a short final page **and** on an empty
  trailing page (exact-multiple total).
- **SC-003** Paged vs. in-memory parity: byte-identical render for the same
  logical fixture.
- **SC-004** The ledger demo renders multiple pages with correct grand totals
  (COUNT + SUM) over a ~20k-row paged feed.
- **SC-005** No change to `renderDefinition`, the filler, or any existing golden;
  full lib + playground suites stay green.
- **SC-006** `JetPagedDataSource` is exported and documented (dartdoc), analyzer
  and `dart format` clean.
