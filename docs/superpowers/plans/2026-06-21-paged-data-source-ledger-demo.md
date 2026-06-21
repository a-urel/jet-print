# Paged Data Source + Sales-Ledger Big-List Demo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is Red→Green TDD.

**Goal:** Add a public, synchronous, lazily-paged data source (`JetPagedDataSource`) that iterates an unknown-total feed one page at a time, and a ~20k-row sales-ledger playground demo that drives the full render pipeline from it.

**Architecture:** A new internal cursor (`PagedCursorDataSet`) pulls pages via a `fetchPage(pageIndex)` callback and stops on a short/empty page — it does NOT need the total row count up front (unlike the existing index-based `RowCursorDataSet`). `JetPagedDataSource` is the public factory over it. Both cursors share one row-projection helper. No engine, filler, or golden change; aggregation (`COUNT`/`SUM`) folds across the paged feed because the calculator advances per row regardless of source.

**Tech Stack:** Dart / Flutter, `flutter_test`. Library = `packages/jet_print` (pure data seam). Demo = `apps/jet_print_playground`. Expression syntax: `$F{field}` field refs, `$V{PAGE_NUMBER}`/`$V{PAGE_COUNT}` chrome vars, `SUM($F{amount})` / `COUNT($F{receiptNo})` aggregates in a `BandType.summary` band.

## Global Constraints

- **No engine/filler/golden change.** `renderDefinition`, `ReportFiller`, and every existing golden stay untouched. If a golden changes, STOP and inspect.
- **Explicit schema required** on `JetPagedDataSource` — no inference (the source never fully loads its data). `fields` is a required parameter.
- **Synchronous only.** No `Future`/`async`/`Stream` in the data layer. Async/remote paging is out of scope (documented non-goal).
- **End-of-feed = a fetched page with fewer than `pageSize` rows** (short or empty). `pageSize < 1` throws `ArgumentError`.
- **Determinism:** the demo data generator uses NO `DateTime.now()` / `Random` — all values derive from the row index, and all monetary values are multiples of 0.25 (dyadic, exact in IEEE-754) so `SUM` matches a test-side fold exactly.
- **DX gate per task that touches Dart:** `dart format` clean, `flutter analyze` clean, dartdoc on every new public symbol.
- **Run `flutter`/`dart` from the package dir** (`packages/jet_print` or `apps/jet_print_playground`). **Run `git` from repo root** `/Users/ahmeturel/Projects/oss/jet-print` (flutter leaves cwd inside the package).
- **Branch is already `040-paged-data-source`.**

## File Map

- `packages/jet_print/lib/src/data/row_projection.dart` — **new**: shared `projectRowOntoFields(fields, raw) → DataRow` (extracted from `RowCursorDataSet._project`).
- `packages/jet_print/lib/src/data/row_cursor_data_set.dart` — **modify**: use the shared helper; drop the private `_project`.
- `packages/jet_print/lib/src/data/paged_cursor_data_set.dart` — **new**: `PagedCursorDataSet` (internal, unknown-total cursor).
- `packages/jet_print/lib/src/data/paged_data_source.dart` — **new**: `JetPagedDataSource` (public factory).
- `packages/jet_print/lib/jet_print.dart` — **modify**: export `JetPagedDataSource`.
- `apps/jet_print_playground/lib/ledger_sample.dart` — **new**: `ledgerSchema` + `ledgerSampleDefinition()`.
- `apps/jet_print_playground/lib/rendered_ledger_example.dart` — **new**: deterministic generators, `ledgerDataSource()`, `renderLedgerDefinition()`.
- `apps/jet_print_playground/lib/main.dart` — **modify**: register the ledger demo tab.
- `apps/jet_print_playground/lib/l10n/app_en.arb`, `app_de.arb`, `app_tr.arb` — **modify**: `tabLedger` label.
- Tests: `test/data/row_projection_test.dart`, `test/data/paged_cursor_data_set_test.dart`, `test/data/paged_data_source_test.dart` (lib); `test/ledger_definition_test.dart`, `test/rendered_ledger_example_test.dart` (playground).

---

## Task 1: Extract the shared row-projection helper

Behaviour-neutral refactor so both cursors project rows identically (preserves the "forward-only semantics live in one place" invariant). Covered by the existing `cursor_contract_test.dart`; add one focused unit test for the new helper.

**Files:**
- Create: `packages/jet_print/lib/src/data/row_projection.dart`
- Modify: `packages/jet_print/lib/src/data/row_cursor_data_set.dart`
- Test (create): `packages/jet_print/test/data/row_projection_test.dart`

**Interfaces:**
- Produces: `DataRow projectRowOntoFields(List<FieldDef> fields, Map<String, Object?> raw)` — projects `raw` onto `fields` (each declared field reads its value; missing key → `null`; undeclared keys dropped).

- [ ] **Step 1: Write the failing test** — `packages/jet_print/test/data/row_projection_test.dart`:

```dart
// projectRowOntoFields projects a raw map onto a declared schema (spec 040).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/row_projection.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('a', type: JetFieldType.integer),
  FieldDef('b', type: JetFieldType.string),
];

void main() {
  group('projectRowOntoFields', () {
    test('reads each declared field; missing key → null; extra key dropped', () {
      final row = projectRowOntoFields(_schema, <String, Object?>{
        'a': 1,
        'extra': 'dropped',
      });
      expect(row.fields, _schema);
      expect(row.field('a'), 1);
      expect(row.field('b'), isNull);
      expect(row.hasField('extra'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run → FAIL** (helper not defined).

Run: `cd packages/jet_print && flutter test test/data/row_projection_test.dart`
Expected: FAIL — `Undefined name 'projectRowOntoFields'` / `row_projection.dart` not found.

- [ ] **Step 3: Create the helper** — `packages/jet_print/lib/src/data/row_projection.dart`:

```dart
/// Internal: the shared raw-row → [DataRow] projection used by both built-in
/// cursors (spec 040).
library;

import 'data_row.dart';
import 'field_def.dart';

/// Projects [raw] onto [fields]: every declared field reads its value from
/// [raw] (a missing key yields `null`); keys not in [fields] are dropped. The
/// single source of the built-in cursors' projection rule, so index-driven
/// ([RowCursorDataSet]) and paged ([PagedCursorDataSet]) sources project
/// identically.
DataRow projectRowOntoFields(
  List<FieldDef> fields,
  Map<String, Object?> raw,
) =>
    DataRow(
      fields: fields,
      values: <String, Object?>{
        for (final FieldDef f in fields) f.name: raw[f.name],
      },
    );
```

- [ ] **Step 4: Point `RowCursorDataSet` at the helper** — in `packages/jet_print/lib/src/data/row_cursor_data_set.dart`:
  - Add import near the other imports: `import 'row_projection.dart';`
  - Replace the `moveNext` projection call `_current = _project(_rowAt(_index));` with `_current = projectRowOntoFields(_fields, _rowAt(_index));`
  - Delete the private `_project` method (lines 70-75):

```dart
  DataRow _project(Map<String, Object?> raw) => DataRow(
        fields: _fields,
        values: <String, Object?>{
          for (final FieldDef f in _fields) f.name: raw[f.name],
        },
      );
```

- [ ] **Step 5: Run → PASS** (new helper test + the existing cursor contract test, unchanged):

Run: `cd packages/jet_print && flutter test test/data/row_projection_test.dart test/data/cursor_contract_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Analyzer + format, then commit.**

```bash
cd packages/jet_print && dart format lib/src/data/row_projection.dart lib/src/data/row_cursor_data_set.dart test/data/row_projection_test.dart && flutter analyze lib/src/data
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/data/row_projection.dart packages/jet_print/lib/src/data/row_cursor_data_set.dart packages/jet_print/test/data/row_projection_test.dart
git commit -m "refactor(data): extract shared projectRowOntoFields for cursors (040)"
```

---

## Task 2: `PagedCursorDataSet` — the unknown-total cursor

**Files:**
- Create: `packages/jet_print/lib/src/data/paged_cursor_data_set.dart`
- Test (create): `packages/jet_print/test/data/paged_cursor_data_set_test.dart`

**Interfaces:**
- Consumes: `projectRowOntoFields` (Task 1); `DataSet`/`DataRow`/`FieldDef`.
- Produces: `class PagedCursorDataSet implements DataSet` with constructor
  `PagedCursorDataSet({required List<FieldDef> fields, required int pageSize, required List<Map<String, Object?>> Function(int pageIndex) fetchPage})`.

- [ ] **Step 1: Write the failing test** — `packages/jet_print/test/data/paged_cursor_data_set_test.dart`:

```dart
// PagedCursorDataSet: forward cursor over an unknown-total paged feed (spec 040).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/paged_cursor_data_set.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('n', type: JetFieldType.integer),
];

/// A paged feed of [total] rows ({'n': i}) served [pageSize] at a time. Counts
/// how many times the source asked for a page, to prove laziness.
({DataSet ds, List<int> fetched}) _feed(int total, int pageSize) {
  final List<int> fetched = <int>[];
  final DataSet ds = PagedCursorDataSet(
    fields: _schema,
    pageSize: pageSize,
    fetchPage: (int pageIndex) {
      fetched.add(pageIndex);
      final int start = pageIndex * pageSize;
      if (start >= total) return const <Map<String, Object?>>[];
      final int end = (start + pageSize) > total ? total : start + pageSize;
      return <Map<String, Object?>>[
        for (int i = start; i < end; i++) <String, Object?>{'n': i},
      ];
    },
  );
  return (ds: ds, fetched: fetched);
}

List<int> _drain(DataSet ds) {
  final List<int> out = <int>[];
  while (ds.moveNext()) {
    out.add(ds.current.field('n')! as int);
  }
  return out;
}

void main() {
  group('PagedCursorDataSet', () {
    test('is a DataSet exposing the declared fields', () {
      final feed = _feed(0, 3);
      expect(feed.ds, isA<DataSet>());
      expect(feed.ds.fields, _schema);
    });

    test('walks every row across pages in order (short final page)', () {
      final feed = _feed(7, 3); // pages: [0,1,2][3,4,5][6] → short last page
      expect(_drain(feed.ds), <int>[0, 1, 2, 3, 4, 5, 6]);
      // Stopped at the short page; never fetched a page beyond it.
      expect(feed.fetched, <int>[0, 1, 2]);
    });

    test('exact-multiple total ends on the empty trailing page', () {
      final feed = _feed(6, 3); // pages: [0,1,2][3,4,5][] → empty page ends it
      expect(_drain(feed.ds), <int>[0, 1, 2, 3, 4, 5]);
      expect(feed.fetched, <int>[0, 1, 2]); // page 2 came back empty
    });

    test('an immediately-empty feed yields no rows', () {
      final feed = _feed(0, 3);
      expect(feed.ds.moveNext(), isFalse);
      expect(feed.fetched, <int>[0]);
    });

    test('is lazy — fetches only the first page before the first moveNext', () {
      final feed = _feed(100, 10);
      expect(feed.fetched, isEmpty); // construction fetches nothing
      expect(feed.ds.moveNext(), isTrue);
      expect(feed.fetched, <int>[0]); // exactly one page pulled so far
    });

    test('projects each raw row onto the schema', () {
      final DataSet ds = PagedCursorDataSet(
        fields: _schema,
        pageSize: 2,
        fetchPage: (int p) => p == 0
            ? <Map<String, Object?>>[
                <String, Object?>{'n': 1, 'extra': 'x'}, // extra key dropped
                <String, Object?>{}, // missing key → null
              ]
            : const <Map<String, Object?>>[],
      );
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('n'), 1);
      expect(ds.current.hasField('extra'), isFalse);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('n'), isNull);
    });

    test('current throws StateError before the first moveNext', () {
      expect(() => _feed(3, 3).ds.current, throwsStateError);
    });

    test('current throws StateError after exhaustion', () {
      final DataSet ds = _feed(1, 3).ds;
      expect(ds.moveNext(), isTrue);
      expect(ds.moveNext(), isFalse);
      expect(() => ds.current, throwsStateError);
    });

    test('moveNext returns false after close; current then throws', () {
      final DataSet ds = _feed(5, 2).ds;
      expect(ds.moveNext(), isTrue);
      ds.close();
      expect(ds.moveNext(), isFalse);
      expect(() => ds.current, throwsStateError);
    });

    test('close() is idempotent', () {
      final DataSet ds = _feed(5, 2).ds;
      ds.close();
      expect(ds.close, returnsNormally);
    });

    test('pageSize < 1 throws ArgumentError', () {
      expect(
        () => PagedCursorDataSet(
          fields: _schema,
          pageSize: 0,
          fetchPage: (int p) => const <Map<String, Object?>>[],
        ),
        throwsArgumentError,
      );
    });
  });
}
```

- [ ] **Step 2: Run → FAIL.**

Run: `cd packages/jet_print && flutter test test/data/paged_cursor_data_set_test.dart`
Expected: FAIL — `paged_cursor_data_set.dart` not found.

- [ ] **Step 3: Implement** — `packages/jet_print/lib/src/data/paged_cursor_data_set.dart`:

```dart
/// Internal: the cursor backing [JetPagedDataSource] — a forward-only walk over
/// a lazily-paged feed of unknown total length (spec 040).
library;

import 'data_row.dart';
import 'data_set.dart';
import 'field_def.dart';
import 'row_projection.dart';

/// A [DataSet] that pulls rows one page at a time via [fetchPage] and discards
/// each page once iterated, so the full dataset is never held in memory.
///
/// The total is **unknown up front**: iteration ends when a fetched page returns
/// fewer than [pageSize] rows (a short or empty final page). When the total is an
/// exact multiple of [pageSize], the last full page is followed by one empty
/// fetch that ends the feed. [fetchPage] must return at most [pageSize] rows; a
/// full page (`== pageSize`) signals "there may be more", fewer signals "this is
/// the last page". Fetching is synchronous.
///
/// Internal to the data seam — not part of the public API. Row projection is
/// shared with [RowCursorDataSet] via [projectRowOntoFields].
class PagedCursorDataSet implements DataSet {
  /// Creates a cursor over the [fetchPage] feed, projecting onto [fields].
  PagedCursorDataSet({
    required List<FieldDef> fields,
    required int pageSize,
    required List<Map<String, Object?>> Function(int pageIndex) fetchPage,
  })  : _fields = List<FieldDef>.unmodifiable(fields),
        _pageSize = pageSize,
        _fetchPage = fetchPage {
    if (pageSize < 1) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be >= 1');
    }
  }

  final List<FieldDef> _fields;
  final int _pageSize;
  final List<Map<String, Object?>> Function(int pageIndex) _fetchPage;

  int _pageIndex = -1; // index of the most recently fetched page
  List<Map<String, Object?>> _page = const <Map<String, Object?>>[];
  int _posInPage = -1; // cursor within _page
  bool _exhausted = false; // a short/empty page was seen → no more pages exist
  bool _closed = false;
  DataRow? _current;

  @override
  List<FieldDef> get fields => _fields;

  @override
  bool moveNext() {
    if (_closed) {
      _current = null;
      return false;
    }
    while (true) {
      // Serve the next row of the current page, if any.
      if (_posInPage + 1 < _page.length) {
        _posInPage++;
        _current = projectRowOntoFields(_fields, _page[_posInPage]);
        return true;
      }
      // Current page is drained — fetch the next, unless the feed has ended.
      if (_exhausted) {
        _current = null;
        return false;
      }
      _pageIndex++;
      final List<Map<String, Object?>> next = _fetchPage(_pageIndex);
      _page = next;
      _posInPage = -1;
      if (next.length < _pageSize) {
        _exhausted = true; // short or empty page → this is the last fetch
      }
      if (next.isEmpty) {
        _current = null;
        return false; // empty page → no row to serve, end of feed
      }
      // Loop to serve the first row of the freshly fetched page.
    }
  }

  @override
  DataRow get current {
    final DataRow? row = _current;
    if (row == null) {
      throw StateError(
        'No current row: call moveNext() and check it returned true first.',
      );
    }
    return row;
  }

  @override
  void close() {
    _closed = true;
    _current = null;
  }
}
```

- [ ] **Step 4: Run → PASS.**

Run: `cd packages/jet_print && flutter test test/data/paged_cursor_data_set_test.dart`
Expected: PASS (all 11 tests).

- [ ] **Step 5: Analyzer + format, then commit.**

```bash
cd packages/jet_print && dart format lib/src/data/paged_cursor_data_set.dart test/data/paged_cursor_data_set_test.dart && flutter analyze lib/src/data
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/data/paged_cursor_data_set.dart packages/jet_print/test/data/paged_cursor_data_set_test.dart
git commit -m "feat(data): PagedCursorDataSet — unknown-total lazily-paged cursor (040)"
```

---

## Task 3: `JetPagedDataSource` (public factory) + export

**Files:**
- Create: `packages/jet_print/lib/src/data/paged_data_source.dart`
- Modify: `packages/jet_print/lib/jet_print.dart`
- Test (create): `packages/jet_print/test/data/paged_data_source_test.dart`

**Interfaces:**
- Consumes: `PagedCursorDataSet` (Task 2); `JetDataSource`/`DataSet`/`FieldDef`.
- Produces: `class JetPagedDataSource implements JetDataSource` with constructor
  `JetPagedDataSource({required List<FieldDef> fields, required int pageSize, required List<Map<String, Object?>> Function(int pageIndex) fetchPage})` and a `List<FieldDef> get fields`.

- [ ] **Step 1: Write the failing test** — `packages/jet_print/test/data/paged_data_source_test.dart`:

```dart
// JetPagedDataSource: public lazily-paged source (spec 040). No Flutter UI import.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart' show JetDataSource, JetPagedDataSource;
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('n', type: JetFieldType.integer),
];

JetPagedDataSource _source(int total, {int pageSize = 3}) => JetPagedDataSource(
      fields: _schema,
      pageSize: pageSize,
      fetchPage: (int pageIndex) {
        final int start = pageIndex * pageSize;
        if (start >= total) return const <Map<String, Object?>>[];
        final int end = (start + pageSize) > total ? total : start + pageSize;
        return <Map<String, Object?>>[
          for (int i = start; i < end; i++) <String, Object?>{'n': i},
        ];
      },
    );

void main() {
  group('JetPagedDataSource', () {
    test('is a JetDataSource exposing its explicit schema', () {
      final JetPagedDataSource s = _source(0);
      expect(s, isA<JetDataSource>());
      expect(s.fields, _schema);
    });

    test('walks an unknown-total feed to completion', () {
      final DataSet ds = _source(7).open();
      final List<int> out = <int>[];
      while (ds.moveNext()) {
        out.add(ds.current.field('n')! as int);
      }
      expect(out, <int>[0, 1, 2, 3, 4, 5, 6]);
    });

    test('open() yields fresh independent cursors', () {
      final JetDataSource s = _source(5);
      final DataSet a = s.open();
      final DataSet b = s.open();
      expect(a.moveNext(), isTrue);
      expect(a.current.field('n'), 0);
      expect(b.moveNext(), isTrue);
      expect(b.current.field('n'), 0); // b independent, still at the start
    });

    test('open() accepts but ignores params', () {
      final DataSet ds = _source(2).open(<String, Object?>{'unused': 1});
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('n'), 0);
      expect(ds.moveNext(), isTrue);
      expect(ds.moveNext(), isFalse);
    });

    test('pageSize < 1 throws ArgumentError', () {
      expect(
        () => JetPagedDataSource(
          fields: _schema,
          pageSize: 0,
          fetchPage: (int p) => const <Map<String, Object?>>[],
        ),
        throwsArgumentError,
      );
    });
  });
}
```

- [ ] **Step 2: Run → FAIL.**

Run: `cd packages/jet_print && flutter test test/data/paged_data_source_test.dart`
Expected: FAIL — `JetPagedDataSource` is not exported / not defined.

- [ ] **Step 3: Implement** — `packages/jet_print/lib/src/data/paged_data_source.dart`:

```dart
/// Lazily-paged data source: pulls rows one page at a time (spec 040).
library;

import 'data_set.dart';
import 'field_def.dart';
import 'jet_data_source.dart';
import 'paged_cursor_data_set.dart';

/// A [JetDataSource] that fetches rows one page at a time via [fetchPage] and
/// never holds the whole dataset in memory — the fourth public source alongside
/// `JetInMemoryDataSource`, `JetJsonDataSource`, and `JetObjectDataSource`.
///
/// Use it when the dataset is generated on demand or arrives in batches and you
/// do not want to (or cannot) materialize it as one `List`:
///
/// ```dart
/// JetPagedDataSource(
///   fields: schema.fields,            // explicit — see below
///   pageSize: 250,
///   fetchPage: (int pageIndex) {
///     final int start = pageIndex * 250;
///     if (start >= total) return const <Map<String, Object?>>[];
///     return rowsFor(start, 250);     // up to 250 rows, fewer on the last page
///   },
/// )
/// ```
///
/// **Unknown total.** Iteration ends when [fetchPage] returns fewer than
/// [pageSize] rows (a short or empty final page); the cursor never asks for the
/// total up front. [fetchPage] must return at most [pageSize] rows per call.
///
/// **Explicit schema required.** Unlike the in-memory sources, [fields] cannot be
/// inferred — the source never sees the whole dataset — so you must declare it.
///
/// **Synchronous.** [fetchPage] returns rows directly, matching the engine's
/// synchronous fill pass. For a remote/async backend, pre-fetch each page into
/// memory before returning it. [open] ignores its `params`.
class JetPagedDataSource implements JetDataSource {
  /// Creates a paged source over [fetchPage], described by [fields], with
  /// [pageSize] rows per page. Throws [ArgumentError] if [pageSize] < 1.
  JetPagedDataSource({
    required List<FieldDef> fields,
    required int pageSize,
    required List<Map<String, Object?>> Function(int pageIndex) fetchPage,
  })  : _fields = List<FieldDef>.unmodifiable(fields),
        _pageSize = pageSize,
        _fetchPage = fetchPage {
    if (pageSize < 1) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be >= 1');
    }
  }

  final List<FieldDef> _fields;
  final int _pageSize;
  final List<Map<String, Object?>> Function(int pageIndex) _fetchPage;

  /// The explicit schema, in column order.
  List<FieldDef> get fields => _fields;

  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      PagedCursorDataSet(
        fields: _fields,
        pageSize: _pageSize,
        fetchPage: _fetchPage,
      );
}
```

- [ ] **Step 4: Export it** — in `packages/jet_print/lib/jet_print.dart`, add this line beside the other data-source exports (after the `json_data_source.dart` export):

```dart
export 'src/data/paged_data_source.dart' show JetPagedDataSource;
```

- [ ] **Step 5: Run → PASS.**

Run: `cd packages/jet_print && flutter test test/data/paged_data_source_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 6: Analyzer + format, then commit.**

```bash
cd packages/jet_print && dart format lib/src/data/paged_data_source.dart lib/jet_print.dart test/data/paged_data_source_test.dart && flutter analyze lib
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/data/paged_data_source.dart packages/jet_print/lib/jet_print.dart packages/jet_print/test/data/paged_data_source_test.dart
git commit -m "feat(data): public JetPagedDataSource over the paged cursor (040)"
```

---

## Task 4: Ledger report definition + schema (playground)

**Files:**
- Create: `apps/jet_print_playground/lib/ledger_sample.dart`
- Test (create): `apps/jet_print_playground/test/ledger_definition_test.dart`

**Interfaces:**
- Produces: `const JetDataSchema ledgerSchema` (7 fields: `time` string, `receiptNo` string, `item` string, `qty` integer, `unitPrice` double, `amount` double, `status` string) and `ReportDefinition ledgerSampleDefinition()`. The detail band id is `txn`; the summary band carries `txnCount` (`COUNT($F{receiptNo})`) and `grandSum` (`SUM($F{amount})`).

- [ ] **Step 1: Write the failing test** — `apps/jet_print_playground/test/ledger_definition_test.dart`:

```dart
// The ledger sample definition + schema (spec 040). Authored through the public
// API only; this pins the schema and the summary aggregates.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/ledger_sample.dart';

void main() {
  group('ledger sample', () {
    test('schema declares the seven transaction fields, typed', () {
      expect(ledgerSchema.fields, const <FieldDef>[
        FieldDef('time', type: JetFieldType.string),
        FieldDef('receiptNo', type: JetFieldType.string),
        FieldDef('item', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('unitPrice', type: JetFieldType.double),
        FieldDef('amount', type: JetFieldType.double),
        FieldDef('status', type: JetFieldType.string),
      ]);
    });

    test('has a single detail band and a summary with the grand totals', () {
      final ReportDefinition def = ledgerSampleDefinition();
      // Exactly one per-row (detail) band under the root scope.
      final List<ScopeNode> children = def.body.root.children;
      expect(children.whereType<BandNode>().length, 1);
      final BandNode detail = children.whereType<BandNode>().single;
      expect(detail.band.type, BandType.detail);
      expect(detail.band.id, 'txn');

      // The summary band exists with the two aggregate elements.
      final Band? summary = def.body.summary;
      expect(summary, isNotNull);
      expect(summary!.type, BandType.summary);
      final Map<String, String?> exprById = <String, String?>{
        for (final ReportElement e in summary.elements)
          if (e is TextElement) e.id: e.expression,
      };
      expect(exprById['txnCount'], r'COUNT($F{receiptNo})');
      expect(exprById['grandSum'], r'SUM($F{amount})');
    });
  });
}
```

NOTE before implementing: the `whereType<BandNode>()`/`ScopeNode`/`BandNode` and `TextElement.expression` access mirror existing playground `*_definition_test.dart` files. If `ScopeNode`/`BandNode` are not exported from the barrel, copy the import style used by `apps/jet_print_playground/test/nested_list_definition_test.dart` (it asserts over the same scope tree). Adjust the import line to match before running.

- [ ] **Step 2: Run → FAIL.**

Run: `cd apps/jet_print_playground && flutter test test/ledger_definition_test.dart`
Expected: FAIL — `ledger_sample.dart` not found.

- [ ] **Step 3: Implement** — `apps/jet_print_playground/lib/ledger_sample.dart`:

```dart
/// The playground's sales-ledger sample — a flat, multi-page transaction list
/// authored entirely through the library's public API
/// (`package:jet_print/jet_print.dart`). It is the demo for [JetPagedDataSource]
/// (spec 040): the data is generated on demand, one page at a time, never held
/// whole in memory (see `rendered_ledger_example.dart`).
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

/// A flat transaction row. `time` is a pre-formatted timestamp string.
const JetDataSchema ledgerSchema = JetDataSchema(
  name: 'Transaction',
  fields: <FieldDef>[
    FieldDef('time', type: JetFieldType.string),
    FieldDef('receiptNo', type: JetFieldType.string),
    FieldDef('item', type: JetFieldType.string),
    FieldDef('qty', type: JetFieldType.integer),
    FieldDef('unitPrice', type: JetFieldType.double),
    FieldDef('amount', type: JetFieldType.double),
    FieldDef('status', type: JetFieldType.string),
  ],
);

/// Muted grey for secondary text.
const JetColor _grey = JetColor(0xFF888888);

/// A thin rule under the header and above the grand total.
const JetColor _rule = JetColor(0xFFB0B0B0);

/// Content width of an A4 portrait page's body band (matches the other samples).
const double _w = 538;

/// Two-decimal money mask.
const String _money = '#,##0.00';

/// Thousands-grouped integer mask.
const String _int = '#,##0';

/// The sales-ledger report authored in the reified band model (spec 024/040).
ReportDefinition ledgerSampleDefinition() => ReportDefinition(
      name: 'Sales Ledger',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 40,
          elements: const <ReportElement>[
            TextElement(
              id: 'title',
              bounds: JetRect(x: 0, y: 0, width: _w, height: 18),
              text: 'Sales Ledger',
              style: JetTextStyle(fontSize: 14, weight: JetFontWeight.bold),
            ),
            // Column headings — repeat on every page via the page header.
            TextElement(
              id: 'hTime',
              bounds: JetRect(x: 0, y: 24, width: 92, height: 12),
              text: 'Time',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hReceipt',
              bounds: JetRect(x: 96, y: 24, width: 66, height: 12),
              text: 'Receipt',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hItem',
              bounds: JetRect(x: 166, y: 24, width: 190, height: 12),
              text: 'Item',
              style: JetTextStyle(fontSize: 8, color: _grey),
            ),
            TextElement(
              id: 'hQty',
              bounds: JetRect(x: 360, y: 24, width: 34, height: 12),
              text: 'Qty',
              style: JetTextStyle(fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'hAmount',
              bounds: JetRect(x: 398, y: 24, width: 74, height: 12),
              text: 'Amount',
              style: JetTextStyle(fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            TextElement(
              id: 'hStatus',
              bounds: JetRect(x: 476, y: 24, width: 62, height: 12),
              text: 'Status',
              style: JetTextStyle(fontSize: 8, color: _grey, align: JetTextAlign.right),
            ),
            ShapeElement(
              id: 'headerRule',
              bounds: JetRect(x: 0, y: 38, width: _w, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _rule),
            ),
          ],
        ),
        pageFooter: Band(
          id: 'pageFooter',
          type: BandType.pageFooter,
          height: 18,
          elements: const <ReportElement>[
            TextElement(
              id: 'pageNo',
              bounds: JetRect(x: 0, y: 2, width: _w, height: 12),
              text: 'Page',
              style: JetTextStyle(fontSize: 8, color: _grey, align: JetTextAlign.right),
              expression: r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ),
      body: ReportBody(
        summary: Band(
          id: 'summary',
          type: BandType.summary,
          height: 34,
          elements: const <ReportElement>[
            ShapeElement(
              id: 'summaryRule',
              bounds: JetRect(x: 0, y: 4, width: _w, height: 0.75),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _rule),
            ),
            TextElement(
              id: 'countLabel',
              bounds: JetRect(x: 0, y: 10, width: 120, height: 16),
              text: 'Transactions',
              style: JetTextStyle(weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'txnCount',
              bounds: JetRect(x: 124, y: 10, width: 90, height: 16),
              text: 'count',
              style: JetTextStyle(),
              expression: r'COUNT($F{receiptNo})',
              format: _int,
            ),
            TextElement(
              id: 'sumLabel',
              bounds: JetRect(x: 300, y: 10, width: 120, height: 16),
              text: 'Total',
              style: JetTextStyle(align: JetTextAlign.right, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'grandSum',
              bounds: JetRect(x: 424, y: 10, width: 114, height: 16),
              text: 'total',
              style: JetTextStyle(align: JetTextAlign.right, weight: JetFontWeight.bold),
              expression: r'SUM($F{amount})',
              format: _money,
            ),
          ],
        ),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'txn',
              type: BandType.detail,
              height: 15,
              elements: const <ReportElement>[
                TextElement(
                  id: 'cTime',
                  bounds: JetRect(x: 0, y: 1, width: 92, height: 12),
                  text: 'time',
                  style: JetTextStyle(fontSize: 8),
                  expression: r'$F{time}',
                ),
                TextElement(
                  id: 'cReceipt',
                  bounds: JetRect(x: 96, y: 1, width: 66, height: 12),
                  text: 'receiptNo',
                  style: JetTextStyle(fontSize: 8),
                  expression: r'$F{receiptNo}',
                ),
                TextElement(
                  id: 'cItem',
                  bounds: JetRect(x: 166, y: 1, width: 190, height: 12),
                  text: 'item',
                  style: JetTextStyle(fontSize: 8),
                  expression: r'$F{item}',
                ),
                TextElement(
                  id: 'cQty',
                  bounds: JetRect(x: 360, y: 1, width: 34, height: 12),
                  text: 'qty',
                  style: JetTextStyle(fontSize: 8, align: JetTextAlign.right),
                  expression: r'$F{qty}',
                  format: _int,
                ),
                TextElement(
                  id: 'cAmount',
                  bounds: JetRect(x: 398, y: 1, width: 74, height: 12),
                  text: 'amount',
                  style: JetTextStyle(fontSize: 8, align: JetTextAlign.right),
                  expression: r'$F{amount}',
                  format: _money,
                ),
                TextElement(
                  id: 'cStatus',
                  bounds: JetRect(x: 476, y: 1, width: 62, height: 12),
                  text: 'status',
                  style: JetTextStyle(fontSize: 8, align: JetTextAlign.right),
                  expression: r'$F{status}',
                ),
              ],
            )),
          ],
        ),
      ),
    );
```

VERIFY before trusting the sketch: open `apps/jet_print_playground/lib/menu_sample.dart` and confirm the exact constructor names/parameters (`PageFurniture`, `Band`, `BandNode`, `DetailScope`, `ReportBody`, `JetTextStyle`, `JetTextAlign`, `JetBoxStyle`, `ShapeElement`, `ShapeKind`, `JetColor`, `PageFormat.a4Portrait`) — this sketch follows that file. Fix any drift (e.g. a required named arg) before running.

- [ ] **Step 4: Run → PASS.**

Run: `cd apps/jet_print_playground && flutter test test/ledger_definition_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyzer + format, then commit.**

```bash
cd apps/jet_print_playground && dart format lib/ledger_sample.dart test/ledger_definition_test.dart && flutter analyze lib/ledger_sample.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/ledger_sample.dart apps/jet_print_playground/test/ledger_definition_test.dart
git commit -m "feat(playground): sales-ledger report definition + schema (040)"
```

---

## Task 5: Paged ledger data source + render helper + render/parity test

**Files:**
- Create: `apps/jet_print_playground/lib/rendered_ledger_example.dart`
- Test (create): `apps/jet_print_playground/test/rendered_ledger_example_test.dart`

**Interfaces:**
- Consumes: `ledgerSchema` / `ledgerSampleDefinition()` (Task 4); `JetPagedDataSource` (Task 3).
- Produces: `const int kLedgerRowCount`, `const int kLedgerPageSize`, `double ledgerAmountAt(int index)`, `Map<String, Object?> ledgerRowAt(int index)`, `List<Map<String, Object?>> ledgerFetchPage(int pageIndex)`, `JetDataSource ledgerDataSource()`, and `RenderedReport renderLedgerDefinition({ReportDefinition? definition, JetDataSource? source, List<JetFontFamily> fonts})`.

- [ ] **Step 1: Write the failing test** — `apps/jet_print_playground/test/rendered_ledger_example_test.dart`:

```dart
// Rendered sales-ledger example (spec 040): a JetPagedDataSource drives a
// multi-page render whose grand totals equal the deterministic feed's sums, and
// the paged source renders identically to an in-memory source over the same rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/ledger_sample.dart';
import 'package:jet_print_playground/rendered_ledger_example.dart';

/// The rendered text of [elementId] on a single [pageIndex], runs joined.
List<String> _runsOnPage(RenderedReport r, int pageIndex, String elementId) =>
    <String>[
      for (final TextRunPrimitive p
          in r.pageAt(pageIndex).frame.primitives.whereType<TextRunPrimitive>())
        if (p.elementId == elementId) p.lines.map((TextLine l) => l.text).join(),
    ];

/// Every text run across all pages, tagged by page + element, for parity.
List<String> _allRuns(RenderedReport r) => <String>[
      for (int i = 0; i < r.pageCount; i++)
        for (final TextRunPrimitive p
            in r.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          '$i|${p.elementId}|${p.lines.map((TextLine l) => l.text).join()}',
    ];

void main() {
  group('rendered sales-ledger example', () {
    test('renders many pages with no error diagnostics', () {
      final RenderedReport report = renderLedgerDefinition();
      expect(report.pageCount, greaterThan(1));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });

    test('grand totals equal the deterministic feed sums', () {
      final RenderedReport report = renderLedgerDefinition();
      double sum = 0;
      for (int i = 0; i < kLedgerRowCount; i++) {
        sum += ledgerAmountAt(i);
      }
      final int last = report.pageCount - 1; // summary prints once, at the end
      expect(_runsOnPage(report, last, 'grandSum'),
          <String>[NumberFormat(r'#,##0.00').format(sum)]);
      expect(_runsOnPage(report, last, 'txnCount'),
          <String>[NumberFormat(r'#,##0').format(kLedgerRowCount)]);
    });

    test('paged source renders identically to in-memory over the same rows', () {
      final List<Map<String, Object?>> fixture = <Map<String, Object?>>[
        for (int i = 0; i < 5; i++) ledgerRowAt(i),
      ];
      const int pageSize = 2;
      final JetDataSource paged = JetPagedDataSource(
        fields: ledgerSchema.fields,
        pageSize: pageSize,
        fetchPage: (int p) {
          final int start = p * pageSize;
          if (start >= fixture.length) return const <Map<String, Object?>>[];
          final int end = (start + pageSize) > fixture.length
              ? fixture.length
              : start + pageSize;
          return fixture.sublist(start, end);
        },
      );
      final JetDataSource inMemory =
          JetInMemoryDataSource(fixture, fields: ledgerSchema.fields);

      final RenderedReport a = renderLedgerDefinition(source: paged);
      final RenderedReport b = renderLedgerDefinition(source: inMemory);
      expect(a.pageCount, b.pageCount);
      expect(_allRuns(a), _allRuns(b));
    });
  });
}
```

- [ ] **Step 2: Run → FAIL.**

Run: `cd apps/jet_print_playground && flutter test test/rendered_ledger_example_test.dart`
Expected: FAIL — `rendered_ledger_example.dart` not found.

- [ ] **Step 3: Implement** — `apps/jet_print_playground/lib/rendered_ledger_example.dart`:

```dart
/// The playground's rendered sales-ledger example (spec 040): a
/// [JetPagedDataSource] generates ~20k transactions on demand, one page at a
/// time, and the public engine renders them into a multi-page report. The whole
/// integration — paged source + render — goes through
/// `package:jet_print/jet_print.dart` only.
///
/// The data is **deterministic**: every value derives from the row index (no
/// clock, no randomness), and amounts are multiples of 0.25 so the rendered
/// `SUM` is exact and equals a test-side fold.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'ledger_sample.dart';

/// The demo's logical row count.
const int kLedgerRowCount = 20000;

/// Rows fetched per page by [ledgerDataSource]. 20000 is an exact multiple, so
/// the feed ends on an empty trailing page — exercising that path live.
const int kLedgerPageSize = 250;

/// Sample item names, chosen by index.
const List<String> _items = <String>[
  'Espresso',
  'Flat White',
  'Croissant',
  'Bagel',
  'Orange Juice',
  'Club Sandwich',
  'Caesar Salad',
  'Cheesecake',
];

/// Transaction statuses, mostly PAID.
const List<String> _statuses = <String>['PAID', 'PAID', 'PAID', 'REFUND'];

/// The quantity for row [index] (1..5).
int _qtyAt(int index) => (index % 5) + 1;

/// The unit price for row [index] — a multiple of 0.25 in [0.25, 10.00].
double _unitPriceAt(int index) => (((index * 3 + 1) % 40) + 1) * 0.25;

/// The line amount for row [index] = qty × unitPrice — a multiple of 0.25, so
/// the report's `SUM($F{amount})` is exact in IEEE-754.
double ledgerAmountAt(int index) => _qtyAt(index) * _unitPriceAt(index);

/// A deterministic `yyyy-MM-dd HH:mm` timestamp for row [index] (one minute
/// apart from a fixed epoch — no `DateTime.now()`).
String _timeAt(int index) => DateTime.utc(2026, 1, 1)
    .add(Duration(minutes: index))
    .toIso8601String()
    .substring(0, 16)
    .replaceFirst('T', ' ');

/// The full row map for transaction [index].
Map<String, Object?> ledgerRowAt(int index) => <String, Object?>{
      'time': _timeAt(index),
      'receiptNo': 'R-${100000 + index}',
      'item': _items[index % _items.length],
      'qty': _qtyAt(index),
      'unitPrice': _unitPriceAt(index),
      'amount': ledgerAmountAt(index),
      'status': _statuses[index % _statuses.length],
    };

/// Page [pageIndex] of the feed: up to [kLedgerPageSize] rows, fewer (or empty)
/// once the feed is exhausted — the signal [JetPagedDataSource] stops on.
List<Map<String, Object?>> ledgerFetchPage(int pageIndex) {
  final int start = pageIndex * kLedgerPageSize;
  if (start >= kLedgerRowCount) return const <Map<String, Object?>>[];
  final int end = (start + kLedgerPageSize) > kLedgerRowCount
      ? kLedgerRowCount
      : start + kLedgerPageSize;
  return <Map<String, Object?>>[
    for (int i = start; i < end; i++) ledgerRowAt(i),
  ];
}

/// The demo data source: a lazily-paged feed that never holds all rows at once.
JetDataSource ledgerDataSource() => JetPagedDataSource(
      fields: ledgerSchema.fields,
      pageSize: kLedgerPageSize,
      fetchPage: ledgerFetchPage,
    );

/// The flat set of every schema field name (for schema-aware render).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };

/// Renders the ledger definition against the paged source (or an injected
/// [source]/[definition], used by the parity test).
RenderedReport renderLedgerDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? ledgerSampleDefinition(),
      source ?? ledgerDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(ledgerSchema.fields),
        fonts: fonts,
      ),
    );
```

- [ ] **Step 4: Run → PASS.**

Run: `cd apps/jet_print_playground && flutter test test/rendered_ledger_example_test.dart`
Expected: PASS (3 tests). If the grand-totals test fails on a formatting mismatch, confirm the `_money`/`_int` masks in `ledger_sample.dart` match `NumberFormat(r'#,##0.00')`/`NumberFormat(r'#,##0')` in the test (they must be identical).

- [ ] **Step 5: Analyzer + format, then commit.**

```bash
cd apps/jet_print_playground && dart format lib/rendered_ledger_example.dart test/rendered_ledger_example_test.dart && flutter analyze lib/rendered_ledger_example.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/rendered_ledger_example.dart apps/jet_print_playground/test/rendered_ledger_example_test.dart
git commit -m "feat(playground): paged ledger data source + render + parity test (040)"
```

---

## Task 6: Wire the ledger demo tab into the playground shell

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart`
- Modify: `apps/jet_print_playground/lib/l10n/app_en.arb`, `app_de.arb`, `app_tr.arb`

**Interfaces:**
- Consumes: `ledgerSampleDefinition()`, `ledgerSchema` (Task 4); `renderLedgerDefinition` (Task 5); the generated `l10n.tabLedger` getter.

- [ ] **Step 1: Add the l10n label** to all three arb files (keep valid JSON — match the surrounding commas).
  - `app_en.arb` — beside the other `tab*` keys, add the key plus its metadata block (mirroring `@tabList`):

```json
  "tabLedger": "Ledger",
  "@tabLedger": {
    "description": "Big-list sales-ledger demo tab label"
  },
```

  - `app_de.arb` — add: `"tabLedger": "Journal",`
  - `app_tr.arb` — add: `"tabLedger": "Defter",`

- [ ] **Step 2: Regenerate the localizations.**

Run: `cd apps/jet_print_playground && flutter gen-l10n`
Expected: no error; `lib/l10n/app_localizations.dart` now declares `String get tabLedger;` (verify with `grep -n tabLedger lib/l10n/app_localizations.dart`).

- [ ] **Step 3: Import the ledger demo** — in `apps/jet_print_playground/lib/main.dart`, add beside the other sample imports (e.g. after the `nested_list_sample.dart` import) and the rendered-example imports:

```dart
import 'ledger_sample.dart';
import 'rendered_ledger_example.dart';
```

(Match the existing import grouping — sample imports are grouped together, rendered-example imports lower down. If `rendered_*` imports are not separately listed, add only the line(s) the file actually needs; `ledger_sample.dart` exposes `ledgerSampleDefinition`/`ledgerSchema`, `rendered_ledger_example.dart` exposes `renderLedgerDefinition`.)

- [ ] **Step 4: Register the demo body** — in `_demoBodies` (built in `initState`), insert this record immediately AFTER the `'nested-lists'` entry:

```dart
      (
        value: 'defter',
        icon: LucideIcons.scrollText,
        body: tab(ledgerSampleDefinition(), ledgerSchema,
            (d) => renderLedgerDefinition(definition: d, fonts: widget.fonts)),
      ),
```

- [ ] **Step 5: Register the label** — in the `labels` list inside `build()`, insert `l10n.tabLedger` at the SAME position (immediately after `l10n.tabList`, which is the `'nested-lists'` label):

```dart
      l10n.tabList,
      l10n.tabLedger,
      l10n.tabMenu,
```

VERIFY: `_demoBodies` and `labels` must stay index-aligned — the ledger entry and `l10n.tabLedger` must sit at the same ordinal in both lists. Re-read both lists after editing to confirm alignment (the `ShadTab` loop pairs `_demoBodies[i]` with `labels[i]`).

- [ ] **Step 6: Confirm the app still compiles and its tests pass.**

Run: `cd apps/jet_print_playground && flutter analyze && flutter test`
Expected: analyze clean; all playground tests green (including `app_consumes_library_test.dart`, `widget_test.dart`).

- [ ] **Step 7: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart apps/jet_print_playground/lib/l10n
git commit -m "feat(playground): add the sales-ledger (Defter) demo tab (040)"
```

---

## Task 7: Full verification sweep

Verification only — no new code unless a check fails.

- [ ] **Step 1: Library suite + analyzer + format.**

```bash
cd packages/jet_print
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
```
Expected: analyze clean; format reports no changes; **all tests green, with NO golden changes** (this slice never touches the render path). If a golden fails, STOP and inspect — it indicates an unintended engine effect.

- [ ] **Step 2: Playground suite + analyzer + format.**

```bash
cd apps/jet_print_playground
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
```
Expected: all green.

- [ ] **Step 3: Confirm the public API gained exactly one symbol.**

Run: `grep -n "JetPagedDataSource" packages/jet_print/lib/jet_print.dart`
Expected: one export line. (No other public surface changed.)

- [ ] **Step 4: Confirm success criteria.**
  - SC-001 (unknown-total iteration, one page held) → `paged_cursor_data_set_test.dart` walk + laziness tests; `paged_data_source_test.dart` walk.
  - SC-002 (ends on short page AND empty trailing page) → `paged_cursor_data_set_test.dart` short/exact-multiple/empty tests.
  - SC-003 (paged vs in-memory parity) → `rendered_ledger_example_test.dart` parity test.
  - SC-004 (multi-page demo with correct COUNT+SUM over ~20k) → `rendered_ledger_example_test.dart` page-count + grand-totals tests.
  - SC-005 (no engine/filler/golden change; suites green) → Steps 1-2.
  - SC-006 (exported + documented; analyzer/format clean) → Step 3 + per-task dartdoc + Steps 1-2 format/analyze.

- [ ] **Step 5: Optional manual GUI smoke.** `cd apps/jet_print_playground && flutter run -d macos`; open the **Defter** tab; hit Preview; confirm a multi-page ledger renders, page footers read "Page X of N", and the final page shows `Transactions 20,000` and a `Total`. (Not required for completion; the rendered-example test already pins these as values.)

---

## Self-Review

- **Spec coverage:**
  - "Sync `JetPagedDataSource`, explicit schema, unknown total" → Task 3 (+ cursor in Task 2).
  - "New `PagedCursorDataSet`, end on short/empty page, one page at a time" → Task 2.
  - "Shared projection (one place)" → Task 1.
  - "Export from `jet_print.dart`" → Task 3 Step 4.
  - "Ledger demo: page header/footer, repeating detail, summary COUNT+SUM, ~20k rows, pageSize 250, tab" → Tasks 4-6.
  - "Lib unit tests (cursor walk, short/empty end, current/close, projection, re-open, pageSize guard)" → Tasks 2-3.
  - "Parity test (byte/render-identical paged vs in-memory)" → Task 5 (asserts identical pageCount + full text-run stream; the deterministic primitive stream is what produces the bytes).
  - "Playground test (page count + correct totals, no pixel golden)" → Task 5.
  - "No engine/golden change; suites green; dartdoc; analyzer/format clean" → per-task + Task 7.
  - Non-goals (async, JSON/object paged variants, first-page inference) → not implemented, by design.
- **Placeholder scan:** none — every code step carries complete code; every command has expected output.
- **Type consistency:** `projectRowOntoFields(List<FieldDef>, Map<String, Object?>) → DataRow` defined in Task 1, consumed in Tasks 1-2. `PagedCursorDataSet({fields, pageSize, fetchPage})` defined in Task 2, consumed in Task 3. `JetPagedDataSource({fields, pageSize, fetchPage})` + `fields` getter defined in Task 3, consumed in Task 5. Demo element ids (`txn`, `txnCount`→`COUNT($F{receiptNo})`, `grandSum`→`SUM($F{amount})`) defined in Task 4, asserted in Tasks 4-5. `kLedgerRowCount`/`kLedgerPageSize`/`ledgerAmountAt`/`ledgerRowAt`/`ledgerFetchPage`/`ledgerDataSource`/`renderLedgerDefinition` defined in Task 5, consumed in Tasks 5-6.
- **Risks called out inline:** band/scope constructor drift (Task 4 VERIFY note → check `menu_sample.dart`); `ScopeNode`/`BandNode` import path (Task 4 NOTE → mirror `nested_list_definition_test.dart`); number-mask must match between sample and test (Task 5 Step 4); `_demoBodies`/`labels` index alignment (Task 6 VERIFY); gen-l10n must run and expose `tabLedger` (Task 6 Step 2).
