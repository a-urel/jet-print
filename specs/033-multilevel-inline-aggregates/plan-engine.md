# Multi-Level Inline Aggregates — Engine Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the same `{AGG([leafField])}` inline aggregate, placed in any aggregate-sink band (summary, root group footer, nested-scope footer), fold over **all descendant leaf rows** of that band's scope instance — a flat fold at arbitrary nesting depth — computed by the filler and validated at author time.

**Architecture:** Add a pure data-layer **path resolver** (`resolveAggregatePath`) that maps a scope's fields + an operand name to `sameScope | descend(path) | notFound | ambiguous`. Add a pure fill helper (`foldDescendantLeaves`) that folds an operand over every descendant leaf reached by descending a collection-field path. The filler computes descendant aggregates with **leaf-folding accumulators reset by sink scope** (report → summary, group → root group footer, scope-row → nested footer), reusing the existing `VariableAccumulator`. Same-scope aggregates keep their current path (spec 028 `expandAggregates` for summary/group-footer, spec 029 `prepareNestedFooter` for nested footers) so existing goldens are byte-identical. `validate()` gains an optional schema and extends rule I8 to accept a unique descendant operand and error on ambiguous/not-found ones.

**Tech Stack:** Dart (Flutter workspace). Package under test: `packages/jet_print`. Tests use `flutter test` run **from the package directory** `packages/jet_print`. The playground app lives at `apps/jet_print_playground` (run its tests from that directory). No new dependencies.

## Global Constraints

- **No new serialization fields or grammar tokens** (spec Scope / FR-009). The feature is authoring + resolution + a flat descendant fold only; the stored grammar is the existing `{AGG([field])}` → `AGG($F{field})`.
- **Existing goldens MUST remain byte-identical** except the playground sample's optional migration, which MUST stay numerically identical (SC-001, SC-005).
- **Flat fold semantics** (spec Clarifications, FR-004): SUM/COUNT/MIN/MAX over descendant leaves equal the hierarchical roll-up; AVG is flat `sum÷count` over **all** descendant leaves (never average-of-averages). Empty leaf sets follow existing `VariableAccumulator` behavior: SUM→0, COUNT→0, AVG/MIN/MAX→null.
- **Never a silently-wrong number** (FR-010): an ambiguous or not-found operand surfaces as a validation diagnostic at author time and a fill-time fallback token (default `#ERROR`) at render time — never a guessed collection.
- **Same-scope wins** (FR-001): if the operand is a non-collection field at the band's own scope, the result is `sameScope` regardless of any deeper match — the existing mechanisms handle it unchanged.
- **Reserved synth-name prefix:** descendant-aggregate synth variables are named `__dagg<n>` (sibling to spec 028 `__agg<n>` and spec 029 `__nagg<n>`). Do not collide with those prefixes.
- Aggregate vocabulary is single-sourced in `aggregate_functions.dart` (`aggregateCalculationFor`, `topLevelAggregate`). Reuse it; never re-list `SUM`/`AVG`/`COUNT`/`MIN`/`MAX`.

---

## File Structure

**Create:**
- `packages/jet_print/lib/src/data/aggregate_path.dart` — pure resolver: `AggregatePath` sealed type + `resolveAggregatePath(List<FieldDef>, String)`. Data layer (operates on `FieldDef`), reusable by the filler, validation, and (designer plan) author-time resolution.
- `packages/jet_print/lib/src/expression/aggregate/descendant_aggregate.dart` — pure fill helper: `foldDescendantLeaves(...)`. No Flutter, no `EvalContext` knowledge (takes a leaf-eval callback).
- Test files mirroring each (see tasks).

**Modify:**
- `packages/jet_print/lib/src/expression/aggregate/aggregate_synthesizer.dart` — generalize the private scanner `_expandInlineAggregates` to a leave-in-place callback; add `liftDescendantAggregates(def, rootFields)` + `DescendantAggregate` / `DescendantLift` result types.
- `packages/jet_print/lib/src/rendering/fill/report_filler.dart` — open the data source before expanding aggregates (to read `ds.fields`), run the descendant-lift pre-pass, wire descendant folds for the three sinks with correct reset.
- `packages/jet_print/lib/src/domain/report_validation.dart` — add optional `JetDataSchema? schema` to `validate()`; extend I8 to resolve operands when a schema is supplied.
- `apps/jet_print_playground/lib/nested_list_sample.dart` — migrate the three totals to inline `{SUM([lineTotal])}` authoring (Task 10).

**Layering note:** `data/aggregate_path.dart` imports only `data/field_def.dart` (which re-exports `domain/value_type.dart`). `domain/report_validation.dart` will import `data/aggregate_path.dart` and `data/data_schema.dart`; this is a leaf dependency (`value_type` never imports validation), so the file-level import graph stays acyclic. Task 8 verifies with `flutter analyze`.

---

### Task 1: Aggregate path resolver (data layer)

**Files:**
- Create: `packages/jet_print/lib/src/data/aggregate_path.dart`
- Test: `packages/jet_print/test/data/aggregate_path_test.dart`

**Interfaces:**
- Consumes: `FieldDef` (name, type, fields), `JetFieldType.collection` from `field_def.dart`.
- Produces:
  - `sealed class AggregatePath` with `const SameScope()`, `const DescendPath(List<String> path)`, `const NotFound()`, `const Ambiguous(List<List<String>> paths)`.
  - `AggregatePath resolveAggregatePath(List<FieldDef> scopeFields, String operand)`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/data/aggregate_path_test.dart`:

```dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/aggregate_path.dart';
import 'package:jet_print/src/data/field_def.dart';

// Customer ▸ Order ▸ Line schema fields (root = customer fields).
const List<FieldDef> _root = <FieldDef>[
  FieldDef('customerName', type: JetFieldType.string),
  FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('orderNo', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('lineTotal', type: JetFieldType.double),
      FieldDef('qty', type: JetFieldType.integer),
    ]),
  ]),
];

void main() {
  test('a non-collection field at this scope is same-scope', () {
    expect(resolveAggregatePath(_root, 'customerName'), isA<SameScope>());
  });

  test('a leaf two collection levels down is a unique descend path', () {
    final AggregatePath r = resolveAggregatePath(_root, 'lineTotal');
    expect(r, isA<DescendPath>());
    expect((r as DescendPath).path, <String>['orders', 'lines']);
  });

  test('a leaf one collection level down is a unique descend path', () {
    final AggregatePath r = resolveAggregatePath(_root, 'orderNo');
    expect((r as DescendPath).path, <String>['orders']);
  });

  test('an unknown operand is not found', () {
    expect(resolveAggregatePath(_root, 'missing'), isA<NotFound>());
  });

  test('same-scope wins even when the name also appears deeper', () {
    const List<FieldDef> fields = <FieldDef>[
      FieldDef('amount', type: JetFieldType.double),
      FieldDef('rows', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
    ];
    expect(resolveAggregatePath(fields, 'amount'), isA<SameScope>());
  });

  test('two distinct sibling descend paths are ambiguous', () {
    const List<FieldDef> fields = <FieldDef>[
      FieldDef('a', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
      FieldDef('b', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
    ];
    final AggregatePath r = resolveAggregatePath(fields, 'amount');
    expect(r, isA<Ambiguous>());
    expect((r as Ambiguous).paths, hasLength(2));
  });

  test('a collection field of the operand name is not a leaf (not found)', () {
    expect(resolveAggregatePath(_root, 'orders'), isA<NotFound>());
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/data/aggregate_path_test.dart`
Expected: FAIL — `aggregate_path.dart` does not exist / `Undefined name 'resolveAggregatePath'`.

- [ ] **Step 3: Write the implementation**

Create `packages/jet_print/lib/src/data/aggregate_path.dart`:

```dart
/// Resolving an inline-aggregate operand against a scope's fields (spec 033).
///
/// Given the fields in scope at an aggregate-sink band and a leaf operand name,
/// this pure resolver answers where that operand lives: a non-collection field
/// at this scope (`SameScope`), a uniquely-reachable non-collection leaf in the
/// descendant collection subtree (`DescendPath`, the chain of collection-field
/// names to descend), `NotFound`, or `Ambiguous` (≥2 distinct descend paths).
///
/// Same-scope wins: a non-collection field at this scope short-circuits, even
/// if the name also appears deeper. The descend search never crosses a
/// same-name match into ambiguity — that is the "the engine does not guess"
/// rule (FR-001). Pure Dart, no Flutter; data layer (operates on [FieldDef]).
library;

import 'field_def.dart';

/// Where an aggregate operand resolves relative to a band's scope.
sealed class AggregatePath {
  const AggregatePath();
}

/// The operand is a non-collection field at the band's own scope; the existing
/// same-scope mechanisms (spec 028 / 029) compute it unchanged.
class SameScope extends AggregatePath {
  const SameScope();
}

/// The operand is a unique non-collection leaf reached by descending [path]
/// (collection-field names, outermost-first) from the band's scope.
class DescendPath extends AggregatePath {
  const DescendPath(this.path);

  /// The collection-field names to descend, outermost-first.
  final List<String> path;
}

/// The operand is neither a field at this scope nor a descendant leaf (e.g. a
/// typo, or a published-total name resolved elsewhere).
class NotFound extends AggregatePath {
  const NotFound();
}

/// The operand names a leaf reachable by ≥2 distinct descend [paths]; the engine
/// refuses to guess which collection was meant (validation error / fill fallback).
class Ambiguous extends AggregatePath {
  const Ambiguous(this.paths);

  /// The distinct descend paths that each reach a leaf named `operand`.
  final List<List<String>> paths;
}

/// Resolves [operand] against [scopeFields]. See [AggregatePath].
AggregatePath resolveAggregatePath(
    List<FieldDef> scopeFields, String operand) {
  for (final FieldDef f in scopeFields) {
    if (f.name == operand && f.type != JetFieldType.collection) {
      return const SameScope();
    }
  }
  final List<List<String>> found = <List<String>>[];
  void descend(List<FieldDef> fields, List<String> trail) {
    for (final FieldDef f in fields) {
      if (f.type != JetFieldType.collection) continue;
      final List<String> next = <String>[...trail, f.name];
      for (final FieldDef child in f.fields) {
        if (child.name == operand && child.type != JetFieldType.collection) {
          found.add(next);
        }
      }
      descend(f.fields, next);
    }
  }

  descend(scopeFields, const <String>[]);
  if (found.isEmpty) return const NotFound();
  if (found.length == 1) return DescendPath(found.single);
  return Ambiguous(found);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run (from `packages/jet_print`): `flutter test test/data/aggregate_path_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/data/aggregate_path.dart packages/jet_print/test/data/aggregate_path_test.dart
git commit -m "feat(033): aggregate-operand path resolver (sameScope/descend/notFound/ambiguous)"
```

---

### Task 2: Descendant leaf-folding helper (fill, pure)

**Files:**
- Create: `packages/jet_print/lib/src/expression/aggregate/descendant_aggregate.dart`
- Test: `packages/jet_print/test/expression/aggregate/descendant_aggregate_test.dart`

**Interfaces:**
- Consumes: `DataRow` (`data/data_row.dart`), `VariableAccumulator` (`variable_accumulator.dart`), `JetValue` (`expression/value.dart`).
- Produces:
  ```dart
  void foldDescendantLeaves({
    required List<DataRow> rows,
    required List<String> path,
    required VariableAccumulator acc,
    required JetValue Function(DataRow leaf) eval,
    required List<DataRow> Function(DataRow row, String collectionField) childRowsOf,
  });
  ```
  Recursively descends `path` from each row in `rows`; at the leaf level (`path` empty) folds `eval(leafRow)` into `acc`. Flat — every leaf folded directly, no intermediate subtotals. An empty `path` folds `eval` over `rows` themselves (the same-scope / one-level case).

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/aggregate/descendant_aggregate_test.dart`:

```dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/expression/aggregate/descendant_aggregate.dart';
import 'package:jet_print/src/expression/aggregate/variable_accumulator.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/value.dart';

// Build a customer row carrying orders → lines, lines holding `lineTotal`.
DataRow _customer(List<List<double>> ordersOfLineTotals) => DataRow(
      fields: const <FieldDef>[
        FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
          FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
            FieldDef('lineTotal', type: JetFieldType.double),
          ]),
        ]),
      ],
      values: <String, Object?>{
        'orders': <Map<String, Object?>>[
          for (final List<double> lines in ordersOfLineTotals)
            <String, Object?>{
              'lines': <Map<String, Object?>>[
                for (final double t in lines)
                  <String, Object?>{'lineTotal': t},
              ],
            },
        ],
      },
    );

// A row's named collection as DataRows (mirrors the filler's childRowsOf, minus
// diagnostics). Returns [] when the field is absent or not a list of maps.
List<DataRow> _childRows(DataRow row, String name) {
  final Object? raw = row.field(name);
  if (raw is! List) return const <DataRow>[];
  final FieldDef declared = row.fields.firstWhere(
    (FieldDef f) => f.name == name,
    orElse: () => const FieldDef(''),
  );
  return <DataRow>[
    for (final Object? entry in raw)
      if (entry is Map)
        DataRow(
          fields: declared.fields,
          values: entry.map((Object? k, Object? v) =>
              MapEntry<String, Object?>(k.toString(), v)),
        ),
  ];
}

JetValue _lineTotal(DataRow leaf) => JetValue.from(leaf.field('lineTotal'));

void main() {
  test('flat SUM folds every descendant leaf across two collection levels', () {
    final VariableAccumulator acc = VariableAccumulator(JetCalculation.sum);
    foldDescendantLeaves(
      rows: <DataRow>[
        _customer(<List<double>>[
          <double>[10, 20],
          <double>[5],
        ]),
      ],
      path: <String>['orders', 'lines'],
      acc: acc,
      eval: _lineTotal,
      childRowsOf: _childRows,
    );
    expect((acc.value as JetNumber).value, 35.0);
  });

  test('flat AVG is sum over all leaves ÷ leaf count (not avg-of-averages)', () {
    final VariableAccumulator acc = VariableAccumulator(JetCalculation.average);
    foldDescendantLeaves(
      rows: <DataRow>[
        _customer(<List<double>>[
          <double>[10, 20], // order avg 15
          <double>[60], // order avg 60; avg-of-avgs would be 37.5
        ]),
      ],
      path: <String>['orders', 'lines'],
      acc: acc,
      eval: _lineTotal,
      childRowsOf: _childRows,
    );
    expect((acc.value as JetNumber).value, (10 + 20 + 60) / 3);
  });

  test('an empty path folds over the rows themselves (one-level case)', () {
    final VariableAccumulator acc = VariableAccumulator(JetCalculation.sum);
    foldDescendantLeaves(
      rows: <DataRow>[
        DataRow(
            fields: const <FieldDef>[FieldDef('lineTotal', type: JetFieldType.double)],
            values: <String, Object?>{'lineTotal': 7.0}),
        DataRow(
            fields: const <FieldDef>[FieldDef('lineTotal', type: JetFieldType.double)],
            values: <String, Object?>{'lineTotal': 3.0}),
      ],
      path: const <String>[],
      acc: acc,
      eval: _lineTotal,
      childRowsOf: _childRows,
    );
    expect((acc.value as JetNumber).value, 10.0);
  });

  test('empty descendant collections fold nothing (SUM 0)', () {
    final VariableAccumulator acc = VariableAccumulator(JetCalculation.sum);
    foldDescendantLeaves(
      rows: <DataRow>[_customer(const <List<double>>[])],
      path: <String>['orders', 'lines'],
      acc: acc,
      eval: _lineTotal,
      childRowsOf: _childRows,
    );
    expect((acc.value as JetNumber).value, 0.0);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/expression/aggregate/descendant_aggregate_test.dart`
Expected: FAIL — `descendant_aggregate.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `packages/jet_print/lib/src/expression/aggregate/descendant_aggregate.dart`:

```dart
/// Flat descendant leaf folding for multi-level inline aggregates (spec 033).
///
/// A sink-band aggregate (`{SUM([lineTotal])}` at a summary, root group footer,
/// or nested-scope footer) folds its operand over **every descendant leaf row**
/// reachable from the band's scope instance by descending a chain of collection
/// fields (the [DescendPath] from `resolveAggregatePath`). The fold is FLAT —
/// each leaf is folded directly into the accumulator, never via per-level
/// subtotals — so SUM/COUNT/MIN/MAX equal the hierarchical roll-up and AVG is a
/// true average over all leaves (FR-002, FR-004).
///
/// Pure: it knows nothing of `EvalContext` or diagnostics. The caller supplies
/// [eval] (operand value for one leaf row) and [childRowsOf] (a row's named
/// collection as child rows) so the filler can inject its own context/diagnostics.
library;

import '../../data/data_row.dart';
import '../value.dart';
import 'variable_accumulator.dart';

/// Folds [eval] over every descendant leaf reached from each row in [rows] by
/// descending the collection-field [path] (outermost-first), into [acc]. An
/// empty [path] folds [eval] over [rows] themselves.
void foldDescendantLeaves({
  required List<DataRow> rows,
  required List<String> path,
  required VariableAccumulator acc,
  required JetValue Function(DataRow leaf) eval,
  required List<DataRow> Function(DataRow row, String collectionField)
      childRowsOf,
}) {
  if (path.isEmpty) {
    for (final DataRow r in rows) {
      acc.fold(eval(r));
    }
    return;
  }
  final String head = path.first;
  final List<String> rest = path.sublist(1);
  for (final DataRow r in rows) {
    foldDescendantLeaves(
      rows: childRowsOf(r, head),
      path: rest,
      acc: acc,
      eval: eval,
      childRowsOf: childRowsOf,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run (from `packages/jet_print`): `flutter test test/expression/aggregate/descendant_aggregate_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/expression/aggregate/descendant_aggregate.dart packages/jet_print/test/expression/aggregate/descendant_aggregate_test.dart
git commit -m "feat(033): flat descendant leaf-folding helper"
```

---

### Task 3: Shared scanner + descendant-lift pre-pass (synthesizer)

Generalize the synthesizer's private scanner so a callback can **leave an aggregate call in place**, then add `liftDescendantAggregates` — a schema-aware pre-pass that rewrites only descendant-operand aggregates in the summary band and root group footers to `$V{__dagg<n>}`, returning their fold specs. Same-scope aggregates are left untouched for the unchanged `expandAggregates` to lift (preserving goldens).

**Files:**
- Modify: `packages/jet_print/lib/src/expression/aggregate/aggregate_synthesizer.dart`
- Test: `packages/jet_print/test/expression/aggregate/descendant_lift_test.dart` (create)

**Interfaces:**
- Consumes: `resolveAggregatePath` (Task 1), `aggregateCalculationFor` / `topLevelAggregate` (`aggregate_functions.dart`), `FieldDef`, `VariableResetScope` / `JetCalculation` (`report_variable.dart`), `Expression`.
- Produces (added to `aggregate_synthesizer.dart`):
  ```dart
  class DescendantAggregate {
    const DescendantAggregate({
      required this.name,          // __dagg<n>
      required this.calculation,
      required this.argument,      // parsed operand expression (e.g. $F{lineTotal})
      required this.path,          // descend path, [] when ambiguous
      required this.resetScope,    // VariableResetScope.report | .group
      required this.resetGroup,    // group name for a root group footer, else null
      required this.ambiguous,     // true → fill renders the fallback token
    });
    final String name;
    final JetCalculation calculation;
    final Expression argument;
    final List<String> path;
    final VariableResetScope resetScope;
    final String? resetGroup;
    final bool ambiguous;
  }
  class DescendantLift {
    const DescendantLift(this.definition, this.aggregates);
    final ReportDefinition definition;       // band elements rewritten to $V{__dagg<n>}
    final List<DescendantAggregate> aggregates;
  }
  DescendantLift liftDescendantAggregates(ReportDefinition def, List<FieldDef> rootFields);
  ```
  Operand selection: for an aggregate's inner expression, the operand is the single `$F{}` field reference when there is exactly one (`Expression.parse(inner).references.fields`). Resolve it against `rootFields`. `DescendPath` → lift (register a `DescendantAggregate`, substitute `$V{__dagg<n>}`). `Ambiguous` → lift with `ambiguous: true`, `path: []` (fill renders fallback). `SameScope` / `NotFound` / not-exactly-one-ref → **leave the call in place** (return null from the scanner callback), so `expandAggregates` / published-total resolution handle it unchanged.

- [ ] **Step 1: Generalize the scanner callback to allow leave-in-place**

In `aggregate_synthesizer.dart`, change the `_expandInlineAggregates` signature so the callback may return `null` to leave the aggregate call text unchanged:

Replace the signature and the call site (lines 126–149 region):

```dart
String _expandInlineAggregates(
  String expr,
  String? Function(JetCalculation calc, String inner) register,
) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < expr.length) {
    final String c = expr[i];
    if (c == '"' || c == "'") {
      i = _copyStringLiteral(expr, i, out);
    } else if (_isIdentStart(c)) {
      final int identEnd = _identEnd(expr, i);
      final String ident = expr.substring(i, identEnd);
      final JetCalculation? calc = aggregateCalculationFor(ident);
      if (calc != null && identEnd < expr.length && expr[identEnd] == '(') {
        final int close = _matchParen(expr, identEnd);
        final String inner = expr.substring(identEnd + 1, close);
        if (_isSingleArgAggregate(ident, inner)) {
          final String? name = register(calc, inner);
          if (name != null) {
            out.write('\$V{$name}');
            i = close + 1;
            continue;
          }
          // name == null → leave this aggregate call exactly as written.
          out.write(expr.substring(i, close + 1));
          i = close + 1;
          continue;
        }
      }
      out.write(ident);
      i = identEnd;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}
```

In `expandAggregates`, the existing `register` callback already always returns a non-null name, so its return type now widens to `String?` with no behavior change. No other edit to `expandAggregates` is needed.

- [ ] **Step 2: Write the failing test for `liftDescendantAggregates`**

Create `packages/jet_print/test/expression/aggregate/descendant_lift_test.dart`:

```dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/aggregate_synthesizer.dart';

const List<FieldDef> _root = <FieldDef>[
  FieldDef('customerCode', type: JetFieldType.string),
  FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('lineTotal', type: JetFieldType.double),
    ]),
  ]),
];

TextElement _el(String id, String expr) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 80, height: 12),
      text: id,
      expression: expr,
    );

ReportDefinition _def({Band? summary, Band? customerFooter}) => ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: summary,
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            if (customerFooter != null)
              GroupLevel(
                id: 'customer',
                name: 'customer',
                key: r'$F{customerCode}',
                footer: customerFooter,
              ),
          ],
        ),
      ),
    );

void main() {
  test('lifts a descendant aggregate in the summary to a __dagg var', () {
    final ReportDefinition def = _def(
      summary: const Band(id: 'summary', type: BandType.summary, height: 20)
          .copyWith(elements: <ReportElement>[_el('g', r'SUM($F{lineTotal})')]),
    );
    final DescendantLift lift = liftDescendantAggregates(def, _root);
    expect(lift.aggregates, hasLength(1));
    final DescendantAggregate a = lift.aggregates.single;
    expect(a.calculation, JetCalculation.sum);
    expect(a.path, <String>['orders', 'lines']);
    expect(a.resetScope, VariableResetScope.report);
    expect(a.resetGroup, isNull);
    expect(a.ambiguous, isFalse);
    final TextElement g = lift.definition.body.summary!.elements.single
        as TextElement;
    expect(g.expression, '\$V{${a.name}}');
  });

  test('lifts a descendant aggregate in a root group footer with group reset',
      () {
    final ReportDefinition def = _def(
      customerFooter:
          const Band(id: 'cf', type: BandType.groupFooter, height: 20)
              .copyWith(elements: <ReportElement>[_el('t', r'SUM($F{lineTotal})')]),
    );
    final DescendantLift lift = liftDescendantAggregates(def, _root);
    expect(lift.aggregates.single.resetScope, VariableResetScope.group);
    expect(lift.aggregates.single.resetGroup, 'customer');
    expect(lift.aggregates.single.path, <String>['orders', 'lines']);
  });

  test('leaves a same-scope aggregate untouched for expandAggregates', () {
    final ReportDefinition def = _def(
      summary: const Band(id: 'summary', type: BandType.summary, height: 20)
          .copyWith(elements: <ReportElement>[_el('g', r'SUM($F{customerCode})')]),
    );
    final DescendantLift lift = liftDescendantAggregates(def, _root);
    expect(lift.aggregates, isEmpty);
    expect(lift.definition.body.summary!.elements.single,
        isA<TextElement>().having((TextElement e) => e.expression, 'expr',
            r'SUM($F{customerCode})'));
  });

  test('marks an ambiguous operand and clears its path', () {
    const List<FieldDef> ambig = <FieldDef>[
      FieldDef('a', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
      FieldDef('b', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
    ];
    final ReportDefinition def = _def(
      summary: const Band(id: 'summary', type: BandType.summary, height: 20)
          .copyWith(elements: <ReportElement>[_el('g', r'SUM($F{amount})')]),
    );
    final DescendantLift lift = liftDescendantAggregates(def, ambig);
    expect(lift.aggregates.single.ambiguous, isTrue);
    expect(lift.aggregates.single.path, isEmpty);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/expression/aggregate/descendant_lift_test.dart`
Expected: FAIL — `liftDescendantAggregates` / `DescendantAggregate` undefined.

- [ ] **Step 4: Implement `liftDescendantAggregates` + result types**

Add to `aggregate_synthesizer.dart` (new imports at top: `import '../../data/aggregate_path.dart';`, `import '../../data/field_def.dart';`; the file already imports `report_definition.dart`, `group_level.dart`, `band.dart`, `text_element.dart`, `report_element.dart`, `report_variable.dart`, `expression.dart`, `expression_exception.dart`, `aggregate_functions.dart`):

```dart
/// One descendant inline aggregate lifted out of a summary band or root group
/// footer: its synth variable [name] (`__dagg<n>`) the element now references,
/// the [calculation], the parsed operand [argument] evaluated per descendant
/// leaf, the collection-field [path] to descend (empty when [ambiguous]), the
/// reset [resetScope]/[resetGroup], and whether the operand was [ambiguous]
/// (the filler then renders the unresolved fallback rather than folding).
class DescendantAggregate {
  /// Creates a descendant-aggregate spec.
  const DescendantAggregate({
    required this.name,
    required this.calculation,
    required this.argument,
    required this.path,
    required this.resetScope,
    required this.resetGroup,
    required this.ambiguous,
  });

  /// The synth variable name (`__dagg<n>`) the rewritten element references.
  final String name;

  /// The fold strategy (SUM / AVG / COUNT / MIN / MAX).
  final JetCalculation calculation;

  /// The operand expression evaluated per descendant leaf row before folding.
  final Expression argument;

  /// The collection-field names to descend from the band's scope, outermost
  /// first; empty when [ambiguous].
  final List<String> path;

  /// `report` for the summary band, `group` for a root group footer.
  final VariableResetScope resetScope;

  /// The owning root group's name for a group footer, else null.
  final String? resetGroup;

  /// True when the operand resolved to ≥2 descend paths; the filler renders the
  /// unresolved fallback for this aggregate (FR-010), never a guessed total.
  final bool ambiguous;
}

/// The result of lifting descendant aggregates: the [definition] with their
/// elements rewritten to `$V{__dagg<n>}`, and the [aggregates] the filler folds.
class DescendantLift {
  /// Creates a descendant-lift result.
  const DescendantLift(this.definition, this.aggregates);

  /// The definition with descendant-aggregate elements rewritten.
  final ReportDefinition definition;

  /// The descendant aggregates to compute in the filler.
  final List<DescendantAggregate> aggregates;
}

/// Lifts every descendant-operand inline aggregate in [def]'s summary band and
/// root group footers (resolved against the master-scope [rootFields]) to a
/// `$V{__dagg<n>}` reference, returning the rewritten definition and the fold
/// specs. Same-scope / not-found operands are left in place for
/// [expandAggregates] and published-total resolution; ambiguous operands are
/// lifted but flagged (the filler renders the fallback). Pure.
DescendantLift liftDescendantAggregates(
    ReportDefinition def, List<FieldDef> rootFields) {
  final List<DescendantAggregate> specs = <DescendantAggregate>[];

  String? Function(JetCalculation, String) registrar(
      VariableResetScope scope, String? group) {
    return (JetCalculation calc, String inner) {
      // Operand = the single $F{} reference, when there is exactly one.
      final Set<String> refs;
      try {
        refs = Expression.parse(inner).references.fields;
      } on ExpressionException {
        return null;
      }
      if (refs.length != 1) return null;
      final AggregatePath resolved =
          resolveAggregatePath(rootFields, refs.single);
      if (resolved is DescendPath) {
        final String name = '__dagg${specs.length}';
        specs.add(DescendantAggregate(
          name: name,
          calculation: calc,
          argument: Expression.parse(inner),
          path: resolved.path,
          resetScope: scope,
          resetGroup: group,
          ambiguous: false,
        ));
        return name;
      }
      if (resolved is Ambiguous) {
        final String name = '__dagg${specs.length}';
        specs.add(DescendantAggregate(
          name: name,
          calculation: calc,
          argument: Expression.parse(inner),
          path: const <String>[],
          resetScope: scope,
          resetGroup: group,
          ambiguous: true,
        ));
        return name;
      }
      return null; // SameScope / NotFound → leave in place.
    };
  }

  Band? rewriteBand(
      Band? band, VariableResetScope scope, String? group) {
    if (band == null) return null;
    bool changed = false;
    final List<ReportElement> els = <ReportElement>[];
    for (final ReportElement e in band.elements) {
      if (e is TextElement && e.expression != null) {
        String parseable = e.expression!;
        try {
          Expression.parse(parseable);
        } on ExpressionException {
          els.add(e);
          continue;
        }
        final String next =
            _expandInlineAggregates(parseable, registrar(scope, group));
        if (next != parseable) {
          changed = true;
          els.add(TextElement(
            id: e.id,
            bounds: e.bounds,
            text: e.text,
            style: e.style,
            expression: next,
            format: e.format,
          ));
          continue;
        }
      }
      els.add(e);
    }
    return changed ? band.copyWith(elements: els) : band;
  }

  final Band? summary =
      rewriteBand(def.body.summary, VariableResetScope.report, null);
  final List<GroupLevel> groups = <GroupLevel>[
    for (final GroupLevel g in def.body.root.groups)
      g.copyWith(
        footer: rewriteBand(g.footer, VariableResetScope.group, g.name),
      ),
  ];

  if (specs.isEmpty) return DescendantLift(def, const <DescendantAggregate>[]);
  return DescendantLift(
    def.copyWith(
      body: def.body.copyWith(
        summary: summary,
        root: def.body.root.copyWith(groups: groups),
      ),
    ),
    specs,
  );
}
```

- [ ] **Step 5: Run both synthesizer test files to verify pass + no regression**

Run (from `packages/jet_print`): `flutter test test/expression/aggregate/descendant_lift_test.dart test/expression/aggregate/aggregate_synthesizer_test.dart`
Expected: PASS — new lift tests pass; existing `aggregate_synthesizer_test.dart` still green (the scanner callback change is behavior-preserving for `expandAggregates`).

- [ ] **Step 6: Commit**

```bash
git add packages/jet_print/lib/src/expression/aggregate/aggregate_synthesizer.dart packages/jet_print/test/expression/aggregate/descendant_lift_test.dart
git commit -m "feat(033): descendant-aggregate lift pre-pass + leave-in-place scanner callback"
```

---

### Task 4: Nested-scope footer multi-level fold (filler)

Generalize the nested-scope footer path so a footer aggregate whose operand is a **descendant** leaf folds over all descendant leaves of the scope instance (reset per parent row). A same-scope operand keeps the existing one-level fold (spec 029), so existing nested-footer goldens are unchanged.

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test: `packages/jet_print/test/rendering/fill/descendant_footer_fill_test.dart` (create)

**Interfaces:**
- Consumes: `resolveAggregatePath` (Task 1), `foldDescendantLeaves` (Task 2), the filler's existing `childRowsOf` closure, `NestedAgg` (spec 029), `VariableAccumulator`.
- Produces: no new public API — internal change to `emitNode`'s `NestedScope` branch.

**Integration detail.** In `report_filler.dart`, `emitNode`'s `NestedScope` branch (current lines ~334–372) folds each `NestedAgg` over the immediate `childRows`. Replace the per-child fold loop so each `NestedAgg`:
1. Determines its operand path **once** per emit using the first child row's fields: `final List<FieldDef> childFields = childRows.first.fields;` (childRows is already known non-empty here — the branch `break`s on empty). The operand name is the single field ref of `a.argument` (`a.argument.references.fields`); if not exactly one, treat as same-scope (path empty).
2. Resolves `resolveAggregatePath(childFields, operand)`:
   - `SameScope` or operand-not-resolvable-as-descend → keep the existing immediate-child fold (path empty).
   - `DescendPath(p)` → fold via `foldDescendantLeaves(rows: childRows, path: p, acc: accs[k], eval: (leaf) => a.argument.evaluate(contextFactory(row: leaf, params: params, variables: calc.values, functions: _functions)), childRowsOf: childRowsOf)` once (NOT inside the per-child loop).
   - `Ambiguous` → do not fold; set the footer var for `a.name` to `JetValue.from(unresolvedFieldToken)` (FR-010).
3. Because `DescendPath`/`Ambiguous` fold once (not per child row), restructure: compute each agg's value after the per-child emit loop, not inside it. Same-scope aggs still fold per child (existing behavior) — keep that inside the loop, and run descend/ambiguous folds once after.

Concretely, replace the `NestedScope` branch body with:

```dart
case NestedScope(scope: final DetailScope s):
  final List<DataRow> childRows =
      childRowsOf(scopeRow, s.collectionField!);
  if (childRows.isEmpty) {
    break; // empty collection → no bands, no footer
  }
  final PreparedFooter? footer =
      s.footer == null ? null : prepareNestedFooter(s.footer!);
  // Classify each footer aggregate operand once: same-scope folds over the
  // immediate child rows (spec 029); a descendant leaf folds over the whole
  // subtree (spec 033); an ambiguous operand renders the fallback (FR-010).
  final List<FieldDef> childFields = childRows.first.fields;
  final List<List<String>?> descPaths = <List<String>?>[]; // null → same-scope
  final List<bool> ambiguousAgg = <bool>[];
  if (footer != null) {
    for (final NestedAgg a in footer.aggs) {
      final Set<String> refs = a.argument.references.fields;
      AggregatePath? resolved =
          refs.length == 1 ? resolveAggregatePath(childFields, refs.single) : null;
      descPaths.add(resolved is DescendPath ? resolved.path : null);
      ambiguousAgg.add(resolved is Ambiguous);
    }
  }
  final List<VariableAccumulator>? accs = footer == null
      ? null
      : <VariableAccumulator>[
          for (final NestedAgg a in footer.aggs)
            VariableAccumulator(a.calculation),
        ];
  for (final DataRow childRow in childRows) {
    for (final ScopeNode child in s.children) {
      emitNode(child, childRow);
    }
    if (footer != null) {
      for (int k = 0; k < footer.aggs.length; k++) {
        // Same-scope: fold over the immediate child rows, as spec 029.
        if (descPaths[k] == null && !ambiguousAgg[k]) {
          accs![k].fold(footer.aggs[k].argument.evaluate(contextFactory(
            row: childRow,
            params: params,
            variables: calc.values,
            functions: _functions,
          )));
        }
      }
    }
  }
  if (footer != null) {
    // Descendant folds run once over the whole subtree of this scope instance.
    for (int k = 0; k < footer.aggs.length; k++) {
      final List<String>? path = descPaths[k];
      if (path != null) {
        foldDescendantLeaves(
          rows: childRows,
          path: path,
          acc: accs![k],
          eval: (DataRow leaf) =>
              footer.aggs[k].argument.evaluate(contextFactory(
            row: leaf,
            params: params,
            variables: calc.values,
            functions: _functions,
          )),
          childRowsOf: childRowsOf,
        );
      }
    }
    final Map<String, JetValue> vars = <String, JetValue>{
      ...calc.values,
      for (int k = 0; k < footer.aggs.length; k++)
        footer.aggs[k].name: ambiguousAgg[k]
            ? JetValue.from(unresolvedFieldToken)
            : accs![k].value,
    };
    addBand(footer.band, scopeRow, vars);
  }
```

Add imports at the top of `report_filler.dart`: `import '../../data/aggregate_path.dart';` and `import '../../expression/aggregate/descendant_aggregate.dart';`.

- [ ] **Step 1: Write the failing fill test**

Create `packages/jet_print/test/rendering/fill/descendant_footer_fill_test.dart`. Build a 2-level definition (root → `orders` nested scope with a footer summing the deeper `lines.lineTotal`) over an in-memory source, fill it, and assert the footer band renders the flat sum of all lines under each order's scope. Model it on existing fill tests in `test/rendering/fill/report_filler_test.dart` for source/definition construction (use `JetInMemoryDataSource`, `ReportFiller().fillDefinition(def, source)`, then find the `FilledBand` of type `groupFooter` and read its resolved element text). Assert: a footer aggregate `{SUM([lineTotal])}` on the `orders` scope (which contains a `lines` collection) renders the sum of all `lineTotal`s across that customer's orders' lines; an empty descendant collection renders `0.00`.

(Construct the definition inline as in `nested_footer_test.dart` / `report_filler_test.dart`; reuse their fixture helpers' style. The operand `SUM($F{lineTotal})` is stored directly on the footer element.)

- [ ] **Step 2: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/rendering/fill/descendant_footer_fill_test.dart`
Expected: FAIL — before the edit the footer folds only immediate child rows (which have no `lineTotal`), so the total is `0.00`, not the expected sum.

- [ ] **Step 3: Apply the `emitNode` integration above**

- [ ] **Step 4: Run the new test + the full filler suite**

Run (from `packages/jet_print`): `flutter test test/rendering/fill/`
Expected: PASS — new descendant-footer test passes; existing `report_filler_test.dart` and `nested_footer`-driven fill tests stay green (same-scope footers unchanged).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/rendering/fill/report_filler.dart packages/jet_print/test/rendering/fill/descendant_footer_fill_test.dart
git commit -m "feat(033): nested-scope footer folds descendant leaves (multi-level)"
```

---

### Task 5: Summary + root group footer descendant folds (filler)

Wire the descendant-lift pre-pass into `fillDefinition` and compute the lifted `__dagg<n>` values with leaf-folding accumulators reset by **report** (summary) and **group** (root group footer), injecting them where those bands are emitted.

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test: `packages/jet_print/test/rendering/fill/descendant_summary_fill_test.dart` (create)

**Interfaces:**
- Consumes: `liftDescendantAggregates` / `DescendantAggregate` (Task 3), `foldDescendantLeaves` (Task 2), `VariableAccumulator`, the existing `childRowsOf` / `contextFactory` / `calc` machinery.
- Produces: no new public API.

**Integration detail.** Restructure the top of `fillDefinition` and the row loop:

1. **Open the source early to read its schema.** Currently `expandAggregates(rawDefinition)` runs at line 79 and `source.open(params)` at line 399. Move the open up: right after building `diagnostics` (line ~80), insert:
   ```dart
   final DataSet ds = source.open(params);
   final List<FieldDef> rootFields = ds.fields;
   ```
   Remove the later `final DataSet ds = source.open(params);` (line ~399); keep the `try { while (ds.moveNext()) … } finally { ds.close(); }` exactly as-is (the cursor is still positioned before the first row).

2. **Run the descendant-lift pre-pass before `expandAggregates`.** Replace `final ReportDefinition definition = expandAggregates(rawDefinition);` (line 79) with:
   ```dart
   final DescendantLift lift = liftDescendantAggregates(rawDefinition, rootFields);
   final ReportDefinition definition = expandAggregates(lift.definition);
   final List<DescendantAggregate> descAggs = lift.aggregates;
   ```
   (`liftDescendantAggregates` rewrites descendant-operand elements to `$V{__dagg<n>}`; `expandAggregates` then lifts the remaining same-scope aggregates as before.)

3. **Build accumulators + a snapshot keyed by `__dagg` name.** Before the row loop, after `calc` is created:
   ```dart
   final List<DescendantAggregate> summaryDescAggs = <DescendantAggregate>[
     for (final DescendantAggregate a in descAggs)
       if (a.resetScope == VariableResetScope.report) a,
   ];
   final List<DescendantAggregate> groupDescAggs = <DescendantAggregate>[
     for (final DescendantAggregate a in descAggs)
       if (a.resetScope == VariableResetScope.group) a,
   ];
   final Map<String, VariableAccumulator> descAcc = <String, VariableAccumulator>{
     for (final DescendantAggregate a in descAggs)
       a.name: VariableAccumulator(a.calculation),
   };
   // Parallels `prevValues`: the group-scoped descendant values through the
   // previous row, used when a group footer is emitted at a break.
   Map<String, JetValue> descGroupSnapshot = <String, JetValue>{
     for (final DescendantAggregate a in groupDescAggs)
       a.name: JetValue.from(unresolvedFieldToken),
   };
   void foldDescInto(DescendantAggregate a, DataRow row) {
     if (a.ambiguous) return; // fallback injected at emit
     foldDescendantLeaves(
       rows: <DataRow>[row],
       path: a.path,
       acc: descAcc[a.name]!,
       eval: (DataRow leaf) => a.argument.evaluate(contextFactory(
         row: leaf, params: params, variables: const <String, JetValue>{},
         functions: _functions)),
       childRowsOf: childRowsOf,
     );
   }
   Map<String, JetValue> descValues(Iterable<DescendantAggregate> aggs) =>
       <String, JetValue>{
         for (final DescendantAggregate a in aggs)
           a.name: a.ambiguous
               ? JetValue.from(unresolvedFieldToken)
               : descAcc[a.name]!.value,
       };
   ```

4. **Fold per master row, reset group accumulators on break — mirroring the master calculator.** In the row loop (current lines 404–423), after `calc.advance(row)` and computing `broken`, and after emitting group footers/headers, add reset + fold + snapshot. The order matters (mirror `VariableCalculator`: footer reads the completed-group value, then reset, then fold the current row):
   - When `broken.isNotEmpty` (the `else if` branch), the footers are emitted with `prevValues` — merge in `descGroupSnapshot` so a lifted group footer shows its completed total. Change `emitGroupFooters(brokenInOrder(broken, reversed: true), prevRow, prevValues)` to pass `{...prevValues, ...descGroupSnapshot}`.
   - Immediately after emitting those footers + headers, reset the accumulators of group descendant aggregates whose group broke:
     ```dart
     for (final DescendantAggregate a in groupDescAggs) {
       if (broken.contains(a.resetGroup)) descAcc[a.name]!.reset();
     }
     ```
   - After `emitDetail(row)` (and the existing `prevValues = calc.values;`), fold this row into all descendant accumulators and refresh the group snapshot:
     ```dart
     for (final DescendantAggregate a in descAggs) {
       foldDescInto(a, row);
     }
     descGroupSnapshot = descValues(groupDescAggs);
     ```

5. **Emit the summary with report-scoped descendant values.** The summary is emitted via `emitOnce(definition.body.summary, null)` (line 435) which uses `calc.values`. Replace that call for the summary with one that merges descendant values:
   ```dart
   if (definition.body.summary != null) {
     addBand(definition.body.summary!, null,
         <String, JetValue>{...calc.values, ...descValues(summaryDescAggs)});
   }
   ```
   And the final group footers (line 434) must also carry `descGroupSnapshot`: change `emitGroupFooters(groupOrder.reversed.toList(), prevRow, prevValues)` to pass `{...prevValues, ...descGroupSnapshot}`.

> **Reset-timing rationale (mirrors `VariableCalculator.advance`):** the master calculator resets a group-scoped variable at the *start* of advancing the breaking row, then folds that row. We emit the broken group's footer from `descGroupSnapshot` (captured at the end of the previous row = the completed group), then reset, then fold the current row at the end of the iteration — so the next group starts clean and the current row counts toward the new group. `descGroupSnapshot` is recomputed after every row, so it always holds "through the previous row," exactly like `prevValues`.

- [ ] **Step 1: Write the failing fill test**

Create `packages/jet_print/test/rendering/fill/descendant_summary_fill_test.dart`. Build the Customer ▸ Order ▸ Line shape (master = customers; `customer` root group with a footer; `orders` nested scope; `lines` nested scope under orders carrying `lineTotal`), with:
- the `customer` root group footer element = `SUM($F{lineTotal})`,
- the summary element = `SUM($F{lineTotal})`.
Provide two customers with known line totals. Fill, then assert:
- each customer group footer renders that customer's flat line sum,
- the summary renders the grand total of all lines,
- `AVG($F{lineTotal})` at the summary (a second assertion / second definition) equals total-sum ÷ total-line-count (flat average), and an all-empty-lines customer contributes nothing.

(Use `JetInMemoryDataSource` with nested `List<Map>` values for `orders`/`lines`, mirroring `report_filler_test.dart`'s nested fixtures.)

- [ ] **Step 2: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/rendering/fill/descendant_summary_fill_test.dart`
Expected: FAIL — before the wiring, `SUM($F{lineTotal})` at the summary/customer-footer is lifted by `expandAggregates` into a master-row variable whose `$F{lineTotal}` is unresolved on a customer row → renders `0`/empty.

- [ ] **Step 3: Apply the `fillDefinition` integration above**

- [ ] **Step 4: Run the new test + full fill suite**

Run (from `packages/jet_print`): `flutter test test/rendering/fill/`
Expected: PASS — new summary/group-footer descendant tests pass; existing fill tests (including spec 028/029/030 same-scope and published-total tests) stay green.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/rendering/fill/report_filler.dart packages/jet_print/test/rendering/fill/descendant_summary_fill_test.dart
git commit -m "feat(033): summary (report-reset) + root group footer (group-reset) descendant folds"
```

---

### Task 6: Ambiguous-operand fill fallback (all sinks)

Lock in FR-010 at fill time across all three sinks: an ambiguous operand renders the fallback token, never a number. Tasks 4 and 5 already inject `JetValue.from(unresolvedFieldToken)` for ambiguous aggregates; this task adds the regression tests that pin the behavior.

**Files:**
- Test: `packages/jet_print/test/rendering/fill/descendant_ambiguous_fill_test.dart` (create)

- [ ] **Step 1: Write the failing/locking test**

Create `packages/jet_print/test/rendering/fill/descendant_ambiguous_fill_test.dart`. Build a schema where the operand name (e.g. `amount`) exists in two sibling collections under the master row, with `SUM($F{amount})` at the summary. Fill with `unresolvedFieldToken: '#ERROR'`. Assert the summary's resolved element text is `#ERROR` (the default token), not a number. Add a second case for a nested-scope footer over an ambiguous deeper operand.

- [ ] **Step 2: Run the test**

Run (from `packages/jet_print`): `flutter test test/rendering/fill/descendant_ambiguous_fill_test.dart`
Expected: PASS (Tasks 4/5 already implement the fallback) — if it FAILS, fix the emit-time injection in the corresponding sink so an `ambiguous` aggregate's value is `JetValue.from(unresolvedFieldToken)`.

- [ ] **Step 3: Commit**

```bash
git add packages/jet_print/test/rendering/fill/descendant_ambiguous_fill_test.dart
git commit -m "test(033): ambiguous descendant operand renders fallback token, never a number"
```

---

### Task 7: Schema-aware validation (I8 operand resolution)

Extend `validate()` to accept an optional schema and, when given, check each aggregate operand in a sink band: same-scope or unique descend → no diagnostic; ambiguous or not-found → error. When no schema is supplied, behavior is unchanged (backward compatible with all existing callers/tests).

**Files:**
- Modify: `packages/jet_print/lib/src/domain/report_validation.dart`
- Test: `packages/jet_print/test/domain/report_validation_aggregate_operand_test.dart` (create)

**Interfaces:**
- Consumes: `resolveAggregatePath` (Task 1), `fieldsInScopeForChain` (`data/binding_scope.dart`), `JetDataSchema` (`data/data_schema.dart`), the existing `topLevelAggregate` / `Expression`.
- Produces: new signature `List<Diagnostic> validate(ReportDefinition def, {JetDataSchema? schema})`.

**Resolving a sink band's scope fields for the operand check:**
- Summary band and a **root** group footer → scope fields are `schema.fields` (the master scope).
- A nested-scope footer → descend `schema.fields` through the chain of enclosing `collectionField`s to that scope (use `fieldsInScopeForChain(schema, chainToScope)`); `walkScope` already tracks the scope chain implicitly — thread the current scope's `collectionField` chain into the check (accumulate a `List<DetailScope>` as `walkScope` recurses, or pass the chain down).

**Important:** a **not-found** operand at the summary / root group footer might be a published total (spec 030), which is legitimately not in `schema`. To avoid false errors, treat `NotFound` as an error **only** when the operand is also not a published-total name reachable for that band. Reuse `_publishedTotalNames`-equivalent logic: collect published-total names from the scope tree and exclude them from the not-found error. (Simplest: gather the full set of published-total names once and skip the not-found error if the operand is in it.)

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/report_validation_aggregate_operand_test.dart`. Build definitions + a Customer ▸ Order ▸ Line `JetDataSchema`. Assert:
- `validate(def)` (no schema) returns no operand diagnostics for any of these (backward compatible);
- `validate(def, schema: s)` returns **no** diagnostic when the summary / customer footer use `SUM($F{lineTotal})` (unique descend) or a same-scope operand;
- `validate(def, schema: s)` returns an **error** when the operand is ambiguous (two sibling collections share the name);
- `validate(def, schema: s)` returns an **error** for a genuinely unknown operand at the summary;
- a published-total operand (e.g. `SUM($F{customerTotal})` where `customerTotal` is a `ScopeTotal`) does **not** error.

- [ ] **Step 2: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/domain/report_validation_aggregate_operand_test.dart`
Expected: FAIL — `validate` has no `schema` named parameter.

- [ ] **Step 3: Implement the schema-aware check**

In `report_validation.dart`: add imports `import '../data/aggregate_path.dart';`, `import '../data/binding_scope.dart';`, `import '../data/data_schema.dart';`, `import 'detail_scope.dart';` (DetailScope is already imported). Change the signature to `List<Diagnostic> validate(ReportDefinition def, {JetDataSchema? schema})`. Add a helper invoked from the aggregate-sink sites (summary band, root group footer, nested-scope footer) that — only when `schema != null` — parses each text element's top-level aggregate, extracts the single operand field ref, resolves it against the sink's scope fields, and appends an `error` Diagnostic for `Ambiguous`, and for `NotFound` unless the operand is a known published-total name. Thread the scope chain through `walkScope` so a nested footer resolves against its descended fields. Leave the existing structural I8 (`aggregateBand`) intact.

- [ ] **Step 4: Run the new test + the full domain suite**

Run (from `packages/jet_print`): `flutter test test/domain/`
Expected: PASS — new operand tests pass; existing `report_validation` tests (which call `validate(def)` with no schema) stay green.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/report_validation.dart packages/jet_print/test/domain/report_validation_aggregate_operand_test.dart
git commit -m "feat(033): schema-aware I8 — accept unique descendant operand, error on ambiguous/not-found"
```

---

### Task 8: Composition with spec-032 sub-term lifting

Verify that compound/embedded aggregates and multiple operands at different depths each resolve and fold independently (FR-008): `{SUM([lineTotal]) * 1.1}` and `{SUM([lineTotal]) + COUNT([orderNo])}` at a customer footer.

**Files:**
- Test: `packages/jet_print/test/rendering/fill/descendant_composition_fill_test.dart` (create)

**Why this should already work:** `liftDescendantAggregates` reuses the same `_expandInlineAggregates` scanner as `expandAggregates`, which lifts aggregate **sub-terms** (spec 032 amendment #2). So `SUM($F{lineTotal}) * 1.1` lifts the `SUM(...)` sub-term to `$V{__dagg0}` and keeps `* 1.1`; `SUM($F{lineTotal}) + COUNT($F{orderNo})` lifts both sub-terms, each resolving its own descend path (`[orders, lines]` and `[orders]`).

- [ ] **Step 1: Write the test**

Create `packages/jet_print/test/rendering/fill/descendant_composition_fill_test.dart`. Fill a Customer ▸ Order ▸ Line definition where the customer footer holds `SUM($F{lineTotal}) * 1.1` and a second element `SUM($F{lineTotal}) + COUNT($F{orderNo})`. Assert the rendered values equal `(flat line sum) * 1.1` and `(flat line sum) + (order count)` respectively, per customer.

- [ ] **Step 2: Run the test**

Run (from `packages/jet_print`): `flutter test test/rendering/fill/descendant_composition_fill_test.dart`
Expected: PASS. If it FAILS because a sub-term wasn't lifted, confirm `liftDescendantAggregates` uses `_expandInlineAggregates` (Task 3) rather than `topLevelAggregate` on the whole expression.

- [ ] **Step 3: Commit**

```bash
git add packages/jet_print/test/rendering/fill/descendant_composition_fill_test.dart
git commit -m "test(033): compound + multi-depth descendant aggregates compose (FR-008)"
```

---

### Task 9: Playground sample parity (SC-001) + full suite + analyze

Migrate the playground nested-lists sample from hand-declared published totals to inline `{SUM([lineTotal])}` authoring at the line footer, customer footer, and summary, and prove the rendered totals are numerically identical. Then run the whole workspace green and `flutter analyze` (catches any import-cycle from Tasks 1/7).

**Files:**
- Modify: `apps/jet_print_playground/lib/nested_list_sample.dart`
- Test: `apps/jet_print_playground/test/nested_list_definition_test.dart` (extend or add a parity test)

**Migration (numerically identical, SC-001):**
- `summary` element `grandTotal`: change `expression: r'SUM($F{customerTotal})'` → `r'SUM($F{lineTotal})'` (descend `[orders, lines]`, report reset).
- `customerFooter` element `customerTotal`: change `expression: r'$F{customerTotal}'` → `r'SUM($F{lineTotal})'` (descend `[orders, lines]`, customer-group reset).
- `linesFooter` element `orderTotalFooter`: change `expression: r'$F{orderTotal}'` → `r'SUM($F{lineTotal})'` (same-scope over the order's lines — existing spec-029 path, byte-identical).
- Remove the now-unneeded `ScopeTotal` declarations (`customerTotal` on the `orders` scope; `orderTotal` on the `lines` scope) **only if** the parity test confirms identical output. (Per spec Out-of-scope, published totals remain valid — leaving them is also acceptable, but the inline version must produce the same numbers. Removing them is the cleaner demonstration of SC-001; keep them if any consumer references the published field elsewhere.)

- [ ] **Step 1: Write the parity test (failing or guarded)**

In `apps/jet_print_playground/test/nested_list_definition_test.dart`, add a test that fills the sample with its fixed sample data and asserts the three rendered totals (an order total, a customer total, the grand total) equal the known expected figures computed directly from the line data (e.g. sum the fixture's `lineTotal`s by order / customer / overall). If a golden image test covers the sample, run it before and after to confirm byte-identical output.

- [ ] **Step 2: Run it against the current (pre-migration) sample to capture expected numbers**

Run (from `apps/jet_print_playground`): `flutter test test/nested_list_definition_test.dart`
Expected: PASS with the published-total authoring (captures the baseline numbers).

- [ ] **Step 3: Apply the sample migration**

- [ ] **Step 4: Run the parity test + sample suite**

Run (from `apps/jet_print_playground`): `flutter test`
Expected: PASS — the inline-authored sample renders identical order/customer/grand totals. If a golden test exists, it must remain byte-identical (no `--update-goldens`).

- [ ] **Step 5: Run the whole package suite + analyze**

Run (from `packages/jet_print`): `flutter test` then `flutter analyze`
Expected: full suite green (engine deltas from spec 032 baseline are the new 033 tests only); `flutter analyze` reports no issues (confirms no import cycle from `domain → data/aggregate_path` and no unused imports).

- [ ] **Step 6: Commit**

```bash
git add apps/jet_print_playground/lib/nested_list_sample.dart apps/jet_print_playground/test/nested_list_definition_test.dart
git commit -m "feat(033): migrate nested-lists sample to inline multi-level aggregates (SC-001 parity)"
```

---

## Self-Review (engine)

**Spec coverage:**
- FR-001 (resolver) → Task 1. FR-002 (descendant fold) → Tasks 2, 4, 5. FR-003 (reset by sink scope) → Tasks 4 (scope-row), 5 (report + group). FR-004 (flat SUM/COUNT/MIN/MAX = roll-up; flat AVG; empty-set) → Tasks 2, 5 tests. FR-005 (I8 accept descend, error ambiguous/not-found) → Task 7. FR-006 (bare deep ref unresolved) → **designer plan** (author-time) + unchanged engine record-blind path; engine never injects a bare deep ref. FR-008 (composition) → Task 8. FR-009 (published totals unchanged, same numbers, no serialization change) → Tasks 5/9 (same-scope + published-total paths untouched; parity). FR-010 (never silently wrong) → Tasks 6, 7. SC-001 → Task 9. SC-004 (flat AVG/empty) → Tasks 2, 5. SC-003 (validate) → Task 7. SC-005 (suite green, goldens unchanged) → Task 9.
- FR-007 (designer aggregate-operand-aware status/palette) and SC-002 (fx editor Valid/Unresolved) are the **designer plan** (`plan-designer.md`), which consumes Task 1's `resolveAggregatePath`.

**Placeholder scan:** none — every code step ships complete code or a precise, line-referenced integration with code. The two fill tests (Tasks 4/5/6/8) describe fixture construction by reference to existing fill tests rather than inlining ~150 lines of fixture each; the assertions and operand expressions are fully specified.

**Type consistency:** `AggregatePath`/`DescendPath.path` (Task 1) used identically in Tasks 3, 4, 7. `DescendantAggregate` fields (Task 3) consumed verbatim in Task 5. `foldDescendantLeaves` named params (Task 2) match every call site (Tasks 4, 5). `validate(def, {schema})` (Task 7) is the only signature change and is backward compatible.

**Milestone:** Tasks 1–9 are an independently shippable engine milestone — multi-level inline aggregates compute correctly at fill time, validate at author time, and the sample proves parity. The designer authoring affordances are a separate, dependent plan.
