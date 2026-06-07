# Data Layer (spec 004) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `src/data/` seam — a synchronous, headless data-access layer (`JetDataSource` factory → `DataSet` forward cursor → immutable `DataRow` snapshots, with typed `FieldDef` metadata) plus three in-memory implementations, so the Fill stage (007) and expression engine (005) have a uniform row source to consume.

**Architecture:** The data seam is the second-innermost ring of the engine (`data → domain`; depends on nothing but the domain's value types, never Flutter/`dart:ui`). A `JetDataSource` is a *factory* opened with a parameter map; each `open()` yields a fresh forward-only `DataSet` cursor. Advancing the cursor exposes an immutable `DataRow` snapshot whose field values are projected onto a declared/​inferred schema of typed `FieldDef`s. All three built-in sources (`List<Map>`, JSON string, typed object list) share one internal `RowCursorDataSet` cursor that does the projection, so cursor semantics live in exactly one place. The layer-boundary and encapsulation architecture tests are extended to police the new seam.

**Tech Stack:** Dart 3 (sealed/value-type idioms already used in `src/domain/`), `dart:convert` for the JSON source (allowed in the headless core — no Flutter). No new package dependencies. Tests use `flutter_test` with absolute `package:jet_print/src/data/...` imports (white-box seam tests).

---

## Design Decisions (settled before planning)

- **Row access shape:** Cursor **+** immutable `DataRow` snapshot — reconciles the blueprint's §4 "`DataSet` (row cursor) → `DataRow`" with §6's literal cursor signature. `DataSet` is the forward-only cursor; `DataRow` is the value snapshot of the current row (easy to stash for group-break detection in 005/007, trivial to assert in tests).
- **In-memory implementations shipped now:** all three — `JetInMemoryDataSource` (`List<Map>`), `JetJsonDataSource` (JSON array string), `JetObjectDataSource<T>` (typed object list).
- **Field typing now:** `FieldDef{name, type}` with a `JetFieldType` enum; in-memory sources infer per-column **best-effort** and fall back to `unknown`. The type is additive metadata (a slot for 005's formatting/coercion), never a hard contract.
- **No serialization in this seam:** data sources are runtime-injected extension points (§6 contract 3), not persisted in the template. 004 adds **no** codecs.
- **Not exported from `jet_print.dart` yet:** like the 003 domain types, the data seam lives under `src/` and is exercised by white-box tests. The single public facade export is batched later (009 / a dedicated export pass). This is the established convention in this repo (deferred public export is intentional, not dead code).
- **`close()` is part of the `DataSet` contract:** in-memory cursors implement it as a no-op, but custom sources (over files/sockets) need it; Fill (007) will call it in a `finally`. Including it now keeps the extension point forward-compatible.

## File Structure

All library files are **pure Dart**, use **relative imports**, carry **dartdoc on every public symbol**, and follow the existing value-type idioms in `src/domain/` (value equality via `Object.hash`/`Object.hashAll`, defensive immutability).

- Create: `packages/jet_print/lib/src/data/field_def.dart` — `JetFieldType` enum + `FieldDef` value type + best-effort `FieldDef.inferType`.
- Create: `packages/jet_print/lib/src/data/data_row.dart` — immutable `DataRow` snapshot (typed-schema field access, value equality).
- Create: `packages/jet_print/lib/src/data/data_set.dart` — abstract `DataSet` forward-cursor contract.
- Create: `packages/jet_print/lib/src/data/jet_data_source.dart` — abstract `JetDataSource` factory contract.
- Create: `packages/jet_print/lib/src/data/row_cursor_data_set.dart` — internal `RowCursorDataSet` shared by all built-in sources (index + projection).
- Create: `packages/jet_print/lib/src/data/in_memory_data_source.dart` — `JetInMemoryDataSource` (`List<Map>`) with schema inference.
- Create: `packages/jet_print/lib/src/data/json_data_source.dart` — `JetJsonDataSource.parse` (JSON array string → rows).
- Create: `packages/jet_print/lib/src/data/object_data_source.dart` — `JetObjectDataSource<T>` (typed object list + extractor).
- Modify: `packages/jet_print/test/encapsulation_test.dart` — allow `/test/data/` as a white-box seam test dir.
- Modify: `packages/jet_print/test/architecture/layer_boundaries_test.dart` — add a `data`-seam group (data may import domain; must not reach rendering/designer/Flutter-UI).
- Modify: `packages/jet_print/CHANGELOG.md` — add the spec-004 "Added" bullet.
- Create (tests): `packages/jet_print/test/data/field_def_test.dart`, `data_row_test.dart`, `cursor_contract_test.dart`, `in_memory_data_source_test.dart`, `json_data_source_test.dart`, `object_data_source_test.dart`.

**Build order rationale:** Task 1 extends the encapsulation allowlist *first* so every later `/test/data/` file is permitted to import `src/` when the full suite runs. Tasks 2→7 build value types and sources bottom-up (each compiles and tests in isolation). Task 8 adds the data-seam layer-boundary group last, once the seam has real files (so the "no false green" check is non-vacuous), and finishes the CHANGELOG + full green gate.

---

### Task 1: Seam guard — allow `/test/data/` white-box tests

The encapsulation test bans every consumer file from importing `package:jet_print/src/...`, with a narrow allowlist for the package's own white-box seam tests (currently only `/test/domain/` and `/test/rendering/`). The data-seam tests must join that allowlist *before* any of them run under the full suite, otherwise the encapsulation test goes red.

**Files:**
- Modify: `packages/jet_print/test/encapsulation_test.dart:43-46`

- [ ] **Step 1: Extend the white-box allowlist**

In `packages/jet_print/test/encapsulation_test.dart`, replace the body of `_isWhiteBoxSeamTest`:

```dart
bool _isWhiteBoxSeamTest(File file) {
  final String path = file.path.replaceAll(r'\', '/');
  return path.contains('/test/domain/') ||
      path.contains('/test/data/') ||
      path.contains('/test/rendering/');
}
```

Also update its doc comment to mention the new seam — change the first sentence to:

```dart
/// White-box seam tests legitimately import the library's own internals to
/// exercise the un-exported `domain`/`data`/`rendering` types in isolation
/// (SC-004).
```

- [ ] **Step 2: Run the encapsulation suite to verify it still passes**

Run: `cd packages/jet_print && flutter test test/encapsulation_test.dart`
Expected: PASS (the allowlist change widens an exception; no `/test/data/` files exist yet, so behavior for existing files is unchanged).

- [ ] **Step 3: Commit**

```bash
git add packages/jet_print/test/encapsulation_test.dart
git commit -m "test(data): allow /test/data white-box seam tests to import src"
```

---

### Task 2: `FieldDef` + `JetFieldType` + best-effort inference

Typed field metadata. `FieldDef` is a value type; `JetFieldType` is the small type enum; `FieldDef.inferType` derives a column type from a sequence of values (nulls ignored; `int`+`double` widens to `double`; any genuinely mixed/unsupported column → `unknown`).

**Files:**
- Create: `packages/jet_print/lib/src/data/field_def.dart`
- Test: `packages/jet_print/test/data/field_def_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/data/field_def_test.dart`:

```dart
// FieldDef + JetFieldType value type and best-effort column-type inference
// (spec 004). No Flutter UI import — the data seam stays headless.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';

void main() {
  group('FieldDef', () {
    test('defaults to an unknown type', () {
      expect(const FieldDef('name').type, JetFieldType.unknown);
    });

    test('has value equality and a consistent hash code', () {
      expect(const FieldDef('qty', type: JetFieldType.integer),
          const FieldDef('qty', type: JetFieldType.integer));
      expect(const FieldDef('qty', type: JetFieldType.integer).hashCode,
          const FieldDef('qty', type: JetFieldType.integer).hashCode);
      expect(
          const FieldDef('qty', type: JetFieldType.integer) ==
              const FieldDef('qty', type: JetFieldType.double),
          isFalse);
      expect(
          const FieldDef('qty', type: JetFieldType.integer) ==
              const FieldDef('price', type: JetFieldType.integer),
          isFalse);
    });
  });

  group('FieldDef.inferType', () {
    test('infers integer / double / boolean / string / dateTime', () {
      expect(FieldDef.inferType(<Object?>[1, 2, 3]), JetFieldType.integer);
      expect(FieldDef.inferType(<Object?>[1.5, 2.0]), JetFieldType.double);
      expect(FieldDef.inferType(<Object?>[true, false]), JetFieldType.boolean);
      expect(FieldDef.inferType(<Object?>['a', 'b']), JetFieldType.string);
      expect(FieldDef.inferType(<Object?>[DateTime(2026), DateTime(2025)]),
          JetFieldType.dateTime);
    });

    test('skips nulls when inferring', () {
      expect(FieldDef.inferType(<Object?>[null, 1, null, 2]),
          JetFieldType.integer);
    });

    test('widens a mixed int/double column to double', () {
      expect(FieldDef.inferType(<Object?>[1, 2.5]), JetFieldType.double);
    });

    test('falls back to unknown for empty, all-null, or mixed columns', () {
      expect(FieldDef.inferType(<Object?>[]), JetFieldType.unknown);
      expect(FieldDef.inferType(<Object?>[null, null]), JetFieldType.unknown);
      expect(FieldDef.inferType(<Object?>[1, 'a']), JetFieldType.unknown);
      expect(FieldDef.inferType(<Object?>[Object()]), JetFieldType.unknown);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/data/field_def_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jet_print/src/data/field_def.dart'` (file not created yet).

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/data/field_def.dart`:

```dart
/// Typed field metadata for the data layer (spec 004).
///
/// A [FieldDef] names a column and tags it with a best-effort [JetFieldType].
/// The type is additive metadata — a slot the expression engine (005) uses for
/// formatting and coercion — never a hard contract; an indeterminate column is
/// simply [JetFieldType.unknown]. Pure Dart, no Flutter dependency.
library;

/// The coarse value type of a data field.
///
/// Deliberately small: enough to drive number/date formatting and coercion
/// without modelling a full type system. [unknown] covers empty, all-null, or
/// genuinely mixed columns.
enum JetFieldType {
  /// Textual values (`String`).
  string,

  /// Whole numbers (`int`).
  integer,

  /// Fractional numbers (`double`), or a column mixing `int` and `double`.
  double,

  /// Boolean values (`bool`).
  boolean,

  /// Timestamps (`DateTime`).
  dateTime,

  /// Indeterminate — empty, all-null, or mixed/unsupported value types.
  unknown,
}

/// An immutable (name, type) pair describing one field of a [DataSet]'s schema.
class FieldDef {
  /// Creates a field named [name] with the given [type] (default
  /// [JetFieldType.unknown]).
  const FieldDef(this.name, {this.type = JetFieldType.unknown});

  /// The field's name, as referenced by `DataRow.field(name)`.
  final String name;

  /// The field's coarse value type (best-effort).
  final JetFieldType type;

  /// Best-effort inference of a column's [JetFieldType] from its [values].
  ///
  /// Nulls are ignored. A column of all `int` is [JetFieldType.integer]; mixing
  /// `int` and `double` widens to [JetFieldType.double]. Any other mixture, an
  /// unsupported runtime type, an empty sequence, or an all-null sequence yields
  /// [JetFieldType.unknown].
  static JetFieldType inferType(Iterable<Object?> values) {
    JetFieldType? result;
    for (final Object? value in values) {
      if (value == null) continue;
      final JetFieldType current = _typeOf(value);
      if (current == JetFieldType.unknown) return JetFieldType.unknown;
      if (result == null) {
        result = current;
      } else if (result != current) {
        final bool intDoubleMix =
            (result == JetFieldType.integer && current == JetFieldType.double) ||
                (result == JetFieldType.double &&
                    current == JetFieldType.integer);
        if (intDoubleMix) {
          result = JetFieldType.double;
        } else {
          return JetFieldType.unknown;
        }
      }
    }
    return result ?? JetFieldType.unknown;
  }

  static JetFieldType _typeOf(Object value) {
    if (value is int) return JetFieldType.integer;
    if (value is double) return JetFieldType.double;
    if (value is bool) return JetFieldType.boolean;
    if (value is DateTime) return JetFieldType.dateTime;
    if (value is String) return JetFieldType.string;
    return JetFieldType.unknown;
  }

  @override
  bool operator ==(Object other) =>
      other is FieldDef && other.name == name && other.type == type;

  @override
  int get hashCode => Object.hash(name, type);

  @override
  String toString() => 'FieldDef($name, $type)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/data/field_def_test.dart`
Expected: PASS (all groups green).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/data/field_def.dart packages/jet_print/test/data/field_def_test.dart
git commit -m "feat(data): add FieldDef + JetFieldType with best-effort inference"
```

---

### Task 3: `DataRow` — immutable row snapshot

The value snapshot of one cursor position: a declared schema (`List<FieldDef>`) plus the row's values projected onto it. `field(name)` returns the (possibly null) value of a *declared* field and throws `ArgumentError` for an undeclared name (a programming error, distinct from a present-but-null value). Value equality so rows are easy to assert.

**Files:**
- Create: `packages/jet_print/lib/src/data/data_row.dart`
- Test: `packages/jet_print/test/data/data_row_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/data/data_row_test.dart`:

```dart
// DataRow immutable row snapshot (spec 004). No Flutter UI import.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';

DataRow _row() => DataRow(
      fields: const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('note', type: JetFieldType.string),
      ],
      values: <String, Object?>{'qty': 3, 'note': null},
    );

void main() {
  group('DataRow', () {
    test('exposes its declared fields', () {
      expect(_row().fields, const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('note', type: JetFieldType.string),
      ]);
    });

    test('field() returns a declared value, including null', () {
      expect(_row().field('qty'), 3);
      expect(_row().field('note'), isNull);
    });

    test('hasField() distinguishes declared from undeclared', () {
      expect(_row().hasField('qty'), isTrue);
      expect(_row().hasField('missing'), isFalse);
    });

    test('field() throws ArgumentError for an undeclared field', () {
      expect(() => _row().field('missing'), throwsArgumentError);
    });

    test('has value equality and a consistent hash code', () {
      expect(_row(), _row());
      expect(_row().hashCode, _row().hashCode);
    });

    test('rows differing in a value are unequal', () {
      final DataRow other = DataRow(
        fields: const <FieldDef>[
          FieldDef('qty', type: JetFieldType.integer),
          FieldDef('note', type: JetFieldType.string),
        ],
        values: <String, Object?>{'qty': 4, 'note': null},
      );
      expect(_row() == other, isFalse);
    });

    test('is immutable — the source map cannot mutate the row after construction',
        () {
      final Map<String, Object?> values = <String, Object?>{'qty': 3, 'note': null};
      final DataRow row = DataRow(
        fields: const <FieldDef>[
          FieldDef('qty', type: JetFieldType.integer),
          FieldDef('note', type: JetFieldType.string),
        ],
        values: values,
      );
      values['qty'] = 99; // mutate the caller's map
      expect(row.field('qty'), 3); // row unaffected
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/data/data_row_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jet_print/src/data/data_row.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/data/data_row.dart`:

```dart
/// Immutable snapshot of one data-source row (spec 004).
library;

import 'field_def.dart';

/// An immutable view of a single row: a declared schema plus the row's values.
///
/// Construction defensively copies both the [fields] and the [values] map into
/// unmodifiable collections, so a [DataRow] never changes after it is created —
/// even if the caller later mutates the map it passed in. This makes rows safe
/// to stash (e.g. comparing the previous and current row to detect a group
/// break in the Fill stage).
class DataRow {
  /// Creates a row over [fields] whose declared values are [values].
  ///
  /// [values] must contain an entry for every declared field name (the value
  /// may be `null`); the built-in cursor guarantees this by projecting each raw
  /// row onto the schema.
  DataRow({
    required List<FieldDef> fields,
    required Map<String, Object?> values,
  })  : _fields = List<FieldDef>.unmodifiable(fields),
        _values = Map<String, Object?>.unmodifiable(values);

  final List<FieldDef> _fields;
  final Map<String, Object?> _values;

  /// The row's declared schema, in order.
  List<FieldDef> get fields => _fields;

  /// The value of the declared field [name] (which may be `null`).
  ///
  /// Throws [ArgumentError] if [name] is not a declared field — an undeclared
  /// name is a programming error, distinct from a declared-but-null value.
  Object? field(String name) {
    if (!_values.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown field');
    }
    return _values[name];
  }

  /// Whether [name] is a declared field of this row.
  bool hasField(String name) => _values.containsKey(name);

  @override
  bool operator ==(Object other) =>
      other is DataRow &&
      _fieldsEqual(_fields, other._fields) &&
      _valuesEqual(_values, other._values);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(_fields),
        Object.hashAll(<Object?>[
          for (final MapEntry<String, Object?> e in _values.entries) ...<Object?>[
            e.key,
            e.value,
          ],
        ]),
      );

  @override
  String toString() => 'DataRow($_values)';
}

bool _fieldsEqual(List<FieldDef> a, List<FieldDef> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _valuesEqual(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final MapEntry<String, Object?> e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/data/data_row_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/data/data_row.dart packages/jet_print/test/data/data_row_test.dart
git commit -m "feat(data): add immutable DataRow snapshot"
```

---

### Task 4: `DataSet` + `JetDataSource` contracts + `RowCursorDataSet`

The cursor contract (`DataSet`), the factory contract (`JetDataSource`), and the one shared concrete cursor (`RowCursorDataSet`) that every built-in source reuses. The cursor is index-driven: it pulls a raw `Map` for each row via a caller-supplied `rowAt(index)` thunk, projects it onto the declared schema (missing keys → `null`, extra keys dropped), and caches the resulting `DataRow`. `current` throws `StateError` before the first successful `moveNext()` and after exhaustion.

**Files:**
- Create: `packages/jet_print/lib/src/data/data_set.dart`
- Create: `packages/jet_print/lib/src/data/jet_data_source.dart`
- Create: `packages/jet_print/lib/src/data/row_cursor_data_set.dart`
- Test: `packages/jet_print/test/data/cursor_contract_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/data/cursor_contract_test.dart`:

```dart
// DataSet cursor protocol via the shared RowCursorDataSet (spec 004).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/row_cursor_data_set.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('a', type: JetFieldType.integer),
  FieldDef('b', type: JetFieldType.string),
];

DataSet _cursorOver(List<Map<String, Object?>> rows) => RowCursorDataSet(
      fields: _schema,
      rowCount: rows.length,
      rowAt: (int i) => rows[i],
    );

void main() {
  group('RowCursorDataSet (DataSet contract)', () {
    test('is a DataSet exposing the declared fields', () {
      final DataSet ds = _cursorOver(const <Map<String, Object?>>[]);
      expect(ds, isA<DataSet>());
      expect(ds.fields, _schema);
    });

    test('iterates rows forward, projecting each onto the schema', () {
      final DataSet ds = _cursorOver(<Map<String, Object?>>[
        <String, Object?>{'a': 1, 'b': 'x'},
        <String, Object?>{'a': 2, 'b': 'y'},
      ]);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('a'), 1);
      expect(ds.current.field('b'), 'x');
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('a'), 2);
      expect(ds.moveNext(), isFalse);
    });

    test('projects a missing key to null and drops extra keys', () {
      final DataSet ds = _cursorOver(<Map<String, Object?>>[
        <String, Object?>{'a': 1, 'extra': 'dropped'},
      ]);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('a'), 1);
      expect(ds.current.field('b'), isNull); // missing key → null
      expect(ds.current.hasField('extra'), isFalse); // extra key dropped
    });

    test('current throws StateError before the first moveNext', () {
      final DataSet ds = _cursorOver(const <Map<String, Object?>>[
        <String, Object?>{'a': 1, 'b': 'x'},
      ]);
      expect(() => ds.current, throwsStateError);
    });

    test('current throws StateError after exhaustion', () {
      final DataSet ds = _cursorOver(const <Map<String, Object?>>[
        <String, Object?>{'a': 1, 'b': 'x'},
      ]);
      expect(ds.moveNext(), isTrue);
      expect(ds.moveNext(), isFalse);
      expect(() => ds.current, throwsStateError);
    });

    test('moveNext returns false after close', () {
      final DataSet ds = _cursorOver(const <Map<String, Object?>>[
        <String, Object?>{'a': 1, 'b': 'x'},
      ]);
      ds.close();
      expect(ds.moveNext(), isFalse);
      expect(() => ds.current, throwsStateError);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/data/cursor_contract_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jet_print/src/data/data_set.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/data/data_set.dart`:

```dart
/// The forward-only row cursor contract (spec 004).
library;

import 'data_row.dart';
import 'field_def.dart';

/// A synchronous, forward-only cursor over a data source's rows.
///
/// Usage:
/// ```dart
/// final DataSet ds = source.open(params);
/// try {
///   while (ds.moveNext()) {
///     final DataRow row = ds.current;
///     // ... read row.field('name')
///   }
///   } finally {
///   ds.close();
/// }
/// ```
///
/// [current] is valid only immediately after a [moveNext] that returned `true`;
/// reading it before the first such call, after [moveNext] returns `false`, or
/// after [close] throws [StateError].
abstract class DataSet {
  /// The cursor's schema, in column order. Stable for the cursor's lifetime.
  List<FieldDef> get fields;

  /// Advances to the next row, returning `true` if one is now available.
  bool moveNext();

  /// The current row snapshot. Throws [StateError] if no row is current.
  DataRow get current;

  /// Releases any resources held by the cursor. Idempotent; in-memory cursors
  /// treat it as a no-op that also disables further iteration.
  void close();
}
```

Create `packages/jet_print/lib/src/data/jet_data_source.dart`:

```dart
/// The data-source factory contract (spec 004).
library;

import 'data_set.dart';

/// A factory that opens forward-only [DataSet] cursors over a row collection.
///
/// A source can be opened repeatedly — each [open] yields a fresh, independent
/// cursor positioned before the first row. [params] carries optional runtime
/// parameters (e.g. filters) for sources that support them; the built-in
/// in-memory sources accept but ignore it. This is extension point #3 of the
/// engine: a custom backend implements [open] returning its own [DataSet].
abstract class JetDataSource {
  /// Opens a fresh cursor, optionally parameterised by [params].
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]);
}
```

Create `packages/jet_print/lib/src/data/row_cursor_data_set.dart`:

```dart
/// Internal: the shared index-driven cursor backing the built-in data sources.
library;

import 'data_row.dart';
import 'data_set.dart';
import 'field_def.dart';

/// A [DataSet] that walks `0..rowCount-1`, pulling each raw row via [rowAt] and
/// projecting it onto a fixed [fields] schema.
///
/// Internal to the data seam — not part of the public API. All three built-in
/// sources (in-memory, JSON, object-list) delegate to this one cursor so the
/// forward-only semantics, schema projection, and `current`/`close` rules live
/// in exactly one place. Projection rule: each declared field reads its value
/// from the raw row (a missing key yields `null`); keys not in the schema are
/// dropped.
class RowCursorDataSet implements DataSet {
  /// Creates a cursor over [rowCount] rows, reading each via [rowAt].
  RowCursorDataSet({
    required List<FieldDef> fields,
    required int rowCount,
    required Map<String, Object?> Function(int index) rowAt,
  })  : _fields = List<FieldDef>.unmodifiable(fields),
        _rowCount = rowCount,
        _rowAt = rowAt;

  final List<FieldDef> _fields;
  final int _rowCount;
  final Map<String, Object?> Function(int index) _rowAt;

  int _index = -1;
  DataRow? _current;
  bool _closed = false;

  @override
  List<FieldDef> get fields => _fields;

  @override
  bool moveNext() {
    if (_closed || _index + 1 >= _rowCount) {
      _index = _rowCount;
      _current = null;
      return false;
    }
    _index++;
    _current = _project(_rowAt(_index));
    return true;
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

  DataRow _project(Map<String, Object?> raw) => DataRow(
        fields: _fields,
        values: <String, Object?>{
          for (final FieldDef f in _fields) f.name: raw[f.name],
        },
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/data/cursor_contract_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/data/data_set.dart packages/jet_print/lib/src/data/jet_data_source.dart packages/jet_print/lib/src/data/row_cursor_data_set.dart packages/jet_print/test/data/cursor_contract_test.dart
git commit -m "feat(data): add DataSet/JetDataSource contracts + shared RowCursorDataSet"
```

---

### Task 5: `JetInMemoryDataSource` (`List<Map>`)

The canonical source: a list of row maps with an optional explicit schema. When `fields` is omitted, it infers the schema — the union of keys across all rows in first-seen order, each typed via `FieldDef.inferType` over that column's values. Rows and the schema are defensively copied; `open` ignores `params`.

**Files:**
- Create: `packages/jet_print/lib/src/data/in_memory_data_source.dart`
- Test: `packages/jet_print/test/data/in_memory_data_source_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/data/in_memory_data_source_test.dart`:

```dart
// JetInMemoryDataSource over List<Map> (spec 004). No Flutter UI import.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/data/jet_data_source.dart';

void main() {
  group('JetInMemoryDataSource', () {
    test('is a JetDataSource', () {
      expect(JetInMemoryDataSource(const <Map<String, Object?>>[]),
          isA<JetDataSource>());
    });

    test('infers a typed schema as the union of keys in first-seen order', () {
      final JetInMemoryDataSource source =
          JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'qty': 2, 'price': 9.5},
        <String, Object?>{'qty': 3, 'note': 'late'}, // introduces `note`
      ]);
      expect(source.fields, const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('price', type: JetFieldType.double),
        FieldDef('note', type: JetFieldType.string),
      ]);
    });

    test('iterates rows, projecting missing keys to null', () {
      final JetDataSource source = JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'qty': 2, 'price': 9.5},
        <String, Object?>{'qty': 3}, // no price
      ]);
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 2);
      expect(ds.current.field('price'), 9.5);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 3);
      expect(ds.current.field('price'), isNull);
      expect(ds.moveNext(), isFalse);
    });

    test('honours an explicit schema over inference', () {
      final JetInMemoryDataSource source = JetInMemoryDataSource(
        <Map<String, Object?>>[
          <String, Object?>{'qty': 2, 'ignored': true},
        ],
        fields: const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
      );
      expect(source.fields,
          const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)]);
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.hasField('ignored'), isFalse);
    });

    test('open() yields independent cursors', () {
      final JetDataSource source = JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'qty': 1},
        <String, Object?>{'qty': 2},
      ]);
      final DataSet a = source.open();
      final DataSet b = source.open();
      expect(a.moveNext(), isTrue);
      expect(a.current.field('qty'), 1);
      // b is independent and still positioned before its first row.
      expect(b.moveNext(), isTrue);
      expect(b.current.field('qty'), 1);
    });

    test('an empty source infers an empty schema and yields no rows', () {
      final JetInMemoryDataSource source =
          JetInMemoryDataSource(const <Map<String, Object?>>[]);
      expect(source.fields, isEmpty);
      expect(source.open().moveNext(), isFalse);
    });

    test('is immutable — mutating the source list does not affect the source',
        () {
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[
        <String, Object?>{'qty': 1},
      ];
      final JetDataSource source = JetInMemoryDataSource(rows);
      rows.add(<Map<String, Object?>>{'qty': 2} as Map<String, Object?>);
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.moveNext(), isFalse); // still only one row
    });
  });
}
```

> Note: the immutability test's `rows.add(...)` cast is deliberately awkward; if the analyzer objects, simplify it to `rows.add(<String, Object?>{'qty': 2});` — the intent is only to mutate the caller's list after construction.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/data/in_memory_data_source_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jet_print/src/data/in_memory_data_source.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/data/in_memory_data_source.dart`:

```dart
/// In-memory data source over a list of row maps (spec 004).
library;

import 'data_set.dart';
import 'field_def.dart';
import 'jet_data_source.dart';
import 'row_cursor_data_set.dart';

/// A [JetDataSource] backed by an in-memory `List<Map<String, Object?>>`.
///
/// The canonical fixture/test source and the one the invoice MVP (009) feeds.
/// When [fields] is omitted the schema is inferred: the union of all row keys
/// in first-seen order, each typed best-effort via [FieldDef.inferType] over
/// that column's values. The rows and schema are copied defensively, so later
/// mutation of the caller's list does not affect the source. [open] ignores its
/// `params`.
class JetInMemoryDataSource implements JetDataSource {
  /// Creates a source over [rows], with an optional explicit [fields] schema.
  JetInMemoryDataSource(
    List<Map<String, Object?>> rows, {
    List<FieldDef>? fields,
  })  : _rows = <Map<String, Object?>>[
          for (final Map<String, Object?> row in rows)
            Map<String, Object?>.unmodifiable(row),
        ],
        _fields = List<FieldDef>.unmodifiable(fields ?? _inferFields(rows));

  final List<Map<String, Object?>> _rows;
  final List<FieldDef> _fields;

  /// The source's schema (explicit or inferred), in column order.
  List<FieldDef> get fields => _fields;

  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      RowCursorDataSet(
        fields: _fields,
        rowCount: _rows.length,
        rowAt: (int i) => _rows[i],
      );

  static List<FieldDef> _inferFields(List<Map<String, Object?>> rows) {
    final List<String> names = <String>[];
    final Set<String> seen = <String>{};
    for (final Map<String, Object?> row in rows) {
      for (final String key in row.keys) {
        if (seen.add(key)) names.add(key);
      }
    }
    return <FieldDef>[
      for (final String name in names)
        FieldDef(
          name,
          type: FieldDef.inferType(
            rows.map((Map<String, Object?> r) => r[name]),
          ),
        ),
    ];
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/data/in_memory_data_source_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/data/in_memory_data_source.dart packages/jet_print/test/data/in_memory_data_source_test.dart
git commit -m "feat(data): add JetInMemoryDataSource with schema inference"
```

---

### Task 6: `JetJsonDataSource` (JSON array string)

A thin convenience source: decode a JSON array-of-objects string into rows and delegate to an internal `JetInMemoryDataSource`. Validates structure — a non-array top level or a non-object element throws `ArgumentError` (fail fast on malformed input). `int`/`double` distinctions from `jsonDecode` flow straight into inference.

**Files:**
- Create: `packages/jet_print/lib/src/data/json_data_source.dart`
- Test: `packages/jet_print/test/data/json_data_source_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/data/json_data_source_test.dart`:

```dart
// JetJsonDataSource over a JSON array string (spec 004). No Flutter UI import.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/data/json_data_source.dart';

void main() {
  group('JetJsonDataSource.parse', () {
    test('is a JetDataSource', () {
      expect(JetJsonDataSource.parse('[]'), isA<JetDataSource>());
    });

    test('decodes an array of objects into typed rows', () {
      final JetJsonDataSource source = JetJsonDataSource.parse(
        '[{"qty": 2, "price": 9.5}, {"qty": 3, "price": 4.0}]',
      );
      expect(source.fields, const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('price', type: JetFieldType.double),
      ]);
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 2);
      expect(ds.current.field('price'), 9.5);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 3);
      expect(ds.moveNext(), isFalse);
    });

    test('honours an explicit schema', () {
      final JetJsonDataSource source = JetJsonDataSource.parse(
        '[{"qty": 2, "extra": 1}]',
        fields: const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
      );
      expect(source.fields,
          const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)]);
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.hasField('extra'), isFalse);
    });

    test('throws ArgumentError when the top level is not an array', () {
      expect(() => JetJsonDataSource.parse('{"qty": 1}'), throwsArgumentError);
    });

    test('throws ArgumentError when an element is not an object', () {
      expect(() => JetJsonDataSource.parse('[{"qty": 1}, 5]'),
          throwsArgumentError);
    });

    test('throws on malformed JSON', () {
      expect(() => JetJsonDataSource.parse('not json'), throwsA(anything));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/data/json_data_source_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jet_print/src/data/json_data_source.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/data/json_data_source.dart`:

```dart
/// Data source decoded from a JSON array-of-objects string (spec 004).
library;

import 'dart:convert';

import 'data_set.dart';
import 'field_def.dart';
import 'in_memory_data_source.dart';
import 'jet_data_source.dart';

/// A [JetDataSource] built by decoding a JSON array of objects.
///
/// A convenience wrapper over [JetInMemoryDataSource]: each top-level array
/// element becomes a row. The JSON must be an array whose elements are all
/// objects — anything else throws [ArgumentError] (structural input is verified
/// up front rather than failing later during iteration). `int`/`double`
/// distinctions produced by `jsonDecode` flow straight into schema inference.
class JetJsonDataSource implements JetDataSource {
  JetJsonDataSource._(this._delegate);

  /// Parses [json] (a JSON array of objects) into a source.
  ///
  /// Pass an explicit [fields] schema to override inference. Throws
  /// [ArgumentError] if the decoded value is not an array of objects, or a
  /// [FormatException] if [json] is not valid JSON.
  factory JetJsonDataSource.parse(String json, {List<FieldDef>? fields}) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! List) {
      throw ArgumentError.value(
        json,
        'json',
        'Expected a JSON array of objects',
      );
    }
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Object? element in decoded) {
      if (element is! Map) {
        throw ArgumentError.value(
          element,
          'json',
          'Every array element must be a JSON object',
        );
      }
      rows.add(element.map<String, Object?>(
        (Object? key, Object? value) => MapEntry<String, Object?>(
          key.toString(),
          value,
        ),
      ));
    }
    return JetJsonDataSource._(JetInMemoryDataSource(rows, fields: fields));
  }

  final JetInMemoryDataSource _delegate;

  /// The source's schema (explicit or inferred), in column order.
  List<FieldDef> get fields => _delegate.fields;

  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      _delegate.open(params);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/data/json_data_source_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/data/json_data_source.dart packages/jet_print/test/data/json_data_source_test.dart
git commit -m "feat(data): add JetJsonDataSource over a JSON array string"
```

---

### Task 7: `JetObjectDataSource<T>` (typed object list)

Lets consumers feed domain objects directly. The caller supplies an explicit typed `fields` schema (T is opaque, so it cannot be inferred) and a `row(T)` extractor mapping each object to a field-value map. Mapping is lazy — performed per row during iteration, not eagerly at construction.

**Files:**
- Create: `packages/jet_print/lib/src/data/object_data_source.dart`
- Test: `packages/jet_print/test/data/object_data_source_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/data/object_data_source_test.dart`:

```dart
// JetObjectDataSource<T> over a typed object list (spec 004). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/data/object_data_source.dart';

class _Line {
  const _Line(this.sku, this.qty);
  final String sku;
  final int qty;
}

JetObjectDataSource<_Line> _source(List<_Line> lines) =>
    JetObjectDataSource<_Line>(
      lines,
      fields: const <FieldDef>[
        FieldDef('sku', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
      ],
      row: (_Line l) => <String, Object?>{'sku': l.sku, 'qty': l.qty},
    );

void main() {
  group('JetObjectDataSource', () {
    test('is a JetDataSource exposing the explicit schema', () {
      final JetObjectDataSource<_Line> source = _source(const <_Line>[]);
      expect(source, isA<JetDataSource>());
      expect(source.fields, const <FieldDef>[
        FieldDef('sku', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
      ]);
    });

    test('iterates objects, mapping each via the extractor', () {
      final DataSet ds = _source(const <_Line>[
        _Line('A1', 2),
        _Line('B2', 5),
      ]).open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('sku'), 'A1');
      expect(ds.current.field('qty'), 2);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('sku'), 'B2');
      expect(ds.moveNext(), isFalse);
    });

    test('maps lazily — the extractor runs only during iteration', () {
      int calls = 0;
      final JetObjectDataSource<_Line> source = JetObjectDataSource<_Line>(
        const <_Line>[_Line('A1', 2), _Line('B2', 5)],
        fields: const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
        row: (_Line l) {
          calls++;
          return <String, Object?>{'qty': l.qty};
        },
      );
      expect(calls, 0); // construction maps nothing
      final DataSet ds = source.open();
      expect(calls, 0); // open maps nothing
      ds.moveNext();
      expect(calls, 1); // first row mapped on demand
    });

    test('open() yields independent cursors', () {
      final JetObjectDataSource<_Line> source =
          _source(const <_Line>[_Line('A1', 2)]);
      final DataSet a = source.open();
      final DataSet b = source.open();
      expect(a.moveNext(), isTrue);
      expect(b.moveNext(), isTrue);
      expect(b.current.field('sku'), 'A1');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/data/object_data_source_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jet_print/src/data/object_data_source.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/data/object_data_source.dart`:

```dart
/// Data source over a typed list of objects (spec 004).
library;

import 'data_set.dart';
import 'field_def.dart';
import 'jet_data_source.dart';
import 'row_cursor_data_set.dart';

/// A [JetDataSource] over a `List<T>` of domain objects.
///
/// Because `T` is opaque, the caller supplies both an explicit typed [fields]
/// schema and a [row] extractor that maps one object to a field-value map.
/// Mapping is lazy: [row] runs per object during iteration, not eagerly at
/// construction. [open] ignores its `params`.
class JetObjectDataSource<T> implements JetDataSource {
  /// Creates a source over [objects], described by [fields] and mapped by [row].
  JetObjectDataSource(
    List<T> objects, {
    required List<FieldDef> fields,
    required Map<String, Object?> Function(T object) row,
  })  : _objects = List<T>.unmodifiable(objects),
        _fields = List<FieldDef>.unmodifiable(fields),
        _row = row;

  final List<T> _objects;
  final List<FieldDef> _fields;
  final Map<String, Object?> Function(T object) _row;

  /// The explicit schema, in column order.
  List<FieldDef> get fields => _fields;

  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      RowCursorDataSet(
        fields: _fields,
        rowCount: _objects.length,
        rowAt: (int i) => _row(_objects[i]),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/data/object_data_source_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/data/object_data_source.dart packages/jet_print/test/data/object_data_source_test.dart
git commit -m "feat(data): add JetObjectDataSource over a typed object list"
```

---

### Task 8: Enforce the `data` seam boundary + finish gates

Extend the layer-boundary architecture test with a `data`-seam group (now that the seam has real files, the "no false green" check is non-vacuous), update the CHANGELOG, and run the full quality gate (suite + analyzer + format).

**Files:**
- Modify: `packages/jet_print/test/architecture/layer_boundaries_test.dart`
- Modify: `packages/jet_print/CHANGELOG.md`

- [ ] **Step 1: Add the failing data-seam boundary group**

In `packages/jet_print/test/architecture/layer_boundaries_test.dart`, inside `main()`, add a `dataDir` next to `domainDir` and a second group. The `data` seam may import `domain` (the URI contains neither `rendering` nor `designer`, so `_reachesOtherSeam` already permits it) but must not reach the rendering/designer seams or any Flutter UI library.

Add after the `domainDir` declaration:

```dart
  final Directory dataDir =
      Directory('${root.path}/packages/jet_print/lib/src/data');

  List<File> dataFiles() => dataDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((FileSystemEntity f) => f.path.endsWith('.dart'))
      .toList();
```

Add after the closing `});` of the existing `group('layer boundaries — domain seam', ...)`:

```dart
  group('layer boundaries — data seam', () {
    test('the data seam has source files to check (no false green)', () {
      expect(dataDir.existsSync(), isTrue, reason: 'Missing ${dataDir.path}');
      expect(dataFiles(), isNotEmpty,
          reason: 'No .dart files found under ${dataDir.path}');
    });

    test('data imports no outer seam and no Flutter UI library', () {
      final List<String> violations = <String>[];
      for (final File file in dataFiles()) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (_reachesOtherSeam(uri) || _isFlutterUi(uri)) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'The data seam may depend only on domain. Violations:\n'
            '${violations.join('\n')}',
      );
    });
  });
```

- [ ] **Step 2: Run the architecture test to verify the new group passes**

Run: `cd packages/jet_print && flutter test test/architecture/layer_boundaries_test.dart`
Expected: PASS — both the domain and the new data group are green (the data files import only `dart:convert` and sibling `data/`/`domain` URIs, none of which match `_reachesOtherSeam`/`_isFlutterUi`).

> If this group ever fails, a data file imported `rendering`, `designer`, or a Flutter UI library — fix the import, do not loosen the test.

- [ ] **Step 3: Update the CHANGELOG**

In `packages/jet_print/CHANGELOG.md`, under `## Unreleased` → `### Added`, append this bullet after the spec-003 Part 2 bullet (the one ending `…to wire all four built-in element codecs.`):

```markdown
- Data layer (spec 004): the headless data-access seam — `JetDataSource`
  (factory) → `DataSet` (forward-only cursor) → immutable `DataRow` snapshots,
  with typed `FieldDef`/`JetFieldType` metadata (best-effort column-type
  inference). Three in-memory implementations: `JetInMemoryDataSource`
  (`List<Map>`), `JetJsonDataSource` (JSON array string), and
  `JetObjectDataSource<T>` (typed object list). The architecture test now also
  enforces the `data → domain` boundary.
```

- [ ] **Step 4: Run the full quality gate**

Run: `cd packages/jet_print && flutter test`
Expected: PASS — all suites green (the prior 146 plus the new data tests; no regressions in `encapsulation_test` or `public_api_test`).

Run: `cd packages/jet_print && dart format --output=none --set-exit-if-changed lib/src/data test/data test/architecture/layer_boundaries_test.dart test/encapsulation_test.dart`
Expected: exit 0 (no formatting changes needed). If it reports changes, run `dart format lib/src/data test/data` and re-run.

Run: `cd packages/jet_print && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/test/architecture/layer_boundaries_test.dart packages/jet_print/CHANGELOG.md
git commit -m "test(data): enforce data->domain seam boundary; changelog for spec 004"
```

---

## Self-Review (completed before handoff)

**Spec coverage** (blueprint §4 #3, §6 contract 3, §11 row 004):
- `JetDataSource` factory → Task 4. `DataSet` row cursor → Task 4. `DataRow` → Task 3. Field metadata (`FieldDef`) → Task 2. In-memory impls (`List<Map>`, JSON, object-list) → Tasks 5–7. Tests for iteration & field access → Tasks 3–7. Inward dependency rule (`data → domain`) → Task 8. All covered.

**Placeholder scan:** none — every code step contains complete source and exact run/commit commands.

**Type consistency:** `JetFieldType`, `FieldDef(name, {type})`, `FieldDef.inferType(Iterable<Object?>)`, `DataRow({fields, values})` + `field`/`hasField`/`fields`, `DataSet` (`fields`/`moveNext`/`current`/`close`), `JetDataSource.open([params])`, `RowCursorDataSet({fields, rowCount, rowAt})`, `JetInMemoryDataSource(rows, {fields})`, `JetJsonDataSource.parse(json, {fields})`, `JetObjectDataSource<T>(objects, {fields, row})` — names and signatures are consistent across every task that references them.

**Convention checks:** white-box test allowlist extended (Task 1) before any `/test/data/` test runs under the full suite; relative imports + `directives_ordering` (dart: first, then alphabetical relative) honoured in every library file; value-type equality mirrors `src/domain/`; no new package dependencies; the public facade `jet_print.dart` is intentionally untouched (deferred export, per repo convention).
