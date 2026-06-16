# Recursive Scope Totals (Phase B2) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Each task is Red→Green TDD (Constitution III).

**Goal:** A nested `DetailScope` can **publish named totals** — `ScopeTotal {name, expression}` where `expression` is a Phase A top-level aggregate (`SUM($F{lineTotal})`). The filler computes them **bottom-up** and injects each as a **synthetic field on the parent row**, so an enclosing scope (`SUM($F{orderTotal})`), a group footer (`$F{customerTotal}`), and the existing Phase A summary (`SUM($F{customerTotal})` → `grandTotal`) all consume them through the **unchanged** master calculator. Completes the nested-aggregation chain: Customer ▸ Order ▸ Line, every total live.

**Architecture (data-prep rollup, master calculator + render untouched):**
- `DetailScope` gains `List<ScopeTotal> totals` (default empty). The root scope must not carry any (validation error). A `ScopeTotal` is an immutable `{String name, String expression}`.
- A new pure helper `expression/aggregate/scope_totals.dart`: `prepareScopeTotals(List<ScopeTotal>) → List<ScopeAgg>` parses each `expression` into `{name, JetCalculation calculation, Expression argument}` (mirrors `prepareNestedFooter`'s detect+slice, reusing `topLevelAggregate`). Pure, independently tested.
- The filler runs a **single bottom-up `augmentForScope(scope, row)` pass per master row, BEFORE `calc.advance`** (`report_filler.dart`). For each nested child scope it: derives the child rows, recursively augments each (so a child's own published totals are fields on it), folds each `ScopeAgg` over the augmented child rows with a `VariableAccumulator` (reset per parent → structural), injects the results as fields on the parent row, and **replaces the parent's collection value + schema with the augmented child rows** so `emitNode`'s existing `childRowsOf` yields rows already carrying their published totals. Result: each published total folds **exactly once**; `emitNode`/layout/paging/render are unchanged; the master `VariableCalculator` just sees richer rows.
- `JetValue.from` returns an existing `JetValue` unchanged → the accumulator's `JetValue` is stored **directly** as the field value; `resolveField` round-trips it (no raw-unwrap).
- **`grandTotal` needs no change:** `expandAggregates` already turns the summary `SUM($F{customerTotal})` into a hidden report-scope `ReportVariable`; once `customerTotal` is a field on each master row at advance time, that variable sums it live.

**Tech Stack:** Dart / Flutter, `flutter_test`. Domain + serialization + expression/aggregate + fill layers. Builds on [[spec-029-nested-aggregates-status]] (B1's `prepareNestedFooter`/`DetailScope.footer`), [[spec-028-inline-aggregates-status]] (the `topLevelAggregate` detector + `VariableAccumulator` + `expandAggregates`), and [[report-engine-aggregation-scope]].

**Conventions:** Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` ([[git-cwd-drift-after-flutter]]). Branch is already `030-recursive-aggregates`.

## Constitution Check

| Principle | Status |
|---|---|
| I. Library-first / clean API | PASS — `totals` is a natural domain field; `ScopeTotal` + the helper live under `src/`; nothing new exported beyond `ScopeTotal` if the public barrel re-exports domain types (match how `GroupLevel`/`Band` are exported). |
| II. Layered architecture | PASS — domain value type + field, codec, a pure expression-seam helper, a filler data-prep pass. Dependencies point inward; no UI/render coupling. |
| III. Test-First (NON-NEGOTIABLE) | PASS — every task Red→Green. |
| IV. Rendering fidelity / WYSIWYG | PASS — no parallel render path; the rollup only enriches data rows before the unchanged calculator/render consume them; each aggregate folds once. The sample migration's golden change (precomputed→live values, value-equal) is reviewed deliberately. |
| V. Serialization | PASS — `totals` is an OPTIONAL key; pre-feature JSON (no key) loads unchanged. Backward-compatible (MINOR), no schema break. |
| VI. Docs/DX | PASS — dartdoc on the new type/field/helper; `dart format` + clean analyzer gate in Task 6. |

No violations → Complexity Tracking omitted.

---

## File Map

- `packages/jet_print/lib/src/domain/scope_total.dart` — **new**: `ScopeTotal {name, expression}` value type (==/hashCode/toString).
- `packages/jet_print/lib/src/domain/detail_scope.dart` — **modify**: add `List<ScopeTotal> totals` (ctor, field, copyWith, ==, hashCode, toString); import `scope_total.dart`.
- `packages/jet_print/lib/jet_print.dart` (or the public barrel) — **modify if** domain value types are re-exported: export `ScopeTotal` alongside `DetailScope`/`GroupLevel` (VERIFY how `GroupLevel` is exported and match).
- `packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart` — **modify**: `_encodeScope` adds `if (scope.totals.isNotEmpty) 'totals': [...]`; `_decodeScope` adds `totals: _decodeScopeTotals(json['totals'])`.
- `packages/jet_print/lib/src/domain/report_validation.dart` — **modify**: in `walkScope`, root `totals` → error; each nested `ScopeTotal` parsed, must be a top-level aggregate, names unique within the scope.
- `packages/jet_print/lib/src/expression/aggregate/scope_totals.dart` — **new**: `ScopeAgg {name, calculation, argument}` + `prepareScopeTotals(List<ScopeTotal>)`.
- `packages/jet_print/lib/src/rendering/fill/report_filler.dart` — **modify**: add `augmentForScope` (bottom-up rollup + row augmentation); call it on each master row before `calc.advance`; `emitNode` is unchanged (consumes the augmented rows via `childRowsOf`).
- `apps/jet_print_playground/lib/nested_list_sample.dart` — **modify**: publish `orderTotal` on `lines` + display `$F{orderTotal}` in its footer; publish `customerTotal` on `orders`; customer group footer + summary unchanged; remove the precomputed `customerTotal`/`orderTotal` data fields.
- `apps/jet_print_playground/lib/rendered_nested_list_example.dart` — **modify if** `kSampleCustomers` carries `customerTotal`/`orderTotal` (drop them; they're now computed).
- Tests: `scope_total_test.dart` (new), `detail_scope_test.dart` (extend — totals equality/copyWith), codec round-trip (extend), `report_validation_test.dart` (extend), `scope_totals_test.dart` (new), `jet_report_engine_test.dart` (extend — recursive rollup integration), `apps/jet_print_playground/test/nested_list_definition_test.dart` (update).

---

## Task 1: `ScopeTotal` value type + `DetailScope.totals` field + serialization

**Files:**
- New: `packages/jet_print/lib/src/domain/scope_total.dart`
- Modify: `packages/jet_print/lib/src/domain/detail_scope.dart`, `packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart`, public barrel (if domain types are re-exported)
- Tests (new/modify): `packages/jet_print/test/domain/scope_total_test.dart`, `packages/jet_print/test/domain/detail_scope_test.dart`, the codec round-trip test.

- [ ] **Step 1: Write failing tests**
  - `ScopeTotal`: equality/hashCode by `(name, expression)`; `toString` includes both.
  - Domain: a `DetailScope` with `totals` differs (`!=`) from one without; `copyWith()` preserves existing `totals`; `copyWith(totals: [...])` replaces.
  - Codec: a nested `DetailScope` carrying `totals` round-trips encode→decode; a scope JSON with **no** `totals` key decodes to `totals == const []` (backward compatibility); the encoded form omits the key when empty.

  ```dart
  // scope_total_test.dart (sketch)
  test('ScopeTotal equality + toString', () {
    const a = ScopeTotal('orderTotal', r'SUM($F{lineTotal})');
    const b = ScopeTotal('orderTotal', r'SUM($F{lineTotal})');
    const c = ScopeTotal('x', r'SUM($F{lineTotal})');
    expect(a, b);
    expect(a, isNot(c));
    expect(a.toString(), allOf(contains('orderTotal'), contains('SUM')));
  });

  // detail_scope_test.dart (add)
  test('a scope with totals differs from one without; copyWith preserves them', () {
    const t = ScopeTotal('orderTotal', r'SUM($F{lineTotal})');
    const a = DetailScope(id: 's', collectionField: 'lines', totals: <ScopeTotal>[t]);
    const b = DetailScope(id: 's', collectionField: 'lines');
    expect(a, isNot(b));
    expect(a.copyWith(id: 's2').totals, <ScopeTotal>[t]);
  });
  ```
  For the codec test, follow the existing serialization test's pattern: build a ReportDefinition with a nested scope carrying `totals`, encode→decode, assert equality; and decode a hand-written scope map without `totals` → `const []`.

- [ ] **Step 2: Run → FAIL** (`ScopeTotal`/`totals` don't exist; codec drops them).

- [ ] **Step 3a: Create `scope_total.dart`**
  ```dart
  /// A named roll-up total published by a nested [DetailScope] (spec 030, B2).
  ///
  /// [expression] is a top-level inline aggregate (Phase A grammar, e.g.
  /// `SUM($F{lineTotal})`) folded over the scope's child rows; the result is
  /// injected as a field named [name] on the scope's PARENT row, so an enclosing
  /// scope, a group footer, or the report summary can reference it as `$F{name}`.
  library;

  /// An immutable `{name, expression}` published total.
  class ScopeTotal {
    /// Creates a published total binding [name] to the aggregate [expression].
    const ScopeTotal(this.name, this.expression);

    /// The field name this total is injected under on the parent row.
    final String name;

    /// The stored top-level aggregate (e.g. `SUM($F{lineTotal})`).
    final String expression;

    @override
    bool operator ==(Object other) =>
        other is ScopeTotal && other.name == name && other.expression == expression;

    @override
    int get hashCode => Object.hash(name, expression);

    @override
    String toString() => 'ScopeTotal($name = $expression)';
  }
  ```

- [ ] **Step 3b: Add `totals` to `DetailScope`** (`detail_scope.dart`)
  Import `scope_total.dart`. Add `this.totals = const <ScopeTotal>[]` to the const constructor; `final List<ScopeTotal> totals;` with dartdoc ("Named roll-up totals this scope publishes onto its parent row (spec 030); empty on the root."). Thread through `copyWith` (`List<ScopeTotal>? totals` → `totals: totals ?? this.totals`), `==` (`&& listEquals(other.totals, totals)`), `hashCode` (add `Object.hashAll(totals)`), and `toString`.

- [ ] **Step 3c: Codec** (`report_definition_codec.dart`)
  In `_encodeScope` (near the `footer` key, ~line 90):
  ```dart
      if (scope.totals.isNotEmpty)
        'totals': <Map<String, Object?>>[
          for (final ScopeTotal t in scope.totals)
            <String, Object?>{'name': t.name, 'expression': t.expression},
        ],
  ```
  In `_decodeScope` (near `footer:`, ~line 233): `totals: _decodeScopeTotals(json['totals']),` with a small private helper:
  ```dart
  List<ScopeTotal> _decodeScopeTotals(Object? raw) {
    if (raw is! List) return const <ScopeTotal>[];
    return <ScopeTotal>[
      for (final Object? e in raw)
        if (e is Map)
          ScopeTotal(e['name'] as String, e['expression'] as String),
    ];
  }
  ```
  Import `ScopeTotal` in the codec. VERIFY the codec's import style (it likely imports the domain barrel or `detail_scope.dart`).

- [ ] **Step 3d: Public export** — if `GroupLevel`/`DetailScope` are re-exported from the public barrel, add `ScopeTotal` (the playground authors it). VERIFY by grepping the barrel for `GroupLevel`.

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Analyzer + format the changed files. FULL suite (`flutter test`)** — existing serialization/golden tests stay green (a scope without `totals` encodes identically; the `isNotEmpty` guard omits the key).
- [ ] **Step 6: Commit** — `feat(domain): ScopeTotal value type + DetailScope.totals + serialization`.

---

## Task 2: `prepareScopeTotals` — pure published-total prep

**Files:**
- New: `packages/jet_print/lib/src/expression/aggregate/scope_totals.dart`
- Test (new): `packages/jet_print/test/expression/aggregate/scope_totals_test.dart`

Mirrors `nested_footer.dart`: parse each `ScopeTotal.expression` into a fold spec. Reuses `topLevelAggregate` (detect) + the string-slice for the inner arg. Unlike `prepareNestedFooter` there is **no band to rewrite** — just `name → {calculation, argument}`.

- [ ] **Step 1: Write failing tests**
  ```dart
  test('prepares an aggregate total into name + calc + argument', () {
    final specs = prepareScopeTotals(const <ScopeTotal>[
      ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
    ]);
    expect(specs, hasLength(1));
    expect(specs.single.name, 'orderTotal');
    expect(specs.single.calculation, JetCalculation.sum);
    // argument evaluates $F{lineTotal} against a row → its value
  });

  test('keeps the whole inner of an expression-argument aggregate', () {
    final specs = prepareScopeTotals(const <ScopeTotal>[
      ScopeTotal('t', r'SUM($F{qty} * $F{price})'),
    ]);
    expect(specs.single.calculation, JetCalculation.sum);
  });

  test('a non-aggregate or unparseable expression is skipped (returns no spec)', () {
    expect(prepareScopeTotals(const <ScopeTotal>[ScopeTotal('t', r'$F{x} + 1')]), isEmpty);
    expect(prepareScopeTotals(const <ScopeTotal>[ScopeTotal('t', r'SUM(')]), isEmpty);
  });
  ```
  (Validation Task 3 is what *rejects* a non-aggregate at author time; this pure helper simply produces no spec for one, so the filler skips it safely.)

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Create `scope_totals.dart`**
  ```dart
  /// Published-total preparation for nested collection scopes (spec 030, B2).
  ///
  /// A nested `DetailScope.totals` holds named top-level aggregates (Phase A
  /// grammar) summing over the scope's OWN child rows. This pure helper parses
  /// each into a fold spec the filler evaluates per child row, then injects the
  /// result as a field on the parent row. Sibling to `nested_footer.dart` (which
  /// rewrites a footer band); here there is no band — totals are pure data.
  library;

  import '../../domain/report_variable.dart';
  import '../../domain/scope_total.dart';
  import '../expression.dart';
  import '../expression_exception.dart';
  import 'aggregate_functions.dart';

  /// One published total: its [name], fold [calculation], and [argument] folded
  /// over each child row.
  class ScopeAgg {
    const ScopeAgg(this.name, this.calculation, this.argument);
    final String name;
    final JetCalculation calculation;
    final Expression argument;
  }

  /// Parses each top-level-aggregate [ScopeTotal] into a [ScopeAgg]; a total whose
  /// expression is not a parseable top-level aggregate is skipped. Pure.
  List<ScopeAgg> prepareScopeTotals(List<ScopeTotal> totals) {
    final List<ScopeAgg> out = <ScopeAgg>[];
    for (final ScopeTotal t in totals) {
      final AggregateCall? agg;
      try {
        agg = topLevelAggregate(Expression.parse(t.expression).root);
      } on ExpressionException {
        continue;
      }
      if (agg == null) continue;
      final String inner = t.expression
          .substring(t.expression.indexOf('(') + 1, t.expression.lastIndexOf(')'));
      out.add(ScopeAgg(t.name, agg.calculation, Expression.parse(inner)));
    }
    return out;
  }
  ```
  VERIFY: `Expression.parse(...).root` is an `Expr`; `topLevelAggregate(Expr)` returns `AggregateCall?` (confirmed in `aggregate_functions.dart`). The string-slice mirrors `nested_footer.dart` exactly.

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Analyzer + format. Full suite green** (nothing calls it yet).
- [ ] **Step 6: Commit** — `feat(expr): prepareScopeTotals parses published totals into fold specs`.

---

## Task 3: Validation — root-forbidden, must-be-aggregate, unique names

**Files:**
- Modify: `packages/jet_print/lib/src/domain/report_validation.dart`
- Test (modify): `packages/jet_print/test/domain/report_validation_test.dart`

Context — `walkScope(scope, {isRoot})` already has the footer block (root-forbidden / nested aggregate sink). Add a `totals` block next to it. `topLevelAggregate(Expression.parse(expr).root)` + `aggregateNameFor` are already imported.

- [ ] **Step 1: Write failing tests**
  ```dart
  test('totals on the ROOT scope is an error', () {
    final def = ReportDefinition(name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(root: DetailScope(id: 'root',
        totals: const <ScopeTotal>[ScopeTotal('x', r'SUM($F{a})')])));
    expect(validate(def).where((d) => d.severity == DiagnosticSeverity.error)
        .map((d) => d.message), anyElement(contains('root')));
  });

  test('a published total on a nested scope is valid', () {
    final def = ReportDefinition(name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(root: DetailScope(id: 'root', children: <ScopeNode>[
        NestedScope(DetailScope(id: 'lines', collectionField: 'lines',
          totals: const <ScopeTotal>[ScopeTotal('orderTotal', r'SUM($F{lineTotal})')])),
      ])));
    expect(validate(def).where((d) => d.severity == DiagnosticSeverity.error), isEmpty);
  });

  test('a non-aggregate published total is an error', () {
    final def = ReportDefinition(name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(root: DetailScope(id: 'root', children: <ScopeNode>[
        NestedScope(DetailScope(id: 'lines', collectionField: 'lines',
          totals: const <ScopeTotal>[ScopeTotal('t', r'$F{x} + 1')])),
      ])));
    expect(validate(def).where((d) => d.severity == DiagnosticSeverity.error)
        .map((d) => d.message), anyElement(contains('aggregate')));
  });

  test('duplicate published-total names in one scope is an error', () {
    final def = ReportDefinition(name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(root: DetailScope(id: 'root', children: <ScopeNode>[
        NestedScope(DetailScope(id: 'lines', collectionField: 'lines',
          totals: const <ScopeTotal>[
            ScopeTotal('t', r'SUM($F{a})'), ScopeTotal('t', r'SUM($F{b})')])),
      ])));
    expect(validate(def).where((d) => d.severity == DiagnosticSeverity.error)
        .map((d) => d.message), anyElement(contains('duplicate')));
  });
  ```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Add a `totals` block to `walkScope`** (after the footer block, ~line 123):
  ```dart
    // Spec 030 — a nested scope may publish named roll-up totals onto its parent
    // row. The root has no parent row, so it must not. Each expression must be a
    // top-level aggregate (a published total is by definition a roll-up); names
    // are unique within the scope. (A name shadowing a real data field is a
    // FILL-time diagnostic — the schema is unknown here.)
    if (isRoot && scope.totals.isNotEmpty) {
      out.add(Diagnostic(DiagnosticSeverity.error,
          'root scope "${scope.id}" must not publish totals'));
    }
    if (!isRoot) {
      final Set<String> seenTotals = <String>{};
      for (final ScopeTotal t in scope.totals) {
        if (!seenTotals.add(t.name)) {
          out.add(Diagnostic(DiagnosticSeverity.error,
              'duplicate published-total name "${t.name}" in scope "${scope.id}"'));
        }
        AggregateCall? agg;
        try {
          agg = topLevelAggregate(Expression.parse(t.expression).root);
        } on ExpressionException catch (e) {
          out.add(Diagnostic(DiagnosticSeverity.error,
              'published total "${t.name}" failed to parse: ${e.message}'));
          continue;
        }
        if (agg == null) {
          out.add(Diagnostic(DiagnosticSeverity.error,
              'published total "${t.name}" is not a top-level aggregate '
              '(SUM/AVG/COUNT/MIN/MAX)'));
        }
      }
    }
  ```
  Import `ScopeTotal` if not already visible via `detail_scope.dart` (it re-exports? VERIFY — likely add `import 'scope_total.dart';`).

- [ ] **Step 4: Run → PASS** (4 new + existing validation tests green).
- [ ] **Step 5: Analyzer + format. Full suite green.**
- [ ] **Step 6: Commit** — `feat(domain): validate published scope totals (root-forbidden, aggregate-only, unique)`.

---

## Task 4: Filler — bottom-up rollup pass injecting published totals as fields

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test (modify): `packages/jet_print/test/rendering/engine/jet_report_engine_test.dart`

This is the core. Add an `augmentForScope` closure inside `fillDefinition` (it needs `childRowsOf`, `contextFactory`, `params`, `_functions`, `diagnostics`, `warnedFields`). Call it on each master row **before** `calc.advance`.

**Design:**
```dart
// Returns `row` enriched so that, for every nested child scope of `scope`,
// each published total is a field on `row`, and the child collection value +
// schema are replaced with the augmented child rows (which themselves carry
// their own deeper published totals). Bottom-up: a child's totals exist before
// the parent folds over them. Pure w.r.t. the report; folds each total once.
DataRow augmentForScope(DetailScope scope, DataRow row) {
  final Map<String, JetValue> extras = <String, JetValue>{};      // totals onto `row`
  final Map<String, List<DataRow>> replaced = <String, List<DataRow>>{}; // augmented collections
  for (final ScopeNode node in scope.children) {
    if (node is! NestedScope) continue;
    final DetailScope cs = node.scope;
    final String field = cs.collectionField!;
    final List<DataRow> childRows = childRowsOf(row, field);
    final List<DataRow> augChildren = <DataRow>[
      for (final DataRow cr in childRows) augmentForScope(cs, cr),  // recurse first
    ];
    final List<ScopeAgg> aggs = prepareScopeTotals(cs.totals);
    for (final ScopeAgg a in aggs) {
      final VariableAccumulator acc = VariableAccumulator(a.calculation);
      for (final DataRow acr in augChildren) {
        acc.fold(a.argument.evaluate(contextFactory(
          row: acr, params: params, variables: const <String, JetValue>{},
          functions: _functions)));
      }
      if (row.hasField(a.name)) {            // FR-010 shadow diagnostic
        diagnostics.warning(
            'published total "${a.name}" shadows a data field on scope '
            '"${cs.id}"; the computed total is used');
      }
      extras[a.name] = acc.value;
    }
    if (augChildren.isNotEmpty) replaced[field] = augChildren;
  }
  if (extras.isEmpty && replaced.isEmpty) return row;
  return _augmentRow(row, extras, replaced);
}
```
`_augmentRow` rebuilds an immutable `DataRow` (DataRow is immutable; build a new one):
```dart
DataRow _augmentRow(DataRow row, Map<String, JetValue> extras,
    Map<String, List<DataRow>> replaced) {
  final List<FieldDef> fields = <FieldDef>[
    for (final FieldDef f in row.fields)
      // swap a replaced collection's FieldDef for one whose child schema includes
      // the published-total names the augmented rows now carry
      if (replaced.containsKey(f.name) && replaced[f.name]!.isNotEmpty)
        FieldDef(f.name, type: f.type, fields: replaced[f.name]!.first.fields)
      else
        f,
    // append any published-total field this row didn't already declare
    for (final String name in extras.keys)
      if (!row.hasField(name)) FieldDef(name, type: JetFieldType.double),
  ];
  final Map<String, Object?> values = <String, Object?>{
    for (final FieldDef f in row.fields) f.name: row.field(f.name),
    for (final MapEntry<String, List<DataRow>> e in replaced.entries)
      e.key: <Map<String, Object?>>[
        for (final DataRow cr in e.value)
          <String, Object?>{for (final FieldDef cf in cr.fields) cf.name: cr.field(cf.name)},
      ],
    for (final MapEntry<String, JetValue> e in extras.entries) e.key: e.value, // JetValue stored directly
  };
  return DataRow(fields: fields, values: values);
}
```
**Wiring in the main loop** (`while (ds.moveNext())`):
```dart
  DataRow row = ds.current;
  row = augmentForScope(definition.body.root, row);   // ← NEW: inject top-level totals + augment tree
  calc.advance(row, params: params);                  // grandTotal (Phase A) now sums $F{customerTotal}
  ... group header/footer logic, emitDetail(row) ...  // unchanged; prevRow = row (augmented)
```

- [ ] **Step 1: Write failing integration tests** (append in the nested-rendering area; reuse `tallPage`/`runsFor`/`JetInMemoryDataSource` helpers):
  ```dart
  test('a parent total sums a child scope\'s published total, resetting per parent', () {
    final def = ReportDefinition(name: 'recursive', page: tallPage,
      body: ReportBody(
        summary: Band(id: 'summary', type: BandType.summary, height: 16,
          elements: <ReportElement>[
            TextElement(id: 'gt', bounds: const JetRect(x: 0, y: 0, width: 100, height: 14),
              text: 'gt', expression: r'SUM($F{custTotal})')]),
        root: DetailScope(id: 'root', children: <ScopeNode>[
          NestedScope(DetailScope(id: 'orders', collectionField: 'orders',
            totals: const <ScopeTotal>[ScopeTotal('custTotal', r'SUM($F{ordTotal})')],
            footer: Band(id: 'cf', type: BandType.groupFooter, height: 14,
              elements: <ReportElement>[
                TextElement(id: 'ct', bounds: const JetRect(x: 0, y: 0, width: 100, height: 12),
                  text: 'ct', expression: r'$F{custTotal}')]),
            children: <ScopeNode>[
              NestedScope(DetailScope(id: 'lines', collectionField: 'lines',
                totals: const <ScopeTotal>[ScopeTotal('ordTotal', r'SUM($F{lineTotal})')],
                footer: Band(id: 'lf', type: BandType.groupFooter, height: 12,
                  elements: <ReportElement>[
                    TextElement(id: 'ot', bounds: const JetRect(x: 0, y: 0, width: 100, height: 10),
                      text: 'ot', expression: r'$F{ordTotal}')]),
                children: <ScopeNode>[
                  BandNode(Band(id: 'l', type: BandType.detail, height: 10,
                    elements: <ReportElement>[
                      TextElement(id: 'lt', bounds: const JetRect(x: 0, y: 0, width: 100, height: 10),
                        text: 'lt', expression: r'$F{lineTotal}')])),
                ])),
            ])),
        ])));
    // Customer A: order#1 lines [10,20]=30, order#2 lines [5]=5 → custTotal 35
    // Customer B: order#1 lines [12]=12 → custTotal 12 ; grand total 47
    final source = JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'orders': <Map<String, Object?>>[
        <String, Object?>{'lines': <Map<String, Object?>>[
          <String, Object?>{'lineTotal': 10}, <String, Object?>{'lineTotal': 20}]},
        <String, Object?>{'lines': <Map<String, Object?>>[<String, Object?>{'lineTotal': 5}]},
      ]},
      <String, Object?>{'orders': <Map<String, Object?>>[
        <String, Object?>{'lines': <Map<String, Object?>>[<String, Object?>{'lineTotal': 12}]},
      ]},
    ]);
    final report = const JetReportEngine().renderDefinition(def, source);
    expect(runsFor(report, 'ot'), <String>['30.0', '5.0', '12.0']); // per-order, B2 reads published field
    expect(runsFor(report, 'ct'), <String>['35.0', '12.0']);        // per-customer footer, recursive
    expect(runsFor(report, 'gt'), <String>['47.0']);                // grand total via Phase A, unchanged
  });

  test('an expression-argument published total folds the per-row product', () {
    // orders publishes lineExt = SUM($F{qty} * $F{unitPrice}); assert the folded value
  });
  ```
  VERIFY the exact `runsFor`/text-run formatting (the engine emits `'30.0'` vs `'30'`); match the existing nested tests' expectations (B1 used `'30.0'`/`'5.0'`).

- [ ] **Step 2: Run → FAIL** (`custTotal`/`gt` unresolved; `ot` empty until published-field display works).

- [ ] **Step 3: Implement `augmentForScope` + `_augmentRow`** per the design above; add the master-row call before `calc.advance`. Imports to add: `import '../../expression/aggregate/scope_totals.dart';`, `import '../../expression/aggregate/variable_accumulator.dart';` (already imported for B1), `import '../../domain/scope_total.dart';` (if `ScopeTotal` not already visible), `field_def.dart`/`JetFieldType` (VERIFY the type enum name — `JetFieldType`).

  VERIFY against the real code:
  - `contextFactory`'s named params — `{DataRow? row, Map<String,Object?> params, Map<String,JetValue> variables, required JetFunctionRegistry functions}`. Passing `variables: const {}` is fine (the published-total argument references only child-row fields, not variables).
  - `childRowsOf(DataRow, String)` is the closure already defined in `fillDefinition`; it dedupes its own collection warnings via `warnedCollections` — reusing it means the rollup and `emitNode` share dedup (no double warnings).
  - `FieldDef` constructor: `FieldDef(name, {type, fields})` — confirm the named params (B1's `_inferChildFields` uses `FieldDef(name, type: ...)`; nested schema uses `fields:`).
  - `DataRow({required fields, required values})` copies defensively — building a fresh one is correct and immutable-safe.
  - Storing a `JetValue` directly as a `values` entry: `JetValue.from` returns it unchanged on read (confirmed) → `$F{name}` resolves to the computed value. `childRowsOf`'s re-projection of a replaced collection reads `m[f.name]` where the map already holds the published `JetValue` and `f.name` is in the extended schema → preserved.
  - **emitNode is UNCHANGED**: it calls `childRowsOf(augmentedRow, field)` which now yields rows carrying published totals (because the augmented row's collection value+schema were replaced). The B1 footer path still folds any *inline* footer aggregate, but the playground's footers display `$F{published}` (no inline aggregate → no double fold).

- [ ] **Step 4: Run → PASS** (both new tests). Then FULL suite `flutter test` — scopes without `totals` are unaffected (`augmentForScope` returns `row` unchanged when `extras`+`replaced` are empty: a definition with no published totals and no nested collections short-circuits; a definition with nested collections but no totals still *replaces* collections with re-derived identical rows — VERIFY this is value-identical and changes no existing golden; if a pre-existing nested golden shifts, STOP and inspect). **If any existing GOLDEN fails, STOP** — no existing report publishes totals, so none should change.
- [ ] **Step 5: Analyzer + format.**
- [ ] **Step 6: Commit** — `feat(fill): bottom-up rollup injects published scope totals as parent-row fields`.

> **Performance note (non-blocking):** the rollup re-derives child rows already derived by `emitNode`; both are O(rows) and pure. If profiling later shows it matters, memoize the augmented master row tree and have `emitDetail` consume it directly. Not needed for B2 (correctness + single-fold-per-total already hold).

---

## Task 5: Playground migration — live `customerTotal` + `grandTotal` (SC-001/002)

**Files:**
- Modify: `apps/jet_print_playground/lib/nested_list_sample.dart`, `apps/jet_print_playground/lib/rendered_nested_list_example.dart`
- Test (modify): `apps/jet_print_playground/test/nested_list_definition_test.dart`

- [ ] **Step 1: Update the sample test (Red)**
  - Shape: the `lines` scope publishes `orderTotal = SUM($F{lineTotal})` and its footer displays `$F{orderTotal}`; the `orders` scope publishes `customerTotal = SUM($F{orderTotal})`.
  - Value: rendered per-customer totals equal the data-derived customer sums of `kSampleCustomers`; the grand total equals the overall sum. Reuse `kSampleCustomers` (single source of truth) + `NumberFormat('#,##0.00')` (NOT `toStringAsFixed` — B1 lesson). Add a `_findScope(root, id)` recursive walk if not already present.
  ```dart
  test('customerTotal is a published recursive total; grandTotal source unchanged', () {
    final root = nestedListsDefinition().body.root;
    final orders = _findScope(root, 'orders');
    expect(orders.totals.map((t) => t.expression), contains(r'SUM($F{orderTotal})'));
    final lines = _findScope(root, 'lines');
    expect(lines.totals.map((t) => t.expression), contains(r'SUM($F{lineTotal})'));
    // grand total element expression is still SUM($F{customerTotal})
  });
  ```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Migrate the sample** (`nested_list_sample.dart`)
  - `lines` `DetailScope`: add `totals: [ScopeTotal('orderTotal', r'SUM($F{lineTotal})')]`; change the `lines` footer's total element from `expression: r'SUM($F{lineTotal})'` (B1 inline) to `expression: r'$F{orderTotal}'` (the published field — one computation, reused).
  - `orders` `DetailScope`: add `totals: [ScopeTotal('customerTotal', r'SUM($F{orderTotal})')]`.
  - Customer group footer: **unchanged** — still `$F{customerTotal}` (now the injected value).
  - Summary `grandTotal`: **unchanged** — `SUM($F{customerTotal})`.
  - Remove `FieldDef('customerTotal', ...)` and `FieldDef('orderTotal', ...)` from `customersSchema` (they are computed now). In `rendered_nested_list_example.dart` / `kSampleCustomers`, drop the `customerTotal`/`orderTotal` data entries.
  - Rewrite the file's dartdoc: the whole Customer ▸ Order ▸ Line total chain is now live via published scope totals (spec 030); remove the "precomputed … until Phase B2" caveats.

- [ ] **Step 4: Run → PASS.** Confirm the existing "renders cleanly (no error diagnostics)" test still passes — in particular **no FR-010 shadow warning** (we removed the colliding data fields). The nested-list **GOLDEN may change** only if pixels move; values are equal to before (customerTotal/grandTotal were already shown from precomputed data that equals the live sums). If the golden is byte-identical, even better; if it shifts, inspect that the only diff is the now-live values, then regenerate that golden alone (Constitution IV) and call it out in the commit.
- [ ] **Step 5: Analyzer + format both packages. Full suites green.**
- [ ] **Step 6: Commit** — `feat(playground): live customerTotal + grandTotal via published scope totals`.

---

## Task 6: Full verification sweep

**Files:** none (verification only).

- [ ] **Step 1: Analyzer** — `flutter analyze` in `packages/jet_print` and `apps/jet_print_playground` → clean.
- [ ] **Step 2: Format check** — `dart format --output=none --set-exit-if-changed lib test` in both. Fix + note if needed.
- [ ] **Step 3: Full suites** — `flutter test` in both. **GOLDENS:** at most the nested-list sample's golden changes (live values; likely byte-identical). Any OTHER golden diff is a regression — STOP, inspect, do NOT blanket-regenerate ([[verify-subagent-committed-state]]).
- [ ] **Step 4: Confirm success criteria**
  - SC-001 → Task 5 per-customer value-equality test green; precomputed `customerTotal` removed from schema+data.
  - SC-002 → Task 4 `gt`=`['47.0']` + Task 5 grand-total value-equality; the summary source is unchanged.
  - SC-003 → Task 4 two-customer reset (`ct`=`['35.0','12.0']`, `ot`=`['30.0','5.0','12.0']`).
  - SC-004 → Task 3 root-forbidden / non-aggregate / duplicate-name errors; add/confirm a fill test: a published total over an unresolvable name → unresolved-field diagnostic + null (not 0); and a published name shadowing a real field → FR-010 warning (computed wins).
  - SC-005/006 → Phase A + B1 tests still green; master calculator + layout/render/paging untouched (no edits there); each published total folds exactly once (the rollup is the only fold site for published totals; assert via the values, and confirm `emitNode` has no published-total fold).
- [ ] **Step 5: Manual GUI smoke (optional)** — open the nested-list sample; confirm each customer shows a live customer total and the grand total equals the sum of customer totals; edit a line value and Preview to see order→customer→grand totals all change.

---

## Self-Review

- **Spec coverage:** FR-001 → Task 1 (type+field) + Task 3 (root-forbidden). FR-002 → Task 1 codec. FR-003 → Task 4 (fold + inject + reset-per-parent). FR-004 → Task 4 (bottom-up: recurse before fold). FR-005 → Task 4 (master-row inject before `advance`; group footers + Phase A summary unchanged). FR-006 → Tasks 2/4 reuse `topLevelAggregate` + `VariableAccumulator`; master calculator untouched. FR-007 → Task 4 (emitNode consumes the augmented tree; each published total folds once). FR-008 → Task 3 (schema-free: root / non-aggregate / duplicate). FR-009 → Task 4/6 (unresolved-field diagnostic + null). FR-010 → Task 4 (shadow warning, computed wins). US1/SC-001 → Task 5. US2/SC-002 → Tasks 4/5. US3/SC-003 → Task 4. US4/SC-004 → Tasks 3/4/6. SC-005/006 → Task 6.
- **Placeholder scan:** none — every task has concrete code or an exact command + expected outcome. (Task 5's value-equality assertion and `_findScope` are sketched because they depend on the sample data the implementer reads; intent + assertions are explicit.)
- **Key risks called out:** (1) `validate()` has no data schema → the field-collision check is FILL-time (FR-010), not validate-time (Task 3 vs Task 4). (2) `JetValue.from` returns a `JetValue` unchanged → store the accumulator value directly as a field (Task 4). (3) The augmented-collection **schema** must be extended with published names or `childRowsOf` re-projection drops them (Task 4 `_augmentRow`). (4) `augmentForScope` re-derives child rows already derived by `emitNode` — accepted (pure, O(rows)); single-fold-per-total still holds because `emitNode` doesn't fold published totals. (5) Migrating the sample must REMOVE the precomputed `customerTotal`/`orderTotal` data fields, else FR-010 shadow warnings fire (Task 5). (6) Empty collection → no augmented children, no published total surfaced, no footer (Task 4 guard + B1 behavior).
- **No schema-break:** `totals` is an optional codec key; pre-feature JSON loads unchanged (Constitution V).
- **No parallel render path:** the rollup enriches data rows; the unchanged calculator/`emitNode`/layout/render consume them. The only new compute is the bottom-up fold, each published total once.
