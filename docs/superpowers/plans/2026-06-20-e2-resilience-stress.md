# E2 — Resilience & Stress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the report engine is embed-safe with large, dirty datasets — lock its render-don't-crash guarantees as a contract, make the today-silent wrong-type aggregate skip visible (bounded + row-tagged), and stress it to 50k rows.

**Architecture:** One engine change — a fill-layer `DiagnosticBudget` that row-tags and caps per-row *data* diagnostics — fed by a pure, lifetime-monotonic `VariableAccumulator.skippedNonNumeric` counter that the filler reads at all four aggregation sites and routes through the budget. Plus two test suites (an R1–R11 bad-data matrix and a 50k stress test) and a findings record. The expression layer never learns about diagnostics: it only counts; the fill layer reads the count and reports.

**Tech Stack:** Dart / Flutter, `flutter_test`, the existing `jet_print` engine (`packages/jet_print`).

## Global Constraints

Copied verbatim from the spec ([2026-06-20-e2-resilience-stress-design.md](../specs/2026-06-20-e2-resilience-stress-design.md)); every task inherits these:

- The full suite must stay green via the **documented CI command** `flutter test packages/jet_print apps/jet_print_playground`, run from the repo root `/Users/ahmeturel/Projects/oss/jet-print`.
- Run `flutter` / `dart` from `packages/jet_print`; run `git` from the repo root (flutter leaves the cwd inside the package).
- **Goldens must not change.** E2 alters diagnostics and adds tests; it must not alter any render output.
- Architecture tests that scan source files must use `findWorkspaceRoot()` from `test/support/workspace.dart` — never a bare relative `Directory('lib')`.
- The expression layer (`lib/src/expression/**`) must not depend on the fill/render layer (enforced by `architecture/layer_boundaries_test.dart`). The pure `skippedNonNumeric` counter exists to honor this.
- Per-row *data* diagnostics are capped at `DiagnosticBudget.kMaxPerRowDataDiagnostics = 100`; structural/definition diagnostics stay deduped-once on their existing paths; present-but-null values stay silent.
- Commit messages end with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Do not push. Work on a branch `e2-resilience-stress` cut from `main`.

**Branch setup (run once before Task 1, from repo root):**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git checkout -b e2-resilience-stress
```

## Shared interfaces (defined by this plan, used across tasks)

These names are introduced by Tasks 1–4 and consumed by Tasks 5–8. Each task's implementer sees only their own task; this block is the contract between them.

- `int VariableAccumulator.skippedNonNumeric` — Task 1. Lifetime-monotonic count of inputs dropped because they were the wrong type for the calculation. **`reset()` does NOT clear it.**
- `int VariableCalculator.aggregateSkips` — Task 2. Sum of `skippedNonNumeric` across the calculator's internal accumulators (monotonic).
- `class DiagnosticBudget` — Task 3, at `lib/src/rendering/fill/diagnostic_budget.dart`:
  - `DiagnosticBudget(ReportDiagnostics sink)`
  - `static const int kMaxPerRowDataDiagnostics = 100;`
  - `set row(int value)` / `int get row` — setting a new value clears the within-row dedup memory.
  - `void recordRowIssue(String key, String message, {DiagnosticSeverity severity = DiagnosticSeverity.warning, String? elementId})` — dedups by `key` within the current row, caps at the constant, prefixes the recorded message with `"Row <n>: "`.
  - `void finish()` — emits one info summary if any were suppressed; call once at fill completion.

---

### Task 1: `VariableAccumulator.skippedNonNumeric` (pure, lifetime-monotonic counter)

**Files:**
- Modify: `packages/jet_print/lib/src/expression/aggregate/variable_accumulator.dart`
- Test: `packages/jet_print/test/expression/aggregate/variable_accumulator_test.dart`

**Interfaces:**
- Produces: `int get skippedNonNumeric` on `VariableAccumulator`.

**Context:** `VariableAccumulator.fold(JetValue)` silently drops inputs that are the wrong type for the calculation (e.g. a `JetString` folded into a `SUM`). This task adds a pure counter of those drops. It must be lifetime-monotonic — `reset()` (called on group breaks) must NOT clear it — because Task 5 reads it as a per-row *delta* and a decreasing total would produce negative deltas.

- [ ] **Step 1: Write the failing tests**

Add these tests to `test/expression/aggregate/variable_accumulator_test.dart` (the file already imports everything needed):

```dart
  test('skippedNonNumeric counts wrong-type SUM inputs, not null/error', () {
    final VariableAccumulator a = _acc(JetCalculation.sum);
    a.fold(const JetNumber(2));
    a.fold(const JetNull()); // legit blank — NOT a skip
    a.fold(const JetError('x')); // error — NOT a skip
    a.fold(const JetString('y')); // wrong type — a skip
    a.fold(const JetNumber(3));
    expect(a.value, const JetNumber(5));
    expect(a.skippedNonNumeric, 1);
  });

  test('skippedNonNumeric counts wrong-type AVG inputs', () {
    final VariableAccumulator a = _acc(JetCalculation.average);
    a.fold(const JetNumber(4));
    a.fold(const JetString('nope')); // skip
    a.fold(const JetNumber(6));
    expect(a.value, const JetNumber(5)); // (4+6)/2
    expect(a.skippedNonNumeric, 1);
  });

  test('skippedNonNumeric counts incomparable MIN/MAX inputs (after first)', () {
    final VariableAccumulator a = _acc(JetCalculation.min);
    a.fold(const JetNumber(5)); // first value taken unconditionally
    a.fold(const JetString('x')); // incomparable to a number -> skip
    a.fold(const JetNumber(2));
    expect(a.value, const JetNumber(2));
    expect(a.skippedNonNumeric, 1);
  });

  test('count never skips; it accepts any non-null/non-error type', () {
    final VariableAccumulator a = _acc(JetCalculation.count);
    a.fold(const JetString('a'));
    a.fold(const JetNumber(1));
    expect(a.skippedNonNumeric, 0);
  });

  test('reset() does NOT clear skippedNonNumeric (lifetime-monotonic)', () {
    final VariableAccumulator a = _acc(JetCalculation.sum);
    a.fold(const JetString('y')); // skip
    expect(a.skippedNonNumeric, 1);
    a.reset();
    expect(a.value, const JetNumber(0), reason: 'value state resets');
    expect(a.skippedNonNumeric, 1, reason: 'skip count is lifetime-monotonic');
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/expression/aggregate/variable_accumulator_test.dart`
Expected: FAIL — `skippedNonNumeric` is not defined.

- [ ] **Step 3: Implement the counter**

In `lib/src/expression/aggregate/variable_accumulator.dart`, add the field + getter (place the field next to the other private fields, e.g. after `_hasValue`):

```dart
  int _skippedNonNumeric = 0;

  /// The lifetime count of inputs dropped because they were the wrong type for
  /// this calculation (e.g. a string folded into a SUM). Null/error inputs are
  /// legitimate blanks and are NOT counted. Lifetime-monotonic: [reset] does
  /// not clear it, so callers can read it as a per-row delta (spec E2).
  int get skippedNonNumeric => _skippedNonNumeric;
```

Then update `fold` to increment at the wrong-type branches:

```dart
    switch (calculation) {
      case JetCalculation.sum:
        if (input is JetNumber) {
          _sum += input.value;
        } else {
          _skippedNonNumeric++;
        }
      case JetCalculation.average:
        if (input is JetNumber) {
          _sum += input.value;
          _count++;
        } else {
          _skippedNonNumeric++;
        }
      case JetCalculation.count:
        _count++;
      case JetCalculation.min:
        if (!_hasValue) {
          _value = input;
          _hasValue = true;
        } else {
          final int? c = jetCompare(input, _value);
          if (c != null && c < 0) {
            _value = input;
          } else if (c == null) {
            _skippedNonNumeric++;
          }
        }
      case JetCalculation.max:
        if (!_hasValue) {
          _value = input;
          _hasValue = true;
        } else {
          final int? c = jetCompare(input, _value);
          if (c != null && c > 0) {
            _value = input;
          } else if (c == null) {
            _skippedNonNumeric++;
          }
        }
      case JetCalculation.first:
        if (!_hasValue) {
          _value = input;
          _hasValue = true;
        }
      case JetCalculation.last:
        _value = input;
        _hasValue = true;
      case JetCalculation.none:
        break; // handled above
    }
```

Leave `reset()` unchanged (it must NOT touch `_skippedNonNumeric`); add a one-line comment in `reset()` noting the omission is deliberate:

```dart
  void reset() {
    // NB: _skippedNonNumeric is intentionally NOT reset — it is a
    // lifetime-monotonic diagnostic counter (spec E2).
    _sum = 0;
    _count = 0;
    _value = const JetNull();
    _hasValue = false;
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/expression/aggregate/variable_accumulator_test.dart`
Expected: PASS (all tests, including the pre-existing ones).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/expression/aggregate/variable_accumulator.dart packages/jet_print/test/expression/aggregate/variable_accumulator_test.dart
git commit -m "feat(e2): VariableAccumulator.skippedNonNumeric (lifetime-monotonic)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `VariableCalculator.aggregateSkips` (pure getter)

**Files:**
- Modify: `packages/jet_print/lib/src/expression/aggregate/variable_calculator.dart`
- Test: `packages/jet_print/test/expression/aggregate/variable_calculator_test.dart`

**Interfaces:**
- Consumes: `VariableAccumulator.skippedNonNumeric` (Task 1).
- Produces: `int get aggregateSkips` on `VariableCalculator`.

**Context:** The master calculator owns a private `List<VariableAccumulator> _accumulators`. This getter sums their skip counts so the filler (Task 5) can read a per-row delta. Because the counter is lifetime-monotonic, this total never decreases — even when a group break calls `reset()` on a group-scoped accumulator.

- [ ] **Step 1: Write the failing test**

Add to `test/expression/aggregate/variable_calculator_test.dart`. Add a helper that builds a row with an arbitrary `amount` value (the existing `_row` types `amount` as `double`; we need a wrong-type value), then the test:

```dart
  DataRow _rowAny(String cat, Object? amount) => DataRow(
        fields: const <FieldDef>[
          FieldDef('category', type: JetFieldType.string),
          FieldDef('amount', type: JetFieldType.double),
        ],
        values: <String, Object?>{'category': cat, 'amount': amount},
      );

  test('aggregateSkips counts wrong-type folds and is monotonic across a '
      'group break (reset does not lower it)', () {
    final VariableCalculator c = _calc()..start();
    c.advance(_rowAny('A', 10.0));
    expect(c.aggregateSkips, 0);
    // 'oops' folds into BOTH catTotal (group sum) and grand (report sum) -> +2.
    c.advance(_rowAny('A', 'oops'));
    expect(c.aggregateSkips, 2);
    // Group break resets catTotal's accumulator; the monotonic skip total must
    // NOT drop.
    c.advance(_rowAny('B', 3.0));
    expect(c.brokenGroups, <String>{'category'});
    expect(c.aggregateSkips, greaterThanOrEqualTo(2));
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/expression/aggregate/variable_calculator_test.dart`
Expected: FAIL — `aggregateSkips` is not defined.

- [ ] **Step 3: Implement the getter**

In `lib/src/expression/aggregate/variable_calculator.dart`, add after `brokenGroups`:

```dart
  /// The lifetime total of wrong-type inputs dropped across all of this
  /// calculator's aggregates (spec E2). Monotonic — group-break resets do not
  /// lower it — so the fill stage can read it as a per-row delta.
  int get aggregateSkips {
    int n = 0;
    for (final VariableAccumulator a in _accumulators) {
      n += a.skippedNonNumeric;
    }
    return n;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/jet_print && flutter test test/expression/aggregate/variable_calculator_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/expression/aggregate/variable_calculator.dart packages/jet_print/test/expression/aggregate/variable_calculator_test.dart
git commit -m "feat(e2): VariableCalculator.aggregateSkips (monotonic total)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `DiagnosticBudget` (new fill-layer class)

**Files:**
- Create: `packages/jet_print/lib/src/rendering/fill/diagnostic_budget.dart`
- Test: `packages/jet_print/test/rendering/fill/diagnostic_budget_test.dart`

**Interfaces:**
- Consumes: `ReportDiagnostics` (`lib/src/rendering/fill/report_diagnostics.dart`), `Diagnostic` / `DiagnosticSeverity` (`lib/src/domain/diagnostic.dart`).
- Produces: the `DiagnosticBudget` API in the Shared Interfaces block above.

**Context:** A fill over a large dirty dataset can hit the same fault on thousands of rows. This budget bounds the per-row *data* diagnostics it records (so the diagnostics list can't itself become the memory blow-up resilience is meant to prevent), dedups repeats within a row, and tags each with the row position.

- [ ] **Step 1: Write the failing tests**

Create `test/rendering/fill/diagnostic_budget_test.dart`:

```dart
// DiagnosticBudget: row-tagging, within-row dedup, cap + suppression (spec E2).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/rendering/fill/diagnostic_budget.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';

void main() {
  test('prefixes the recorded message with the current row position', () {
    final ReportDiagnostics sink = ReportDiagnostics();
    final DiagnosticBudget b = DiagnosticBudget(sink)..row = 7;
    b.recordRowIssue('k', 'something is off', elementId: 'e1');
    expect(sink.entries, hasLength(1));
    expect(sink.entries.single.message, 'Row 7: something is off');
    expect(sink.entries.single.severity, DiagnosticSeverity.warning);
    expect(sink.entries.single.elementId, 'e1');
  });

  test('dedups by key within a row but re-allows it after the row advances',
      () {
    final ReportDiagnostics sink = ReportDiagnostics();
    final DiagnosticBudget b = DiagnosticBudget(sink)..row = 1;
    b.recordRowIssue('field:x', 'x missing');
    b.recordRowIssue('field:x', 'x missing'); // same key, same row -> ignored
    expect(sink.entries, hasLength(1));
    b.row = 2;
    b.recordRowIssue('field:x', 'x missing'); // new row -> recorded again
    expect(sink.entries, hasLength(2));
    expect(sink.entries.last.message, 'Row 2: x missing');
  });

  test('caps at kMaxPerRowDataDiagnostics and summarizes the remainder', () {
    final ReportDiagnostics sink = ReportDiagnostics();
    final DiagnosticBudget b = DiagnosticBudget(sink);
    const int over = DiagnosticBudget.kMaxPerRowDataDiagnostics + 25;
    for (int i = 0; i < over; i++) {
      b.row = i + 1; // distinct key per row, so dedup never blocks
      b.recordRowIssue('agg', 'skip');
    }
    // Only the cap many are recorded so far (no summary until finish()).
    expect(sink.entries, hasLength(DiagnosticBudget.kMaxPerRowDataDiagnostics));
    b.finish();
    final Diagnostic summary = sink.entries.last;
    expect(summary.severity, DiagnosticSeverity.info);
    expect(summary.message, contains('25 more'));
    expect(summary.message, contains('suppressed'));
  });

  test('finish() is a no-op when nothing was suppressed', () {
    final ReportDiagnostics sink = ReportDiagnostics();
    final DiagnosticBudget b = DiagnosticBudget(sink)..row = 1;
    b.recordRowIssue('k', 'one');
    b.finish();
    expect(sink.entries, hasLength(1));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/rendering/fill/diagnostic_budget_test.dart`
Expected: FAIL — `diagnostic_budget.dart` does not exist.

- [ ] **Step 3: Implement `DiagnosticBudget`**

Create `lib/src/rendering/fill/diagnostic_budget.dart`:

```dart
/// Bounds and row-tags per-row *data* diagnostics during a fill (spec E2).
///
/// A fill over a large, dirty dataset can encounter the same data fault on
/// thousands of rows. Recording one diagnostic per occurrence would grow an
/// unbounded list (the very memory blow-up resilience is meant to prevent),
/// while the engine's historical global-dedup hides *where* the fault is. This
/// budget threads the current master-row position into each per-row data
/// diagnostic, dedups repeats *within a row* by a caller [key], and caps the
/// total emitted at [kMaxPerRowDataDiagnostics] — emitting a single trailing
/// summary at [finish] when any were suppressed.
///
/// Only per-row DATA faults route through here; structural/definition
/// diagnostics (a field/collection absent from the schema, a parse error) stay
/// deduped-once on their existing paths.
library;

import '../../domain/diagnostic.dart';
import 'report_diagnostics.dart';

/// Row-aware, bounded sink wrapper for per-row data diagnostics.
class DiagnosticBudget {
  /// Creates a budget that records into [_sink].
  DiagnosticBudget(this._sink);

  /// The maximum number of per-row data diagnostics recorded before the rest
  /// are counted and summarized at [finish] (spec E2, FR-E2-002).
  static const int kMaxPerRowDataDiagnostics = 100;

  final ReportDiagnostics _sink;
  int _row = 0;
  int _emitted = 0;
  int _suppressed = 0;
  final Set<String> _seenThisRow = <String>{};

  /// The current 1-based master-row position. Setting a new value clears the
  /// within-row dedup memory so the same [key] can be reported again next row.
  set row(int value) {
    if (value != _row) {
      _row = value;
      _seenThisRow.clear();
    }
  }

  int get row => _row;

  /// Records one per-row data issue, deduped by [key] within the current row
  /// and bounded by [kMaxPerRowDataDiagnostics]. The recorded message is
  /// prefixed with the row position; [severity] defaults to warning.
  void recordRowIssue(
    String key,
    String message, {
    DiagnosticSeverity severity = DiagnosticSeverity.warning,
    String? elementId,
  }) {
    if (!_seenThisRow.add(key)) return; // already reported for this row
    if (_emitted >= kMaxPerRowDataDiagnostics) {
      _suppressed++;
      return;
    }
    _emitted++;
    _sink.add(
        Diagnostic(severity, 'Row $_row: $message', elementId: elementId));
  }

  /// Emits a single summary [DiagnosticSeverity.info] when any per-row data
  /// issues were suppressed; a no-op otherwise. Call once at fill completion.
  void finish() {
    if (_suppressed > 0) {
      _sink.info('… and $_suppressed more row-level data issue(s) were '
          'suppressed (showing first $kMaxPerRowDataDiagnostics)');
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/rendering/fill/diagnostic_budget_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill/diagnostic_budget.dart packages/jet_print/test/rendering/fill/diagnostic_budget_test.dart
git commit -m "feat(e2): DiagnosticBudget — row-tagged, bounded per-row data diagnostics

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire the budget into the fill — R2 (missing field) + R7 (non-row entry) row-tagged

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Modify: `packages/jet_print/lib/src/rendering/fill/fill_eval_context.dart`
- Modify: `packages/jet_print/lib/src/rendering/fill/element_resolver.dart`
- Test: `packages/jet_print/test/rendering/fill/per_row_diagnostics_test.dart`

**Interfaces:**
- Consumes: `DiagnosticBudget` (Task 3).
- Produces: the filler now owns a `DiagnosticBudget`, sets `budget.row` per master row, calls `budget.finish()`, and routes R2 + R7 through it. `FillEvalContext` and `ElementResolver` accept an optional `DiagnosticBudget? budget`.

**Context:** Today a missing field (R2) and a non-row collection entry (R7) emit globally-deduped warnings, so the host can't tell which rows are bad. Route both through the budget so they carry the row position and are capped. **Preserve the original message wording** (the budget only *prefixes* `"Row <n>: "`) and **preserve `elementId`**, so existing diagnostic tests that substring-match keep passing; only count-based assertions over multi-row dirty data change (that is the intended behavior change — reconcile them when you run the full suite in Step 6).

- [ ] **Step 1: Write the failing tests**

Create `test/rendering/fill/per_row_diagnostics_test.dart`:

```dart
// Per-row data diagnostics carry the row position and are bounded (spec E2,
// R2 missing field + R7 non-row collection entry).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 100, height: 12);

TextElement _el(String id, {String? text, String? expr}) =>
    TextElement(id: id, bounds: _r, text: text ?? '', expression: expr);

ReportDefinition _flat(List<ReportElement> detail) => ReportDefinition(
      name: 'perRow',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 12,
              elements: detail)),
        ]),
      ),
    );

List<Diagnostic> _warnings(FillResult res) => res.diagnostics.entries
    .where((Diagnostic d) => d.severity == DiagnosticSeverity.warning)
    .toList();

void main() {
  test('R2: missing field is row-tagged, once per row, elementId preserved',
      () {
    final FillResult res = ReportFiller().fillDefinition(
      _flat(<ReportElement>[_el('bad', expr: r'$F{nope}')]),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'name': 'a'},
        <String, Object?>{'name': 'b'},
      ]),
    );
    final List<Diagnostic> w = _warnings(res);
    expect(w, hasLength(2), reason: 'one per row, not globally deduped');
    expect(w[0].message, startsWith('Row 1: '));
    expect(w[0].message, contains('nope'));
    expect(w[0].elementId, 'bad');
    expect(w[1].message, startsWith('Row 2: '));
  });

  test('R7: a non-row collection entry is row-tagged', () {
    final FillResult res = ReportFiller().fillDefinition(
      ReportDefinition(
        name: 'r7',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'line',
                    type: BandType.detail,
                    height: 12,
                    elements: <ReportElement>[_el('v', expr: r'$F{v}')])),
              ],
            )),
          ]),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'lines': <Object?>[
            <String, Object?>{'v': 1},
            'I am not a row', // non-row entry
          ],
        },
      ]),
    );
    final Diagnostic d = _warnings(res).firstWhere(
        (Diagnostic d) => d.message.contains('non-row entry'),
        orElse: () => fail('no non-row-entry diagnostic: '
            '${res.diagnostics.entries}'));
    expect(d.message, startsWith('Row 1: '));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/rendering/fill/per_row_diagnostics_test.dart`
Expected: FAIL — today R2 is globally deduped (one warning, no `Row N:` prefix) and R7 has no row prefix.

- [ ] **Step 3: Add the optional budget to `FillEvalContext`**

In `lib/src/rendering/fill/fill_eval_context.dart`: add the import, a constructor parameter, a field, and route `resolveField`'s missing-field branch through the budget when present.

Add to imports:
```dart
import 'diagnostic_budget.dart';
```
Add the constructor parameter (after `String? elementId,`) and field:
```dart
    DiagnosticBudget? budget,
```
```dart
        _elementId = elementId,
        _budget = budget;
```
```dart
  final String? _elementId;
  final DiagnosticBudget? _budget;
```
Replace the missing-field branch in `resolveField`:
```dart
    if (!row.hasField(name)) {
      final DiagnosticBudget? budget = _budget;
      if (budget != null) {
        budget.recordRowIssue('field:$name',
            'Field "$name" is not in the data schema', elementId: _elementId);
      } else if (_warnedFields.add(name)) {
        _diagnostics.warning('Field "$name" is not in the data schema',
            elementId: _elementId);
      }
      return const JetNull();
    }
```

- [ ] **Step 4: Thread the budget through `ElementResolver`**

In `lib/src/rendering/fill/element_resolver.dart`: add an optional `budget` to the constructor + a field, and pass it into the `FillEvalContext` built in `_resolveText`.

Add the import:
```dart
import 'diagnostic_budget.dart';
```
Add a constructor parameter and field (mirror the existing `warnedFields` wiring):
```dart
    this.budget,
```
```dart
  /// The per-row diagnostic budget (spec E2), or null when the caller does not
  /// supply one (warnings then fall back to global dedup).
  final DiagnosticBudget? budget;
```
In `_resolveText`, add `budget: budget,` to the `FillEvalContext(...)` construction (alongside `warnedFields:` / `pageRefs:` / `elementId:`).

- [ ] **Step 5: Own the budget in `ReportFiller` — create it, set the row, route R7, finish**

In `lib/src/rendering/fill/report_filler.dart`:

(a) Add the import:
```dart
import 'diagnostic_budget.dart';
```

(b) After `final ReportDiagnostics diagnostics = ReportDiagnostics();` create the budget:
```dart
    final DiagnosticBudget budget = DiagnosticBudget(diagnostics);
```

(c) Pass `budget: budget,` into the `ElementResolver(...)` construction and into the `FillEvalContext(...)` built inside `contextFactory`.

(d) Route the R7 (non-row entry) branch in `childRowsOf` through the budget. Replace:
```dart
        } else if (warnedCollections.add('$name#entry')) {
          diagnostics.warning(
              'Collection field "$name" contains a non-row entry; it is '
              'skipped');
        }
```
with:
```dart
        } else {
          budget.recordRowIssue('coll-entry:$name',
              'Collection field "$name" contains a non-row entry; it is '
              'skipped');
        }
```
(Leave the not-in-schema and not-a-list branches above it unchanged — those stay deduped-once structural diagnostics.)

(e) Set the row position at the top of the master loop and call `finish()` at the end. Add a counter before the loop:
```dart
    bool hadRows = false;
    int rowNumber = 0;
```
At the very top of the `while (ds.moveNext())` body (before `augmentForScope`):
```dart
        budget.row = ++rowNumber;
```
After the `if (!hadRows) { ... } else { ... }` block that follows the loop (just before `return FillResult(`):
```dart
    budget.finish();
```

- [ ] **Step 6: Run the new test, then the FULL suite to reconcile existing diagnostics**

Run: `cd packages/jet_print && flutter test test/rendering/fill/per_row_diagnostics_test.dart`
Expected: PASS.

Then run the full documented CI command and reconcile any failures:
Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print apps/jet_print_playground`
Expected: All green. **If a pre-existing diagnostics test now fails**, it is because R2 changed from globally-deduped to per-row (intended). For a single-row test the only change is the `"Row 1: "` prefix — a `contains`/`startsWith` assertion still passes; an exact-equality assertion or a multi-row count must be updated to the new per-row form. Update those tests (do not revert the behavior). Note each updated test in the commit message.

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill/ packages/jet_print/test/rendering/fill/per_row_diagnostics_test.dart
# also add any existing test files you had to reconcile
git commit -m "feat(e2): route R2 missing-field + R7 non-row-entry through DiagnosticBudget

Per-row data faults now carry the master-row position and are capped at 100;
structural diagnostics stay deduped-once.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Surface aggregate skips at the persistent-accumulator sites (master calculator + descendant)

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test: `packages/jet_print/test/rendering/fill/aggregate_skip_diagnostics_test.dart`

**Interfaces:**
- Consumes: `VariableCalculator.aggregateSkips` (Task 2), `VariableAccumulator.skippedNonNumeric` (Task 1), `DiagnosticBudget` (Task 3, already owned by the filler from Task 4).

**Context:** The two *persistent* accumulator sites both fold inside the master loop with the master row in hand: the master `VariableCalculator` (report/group `$V{}` variables and inline `{SUM([...])}`) and the descendant accumulators `descAcc` (spec 033 roll-ups at the summary / group footer). Read each one's per-row skip *delta* and route it through the budget. Deltas are always ≥ 0 because the counter is lifetime-monotonic (Task 1).

- [ ] **Step 1: Write the failing tests**

Create `test/rendering/fill/aggregate_skip_diagnostics_test.dart`:

```dart
// Wrong-type aggregate inputs are surfaced (spec E2, R3/R4) — previously
// silent. Persistent-accumulator sites: master calculator + descendant.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 100, height: 12);

TextElement _el(String id, {String? text, String? expr}) =>
    TextElement(id: id, bounds: _r, text: text ?? '', expression: expr);

Diagnostic _match(FillResult res, Pattern p) => res.diagnostics.entries
    .firstWhere((Diagnostic d) => d.message.contains(p),
        orElse: () => fail('no diagnostic matching "$p": '
            '${res.diagnostics.entries}'));

String _summaryText(FillResult res, String id) =>
    (res.report.bands.last.elements.firstWhere((ReportElement e) => e.id == id)
            as TextElement)
        .text;

// ---- master calculator (report-scoped SUM over a wrong-type field) ----

ReportDefinition _masterSumDef() => ReportDefinition(
      name: 'masterSum',
      page: PageFormat.a4Portrait,
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'total',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.report,
        ),
      ],
      body: ReportBody(
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 12,
          elements: <ReportElement>[_el('total', expr: r'$V{total}')],
        ),
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 12,
              elements: <ReportElement>[_el('amt', expr: r'$F{amount}')])),
        ]),
      ),
    );

// ---- descendant SUM at the summary over a wrong-type leaf ----
// (lifted from descendant_summary_fill_test.dart; explicit schema is required
//  because inference does not type nested List<Map> columns as collections.)

const List<FieldDef> _rootSchema = <FieldDef>[
  FieldDef('customerCode', type: JetFieldType.string),
  FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('orderId', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('lineTotal', type: JetFieldType.double),
    ]),
  ]),
];

ReportDefinition _descendantSummaryDef() => ReportDefinition(
      name: 'descSummary',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 12,
          elements: <ReportElement>[
            _el('grand', expr: r'SUM($F{lineTotal})'),
          ],
        ),
        root: DetailScope(id: 'root', children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'orders',
            collectionField: 'orders',
            children: <ScopeNode>[
              NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                children: <ScopeNode>[
                  BandNode(Band(
                      id: 'line-detail',
                      type: BandType.detail,
                      height: 12,
                      elements: <ReportElement>[
                        _el('lineTotal', expr: r'$F{lineTotal}'),
                      ])),
                ],
              )),
            ],
          )),
        ]),
      ),
    );

void main() {
  test('R3: master-calculator SUM surfaces a row-tagged skip and still sums '
      'the clean rows', () {
    final FillResult res = ReportFiller().fillDefinition(
      _masterSumDef(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'amount': 10.0},
        <String, Object?>{'amount': 'oops'}, // row 2 — wrong type
        <String, Object?>{'amount': 5.0},
      ]),
    );
    final Diagnostic d = _match(res, 'skipped from a numeric aggregate');
    expect(d.severity, DiagnosticSeverity.warning);
    expect(d.message, startsWith('Row 2: '));
    expect(_summaryText(res, 'total'), '15.0',
        reason: 'clean rows still sum; the bad row is isolated');
  });

  test('R3: descendant roll-up SUM surfaces a row-tagged skip', () {
    final FillResult res = ReportFiller().fillDefinition(
      _descendantSummaryDef(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'customerCode': 'A',
          'orders': <Map<String, Object?>>[
            <String, Object?>{
              'orderId': '1',
              'lines': <Map<String, Object?>>[
                <String, Object?>{'lineTotal': 10.0},
                <String, Object?>{'lineTotal': 'bad'}, // wrong type
                <String, Object?>{'lineTotal': 20.0},
              ],
            },
          ],
        },
      ], fields: _rootSchema),
    );
    final Diagnostic d = _match(res, 'skipped from a roll-up aggregate');
    expect(d.message, startsWith('Row 1: '));
    expect(_summaryText(res, 'grand'), '30.0',
        reason: 'clean leaves still sum (10 + 20)');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/rendering/fill/aggregate_skip_diagnostics_test.dart`
Expected: FAIL — no skip diagnostics are produced yet (the skips are silent).

- [ ] **Step 3: Read the master-calculator skip delta in the loop**

In `lib/src/rendering/fill/report_filler.dart`, in the `while (ds.moveNext())` body, replace:
```dart
        final DataRow row = augmentForScope(definition.body.root, ds.current);
        calc.advance(row, params: params);
```
with:
```dart
        final DataRow row = augmentForScope(definition.body.root, ds.current);
        final int calcSkipsBefore = calc.aggregateSkips;
        calc.advance(row, params: params);
        final int calcSkipDelta = calc.aggregateSkips - calcSkipsBefore;
        if (calcSkipDelta > 0) {
          budget.recordRowIssue('agg:calc',
              '$calcSkipDelta non-numeric value(s) were skipped from a '
              'numeric aggregate');
        }
```

- [ ] **Step 4: Read the descendant skip delta around the fold loop**

Add a private helper to the `ReportFiller` class (next to the other `static` helpers near the bottom):
```dart
  /// The total wrong-type skips across [accs] (spec E2). Monotonic per
  /// accumulator, so a difference of two reads is a non-negative per-row delta.
  static int _sumAccSkips(Iterable<VariableAccumulator> accs) {
    int n = 0;
    for (final VariableAccumulator a in accs) {
      n += a.skippedNonNumeric;
    }
    return n;
  }
```
Then wrap the descendant fold loop. Replace:
```dart
        for (final DescendantAggregate a in descAggs) {
          foldDescInto(a, row);
        }
```
with:
```dart
        final int descSkipsBefore = _sumAccSkips(descAcc.values);
        for (final DescendantAggregate a in descAggs) {
          foldDescInto(a, row);
        }
        final int descSkipDelta = _sumAccSkips(descAcc.values) - descSkipsBefore;
        if (descSkipDelta > 0) {
          budget.recordRowIssue('agg:desc',
              '$descSkipDelta non-numeric value(s) were skipped from a '
              'roll-up aggregate');
        }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/rendering/fill/aggregate_skip_diagnostics_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill/report_filler.dart packages/jet_print/test/rendering/fill/aggregate_skip_diagnostics_test.dart
git commit -m "feat(e2): surface wrong-type skips at master-calc + descendant aggregates

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Surface aggregate skips at the fresh-accumulator sites (published totals + nested footers)

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test: `packages/jet_print/test/rendering/fill/aggregate_skip_nested_test.dart`

**Interfaces:**
- Consumes: `VariableAccumulator.skippedNonNumeric` (Task 1), `DiagnosticBudget` (Task 3).

**Context:** The other two aggregation sites build a *fresh* accumulator per scope instance, so there is no delta to take — read `skippedNonNumeric` directly after folding. `augmentForScope` folds a scope's published `ScopeTotal`s (spec 030); `emitNode` folds a nested scope's footer aggregates (spec 029/033). Both run within the master loop, after `budget.row` is set.

- [ ] **Step 1: Write the failing tests**

Create `test/rendering/fill/aggregate_skip_nested_test.dart`:

```dart
// Wrong-type aggregate inputs at the FRESH-accumulator sites are surfaced
// (spec E2): published totals (030) and nested-scope footers (029/033).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/scope_total.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 100, height: 12);

TextElement _el(String id, {String? text, String? expr}) =>
    TextElement(id: id, bounds: _r, text: text ?? '', expression: expr);

Diagnostic _match(FillResult res, Pattern p) => res.diagnostics.entries
    .firstWhere((Diagnostic d) => d.message.contains(p),
        orElse: () => fail('no diagnostic matching "$p": '
            '${res.diagnostics.entries}'));

// ---- published total (030): scope 'lines' publishes SUM($F{amount}) ----

ReportDefinition _scopeTotalDef() => ReportDefinition(
      name: 'scopeTotal',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'lines',
            collectionField: 'lines',
            totals: const <ScopeTotal>[ScopeTotal('lineSum', r'SUM($F{amount})')],
            children: <ScopeNode>[
              BandNode(Band(
                  id: 'line',
                  type: BandType.detail,
                  height: 12,
                  elements: <ReportElement>[_el('a', expr: r'$F{amount}')])),
            ],
          )),
        ]),
      ),
    );

// ---- nested footer (029/033): orders footer SUM($F{lineTotal}) ----
// (lifted from descendant_footer_fill_test.dart)

ReportDefinition _nestedFooterDef() => ReportDefinition(
      name: 'nestedFooter',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'orders',
            collectionField: 'orders',
            footer: Band(
              id: 'orders-footer',
              type: BandType.groupFooter,
              height: 12,
              elements: <ReportElement>[
                _el('orderTotal', expr: r'SUM($F{lineTotal})'),
              ],
            ),
            children: <ScopeNode>[
              BandNode(Band(
                  id: 'order-detail',
                  type: BandType.detail,
                  height: 12,
                  elements: <ReportElement>[_el('orderId', expr: r'$F{orderId}')])),
              NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                children: <ScopeNode>[
                  BandNode(Band(
                      id: 'line-detail',
                      type: BandType.detail,
                      height: 12,
                      elements: <ReportElement>[
                        _el('lineTotal', expr: r'$F{lineTotal}'),
                      ])),
                ],
              )),
            ],
          )),
        ]),
      ),
    );

void main() {
  test('R3: a published total surfaces a row-tagged skip', () {
    final FillResult res = ReportFiller().fillDefinition(
      _scopeTotalDef(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'lines': <Map<String, Object?>>[
            <String, Object?>{'amount': 10.0},
            <String, Object?>{'amount': 'x'}, // wrong type
            <String, Object?>{'amount': 5.0},
          ],
        },
      ]),
    );
    final Diagnostic d = _match(res, 'published total "lineSum"');
    expect(d.severity, DiagnosticSeverity.warning);
    expect(d.message, startsWith('Row 1: '));
    expect(d.message, contains('skipped'));
  });

  test('R3: a nested-scope footer aggregate surfaces a row-tagged skip', () {
    final FillResult res = ReportFiller().fillDefinition(
      _nestedFooterDef(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'orders': <Map<String, Object?>>[
            <String, Object?>{
              'orderId': 'A',
              'lines': <Map<String, Object?>>[
                <String, Object?>{'lineTotal': 10.0},
                <String, Object?>{'lineTotal': 'nope'}, // wrong type
              ],
            },
          ],
        },
      ]),
    );
    final Diagnostic d = _match(res, 'footer aggregate "orderTotal"');
    expect(d.message, startsWith('Row 1: '));
    expect(d.message, contains('skipped'));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/rendering/fill/aggregate_skip_nested_test.dart`
Expected: FAIL — these skips are still silent.

- [ ] **Step 3: Surface published-total skips in `augmentForScope`**

In `lib/src/rendering/fill/report_filler.dart`, inside `augmentForScope`, in the `for (final ScopeAgg a in scopeAggsById[cs.id] ...)` loop, right after the inner `for (final DataRow acr in augChildren)` fold loop completes and before `extras[a.name] = acc.value;`, add:
```dart
          if (acc.skippedNonNumeric > 0) {
            budget.recordRowIssue('agg:scope:${cs.id}:${a.name}',
                '${acc.skippedNonNumeric} non-numeric value(s) were skipped '
                'from published total "${a.name}"');
          }
```
(Place it before the existing collision `if (row.hasField(a.name) || extras.containsKey(a.name))` warning so the read happens once per scope-total per scope instance.)

- [ ] **Step 4: Surface nested-footer skips in `emitNode`**

Still in `report_filler.dart`, in `emitNode`'s `NestedScope` case, inside the final `if (footer != null) { ... }` block, immediately before `addBand(footer.band, scopeRow, vars);`, add:
```dart
            for (int k = 0; k < footer.aggs.length; k++) {
              final int skips = accs![k].skippedNonNumeric;
              if (skips > 0) {
                budget.recordRowIssue('agg:footer:${s.id}:${footer.aggs[k].name}',
                    '$skips non-numeric value(s) were skipped from footer '
                    'aggregate "${footer.aggs[k].name}"');
              }
            }
```
(`accs` is non-null whenever `footer != null`, as it is constructed alongside the footer; `s` is the nested `DetailScope` bound by the `case NestedScope(scope: final DetailScope s)` pattern.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/rendering/fill/aggregate_skip_nested_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full fill suite to confirm no regressions**

Run: `cd packages/jet_print && flutter test test/rendering/fill test/expression`
Expected: All green (the existing descendant/scope/footer fixtures use clean numeric data, so they record no new diagnostics).

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill/report_filler.dart packages/jet_print/test/rendering/fill/aggregate_skip_nested_test.dart
git commit -m "feat(e2): surface wrong-type skips at published-total + nested-footer aggregates

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Bad-data resilience matrix (R1–R11 contract suite)

**Files:**
- Create: `packages/jet_print/test/rendering/resilience/bad_data_matrix_test.dart`

**Interfaces:**
- Consumes: the public engine `JetReportEngine().renderDefinition`, `RenderedReport.diagnostics`, and the per-row diagnostics behavior finalized in Tasks 4–6.

**Context:** This is a tests-only contract suite that pins the engine's render-don't-crash guarantees so they cannot silently regress. Every case asserts: (a) the fill/render does not throw, (b) the documented fallback renders, and (c) the expected diagnostic. No production code changes.

- [ ] **Step 1: Write the matrix suite**

Create `test/rendering/resilience/bad_data_matrix_test.dart`:

```dart
// Bad-data resilience matrix (spec E2, R1–R11). Each fault renders a
// best-effort fallback with no crash and the expected diagnostic. This is a
// CONTRACT suite: it locks the engine's render-don't-crash guarantees.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 360, height: 16);

TextElement _t(String id, {String? text, String? expr, double y = 0}) =>
    TextElement(
      id: id,
      bounds: JetRect(x: 0, y: y, width: 360, height: 16),
      text: text ?? id,
      expression: expr,
    );

ReportDefinition _flat(
  List<ReportElement> detail, {
  Band? summary,
  Band? noData,
  List<ReportVariable> variables = const <ReportVariable>[],
}) =>
    ReportDefinition(
      name: 'matrix',
      page: const PageFormat(
          width: 400, height: 400, margins: JetEdgeInsets.all(10)),
      variables: variables,
      body: ReportBody(
        summary: summary,
        noData: noData,
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'root/c0', type: BandType.detail, height: 40, elements: detail)),
        ]),
      ),
    );

RenderedReport _render(ReportDefinition def, List<Map<String, Object?>> rows) =>
    const JetReportEngine()
        .renderDefinition(def, JetInMemoryDataSource(rows));

List<Diagnostic> _diags(RenderedReport r) => r.diagnostics.entries;

Diagnostic _match(RenderedReport r, Pattern p) => _diags(r).firstWhere(
    (Diagnostic d) => d.message.contains(p),
    orElse: () => fail('no diagnostic matching "$p": ${_diags(r)}'));

Map<String, String> _texts(RenderedReport r) => <String, String>{
      for (final TextRunPrimitive p
          in r.pageAt(0).frame.primitives.whereType<TextRunPrimitive>())
        if (p.elementId != null)
          p.elementId!: p.lines.map((TextLine l) => l.text).join(),
    };

Band _summaryBand(String id, String expr) => Band(
      id: 'body/summary',
      type: BandType.summary,
      height: 16,
      elements: <ReportElement>[_t(id, expr: expr)],
    );

void main() {
  test('R1: schema-aware unknown field -> token + deduped (structural) warning',
      () {
    // With knownFields supplied, the resolver returns the unresolved token and
    // warns ONCE for the whole report (structural — not per row).
    final RenderedReport r = const JetReportEngine().renderDefinition(
      _flat(<ReportElement>[_t('good', expr: r'$F{name}'), _t('bad', expr: r'$F{nope}')]),
      JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{'name': 'alpha'}]),
      options: const RenderOptions(knownFields: <String>{'name'}),
    );
    final List<Diagnostic> nope =
        _diags(r).where((Diagnostic d) => d.message.contains('nope')).toList();
    expect(nope, hasLength(1), reason: 'deduped once for the report');
    expect(nope.single.severity, DiagnosticSeverity.warning);
    expect(_texts(r)['good'], 'alpha');
    expect(_texts(r)['bad'], '#ERROR', reason: 'the unresolved-field token');
  });

  test('R2: non-schema-aware missing field is row-tagged (one per row)', () {
    // No knownFields: a binding to a field absent from the data schema renders
    // blank and warns PER ROW with the row position (not globally deduped).
    final RenderedReport r = _render(
      _flat(<ReportElement>[_t('bad', expr: r'$F{nope}')]),
      <Map<String, Object?>>[
        <String, Object?>{'name': 'a'},
        <String, Object?>{'name': 'b'},
      ],
    );
    final List<Diagnostic> nope = _diags(r)
        .where((Diagnostic d) =>
            d.severity == DiagnosticSeverity.warning && d.message.contains('nope'))
        .toList();
    expect(nope, hasLength(2), reason: 'one per row, not globally deduped');
    expect(nope[0].message, contains('Row 1'));
    expect(nope[1].message, contains('Row 2'));
    expect(_texts(r)['bad'], '', reason: 'blank fallback');
  });

  test('R3: wrong-type SUM input is surfaced (row-tagged) and clean rows sum',
      () {
    final RenderedReport r = _render(
      _flat(
        <ReportElement>[_t('amt', expr: r'$F{amount}')],
        summary: _summaryBand('total', r'$V{total}'),
        variables: const <ReportVariable>[
          ReportVariable(
              name: 'total',
              expression: r'$F{amount}',
              calculation: JetCalculation.sum,
              resetScope: VariableResetScope.report),
        ],
      ),
      <Map<String, Object?>>[
        <String, Object?>{'amount': 10.0},
        <String, Object?>{'amount': 'oops'},
        <String, Object?>{'amount': 5.0},
      ],
    );
    final Diagnostic d = _match(r, 'skipped from a numeric aggregate');
    expect(d.severity, DiagnosticSeverity.warning);
    expect(d.message, contains('Row '));
  });

  test('R4: wrong-type MIN/MAX input does not crash (best-effort)', () {
    final RenderedReport r = _render(
      _flat(
        <ReportElement>[_t('amt', expr: r'$F{amount}')],
        summary: _summaryBand('peak', r'$V{peak}'),
        variables: const <ReportVariable>[
          ReportVariable(
              name: 'peak',
              expression: r'$F{amount}',
              calculation: JetCalculation.max,
              resetScope: VariableResetScope.report),
        ],
      ),
      <Map<String, Object?>>[
        <String, Object?>{'amount': 3.0},
        <String, Object?>{'amount': 'x'},
        <String, Object?>{'amount': 9.0},
      ],
    );
    // No throw; the report renders. (MIN/MAX over mixed types is best-effort.)
    expect(r.pageCount, greaterThan(0));
    expect(_texts(r)['amt'], isNotNull);
  });

  test('R5: a null collection field emits no nested rows, no diagnostic', () {
    final RenderedReport r = const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'r5',
        page: const PageFormat(
            width: 400, height: 400, margins: JetEdgeInsets.all(10)),
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'line',
                    type: BandType.detail,
                    height: 16,
                    elements: <ReportElement>[_t('v', expr: r'$F{v}')])),
              ],
            )),
          ]),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'lines': null},
      ]),
    );
    expect(r.pageCount, greaterThan(0));
    expect(_diags(r).where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty);
  });

  test('R6: a non-list collection field warns and emits no rows', () {
    final RenderedReport r = const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'r6',
        page: const PageFormat(
            width: 400, height: 400, margins: JetEdgeInsets.all(10)),
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'line',
                    type: BandType.detail,
                    height: 16,
                    elements: <ReportElement>[_t('v', expr: r'$F{v}')])),
              ],
            )),
          ]),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'lines': 'not a list'},
      ]),
    );
    _match(r, 'did not resolve to a collection');
    expect(r.pageCount, greaterThan(0));
  });

  test('R7: a non-row entry inside a collection is skipped + row-tagged', () {
    final RenderedReport r = const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'r7',
        page: const PageFormat(
            width: 400, height: 400, margins: JetEdgeInsets.all(10)),
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'line',
                    type: BandType.detail,
                    height: 16,
                    elements: <ReportElement>[_t('v', expr: r'$F{v}')])),
              ],
            )),
          ]),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'lines': <Object?>[
            <String, Object?>{'v': 1},
            'not a row',
          ],
        },
      ]),
    );
    final Diagnostic d = _match(r, 'non-row entry');
    expect(d.message, contains('Row '));
  });

  test('R8: a malformed expression -> error diagnostic + !ERR', () {
    final RenderedReport r = _render(
      _flat(<ReportElement>[_t('boom', expr: r'$F{a} +')]),
      <Map<String, Object?>>[<String, Object?>{'a': 1}],
    );
    final Diagnostic d = _diags(r)
        .firstWhere((Diagnostic d) => d.severity == DiagnosticSeverity.error,
            orElse: () => fail('expected a parse error: ${_diags(r)}'));
    expect(d.elementId, 'boom');
    expect(_texts(r)['boom'], '!ERR');
  });

  test('R9: divide-by-zero -> error diagnostic + !ERR', () {
    final RenderedReport r = _render(
      _flat(<ReportElement>[_t('boom', expr: r'$F{a} / 0')]),
      <Map<String, Object?>>[<String, Object?>{'a': 5}],
    );
    final Diagnostic d = _match(r, 'zero');
    expect(d.severity, DiagnosticSeverity.error);
    expect(_texts(r)['boom'], '!ERR');
  });

  test('R10: unknown function -> error diagnostic + !ERR', () {
    final RenderedReport r = _render(
      _flat(<ReportElement>[_t('boom', expr: r'NOPE($F{a})')]),
      <Map<String, Object?>>[<String, Object?>{'a': 5}],
    );
    final Diagnostic d = _diags(r)
        .firstWhere((Diagnostic d) => d.severity == DiagnosticSeverity.error,
            orElse: () => fail('expected an unknown-function error: ${_diags(r)}'));
    expect(_texts(r)['boom'], '!ERR');
  });

  test('R11: an empty data source renders the noData band + info', () {
    final RenderedReport r = _render(
      _flat(
        <ReportElement>[_t('d', expr: r'$F{name}')],
        noData: const Band(
          id: 'body/noData',
          type: BandType.noData,
          height: 16,
          elements: <ReportElement>[
            TextElement(id: 'nd', bounds: _r, text: 'No data'),
          ],
        ),
      ),
      <Map<String, Object?>>[],
    );
    _match(r, 'no rows');
    expect(_texts(r)['nd'], 'No data');
  });
}
```

- [ ] **Step 2: Run the matrix**

Run: `cd packages/jet_print && flutter test test/rendering/resilience/bad_data_matrix_test.dart`
Expected: PASS (all 11 cases). If R2/R3/R7 fail, the engine wiring (Tasks 4–6) is incomplete — fix there, not by weakening the assertion. If R8/R10's exact error message differs, adjust the `Pattern` to a substring that the actual diagnostic contains (keep the severity + `!ERR` assertions).

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/rendering/resilience/bad_data_matrix_test.dart
git commit -m "test(e2): bad-data resilience matrix (R1–R11 contract suite)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: 50k stress test + findings record

**Files:**
- Create: `packages/jet_print/test/rendering/resilience/stress_dirty_dataset_test.dart`
- Create: `docs/superpowers/specs/2026-06-20-e2-findings.md`

**Interfaces:**
- Consumes: `JetReportEngine().renderDefinition`, `RenderedReport.diagnostics`, `DiagnosticBudget.kMaxPerRowDataDiagnostics`.

**Context:** One committed stress test proves the resilience invariants hold at scale; it asserts no-crash + bounded diagnostics + per-row isolation, and *logs* RSS/wall-time as advisory (no time/memory gate — honoring "resilience-only"). The findings record documents the escalating-N exploration and the E2b (streaming-fill) recommendation.

- [ ] **Step 1: Write the stress test**

Create `test/rendering/resilience/stress_dirty_dataset_test.dart`:

```dart
// 50k-row stress-to-failure (spec E2, Pillar 3): a large dataset with
// scattered wrong-type data must not crash, must keep diagnostics bounded, and
// must still isolate the bad rows (clean rows sum correctly). Time/RSS are
// logged ADVISORY only — there is no perf gate (resilience-only).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/fill/diagnostic_budget.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

// Keep this CI-stable: a flat report (no images) over N rows. If wall time on
// the dev/CI machine exceeds a few seconds, lower N and record the value in the
// E2 findings doc — do NOT add a time assertion.
const int _n = 50000;
const int _dirtyEvery = 100; // every 100th row has a wrong-type amount

ReportDefinition _def() => ReportDefinition(
      name: 'stress',
      page: PageFormat.a4Portrait,
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'total',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.report,
        ),
      ],
      body: ReportBody(
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 16,
          elements: <ReportElement>[
            TextElement(
                id: 'total',
                bounds: const JetRect(x: 0, y: 0, width: 240, height: 16),
                text: '',
                expression: r'$V{total}'),
          ],
        ),
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 16,
              elements: <ReportElement>[
                TextElement(
                    id: 'name',
                    bounds: const JetRect(x: 0, y: 0, width: 240, height: 16),
                    text: '',
                    expression: r'$F{name}'),
              ])),
        ]),
      ),
    );

JetInMemoryDataSource _dirtyRows(int n) =>
    JetInMemoryDataSource(<Map<String, Object?>>[
      for (int i = 0; i < n; i++)
        <String, Object?>{
          'name': 'row $i',
          // Every _dirtyEvery-th row has a string amount (skipped from SUM).
          'amount': (i % _dirtyEvery == 0) ? 'NaN' : 1.0,
        },
    ]);

String _summaryText(RenderedReport r) {
  for (int p = 0; p < r.pageCount; p++) {
    for (final TextRunPrimitive prim
        in r.pageAt(p).frame.primitives.whereType<TextRunPrimitive>()) {
      if (prim.elementId == 'total') {
        return prim.lines.map((TextLine l) => l.text).join();
      }
    }
  }
  return '<not found>';
}

void main() {
  test('50k rows with scattered wrong-type data: no crash, bounded '
      'diagnostics, clean rows still sum (per-row isolation at scale)', () {
    final int rssBefore = ProcessInfo.currentRss;
    final Stopwatch watch = Stopwatch()..start();

    final RenderedReport report =
        const JetReportEngine().renderDefinition(_def(), _dirtyRows(_n));
    final int pageCount = report.pageCount;
    final List<Diagnostic> entries = report.diagnostics.entries;
    // Force the summary page to build (the last page carries the summary band).
    final String total = _summaryText(report);

    watch.stop();
    final int rssAfter = ProcessInfo.currentRss;
    // ignore: avoid_print
    print('[advisory][E2 stress] N=$_n -> $pageCount pages, '
        '${entries.length} diagnostics, total=$total in '
        '${watch.elapsedMilliseconds} ms, '
        'rssΔ=${((rssAfter - rssBefore) / (1024 * 1024)).round()} MB');

    // Invariant 1: it did not throw (reaching here proves it) and produced pages.
    expect(pageCount, greaterThan(0));

    // Invariant 2: diagnostics are BOUNDED — per-row data warnings cannot exceed
    // the cap, and the suppression summary is present (dirty rows >> cap).
    final int warnings = entries
        .where((Diagnostic d) => d.severity == DiagnosticSeverity.warning)
        .length;
    expect(warnings,
        lessThanOrEqualTo(DiagnosticBudget.kMaxPerRowDataDiagnostics));
    expect(
        entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.info &&
            d.message.contains('suppressed')),
        isTrue,
        reason: 'more than $warnings dirty rows -> a suppression summary');

    // Invariant 3: per-row isolation — the clean rows summed correctly; only the
    // dirty rows (every _dirtyEvery-th) were skipped.
    final int dirty = (_n / _dirtyEvery).ceil(); // i = 0,100,200,...
    final double expectedTotal = (_n - dirty) * 1.0;
    expect(total, '$expectedTotal');
  });
}
```

- [ ] **Step 2: Run the stress test and capture the advisory numbers**

Run: `cd packages/jet_print && flutter test test/rendering/resilience/stress_dirty_dataset_test.dart`
Expected: PASS. Note the printed `[advisory][E2 stress]` line (pages, diagnostics, total, ms, RSS Δ). If wall time exceeds ~5 s, lower `_n` (e.g. to 25000), keep the test green, and record the chosen `_n` + the reason in the findings doc (Step 4). Re-run to confirm the `expectedTotal` math still matches.

- [ ] **Step 3: Run the escalating-N exploration (one-off, not committed)**

Temporarily set `_n` to 10000, run, note the advisory line; repeat for 50000 and 100000 (and higher until it becomes unacceptably slow or the VM runs out of memory). Record each (N, pages, ms, RSS Δ, outcome) for the findings doc. **Restore `_n` to its committed value (50000, or the CI-stable value chosen in Step 2) before committing.**

- [ ] **Step 4: Write the findings record**

Create `docs/superpowers/specs/2026-06-20-e2-findings.md` with the real measured numbers from Step 3 (replace the bracketed placeholders with actual observations):

```markdown
# E2 — Resilience & Stress: Findings

- **Date:** 2026-06-20
- **Spec:** [2026-06-20-e2-resilience-stress-design.md](./2026-06-20-e2-resilience-stress-design.md)

## Committed stress test

`test/rendering/resilience/stress_dirty_dataset_test.dart` renders a flat report
over N = <committed N> rows with a wrong-type `amount` every 100th row. It
asserts resilience invariants only (no crash; per-row data warnings ≤
`DiagnosticBudget.kMaxPerRowDataDiagnostics`; a suppression summary present;
clean rows sum correctly). Time and RSS are logged, not gated.

## Escalating-N exploration (one-off; not committed)

| N | pages | fill+layout wall time | RSS Δ | outcome |
|---|------:|----------------------:|------:|---------|
| 10,000 | <p> | <ms> | <MB> | OK |
| 50,000 | <p> | <ms> | <MB> | OK |
| 100,000 | <p> | <ms> | <MB> | <OK / slow / OOM> |
| <next> | … | … | … | <breaking point> |

Observed breaking point: <describe — where time/RSS became unacceptable, or
"none observed up to N=<max tried>">.

## Recommendation (E2b gate)

The fill stage materializes every band for every row into one `List<FilledBand>`
before returning (`report_filler.dart`), and PDF export assembles the whole
document in memory. Based on the table above:

- **<If memory/time climbed roughly linearly and stayed acceptable at the target
  embed volume>:** E2b (streaming fill / streaming export) is NOT required for
  the embed gate; record the safe ceiling and defer.
- **<If a breaking point was hit at or below the target embed volume>:** open
  E2b to stream the fill and/or export; this finding is its motivating evidence.

Final call: <state the recommendation explicitly, with the N it is based on>.
```

- [ ] **Step 5: Run the full documented CI command**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print apps/jet_print_playground`
Expected: All green.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/rendering/resilience/stress_dirty_dataset_test.dart docs/superpowers/specs/2026-06-20-e2-findings.md
git commit -m "test(e2): 50k dirty-data stress test + E2 findings record

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] Run the full documented CI command from repo root: `flutter test packages/jet_print apps/jet_print_playground` — expect "All tests passed!".
- [ ] Run `cd packages/jet_print && flutter analyze` — expect no issues.
- [ ] Run `cd packages/jet_print && dart format --output=none --set-exit-if-changed lib/src/rendering/fill/diagnostic_budget.dart lib/src/rendering/fill/report_filler.dart lib/src/rendering/fill/fill_eval_context.dart lib/src/rendering/fill/element_resolver.dart lib/src/expression/aggregate/variable_accumulator.dart lib/src/expression/aggregate/variable_calculator.dart` — expect no changes (E2's own files are format-clean).
- [ ] Confirm no golden files changed: `cd /Users/ahmeturel/Projects/oss/jet-print && git diff --name-only main -- '*.png'` — expect empty output.
- [ ] Then use **superpowers:finishing-a-development-branch** to integrate.

## Notes for the executor

- **Ordering matters.** Tasks 1–3 build the primitives; Task 4 wires the budget and changes R2/R7 behavior (run the full suite here to reconcile existing diagnostics tests); Tasks 5–6 add aggregate-skip surfacing; Task 7's matrix asserts the *final* behavior, so it must run after Tasks 4–6; Task 8 stresses it.
- **Layer boundary.** The skip counter lives in the expression layer and is pure (no diagnostics import). Only the fill layer (`report_filler.dart`) reads it and talks to the `DiagnosticBudget`. Do not import `DiagnosticBudget` or `ReportDiagnostics` into `lib/src/expression/**` — `architecture/layer_boundaries_test.dart` will fail if you do.
- **No goldens.** Nothing here changes render output; if a golden test fails, something is wrong — investigate, do not regenerate.
```
