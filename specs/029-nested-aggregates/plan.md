# Nested-Scope Footers + Single-Level Aggregates (Phase B1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Each task is Red→Green TDD (Constitution III).

**Goal:** A nested `DetailScope` gains an optional `footer` band, emitted once after its rows. An inline aggregate there (`{SUM([lineTotal])}`, Phase A grammar) sums over **that scope's immediate collection**, computed by the filler during nested iteration. Single-level over raw fields; recursion is B2.

**Architecture (filler-local, master calculator untouched):**
- `DetailScope` gains `Band? footer`. The root scope must not carry one. The footer band's `type` is `BandType.groupFooter`, emitted into the flat band stream with `group: null` so layout treats it as an ordinary linear band — layout/render/paging are **unchanged** (the stream is nesting-agnostic, keyed on `type` + `group`).
- A nested footer's aggregates are computed by the **filler**, not the master `VariableCalculator` (which only sees master rows). A pure helper `prepareNestedFooter(footer)` rewrites each top-level-aggregate `TextElement` expression to `$V{__naggN}` and returns the aggregate specs; during `emitNode(NestedScope)` the filler folds each spec's argument over the child rows with a `VariableAccumulator` (reset per parent invocation), then emits the rewritten footer with the results injected into its variables. Reuses Phase A's `topLevelAggregate` + the existing `VariableAccumulator` — no new evaluator, no parallel render path (Constitution IV).
- Phase A's master path (`expandAggregates`, summary + root group footers) is untouched.

**Tech Stack:** Dart / Flutter, `flutter_test`. Domain + serialization + expression/aggregate + fill layers. Builds on [[spec-028-inline-aggregates-status]] (the `aggregate_functions.dart` detector and `VariableAccumulator` it reuses) and [[report-engine-aggregation-scope]].

**Conventions:** Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` ([[git-cwd-drift-after-flutter]]). Branch is already `029-nested-aggregates`.

## Constitution Check

| Principle | Status |
|---|---|
| I. Library-first / clean API | PASS — `footer` is a natural domain field; the helper lives under `src/`; nothing new exported. |
| II. Layered architecture | PASS — domain field + codec + a pure expression-seam helper + a filler change; dependencies point inward; no UI/render coupling. |
| III. Test-First (NON-NEGOTIABLE) | PASS — every task Red→Green. |
| IV. Rendering fidelity / WYSIWYG | PASS — no parallel render path; the footer is an ordinary band; reuses the one accumulator. The sample migration's golden change (an added footer row) is reviewed deliberately. |
| V. Serialization | PASS — `footer` is an OPTIONAL key; pre-feature JSON (no key) loads unchanged. Backward-compatible (MINOR), no breaking schema change. |
| VI. Docs/DX | PASS — dartdoc on the new field/helper; `dart format` + clean analyzer gate in Task 6. |

No violations → Complexity Tracking omitted.

---

## File Map

- `packages/jet_print/lib/src/domain/detail_scope.dart` — **modify**: add `Band? footer` (ctor, field, copyWith, ==, hashCode, toString).
- `packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart` — **modify**: encode/decode `scope.footer` (optional).
- `packages/jet_print/lib/src/domain/report_validation.dart` — **modify**: root scope must not carry a footer; a nested-scope footer is slot-checked (`groupFooter`) and is an aggregate sink.
- `packages/jet_print/lib/src/expression/aggregate/nested_footer.dart` — **new**: `prepareNestedFooter(Band)` → rewritten band + `List<NestedAgg>` specs.
- `packages/jet_print/lib/src/rendering/fill/report_filler.dart` — **modify**: in `emitNode`'s `NestedScope` case, fold footer aggregates over child rows and emit the footer.
- `apps/jet_print_playground/lib/nested_list_sample.dart` — **modify**: add a `lines`-scope footer with `{SUM([lineTotal])}` (the live `orderTotal`), drop the order band's precomputed `$F{orderTotal}` display.
- Tests: new `detail_scope_test.dart` (footer equality), codec test (round-trip), `report_validation_test.dart` (extend), new `nested_footer_test.dart`, `jet_report_engine_test.dart` (extend — nested-footer integration), `apps/jet_print_playground/test/nested_list_definition_test.dart` (update).

---

## Task 1: `DetailScope.footer` domain field + serialization

**Files:**
- Modify: `packages/jet_print/lib/src/domain/detail_scope.dart`, `packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart`
- Tests (new/modify): `packages/jet_print/test/domain/detail_scope_test.dart` (create if absent), the existing codec round-trip test (find it, e.g. `report_definition_codec_test.dart`).

- [ ] **Step 1: Write failing tests**
  - Domain: a `DetailScope` with a `footer` differs (`!=`) from one without; `copyWith()` preserves an existing footer.
  - Codec: a nested `DetailScope` carrying a `footer` band round-trips through encode→decode; a scope JSON with **no** `footer` key decodes to `footer == null` (backward compatibility).

  ```dart
  // detail_scope_test.dart (sketch — match existing domain test style/imports)
  test('a scope with a footer differs from one without and copyWith preserves it', () {
    const footer = Band(id: 'f', type: BandType.groupFooter, height: 12);
    const a = DetailScope(id: 's', collectionField: 'lines', footer: footer);
    const b = DetailScope(id: 's', collectionField: 'lines');
    expect(a, isNot(b));
    expect(a.copyWith(id: 's2').footer, footer);
  });
  ```
  For the codec test, follow the existing serialization test's pattern (build a ReportDefinition with a nested scope that has a footer, `encode` → `decode`, assert equality; and decode a hand-written map without `footer` → null).

- [ ] **Step 2: Run → FAIL** (footer param/field doesn't exist; codec drops it).

- [ ] **Step 3a: Add the field to `DetailScope`** (`detail_scope.dart`)
  Add `this.footer` to the constructor, `final Band? footer;` (dartdoc: "Emitted once after this scope's rows — the structural home of a collection total (spec 029). Null on the root scope."), and thread it through `copyWith` (`Band? footer` param → `footer: footer ?? this.footer`), `==` (`&& other.footer == footer`), `hashCode` (include `footer`), and `toString` if it enumerates fields. `band.dart` is already imported here (DetailScope references `Band` via GroupLevel); verify.

- [ ] **Step 3b: Codec** (`report_definition_codec.dart`)
  In `_encodeScope`, add (alongside `collectionField`/`groups`/`children`):
  ```dart
      if (scope.footer != null) 'footer': _encodeBand(scope.footer!, registry),
  ```
  In `_decodeScope`, add to the `DetailScope(...)` construction:
  ```dart
      footer: _decodeBandOrNull(json['footer'], registry),
  ```
  (Both `_encodeBand` and `_decodeBandOrNull` already exist — used for group header/footer. Verify the exact names and reuse them.)

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Analyzer + format** the changed files. Run the FULL suite (`flutter test`) — existing serialization/golden tests must stay green (a scope without a footer encodes identically; the `if (scope.footer != null)` guard means no new key for existing defs).
- [ ] **Step 6: Commit** — `feat(domain): DetailScope.footer field + serialization`.

---

## Task 2: Validation — root-footer error + nested footer as aggregate sink

**Files:**
- Modify: `packages/jet_print/lib/src/domain/report_validation.dart`
- Test (modify): `packages/jet_print/test/domain/report_validation_test.dart`

Context — current `walkScope(scope, {isRoot})` handles I6 collectionField, I7 per-scope groups, group slot/aggregate checks, then iterates children. The `aggregateBand(Band?, {required bool supported})` helper flags an aggregate in an UNsupported band. Group footers use `aggregateBand(g.footer, supported: isRoot)`. `slotBand(Band?, BandType)` checks band-type-vs-slot and `claim`s the id; both helpers no-op on null.

- [ ] **Step 1: Write failing tests**
  ```dart
  test('a footer on the ROOT scope is an error', () {
    final def = ReportDefinition(
      name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(root: DetailScope(id: 'root',
        footer: Band(id: 'rf', type: BandType.groupFooter, height: 12))));
    expect(
      validate(def).where((d) => d.severity == DiagnosticSeverity.error)
          .map((d) => d.message),
      anyElement(contains('root')),
    );
  });

  test('an inline aggregate in a NESTED-scope footer is valid (a sink)', () {
    final def = ReportDefinition(
      name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(root: DetailScope(id: 'root', children: <ScopeNode>[
        NestedScope(DetailScope(id: 'lines', collectionField: 'lines',
          footer: Band(id: 'lf', type: BandType.groupFooter, height: 12,
            elements: <ReportElement>[
              TextElement(id: 'ot',
                bounds: const JetRect(x: 0, y: 0, width: 100, height: 12),
                text: 'ot', expression: r'SUM($F{lineTotal})'),
            ]))),
      ])));
    expect(validate(def).where((d) => d.message.contains('aggregate')), isEmpty,
        reason: 'a nested-scope footer is an aggregate sink in B1');
  });

  test('a nested footer with the wrong band type is a slot error', () {
    final def = ReportDefinition(
      name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(root: DetailScope(id: 'root', children: <ScopeNode>[
        NestedScope(DetailScope(id: 'lines', collectionField: 'lines',
          footer: Band(id: 'lf', type: BandType.detail, height: 12))),
      ])));
    expect(
      validate(def).where((d) => d.severity == DiagnosticSeverity.error)
          .map((d) => d.message),
      anyElement(contains('groupFooter')),
    );
  });
  ```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Add footer handling to `walkScope`**
  Inside `walkScope`, after the I6 collectionField block (placement that keeps each band visited once), add:
  ```dart
    // Spec 029 — a nested scope may carry a footer (a collection total). The root
    // scope must not (it has no collection). The footer is slot-checked and is an
    // aggregate sink; it is NOT record-blind (it renders against the parent row).
    if (isRoot) {
      if (scope.footer != null) {
        out.add(Diagnostic(DiagnosticSeverity.error,
            'root scope "${scope.id}" must not carry a footer'));
      }
    } else {
      slotBand(scope.footer, BandType.groupFooter);
      aggregateBand(scope.footer, supported: true);
    }
  ```
  (`slotBand(null, ...)`/`aggregateBand(null, ...)` no-op, so a scope without a footer is unaffected. `slotBand` `claim`s the id for the I1 duplicate-id check.)

- [ ] **Step 4: Run → PASS** (3 new + existing validation tests green).
- [ ] **Step 5: Analyzer + format. Full suite green.**
- [ ] **Step 6: Commit** — `feat(domain): validate nested-scope footers (root-forbidden, aggregate sink)`.

---

## Task 3: `prepareNestedFooter` — pure footer-aggregate prep

**Files:**
- New: `packages/jet_print/lib/src/expression/aggregate/nested_footer.dart`
- Test (new): `packages/jet_print/test/expression/aggregate/nested_footer_test.dart`

This pure helper takes a footer `Band`, rewrites each top-level-aggregate `TextElement` expression to `$V{__naggN}`, and returns the aggregate specs the filler folds over child rows. Reuses `topLevelAggregate` (detect) + the string-slice (inner expr) from Phase A; parses each inner once into an `Expression` for per-child-row evaluation.

- [ ] **Step 1: Write failing tests**
  ```dart
  library;
  import 'package:flutter_test/flutter_test.dart';
  import 'package:jet_print/src/domain/band.dart';
  import 'package:jet_print/src/domain/elements/text_element.dart';
  import 'package:jet_print/src/domain/geometry.dart';
  import 'package:jet_print/src/domain/report_band.dart';
  import 'package:jet_print/src/domain/report_element.dart';
  import 'package:jet_print/src/domain/report_variable.dart';
  import 'package:jet_print/src/expression/aggregate/nested_footer.dart';

  TextElement _el(String id, String expr) => TextElement(
        id: id, bounds: const JetRect(x: 0, y: 0, width: 80, height: 12),
        text: id, expression: expr);

  void main() {
    test('rewrites an aggregate element to a synth var and returns its spec', () {
      final band = const Band(id: 'f', type: BandType.groupFooter, height: 12)
          .copyWith(elements: <ReportElement>[
        _el('label', r'$F{label}'), _el('total', r'SUM($F{lineTotal})'),
      ]);
      final prepared = prepareNestedFooter(band);
      expect(prepared.aggs, hasLength(1));
      expect(prepared.aggs.single.calculation, JetCalculation.sum);
      final total = prepared.band.elements
          .firstWhere((e) => e.id == 'total') as TextElement;
      expect(total.expression, '\$V{${prepared.aggs.single.name}}');
      final label = prepared.band.elements
          .firstWhere((e) => e.id == 'label') as TextElement;
      expect(label.expression, r'$F{label}', reason: 'non-aggregate untouched');
    });

    test('a footer with no aggregate returns the band unchanged and no specs', () {
      final band = const Band(id: 'f', type: BandType.groupFooter, height: 12)
          .copyWith(elements: <ReportElement>[_el('x', r'$F{x}')]);
      final prepared = prepareNestedFooter(band);
      expect(prepared.aggs, isEmpty);
      expect(identical(prepared.band, band), isTrue);
    });

    test('an expression-argument aggregate keeps the whole inner', () {
      final band = const Band(id: 'f', type: BandType.groupFooter, height: 12)
          .copyWith(elements: <ReportElement>[
        _el('t', r'SUM($F{qty} * $F{price})')]);
      expect(prepareNestedFooter(band).aggs.single.calculation,
          JetCalculation.sum);
    });
  }
  ```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Create `nested_footer.dart`**
  ```dart
  /// Footer-aggregate preparation for nested collection scopes (spec 029, B1).
  ///
  /// A nested `DetailScope.footer` may hold inline aggregates (Phase A grammar)
  /// that sum over the scope's OWN collection. Unlike master-scope aggregates
  /// (which `expandAggregates` turns into `ReportVariable`s for the master
  /// calculator), these are folded by the filler over the scope's child rows.
  /// This pure helper rewrites each aggregate element to a `$V{__naggN}` reference
  /// and returns the specs the filler evaluates per child row.
  library;

  import '../../domain/band.dart';
  import '../../domain/elements/text_element.dart';
  import '../../domain/report_element.dart';
  import '../../domain/report_variable.dart';
  import '../expression.dart';
  import '../expression_exception.dart';
  import 'aggregate_functions.dart';

  /// One nested-footer aggregate: the synth variable [name] its element now
  /// references, the [calculation], and the [argument] expression folded over
  /// each child row.
  class NestedAgg {
    const NestedAgg(this.name, this.calculation, this.argument);
    final String name;
    final JetCalculation calculation;
    final Expression argument;
  }

  /// The result of preparing a footer: the [band] with aggregate elements
  /// rewritten to `$V{__naggN}`, and the [aggs] to fold. Returns the input band
  /// unchanged (identical) and empty [aggs] when no element holds an aggregate.
  class PreparedFooter {
    const PreparedFooter(this.band, this.aggs);
    final Band band;
    final List<NestedAgg> aggs;
  }

  /// Prepares [footer] (see [PreparedFooter]).
  PreparedFooter prepareNestedFooter(Band footer) {
    final List<NestedAgg> aggs = <NestedAgg>[];
    bool changed = false;
    final List<ReportElement> els = <ReportElement>[
      for (final ReportElement e in footer.elements)
        _rewrite(e, aggs, () => changed = true),
    ];
    if (!changed) return PreparedFooter(footer, const <NestedAgg>[]);
    return PreparedFooter(footer.copyWith(elements: els), aggs);
  }

  ReportElement _rewrite(
      ReportElement e, List<NestedAgg> aggs, void Function() mark) {
    if (e is! TextElement || e.expression == null) return e;
    final String expr = e.expression!;
    AggregateCall? agg;
    try {
      agg = topLevelAggregate(Expression.parse(expr).root);
    } on ExpressionException {
      return e;
    }
    if (agg == null) return e;
    final String inner =
        expr.substring(expr.indexOf('(') + 1, expr.lastIndexOf(')'));
    final String name = '__nagg${aggs.length}';
    aggs.add(NestedAgg(name, agg.calculation, Expression.parse(inner)));
    mark();
    return TextElement(
      id: e.id, bounds: e.bounds, text: e.text, style: e.style,
      expression: '\$V{$name}', format: e.format,
    );
  }
  ```
  (Mirrors the Phase A synthesizer's TextElement-rebuild + string-slice. `Band.copyWith(elements:)` exists. Confirm `TextElement` constructor params `id/bounds/text/style/expression/format`.)

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Analyzer + format. Full suite green** (nothing calls it yet).
- [ ] **Step 6: Commit** — `feat(expr): prepareNestedFooter rewrites footer aggregates for filler-local folding`.

---

## Task 4: Filler — emit nested footers, fold aggregates over child rows

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test (modify): `packages/jet_print/test/rendering/engine/jet_report_engine_test.dart`

Context — `emitNode(ScopeNode node, DataRow scopeRow)` currently:
```dart
case NestedScope(scope: final DetailScope s):
  for (final DataRow childRow in childRowsOf(scopeRow, s.collectionField!)) {
    for (final ScopeNode child in s.children) {
      emitNode(child, childRow);
    }
  }
```
The filler also has local `contextFactory({row, params, variables, functions})` → `EvalContext`, `addBand(Band, DataRow?, Map<String,JetValue>, {String? group})`, `calc` (`.values`), `params`, `_functions`.

- [ ] **Step 1: Write failing integration tests** (append in the nested-rendering area):
  ```dart
  test('a nested-scope footer sums its collection and resets per parent', () {
    final def = ReportDefinition(
      name: 'nestedFooter', page: tallPage,
      body: ReportBody(root: DetailScope(id: 'root', children: <ScopeNode>[
        NestedScope(DetailScope(id: 'lines', collectionField: 'lines',
          footer: Band(id: 'lf', type: BandType.groupFooter, height: 16,
            elements: <ReportElement>[
              TextElement(id: 'ot',
                bounds: const JetRect(x: 0, y: 0, width: 100, height: 14),
                text: 'ot', expression: r'SUM($F{lineTotal})')]),
          children: <ScopeNode>[
            BandNode(Band(id: 'l', type: BandType.detail, height: 16,
              elements: <ReportElement>[
                TextElement(id: 'lt',
                  bounds: const JetRect(x: 0, y: 0, width: 100, height: 14),
                  text: 'lt', expression: r'$F{lineTotal}')])),
          ])),
      ])));
    final source = JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'lines': <Map<String, Object?>>[
        <String, Object?>{'lineTotal': 10}, <String, Object?>{'lineTotal': 20}]},
      <String, Object?>{'lines': <Map<String, Object?>>[
        <String, Object?>{'lineTotal': 5}]},
    ]);
    final report = const JetReportEngine().renderDefinition(def, source);
    expect(runsFor(report, 'ot'), <String>['30.0', '5.0'],
        reason: 'the footer sums each parent\'s lines and resets per parent');
  });

  test('an empty nested collection emits no footer', () {
    final def = ReportDefinition(
      name: 'emptyNested', page: tallPage,
      body: ReportBody(root: DetailScope(id: 'root', children: <ScopeNode>[
        NestedScope(DetailScope(id: 'lines', collectionField: 'lines',
          footer: Band(id: 'lf', type: BandType.groupFooter, height: 16,
            elements: <ReportElement>[
              TextElement(id: 'ot',
                bounds: const JetRect(x: 0, y: 0, width: 100, height: 14),
                text: 'ot', expression: r'SUM($F{lineTotal})')]),
          children: <ScopeNode>[
            BandNode(Band(id: 'l', type: BandType.detail, height: 16,
              elements: <ReportElement>[
                TextElement(id: 'lt',
                  bounds: const JetRect(x: 0, y: 0, width: 100, height: 14),
                  text: 'lt', expression: r'$F{lineTotal}')])),
          ])),
      ])));
    final source = JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'lines': <Map<String, Object?>>[]},
    ]);
    final report = const JetReportEngine().renderDefinition(def, source);
    expect(runsFor(report, 'ot'), isEmpty, reason: 'no rows → no footer');
  });
  ```

- [ ] **Step 2: Run → FAIL** (footer never emits; `ot` runs empty).

- [ ] **Step 3: Implement in `emitNode`'s `NestedScope` case**
  ```dart
  case NestedScope(scope: final DetailScope s):
    final List<DataRow> childRows = childRowsOf(scopeRow, s.collectionField!);
    if (childRows.isEmpty) break; // empty collection → no child bands, no footer
    final PreparedFooter? footer =
        s.footer == null ? null : prepareNestedFooter(s.footer!);
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
          accs![k].fold(footer.aggs[k].argument.evaluate(contextFactory(
            row: childRow, params: params,
            variables: calc.values, functions: _functions)));
        }
      }
    }
    if (footer != null) {
      final Map<String, JetValue> vars = <String, JetValue>{
        ...calc.values,
        for (int k = 0; k < footer.aggs.length; k++)
          footer.aggs[k].name: accs![k].value,
      };
      addBand(footer.band, scopeRow, vars);
    }
  ```
  Imports to add: `import '../../expression/aggregate/nested_footer.dart';` and `import '../../expression/aggregate/variable_accumulator.dart';`. `contextFactory`, `params`, `calc`, `_functions`, `addBand`, `childRowsOf` are already in scope inside `fillDefinition`.

  VERIFY against the real code:
  - `contextFactory`'s exact signature + that its return type is what `Expression.evaluate(...)` accepts (it builds the `FillEvalContext` used elsewhere in the filler). Match the named params.
  - `addBand`'s 4th param `{String? group}` — omit it (defaults null) so the footer lays out linearly.
  - `break` exits the `switch` case — confirm `emitNode` uses a `switch`; if it's `if/else`, restructure to `return` after the case body. (Note `emitNode` is `void`.)
  - `VariableAccumulator(JetCalculation)` + `.fold(JetValue)` + `.value`. Confirm.
  - The footer band gets `scopeRow` (the PARENT row) so `$F{...}` parent fields resolve; aggregate values come from `vars`.

- [ ] **Step 4: Run → PASS** (both new tests). Then FULL suite `flutter test` — existing nested tests stay green (scopes without a footer are unaffected: `s.footer == null` path is identical to today). **If a GOLDEN fails, STOP and inspect** — existing goldens have no footers, so none should change here.
- [ ] **Step 5: Analyzer + format.**
- [ ] **Step 6: Commit** — `feat(fill): emit nested-scope footers with collection-folded aggregates`.

---

## Task 5: Playground migration — live `orderTotal` (SC-001)

**Files:**
- Modify: `apps/jet_print_playground/lib/nested_list_sample.dart`
- Test (modify): `apps/jet_print_playground/test/nested_list_definition_test.dart`

- [ ] **Step 1: Update the sample test (Red)**
  Add (a) a shape test: the `lines` scope now has a `footer` whose element expression is `SUM($F{lineTotal})`; (b) a value-equality test: the rendered per-order footer totals equal the per-order line sums computed from the sample data (SC-001). Reuse the `_textRuns`/source helpers from the Phase A migration test. Implement a tiny `_findScope(root, 'lines')` recursive walk over `NestedScope` children.

  ```dart
  test('orderTotal is a live nested-footer aggregate', () {
    final lines = _findScope(nestedListsDefinition().body.root, 'lines');
    expect(lines.footer, isNotNull);
    expect(
      lines.footer!.elements.whereType<TextElement>()
          .map((e) => e.expression),
      contains(r'SUM($F{lineTotal})'),
    );
  });

  test('rendered per-order totals equal the data line-sums', () {
    // expected = for each order in customersDataSource(), sum of its lines' lineTotal
    // actual   = the footer 'ot'-id runs from renderNestedListsDefinition()
    // assert value-equality (e.g. both as List<double> or formatted strings)
  });
  ```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Migrate the sample** (`nested_list_sample.dart`)
  - Add a `footer:` to the `lines` `DetailScope`: a `Band(type: BandType.groupFooter)` with a label ("Order total") and a `TextElement(id: 'ot', expression: r'SUM($F{lineTotal})', format: '#,##0.00')`.
  - Remove the order detail band's precomputed `$F{orderTotal}` display element (the live footer replaces it). Leave the `orderTotal` data field in the source (unused, harmless) to avoid touching the data.
  - Update the sample dartdoc: `orderTotal` is now a live `lines`-scope footer aggregate; `customerTotal`/`grandTotal` remain Phase-A/precomputed until B2.

- [ ] **Step 4: Run → PASS.** Confirm the existing "renders cleanly (no error diagnostics)" test still passes. The nested-list **GOLDEN changes** (an order-total footer row added; order band loses its precomputed total) — the single deliberate visual change of B1. Regenerate THAT golden only after visually confirming the diff is exactly that (use the project's golden-update flow), and call it out in the commit.
- [ ] **Step 5: Analyzer + format both packages. Full suites green.**
- [ ] **Step 6: Commit** — `feat(playground): live per-order total via a lines-scope footer SUM([lineTotal])`.

---

## Task 6: Full verification sweep

**Files:** none (verification only).

- [ ] **Step 1: Analyzer** — `flutter analyze` in `packages/jet_print` and `apps/jet_print_playground` → clean.
- [ ] **Step 2: Format check** — `dart format --output=none --set-exit-if-changed lib test` in both. Fix + note if needed.
- [ ] **Step 3: Full suites** — `flutter test` in both. **GOLDENS:** exactly ONE golden should change (the nested-list sample's added footer row). Any OTHER golden diff is a regression — STOP, inspect, do NOT blanket-regenerate ([[verify-subagent-committed-state]]).
- [ ] **Step 4: Confirm success criteria**
  - SC-001 → Task 5 value-equality test green + the single reviewed golden.
  - SC-002 → Task 4 per-parent-reset test (`['30.0','5.0']`).
  - SC-003 → add/confirm an engine test with a footer `SUM($F{qty} * $F{price})` folding the product.
  - SC-004 → Task 2 root-footer error + Task 4 empty-collection test; confirm a footer aggregate over a non-collection field (e.g. `SUM($F{masterOnly})`) surfaces an unresolved-field diagnostic at fill (the FillEvalContext path, as in Phase A FR-008).
  - SC-005 → Phase A master-scope aggregate tests still green; layout/render/paging unchanged (no edits there).
- [ ] **Step 5: Manual GUI smoke (optional)** — in the playground, open the nested-list sample; confirm each order shows a live "Order total" row under its lines; edit a line value and Preview to see the total change.

---

## Self-Review

- **Spec coverage:** FR-001 → Task 1 (field) + Task 2 (root-forbidden). FR-002 → Task 1 codec. FR-003 → Task 4 (emit-after-rows + empty-skip). FR-004 → Task 3 (specs) + Task 4 (fold + reset-per-parent). FR-005 → Task 3/4 reuse `topLevelAggregate` + `VariableAccumulator`; master calculator untouched. FR-006 → Task 2 (aggregate sink). FR-007 → Task 6 SC-004 (unresolved-field diagnostic). FR-008 → Task 2 slot check (`groupFooter`) + Task 4 emit with `group: null`. US1/SC-001 → Task 5. US2/SC-002 → Task 4. US3/SC-003 → Task 6. US4/SC-004 → Tasks 2/4/6. SC-005 → Task 6.
- **Placeholder scan:** none — every task has concrete code or an exact command + expected outcome. (Task 5's value-equality assertion and `_findScope` are sketched because they depend on the sample data shape the implementer reads; the intent and assertions are explicit.)
- **Key risks called out:** (1) `TextElement.copyWith` cannot set `expression` → Task 3 rebuilds via the constructor (same as Phase A). (2) Master calculator is master-only → nested aggregates are filler-local (Task 4), NOT routed through `expandAggregates`. (3) Footer must lay out as an ordinary band → emit with `group: null` (Task 4) + type `groupFooter` (Task 2); layout/paging untouched. (4) The sample golden DOES change (one footer row) — the only deliberate visual diff; regenerate that golden alone after review (Constitution IV). (5) Empty collection → skip footer (Task 4 guard).
- **No schema-break:** `footer` is an optional codec key; pre-feature JSON loads unchanged (Constitution V).
