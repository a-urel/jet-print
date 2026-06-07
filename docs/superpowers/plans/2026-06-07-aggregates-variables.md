# Aggregates & Variables (spec 005b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add report **variables**, **groups**, and **parameters** to the model and a one-pass **`VariableCalculator`** that computes aggregates (SUM/COUNT/AVG/MIN/MAX/FIRST/LAST + plain expressions) with running totals and group-scoped resets, plus `$V{}` variable references threaded through the 005a expression pipeline.

**Architecture:** Three domain value types (`ReportParameter`, `ReportGroup`, `ReportVariable`) join `ReportTemplate` and serialize sparsely (no schema-version bump — additive). The `JetFieldType` value-type taxonomy moves from `data` to `domain` (its rightful innermost home) so `ReportParameter.type` can use it; `data/field_def.dart` re-exports it for zero churn. The expression seam gains a `$V{}` token/AST node/eval path and a `resolveVariable` context method. The new `VariableCalculator` (expression seam; `expression → domain, data`) compiles each variable's expression once, then `advance(row)` per row: evaluate group keys → detect the outermost broken group (cascading to inner) → reset that group's variables → fold each variable's per-row value into its accumulator in declaration order. Variable values are exposed via `valueOf`/`values` for the Fill stage (007) to feed into element-expression evaluation.

**Tech Stack:** Dart 3 (sealed/enum idioms), reuses the 005a `Expression`/`EvalContext`/`JetValue` and 004 `DataRow`. No new package dependencies. Tests use `flutter_test` with absolute `package:jet_print/src/...` imports.

---

## Design Decisions (settled before planning)

- **Reset scopes: report + group.** A variable resets at report start (grand total / running total) or when a named group's key changes (group subtotal). Page/column resets are deferred to 008 (they need page boundaries).
- **Calculations: all eight** — `none` (plain per-row expression, no folding), `sum`, `count`, `average`, `min`, `max`, `first`, `last`.
- **Formalize `ReportParameter`** — `{name, type: JetFieldType, defaultValue}` in the domain model + serialization. To give it a type without violating `domain → data` (the wrong direction), **relocate `JetFieldType` to `domain/value_type.dart`** and re-export it from `data/field_def.dart` (the correct direction is `data → domain`; the re-export keeps existing importers unchanged).
- **Additive serialization, no version bump.** `parameters`/`variables`/`groups` are sparse optional fields (omitted when empty, default empty when absent). `kReportSchemaVersion` stays `1`; the migration framework is untouched. (A bump is only for breaking changes — Principle V.)
- **Calculator lives in the expression seam** (`src/expression/aggregate/`), depending on `domain` (the variable/group types) + `data` (`DataRow`) + the expression internals — all allowed by the DAG.

## Calculation semantics (reference — pinned)

A variable holds an `expression` (a 005a expression string) and a `calculation`. Each row, the calculator evaluates the expression to a per-row `JetValue` and **folds** it into the variable's accumulator. The exposed value (`$V{name}`, `valueOf`) is the accumulator's current value.

- **Contribution filter:** an evaluated value is *skipped* (accumulator unchanged) when it is `JetNull`, a `JetError`, or the wrong type for the calculation. This keeps running totals robust — one bad/blank row never poisons a total (the per-row error is still visible wherever that row's expression is rendered directly).
- **`none`** — value = the evaluated expression *as-is* (including null/error — it is not aggregating).
- **`sum`** — seed `JetNumber(0)`; for each `JetNumber` increment, add. Value is the running sum.
- **`count`** — seed `JetNumber(0)`; increments by 1 for every non-null, non-error value (any type). Value is the running count.
- **`average`** — track sum + count of `JetNumber`s; value is `JetNumber(sum/count)`, or `JetNull` while count is 0.
- **`min` / `max`** — first contributable value seeds; thereafter keep the lesser/greater via `jetCompare` (same-type orderable only — number/string/date). Value is `JetNull` until the first contribution.
- **`first` / `last`** — `first` keeps the first contributable value and ignores the rest; `last` keeps the most recent. `JetNull` until the first contribution.
- **Reset:** at report start, all accumulators seed. At a group break, every variable with `resetScope == group && resetGroup == <broken group>` re-seeds **before** the breaking row is folded in.
- **Evaluation order:** variables fold in declaration order each row; a variable's expression sees, via `$V{}`, the *current* `values` map — i.e. updated values for earlier-declared variables this row, and previous values for itself/later variables.
- **Group-break detection:** evaluate every group's key expression each row. On the first row, no breaks (keys initialize). Otherwise, find the *outermost* (earliest-declared) group whose key changed; that group **and all inner groups** break. Resets cascade outer→inner.

## File Structure

All library files: pure Dart, relative imports (ordered `dart:`→`package:`→relative, alphabetical), dartdoc on every public symbol, value-type idioms.

- Create: `packages/jet_print/lib/src/domain/value_type.dart` — `JetFieldType` (relocated).
- Modify: `packages/jet_print/lib/src/data/field_def.dart` — import + re-export `JetFieldType` from domain; drop the inline enum.
- Create: `packages/jet_print/lib/src/domain/report_parameter.dart` — `ReportParameter`.
- Create: `packages/jet_print/lib/src/domain/report_group.dart` — `ReportGroup`.
- Create: `packages/jet_print/lib/src/domain/report_variable.dart` — `ReportVariable` + `JetCalculation` + `VariableResetScope`.
- Modify: `packages/jet_print/lib/src/domain/report_template.dart` — add `parameters`/`variables`/`groups`.
- Modify: `packages/jet_print/lib/src/domain/serialization/report_codec.dart` — sparse encode/decode of the three lists.
- Modify: `packages/jet_print/lib/src/expression/value.dart` — add `jetCompare`.
- Modify: `packages/jet_print/lib/src/expression/evaluator.dart` — `_compare` delegates to `jetCompare`; handle `VariableRefExpr`.
- Modify: `packages/jet_print/lib/src/expression/token.dart` — add `TokenType.variableRef`.
- Modify: `packages/jet_print/lib/src/expression/lexer.dart` — lex `$V{}`.
- Modify: `packages/jet_print/lib/src/expression/ast.dart` — `VariableRefExpr`.
- Modify: `packages/jet_print/lib/src/expression/parser.dart` — parse `$V{}`.
- Modify: `packages/jet_print/lib/src/expression/eval_context.dart` — `resolveVariable` + `RowEvalContext.variables`.
- Create: `packages/jet_print/lib/src/expression/aggregate/variable_accumulator.dart` — `VariableAccumulator`.
- Create: `packages/jet_print/lib/src/expression/aggregate/variable_calculator.dart` — `VariableCalculator`.
- Modify: `packages/jet_print/lib/src/expression/eval_context_test.dart` stub + `packages/jet_print/CHANGELOG.md`.
- Tests under `test/domain/`, `test/expression/`, `test/expression/aggregate/`.

**Build order:** domain model first (Tasks 1–5), then `$V{}` expression support (6–10), then the calculator (11–12), integration (13), gate (14). Each task is independently green.

---

### Task 1: Relocate `JetFieldType` to the domain seam

`JetFieldType` is a value-type taxonomy that belongs in `domain` (so `ReportParameter` can use it without `domain → data`). Move the enum; re-export from `data/field_def.dart` so every existing importer is unaffected.

**Files:**
- Create: `packages/jet_print/lib/src/domain/value_type.dart`
- Modify: `packages/jet_print/lib/src/data/field_def.dart`
- Test: `packages/jet_print/test/domain/value_type_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/value_type_test.dart`:

```dart
// JetFieldType lives in the domain seam (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/value_type.dart';

void main() {
  test('enumerates the coarse value types', () {
    expect(JetFieldType.values, <JetFieldType>[
      JetFieldType.string,
      JetFieldType.integer,
      JetFieldType.double,
      JetFieldType.boolean,
      JetFieldType.dateTime,
      JetFieldType.unknown,
    ]);
  });

  test('is still reachable through the data seam re-export', () {
    // A separate assertion in the data tests; here just pin the canonical home.
    expect(JetFieldType.integer.name, 'integer');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/value_type_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jet_print/src/domain/value_type.dart'`.

- [ ] **Step 3: Create the domain home and re-export from data**

Create `packages/jet_print/lib/src/domain/value_type.dart`:

```dart
/// The coarse value-type taxonomy shared across the model (spec 005b).
///
/// A small, deliberately coarse tag used by data-field metadata
/// (`FieldDef.type`) and report-parameter declarations (`ReportParameter.type`)
/// to drive formatting and coercion — never a hard contract. It lives in the
/// innermost (`domain`) seam so both the `data` and `domain` layers can share
/// one enum without violating the inward-dependency rule. Pure Dart.
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
```

Now edit `packages/jet_print/lib/src/data/field_def.dart`: remove the inline `enum JetFieldType { ... }` block (lines 9–32 in the current file) and, at the top, import + re-export the domain enum. The file's library doc comment stays; replace the enum with the import/export. The new head of the file:

```dart
/// Typed field metadata for the data layer (spec 004).
///
/// A [FieldDef] names a column and tags it with a best-effort [JetFieldType]
/// (re-exported from the domain seam). The type is additive metadata — a slot
/// the expression engine uses for formatting and coercion — never a hard
/// contract; an indeterminate column is simply [JetFieldType.unknown]. Pure
/// Dart, no Flutter dependency.
library;

import '../domain/value_type.dart';

export '../domain/value_type.dart' show JetFieldType;

/// An immutable (name, type) pair describing one field of a [DataSet]'s schema.
class FieldDef {
```

(Everything from `class FieldDef {` onward — the constructor, fields, `inferType`, `_typeOf`, equality, `toString` — is unchanged. Only the leading enum is replaced by the import + export.)

- [ ] **Step 4: Run the new test AND the FULL suite to prove zero churn**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/value_type_test.dart`
Expected: PASS.

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test`
Expected: PASS — every existing data/expression test that imports `JetFieldType` via `package:jet_print/src/data/field_def.dart` still resolves it through the re-export. No regressions.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/domain/value_type.dart lib/src/data/field_def.dart test/domain/value_type_test.dart && flutter analyze`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/domain/value_type.dart packages/jet_print/lib/src/data/field_def.dart packages/jet_print/test/domain/value_type_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "refactor(domain): relocate JetFieldType to domain seam; re-export from data"
```

---

### Task 2: `ReportParameter`

A named, typed external input with an optional default. Serializes with the default type-tagged so a `dateTime` default round-trips as ISO 8601.

**Files:**
- Create: `packages/jet_print/lib/src/domain/report_parameter.dart`
- Test: `packages/jet_print/test/domain/report_parameter_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/report_parameter_test.dart`:

```dart
// ReportParameter value type + serialization (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/value_type.dart';

void main() {
  group('ReportParameter', () {
    test('round-trips a typed parameter with a default', () {
      const ReportParameter p = ReportParameter(
        name: 'minAmount',
        type: JetFieldType.double,
        defaultValue: 10.0,
      );
      expect(ReportParameter.fromJson(p.toJson()), p);
    });

    test('omits the default key when null', () {
      const ReportParameter p =
          ReportParameter(name: 'note', type: JetFieldType.string);
      expect(p.toJson().containsKey('default'), isFalse);
      expect(ReportParameter.fromJson(p.toJson()), p);
    });

    test('encodes a dateTime default as ISO 8601 and decodes it back', () {
      final ReportParameter p = ReportParameter(
        name: 'asOf',
        type: JetFieldType.dateTime,
        defaultValue: DateTime(2026, 6, 7),
      );
      expect(p.toJson()['default'], DateTime(2026, 6, 7).toIso8601String());
      expect(ReportParameter.fromJson(p.toJson()), p);
    });

    test('has value equality and a consistent hash code', () {
      expect(const ReportParameter(name: 'a', type: JetFieldType.integer),
          const ReportParameter(name: 'a', type: JetFieldType.integer));
      expect(
          const ReportParameter(name: 'a', type: JetFieldType.integer).hashCode,
          const ReportParameter(name: 'a', type: JetFieldType.integer).hashCode);
      expect(
          const ReportParameter(name: 'a', type: JetFieldType.integer) ==
              const ReportParameter(name: 'b', type: JetFieldType.integer),
          isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/report_parameter_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/report_parameter.dart`:

```dart
/// A declared report parameter — a named external input (spec 005b).
library;

import 'value_type.dart';

/// An immutable parameter declaration: a [name], a coarse [type], and an
/// optional [defaultValue].
///
/// Parameters are supplied at fill time (resolved by `$P{}` references); this
/// declaration lets a template advertise its inputs with types and defaults.
/// The default serializes inline; a [JetFieldType.dateTime] default is written
/// as an ISO-8601 string.
class ReportParameter {
  /// Creates a parameter declaration.
  const ReportParameter({
    required this.name,
    required this.type,
    this.defaultValue,
  });

  /// Reads a [ReportParameter] from its [toJson] map.
  factory ReportParameter.fromJson(Map<String, Object?> json) {
    final JetFieldType type = JetFieldType.values.byName(json['type']! as String);
    return ReportParameter(
      name: json['name']! as String,
      type: type,
      defaultValue:
          json.containsKey('default') ? _decodeDefault(json['default'], type) : null,
    );
  }

  /// The parameter name, as referenced by `$P{name}`.
  final String name;

  /// The parameter's coarse value type.
  final JetFieldType type;

  /// The default value used when the caller supplies none (may be `null`).
  final Object? defaultValue;

  /// Serializes to a JSON-safe map (default omitted when null).
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'type': type.name,
        if (defaultValue != null) 'default': _encodeDefault(defaultValue!, type),
      };

  static Object? _encodeDefault(Object value, JetFieldType type) =>
      type == JetFieldType.dateTime && value is DateTime
          ? value.toIso8601String()
          : value;

  static Object? _decodeDefault(Object? raw, JetFieldType type) =>
      type == JetFieldType.dateTime && raw is String ? DateTime.parse(raw) : raw;

  @override
  bool operator ==(Object other) =>
      other is ReportParameter &&
      other.name == name &&
      other.type == type &&
      other.defaultValue == defaultValue;

  @override
  int get hashCode => Object.hash(name, type, defaultValue);

  @override
  String toString() => 'ReportParameter($name, $type, default: $defaultValue)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/report_parameter_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/domain/report_parameter.dart test/domain/report_parameter_test.dart && flutter analyze lib/src/domain test/domain`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/domain/report_parameter.dart packages/jet_print/test/domain/report_parameter_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(domain): add ReportParameter with typed default serialization"
```

---

### Task 3: `ReportGroup`

A named grouping: a key expression whose change between rows marks a group break.

**Files:**
- Create: `packages/jet_print/lib/src/domain/report_group.dart`
- Test: `packages/jet_print/test/domain/report_group_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/report_group_test.dart`:

```dart
// ReportGroup value type + serialization (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_group.dart';

void main() {
  group('ReportGroup', () {
    test('round-trips through JSON', () {
      const ReportGroup g =
          ReportGroup(name: 'category', expression: r'$F{category}');
      expect(ReportGroup.fromJson(g.toJson()), g);
    });

    test('has value equality and a consistent hash code', () {
      expect(const ReportGroup(name: 'a', expression: 'x'),
          const ReportGroup(name: 'a', expression: 'x'));
      expect(const ReportGroup(name: 'a', expression: 'x').hashCode,
          const ReportGroup(name: 'a', expression: 'x').hashCode);
      expect(
          const ReportGroup(name: 'a', expression: 'x') ==
              const ReportGroup(name: 'a', expression: 'y'),
          isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/report_group_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/report_group.dart`:

```dart
/// A report group — a reset boundary keyed by an expression (spec 005b).
library;

/// An immutable group definition: a [name] and a key [expression].
///
/// The calculator evaluates [expression] per row; when its value changes
/// between consecutive rows the group "breaks" and its group-scoped variables
/// reset. Groups are ordered (outermost first); an outer break cascades to all
/// inner groups.
class ReportGroup {
  /// Creates a group keyed by [expression].
  const ReportGroup({required this.name, required this.expression});

  /// Reads a [ReportGroup] from its [toJson] map.
  factory ReportGroup.fromJson(Map<String, Object?> json) => ReportGroup(
        name: json['name']! as String,
        expression: json['expression']! as String,
      );

  /// The group name (referenced by a variable's `resetGroup`).
  final String name;

  /// The grouping-key expression (005a syntax).
  final String expression;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() =>
      <String, Object?>{'name': name, 'expression': expression};

  @override
  bool operator ==(Object other) =>
      other is ReportGroup &&
      other.name == name &&
      other.expression == expression;

  @override
  int get hashCode => Object.hash(name, expression);

  @override
  String toString() => 'ReportGroup($name, "$expression")';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/report_group_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/domain/report_group.dart test/domain/report_group_test.dart && flutter analyze lib/src/domain test/domain`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/domain/report_group.dart packages/jet_print/test/domain/report_group_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(domain): add ReportGroup"
```

---

### Task 4: `ReportVariable` (+ `JetCalculation`, `VariableResetScope`)

A named computed value: an expression, a calculation, and a reset scope (report or a named group). Sparse serialization (calculation omitted when `none`, scope when `report`, group when null).

**Files:**
- Create: `packages/jet_print/lib/src/domain/report_variable.dart`
- Test: `packages/jet_print/test/domain/report_variable_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/report_variable_test.dart`:

```dart
// ReportVariable value type + serialization (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_variable.dart';

void main() {
  group('ReportVariable', () {
    test('round-trips a group-scoped sum', () {
      const ReportVariable v = ReportVariable(
        name: 'catTotal',
        expression: r'$F{amount}',
        calculation: JetCalculation.sum,
        resetScope: VariableResetScope.group,
        resetGroup: 'category',
      );
      expect(ReportVariable.fromJson(v.toJson()), v);
    });

    test('defaults are sparse (none / report / no group)', () {
      const ReportVariable v =
          ReportVariable(name: 'v', expression: '1');
      final Map<String, Object?> json = v.toJson();
      expect(json.containsKey('calculation'), isFalse);
      expect(json.containsKey('resetScope'), isFalse);
      expect(json.containsKey('resetGroup'), isFalse);
      expect(ReportVariable.fromJson(json), v);
      expect(v.calculation, JetCalculation.none);
      expect(v.resetScope, VariableResetScope.report);
      expect(v.resetGroup, isNull);
    });

    test('round-trips a report-scoped grand total', () {
      const ReportVariable v = ReportVariable(
        name: 'grand',
        expression: r'$F{amount}',
        calculation: JetCalculation.sum,
      );
      expect(ReportVariable.fromJson(v.toJson()), v);
      expect(v.toJson().containsKey('resetScope'), isFalse); // report = default
    });

    test('has value equality and a consistent hash code', () {
      expect(const ReportVariable(name: 'a', expression: '1'),
          const ReportVariable(name: 'a', expression: '1'));
      expect(const ReportVariable(name: 'a', expression: '1').hashCode,
          const ReportVariable(name: 'a', expression: '1').hashCode);
      expect(
          const ReportVariable(
                  name: 'a',
                  expression: '1',
                  calculation: JetCalculation.sum) ==
              const ReportVariable(name: 'a', expression: '1'),
          isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/report_variable_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/report_variable.dart`:

```dart
/// A report variable — a named accumulated/derived value (spec 005b).
library;

/// How a [ReportVariable] folds its per-row expression values.
enum JetCalculation {
  /// No folding — the variable's value is its expression evaluated each row.
  none,

  /// Running sum of numeric values.
  sum,

  /// Count of non-null values.
  count,

  /// Mean of numeric values.
  average,

  /// Running minimum (same-type orderable values).
  min,

  /// Running maximum (same-type orderable values).
  max,

  /// The first contributable value in the reset scope.
  first,

  /// The most recent contributable value in the reset scope.
  last,
}

/// When a [ReportVariable]'s accumulator resets.
enum VariableResetScope {
  /// Resets once at report start (grand total / running total).
  report,

  /// Resets when the named group's key changes (group subtotal).
  group,
}

/// An immutable variable definition.
class ReportVariable {
  /// Creates a variable named [name] folding [expression] via [calculation],
  /// resetting at [resetScope] (and [resetGroup] when scoped to a group).
  const ReportVariable({
    required this.name,
    required this.expression,
    this.calculation = JetCalculation.none,
    this.resetScope = VariableResetScope.report,
    this.resetGroup,
  });

  /// Reads a [ReportVariable] from its [toJson] map.
  factory ReportVariable.fromJson(Map<String, Object?> json) => ReportVariable(
        name: json['name']! as String,
        expression: json['expression']! as String,
        calculation: json['calculation'] == null
            ? JetCalculation.none
            : JetCalculation.values.byName(json['calculation']! as String),
        resetScope: json['resetScope'] == null
            ? VariableResetScope.report
            : VariableResetScope.values.byName(json['resetScope']! as String),
        resetGroup: json['resetGroup'] as String?,
      );

  /// The variable name, as referenced by `$V{name}`.
  final String name;

  /// The per-row expression to fold (005a syntax).
  final String expression;

  /// How per-row values fold into the accumulator.
  final JetCalculation calculation;

  /// When the accumulator resets.
  final VariableResetScope resetScope;

  /// The group whose break resets this variable (when [resetScope] is
  /// [VariableResetScope.group]); otherwise `null`.
  final String? resetGroup;

  /// Serializes to a JSON-safe map (defaults omitted).
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'expression': expression,
        if (calculation != JetCalculation.none) 'calculation': calculation.name,
        if (resetScope != VariableResetScope.report)
          'resetScope': resetScope.name,
        if (resetGroup != null) 'resetGroup': resetGroup,
      };

  @override
  bool operator ==(Object other) =>
      other is ReportVariable &&
      other.name == name &&
      other.expression == expression &&
      other.calculation == calculation &&
      other.resetScope == resetScope &&
      other.resetGroup == resetGroup;

  @override
  int get hashCode =>
      Object.hash(name, expression, calculation, resetScope, resetGroup);

  @override
  String toString() =>
      'ReportVariable($name, "$expression", $calculation, $resetScope'
      '${resetGroup == null ? '' : ', group: $resetGroup'})';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/report_variable_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/domain/report_variable.dart test/domain/report_variable_test.dart && flutter analyze lib/src/domain test/domain`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/domain/report_variable.dart packages/jet_print/test/domain/report_variable_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(domain): add ReportVariable with JetCalculation and reset scope"
```

---

### Task 5: Wire parameters/variables/groups into `ReportTemplate` + serialization

Add the three lists to `ReportTemplate` (default empty) and extend `report_codec` to encode them sparsely and decode them back (default empty when absent), wrapping malformed entries in `ReportFormatException`. No schema-version bump.

**Files:**
- Modify: `packages/jet_print/lib/src/domain/report_template.dart`
- Modify: `packages/jet_print/lib/src/domain/serialization/report_codec.dart`
- Test: `packages/jet_print/test/domain/serialization/report_codec_aggregates_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/serialization/report_codec_aggregates_test.dart`:

```dart
// Template round-trip of parameters/variables/groups (spec 005b). No Flutter UI.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/domain/value_type.dart';

ElementCodecRegistry _registry() => ElementCodecRegistry();

const ReportTemplate _rich = ReportTemplate(
  name: 'Sales',
  page: PageFormat.a4Portrait,
  parameters: <ReportParameter>[
    ReportParameter(name: 'minAmount', type: JetFieldType.double, defaultValue: 0.0),
  ],
  groups: <ReportGroup>[
    ReportGroup(name: 'category', expression: r'$F{category}'),
  ],
  variables: <ReportVariable>[
    ReportVariable(
      name: 'catTotal',
      expression: r'$F{amount}',
      calculation: JetCalculation.sum,
      resetScope: VariableResetScope.group,
      resetGroup: 'category',
    ),
  ],
);

void main() {
  test('round-trips parameters/variables/groups through real JSON', () {
    final ElementCodecRegistry r = _registry();
    final String wire = jsonEncode(encodeTemplate(_rich, r));
    final ReportTemplate decoded =
        decodeTemplate((jsonDecode(wire) as Map).cast<String, Object?>(), r);
    expect(decoded.parameters, _rich.parameters);
    expect(decoded.groups, _rich.groups);
    expect(decoded.variables, _rich.variables);
    // Stable re-encode.
    expect(encodeTemplate(decoded, r), encodeTemplate(_rich, r));
  });

  test('omits the lists when empty (sparse, backward-compatible)', () {
    const ReportTemplate plain =
        ReportTemplate(name: 'Plain', page: PageFormat.a4Portrait);
    final Map<String, Object?> json = encodeTemplate(plain, _registry());
    expect(json.containsKey('parameters'), isFalse);
    expect(json.containsKey('variables'), isFalse);
    expect(json.containsKey('groups'), isFalse);
  });

  test('an old document without the lists decodes to empty lists', () {
    final Map<String, Object?> v1 = <String, Object?>{
      'schemaVersion': kReportSchemaVersion,
      'name': 'Legacy',
      'page': PageFormat.a4Portrait.toJson(),
      'bands': <Object?>[],
    };
    final ReportTemplate decoded = decodeTemplate(v1, _registry());
    expect(decoded.parameters, isEmpty);
    expect(decoded.variables, isEmpty);
    expect(decoded.groups, isEmpty);
  });

  test('throws ReportFormatException on a malformed variable', () {
    final Map<String, Object?> json = <String, Object?>{
      'schemaVersion': kReportSchemaVersion,
      'name': 'X',
      'page': PageFormat.a4Portrait.toJson(),
      'bands': <Object?>[],
      'variables': <Object?>[
        <String, Object?>{'name': 'v', 'expression': '1', 'calculation': 'nonsense'},
      ],
    };
    expect(() => decodeTemplate(json, _registry()),
        throwsA(isA<ReportFormatException>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/serialization/report_codec_aggregates_test.dart`
Expected: FAIL — `ReportTemplate` has no `parameters`/`groups`/`variables` named parameters (compile error).

- [ ] **Step 3: Extend `ReportTemplate`**

Replace `packages/jet_print/lib/src/domain/report_template.dart` with:

```dart
/// The root of a report definition.
library;

import 'page_format.dart';
import 'report_band.dart';
import 'report_group.dart';
import 'report_parameter.dart';
import 'report_variable.dart';

/// An immutable report definition: a named [page] layout with ordered [bands],
/// plus declared [parameters], [variables], and [groups].
/// This is the artifact that serializes to versioned JSON (Constitution V).
class ReportTemplate {
  /// Creates a report template.
  const ReportTemplate({
    required this.name,
    required this.page,
    this.bands = const <ReportBand>[],
    this.parameters = const <ReportParameter>[],
    this.variables = const <ReportVariable>[],
    this.groups = const <ReportGroup>[],
  });

  /// Human-readable template name.
  final String name;

  /// The page the report is laid out onto.
  final PageFormat page;

  /// The report's bands, in vertical/role order.
  final List<ReportBand> bands;

  /// Declared parameters (external inputs resolved by `$P{}`).
  final List<ReportParameter> parameters;

  /// Declared variables (accumulated/derived values resolved by `$V{}`).
  final List<ReportVariable> variables;

  /// Declared groups, outermost first (reset boundaries for variables).
  final List<ReportGroup> groups;
}
```

- [ ] **Step 4: Extend `report_codec`**

In `packages/jet_print/lib/src/domain/serialization/report_codec.dart`, add imports for the three new types (keep imports ordered):

```dart
import '../report_group.dart';
import '../report_parameter.dart';
import '../report_variable.dart';
```

In `encodeTemplate`, add the three sparse lists to the returned map (after `'bands': ...`):

```dart
    if (template.parameters.isNotEmpty)
      'parameters': <Object?>[
        for (final ReportParameter p in template.parameters) p.toJson(),
      ],
    if (template.variables.isNotEmpty)
      'variables': <Object?>[
        for (final ReportVariable v in template.variables) v.toJson(),
      ],
    if (template.groups.isNotEmpty)
      'groups': <Object?>[
        for (final ReportGroup g in template.groups) g.toJson(),
      ],
```

In `decodeTemplate`, pass the three lists to the `ReportTemplate(...)` constructor (after `bands: ...`):

```dart
    parameters: _decodeList<ReportParameter>(
        upgraded['parameters'], 'parameters', ReportParameter.fromJson),
    variables: _decodeList<ReportVariable>(
        upgraded['variables'], 'variables', ReportVariable.fromJson),
    groups: _decodeList<ReportGroup>(
        upgraded['groups'], 'groups', ReportGroup.fromJson),
```

And add this generic decode helper at the bottom of the file (it returns an empty list when the key is absent, validates the list shape, and translates a malformed entry into a `ReportFormatException`):

```dart
List<T> _decodeList<T>(
  Object? raw,
  String key,
  T Function(Map<String, Object?>) fromJson,
) {
  if (raw == null) return <T>[];
  if (raw is! List) {
    throw ReportFormatException('"$key" must be a list.');
  }
  return <T>[
    for (final Object? entry in raw)
      _decodeEntry<T>(entry, key, fromJson),
  ];
}

T _decodeEntry<T>(
  Object? entry,
  String key,
  T Function(Map<String, Object?>) fromJson,
) {
  if (entry is! Map) {
    throw ReportFormatException('Each "$key" entry must be a JSON object.');
  }
  try {
    return fromJson(entry.cast<String, Object?>());
  } on ReportFormatException {
    rethrow;
  } catch (error) {
    throw ReportFormatException('Malformed "$key" entry: $error');
  }
}
```

- [ ] **Step 5: Run the test (and the full domain suite for no regressions)**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/domain/`
Expected: PASS — the new aggregates round-trip test plus all existing `report_codec_test` cases (the existing template without the new lists still round-trips, since the lists are sparse).

- [ ] **Step 6: Format + analyze + commit**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/domain test/domain && flutter analyze lib/src/domain test/domain`
Expected: `No issues found!`.

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/domain/report_template.dart packages/jet_print/lib/src/domain/serialization/report_codec.dart packages/jet_print/test/domain/serialization/report_codec_aggregates_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(domain): serialize parameters/variables/groups on ReportTemplate (sparse, v1)"
```

---

### Task 6: `jetCompare` shared helper

Extract same-type-orderable comparison into a public helper in `value.dart` (the calculator's MIN/MAX needs it), and refactor the evaluator's private `_compare` to delegate — one comparison rule, two callers.

**Files:**
- Modify: `packages/jet_print/lib/src/expression/value.dart`
- Modify: `packages/jet_print/lib/src/expression/evaluator.dart`
- Test: `packages/jet_print/test/expression/value_compare_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/value_compare_test.dart`:

```dart
// jetCompare: same-type orderable comparison (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/value.dart';

void main() {
  group('jetCompare', () {
    test('orders numbers, strings and dates of the same type', () {
      expect(jetCompare(const JetNumber(1), const JetNumber(2))! < 0, isTrue);
      expect(jetCompare(const JetString('b'), const JetString('a'))! > 0, isTrue);
      expect(jetCompare(JetDate(DateTime(2025)), JetDate(DateTime(2026)))! < 0,
          isTrue);
      expect(jetCompare(const JetNumber(3), const JetNumber(3)), 0);
    });

    test('returns null for mismatched or non-orderable types', () {
      expect(jetCompare(const JetNumber(1), const JetString('1')), isNull);
      expect(jetCompare(const JetNull(), const JetNull()), isNull);
      expect(jetCompare(const JetBool(true), const JetBool(false)), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/value_compare_test.dart`
Expected: FAIL — `jetCompare` is undefined.

- [ ] **Step 3: Add `jetCompare` to `value.dart`**

Append to `packages/jet_print/lib/src/expression/value.dart` (after `jetStringify`):

```dart
/// Compares two [JetValue]s that share an orderable type.
///
/// Returns a negative/zero/positive sign for [a] vs [b] when both are
/// [JetNumber], both [JetString], or both [JetDate]; returns `null` when the
/// types differ or are not orderable (null/bool/error). Used by the evaluator's
/// `< <= > >=` and the aggregate calculator's MIN/MAX.
int? jetCompare(JetValue a, JetValue b) {
  if (a is JetNumber && b is JetNumber) return a.value.compareTo(b.value);
  if (a is JetString && b is JetString) return a.value.compareTo(b.value);
  if (a is JetDate && b is JetDate) return a.value.compareTo(b.value);
  return null;
}
```

- [ ] **Step 4: Refactor the evaluator's `_compare` to delegate**

In `packages/jet_print/lib/src/expression/evaluator.dart`, replace the private `_compare` function body so it delegates to `jetCompare` (the import of `value.dart` is already present):

```dart
int? _compare(JetValue l, JetValue r) => jetCompare(l, r);
```

(Leave `_order` calling `_compare` as-is — or, if you prefer, have `_order` call `jetCompare` directly and delete `_compare`. Either is fine; keep the analyzer clean with no unused private function.)

- [ ] **Step 5: Run the value-compare test + the whole expression suite**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/`
Expected: PASS — `jetCompare` green and the evaluator's ordering tests still pass (behavior unchanged).

- [ ] **Step 6: Format + analyze + commit**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/value.dart packages/jet_print/lib/src/expression/evaluator.dart packages/jet_print/test/expression/value_compare_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "refactor(expr): extract shared jetCompare; evaluator ordering delegates to it"
```

---

### Task 7: Lex `$V{}` variable references

Add `TokenType.variableRef` and teach the lexer to recognize the `$V` sigil (the 005a lexer rejects it today).

**Files:**
- Modify: `packages/jet_print/lib/src/expression/token.dart`
- Modify: `packages/jet_print/lib/src/expression/lexer.dart`
- Test: `packages/jet_print/test/expression/lexer_variable_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/lexer_variable_test.dart`:

```dart
// $V{} variable-reference lexing (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/lexer.dart';
import 'package:jet_print/src/expression/token.dart';

void main() {
  test('lexes a variable reference with its name', () {
    final List<Token> tokens = tokenize(r'$V{total}');
    expect(tokens.first.type, TokenType.variableRef);
    expect(tokens.first.literal, 'total');
  });

  test('field, param and variable references coexist', () {
    expect(tokenize(r'$F{a} $P{b} $V{c}').map((Token t) => t.type).toList(),
        <TokenType>[
          TokenType.fieldRef,
          TokenType.paramRef,
          TokenType.variableRef,
          TokenType.eof,
        ]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/lexer_variable_test.dart`
Expected: FAIL — `TokenType.variableRef` is undefined (compile error).

- [ ] **Step 3: Add the token type and lex the sigil**

In `packages/jet_print/lib/src/expression/token.dart`, add a `variableRef` value to `TokenType` immediately after `paramRef`:

```dart
  /// A variable reference `$V{name}` (literal is the variable name `String`).
  variableRef,
```

In `packages/jet_print/lib/src/expression/lexer.dart`, extend `_scanReference`'s sigil dispatch to accept `V`:

```dart
    if (sigil == 'F') {
      type = TokenType.fieldRef;
    } else if (sigil == 'P') {
      type = TokenType.paramRef;
    } else if (sigil == 'V') {
      type = TokenType.variableRef;
    } else {
      throw ExpressionException(
        'Unsupported reference "\$$sigil" at position $_pos '
        '(expected \$F{...}, \$P{...} or \$V{...})',
      );
    }
```

- [ ] **Step 4: Run the new test + the whole expression suite**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/`
Expected: PASS — variable refs lex; the 005a lexer test that asserted `$V` *threw* is now obsolete... **important:** the 005a `lexer_test.dart` has a test `'throws on a bad reference sigil (e.g. unsupported $V in 005a)'` using `$V{total}`. That test will now FAIL because `$V` is valid. Update it to use a still-unsupported sigil:

In `packages/jet_print/test/expression/lexer_test.dart`, change that test's input from `$V{total}` to `$X{total}` and its description from "unsupported \$V in 005a" to "unsupported sigil":

```dart
    test('throws on a bad reference sigil (e.g. unsupported \$X)', () {
      expect(() => tokenize(r'$X{total}'), throwsA(isA<ExpressionException>()));
    });
```

Re-run `flutter test test/expression/` — all green.

- [ ] **Step 5: Format + analyze + commit**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/token.dart packages/jet_print/lib/src/expression/lexer.dart packages/jet_print/test/expression/lexer_variable_test.dart packages/jet_print/test/expression/lexer_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): lex \$V{} variable references"
```

---

### Task 8: `VariableRefExpr` AST node

**Files:**
- Modify: `packages/jet_print/lib/src/expression/ast.dart`
- Test: `packages/jet_print/test/expression/ast_variable_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/ast_variable_test.dart`:

```dart
// VariableRefExpr canonical toString (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/ast.dart';

void main() {
  test('renders a variable reference canonically', () {
    expect(VariableRefExpr('total').toString(), '(var total)');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/ast_variable_test.dart`
Expected: FAIL — `VariableRefExpr` is undefined.

- [ ] **Step 3: Add the node**

In `packages/jet_print/lib/src/expression/ast.dart`, add after `ParamRefExpr`:

```dart
/// A variable reference `$V{name}`.
final class VariableRefExpr extends Expr {
  /// Creates a variable reference node.
  const VariableRefExpr(this.name);

  /// The variable name.
  final String name;

  @override
  String toString() => '(var $name)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/ast_variable_test.dart`
Expected: PASS.

> Note: adding a node to the sealed `Expr` will make the evaluator's exhaustive `switch` a compile error until Task 10 adds the `VariableRefExpr` case. That is expected — the parser (Task 9) builds the node, the evaluator (Task 10) handles it. If you run `flutter analyze` between Tasks 8 and 10 you will see the non-exhaustive-switch error; it resolves in Task 10. To keep each task independently green, **Tasks 8, 9, 10 are committed together is acceptable**, OR add the evaluator case (Task 10 Step 3) now. Recommended: implement Tasks 8→9→10 in sequence and run `flutter test test/expression/` only after Task 10. Commit Task 8's files now without running the full analyzer:

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/ast.dart packages/jet_print/test/expression/ast_variable_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add VariableRefExpr AST node"
```

---

### Task 9: Parse `$V{}`

**Files:**
- Modify: `packages/jet_print/lib/src/expression/parser.dart`
- Test: `packages/jet_print/test/expression/parser_variable_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/parser_variable_test.dart`:

```dart
// Parsing $V{} (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/lexer.dart';
import 'package:jet_print/src/expression/parser.dart';

String _parse(String src) => Parser(tokenize(src)).parseExpression().toString();

void main() {
  test('parses a variable reference', () {
    expect(_parse(r'$V{total}'), '(var total)');
  });

  test('parses a variable in an arithmetic expression', () {
    expect(_parse(r'$V{total} + $F{tax}'), '(+ (var total) (field tax))');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/parser_variable_test.dart`
Expected: FAIL — the parser's `_primary` has no `variableRef` case (falls to `default` and throws).

- [ ] **Step 3: Handle the token in `_primary`**

In `packages/jet_print/lib/src/expression/parser.dart`, add a case to `_primary`'s `switch` next to the `paramRef` case:

```dart
      case TokenType.variableRef:
        _pos++;
        return VariableRefExpr(token.literal! as String);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/parser_variable_test.dart`
Expected: PASS (the `VariableRefExpr` node renders `(var total)`).

- [ ] **Step 5: Commit** (analyzer still flags the evaluator's non-exhaustive switch until Task 10 — that is expected; commit and proceed)

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/parser.dart packages/jet_print/test/expression/parser_variable_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): parse \$V{} variable references"
```

---

### Task 10: Evaluate `$V{}` — `resolveVariable` + context variables

Add `resolveVariable` to `EvalContext`, have the evaluator handle `VariableRefExpr`, and give `RowEvalContext` a `variables` map. This closes the non-exhaustive-switch gap from Tasks 8–9.

**Files:**
- Modify: `packages/jet_print/lib/src/expression/eval_context.dart`
- Modify: `packages/jet_print/lib/src/expression/evaluator.dart`
- Modify: `packages/jet_print/test/expression/eval_context_test.dart` (the `_CtxStub`)
- Test: `packages/jet_print/test/expression/evaluator_variable_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/evaluator_variable_test.dart`:

```dart
// Evaluating $V{} against context variables (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src, Map<String, JetValue> variables) =>
    Expression.parse(src).evaluate(RowEvalContext(
      variables: variables,
      functions: JetFunctionRegistry(),
    ));

void main() {
  test('resolves a variable to its current value', () {
    expect(_eval(r'$V{total}', <String, JetValue>{'total': const JetNumber(42)}),
        const JetNumber(42));
  });

  test('a missing variable resolves to JetNull', () {
    expect(_eval(r'$V{missing}', const <String, JetValue>{}), const JetNull());
  });

  test('variables compose with fields/arithmetic', () {
    expect(
      _eval(r'$V{subtotal} + 1',
          <String, JetValue>{'subtotal': const JetNumber(9)}),
      const JetNumber(10),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/evaluator_variable_test.dart`
Expected: FAIL — `RowEvalContext` has no `variables` parameter and `EvalContext` has no `resolveVariable` (compile errors).

- [ ] **Step 3: Add `resolveVariable` and `variables`**

In `packages/jet_print/lib/src/expression/eval_context.dart`:

Add an abstract method to `EvalContext`:

```dart
  /// Resolves a `$V{name}` variable reference.
  JetValue resolveVariable(String name);
```

Add a `variables` field + constructor param + override to `RowEvalContext`:

```dart
  RowEvalContext({
    DataRow? row,
    Map<String, Object?> params = const <String, Object?>{},
    Map<String, JetValue> variables = const <String, JetValue>{},
    required JetFunctionRegistry functions,
  })  : _row = row,
        _params = params,
        _variables = variables,
        _functions = functions;

  final DataRow? _row;
  final Map<String, Object?> _params;
  final Map<String, JetValue> _variables;
  final JetFunctionRegistry _functions;

  // ... existing functions/resolveField/resolveParam ...

  @override
  JetValue resolveVariable(String name) =>
      _variables[name] ?? const JetNull();
```

(Keep the existing `resolveField`/`resolveParam`/`functions` members. The import of `value.dart` already provides `JetValue`/`JetNull`.)

In `packages/jet_print/lib/src/expression/evaluator.dart`, add the `VariableRefExpr` case to the top-level `switch (expr)`:

```dart
    case VariableRefExpr(name: final String n):
      return context.resolveVariable(n);
```

In `packages/jet_print/test/expression/eval_context_test.dart`, update the `_CtxStub` to satisfy the new interface member:

```dart
class _CtxStub implements EvalContext {
  @override
  JetFunctionRegistry get functions => JetFunctionRegistry();
  @override
  JetValue resolveField(String name) => const JetNull();
  @override
  JetValue resolveParam(String name) => const JetNull();
  @override
  JetValue resolveVariable(String name) => const JetNull();
}
```

- [ ] **Step 4: Run the new test + the whole expression suite (now exhaustive again)**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/`
Expected: PASS — the evaluator `switch` is exhaustive again; variable resolution works; no regressions.

- [ ] **Step 5: Format + analyze + commit**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/eval_context.dart packages/jet_print/lib/src/expression/evaluator.dart packages/jet_print/test/expression/eval_context_test.dart packages/jet_print/test/expression/evaluator_variable_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): resolve \$V{} via EvalContext.resolveVariable + RowEvalContext variables"
```

---

### Task 11: `VariableAccumulator`

The per-calculation fold: seed, fold one value, read the current value, reset. Tested directly so the eight calculations are pinned in isolation before the calculator orchestrates them.

**Files:**
- Create: `packages/jet_print/lib/src/expression/aggregate/variable_accumulator.dart`
- Test: `packages/jet_print/test/expression/aggregate/variable_accumulator_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/aggregate/variable_accumulator_test.dart`:

```dart
// VariableAccumulator: per-calculation folding (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/variable_accumulator.dart';
import 'package:jet_print/src/expression/value.dart';

VariableAccumulator _acc(JetCalculation c) => VariableAccumulator(c);

void main() {
  test('none holds the latest value (including null/error passthrough)', () {
    final VariableAccumulator a = _acc(JetCalculation.none);
    expect(a.value, const JetNull());
    a.fold(const JetNumber(5));
    expect(a.value, const JetNumber(5));
    a.fold(const JetNull());
    expect(a.value, const JetNull());
  });

  test('sum adds numbers and skips null/error/wrong-type', () {
    final VariableAccumulator a = _acc(JetCalculation.sum);
    expect(a.value, const JetNumber(0));
    a.fold(const JetNumber(2));
    a.fold(const JetNull()); // skipped
    a.fold(const JetError('x')); // skipped
    a.fold(const JetString('y')); // skipped (wrong type)
    a.fold(const JetNumber(3));
    expect(a.value, const JetNumber(5));
  });

  test('count counts non-null/non-error values of any type', () {
    final VariableAccumulator a = _acc(JetCalculation.count);
    a.fold(const JetNumber(1));
    a.fold(const JetString('x'));
    a.fold(const JetNull()); // skipped
    a.fold(const JetError('e')); // skipped
    expect(a.value, const JetNumber(2));
  });

  test('average is sum/count, null while empty', () {
    final VariableAccumulator a = _acc(JetCalculation.average);
    expect(a.value, const JetNull());
    a.fold(const JetNumber(2));
    a.fold(const JetNumber(4));
    expect(a.value, const JetNumber(3));
  });

  test('min/max keep the extreme', () {
    final VariableAccumulator lo = _acc(JetCalculation.min);
    final VariableAccumulator hi = _acc(JetCalculation.max);
    for (final JetValue v in <JetValue>[
      const JetNumber(3),
      const JetNumber(1),
      const JetNumber(2),
    ]) {
      lo.fold(v);
      hi.fold(v);
    }
    expect(lo.value, const JetNumber(1));
    expect(hi.value, const JetNumber(3));
  });

  test('first/last pick endpoints, skipping null', () {
    final VariableAccumulator f = _acc(JetCalculation.first);
    final VariableAccumulator l = _acc(JetCalculation.last);
    for (final JetValue v in <JetValue>[
      const JetNull(),
      const JetString('a'),
      const JetString('b'),
    ]) {
      f.fold(v);
      l.fold(v);
    }
    expect(f.value, const JetString('a'));
    expect(l.value, const JetString('b'));
  });

  test('reset returns to the seed', () {
    final VariableAccumulator a = _acc(JetCalculation.sum);
    a.fold(const JetNumber(9));
    a.reset();
    expect(a.value, const JetNumber(0));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/aggregate/variable_accumulator_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/aggregate/variable_accumulator.dart`:

```dart
/// Per-calculation accumulator for a report variable (spec 005b). Internal to
/// the expression seam.
library;

import '../../domain/report_variable.dart';
import '../value.dart';

/// Folds per-row [JetValue]s into a single value per a [JetCalculation].
///
/// Contribution filter: `JetNull`, `JetError`, and wrong-typed values are
/// skipped (the running value is unaffected) — except [JetCalculation.none],
/// which passes its latest value through unchanged.
class VariableAccumulator {
  /// Creates an accumulator for [calculation], seeded to its initial value.
  VariableAccumulator(this.calculation) {
    reset();
  }

  /// The fold strategy.
  final JetCalculation calculation;

  double _sum = 0;
  int _count = 0;
  JetValue _value = const JetNull();
  bool _hasValue = false;

  /// The accumulator's current value.
  JetValue get value => switch (calculation) {
        JetCalculation.none => _value,
        JetCalculation.sum => JetNumber(_sum),
        JetCalculation.count => JetNumber(_count.toDouble()),
        JetCalculation.average =>
          _count == 0 ? const JetNull() : JetNumber(_sum / _count),
        JetCalculation.min ||
        JetCalculation.max ||
        JetCalculation.first ||
        JetCalculation.last =>
          _hasValue ? _value : const JetNull(),
      };

  /// Folds one per-row [input] into the accumulator.
  void fold(JetValue input) {
    if (calculation == JetCalculation.none) {
      _value = input;
      return;
    }
    if (input is JetNull || input is JetError) return; // skip blanks/errors
    switch (calculation) {
      case JetCalculation.sum:
        if (input is JetNumber) _sum += input.value;
      case JetCalculation.average:
        if (input is JetNumber) {
          _sum += input.value;
          _count++;
        }
      case JetCalculation.count:
        _count++;
      case JetCalculation.min:
        if (!_hasValue) {
          _value = input;
          _hasValue = true;
        } else {
          final int? c = jetCompare(input, _value);
          if (c != null && c < 0) _value = input;
        }
      case JetCalculation.max:
        if (!_hasValue) {
          _value = input;
          _hasValue = true;
        } else {
          final int? c = jetCompare(input, _value);
          if (c != null && c > 0) _value = input;
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
  }

  /// Re-seeds the accumulator to its initial (empty-scope) state.
  void reset() {
    _sum = 0;
    _count = 0;
    _value = const JetNull();
    _hasValue = false;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/aggregate/variable_accumulator_test.dart`
Expected: PASS (all eight calculations + reset).

- [ ] **Step 5: Format + analyze + commit**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/aggregate/variable_accumulator.dart packages/jet_print/test/expression/aggregate/variable_accumulator_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add VariableAccumulator (per-calculation folding)"
```

---

### Task 12: `VariableCalculator`

The orchestration: compile each variable's expression and each group's key once, then `advance(row)` per row — evaluate group keys, detect the outermost broken group (cascading inner), reset that group's variables, then fold each variable in declaration order against a context exposing the current `values`.

**Files:**
- Create: `packages/jet_print/lib/src/expression/aggregate/variable_calculator.dart`
- Test: `packages/jet_print/test/expression/aggregate/variable_calculator_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/aggregate/variable_calculator_test.dart`:

```dart
// VariableCalculator: running totals, group resets, breaks (spec 005b).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/variable_calculator.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

DataRow _row(String cat, double amount) => DataRow(
      fields: const <FieldDef>[
        FieldDef('category', type: JetFieldType.string),
        FieldDef('amount', type: JetFieldType.double),
      ],
      values: <String, Object?>{'category': cat, 'amount': amount},
    );

VariableCalculator _calc() => VariableCalculator(
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'catTotal',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.group,
          resetGroup: 'category',
        ),
        ReportVariable(
          name: 'grand',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
        ),
      ],
      groups: const <ReportGroup>[
        ReportGroup(name: 'category', expression: r'$F{category}'),
      ],
      functions: JetFunctionRegistry(),
    );

void main() {
  test('group total resets on a break; grand total runs through', () {
    final VariableCalculator c = _calc()..start();
    // A,10 -> A,5 -> B,3
    c.advance(_row('A', 10));
    expect(c.valueOf('catTotal'), const JetNumber(10));
    expect(c.valueOf('grand'), const JetNumber(10));

    c.advance(_row('A', 5));
    expect(c.valueOf('catTotal'), const JetNumber(15)); // running within A
    expect(c.valueOf('grand'), const JetNumber(15));
    expect(c.brokenGroups, isEmpty);

    c.advance(_row('B', 3));
    expect(c.brokenGroups, <String>{'category'}); // category changed A->B
    expect(c.valueOf('catTotal'), const JetNumber(3)); // reset, then +3
    expect(c.valueOf('grand'), const JetNumber(18)); // grand keeps running
  });

  test('exposes all current values', () {
    final VariableCalculator c = _calc()..start();
    c.advance(_row('A', 4));
    expect(c.values, <String, JetValue>{
      'catTotal': const JetNumber(4),
      'grand': const JetNumber(4),
    });
  });

  test('a variable may reference an earlier variable via \$V{}', () {
    final VariableCalculator c = VariableCalculator(
      variables: const <ReportVariable>[
        ReportVariable(name: 'base', expression: r'$F{amount}'),
        ReportVariable(name: 'doubled', expression: r'$V{base} * 2'),
      ],
      groups: const <ReportGroup>[],
      functions: JetFunctionRegistry(),
    )..start();
    c.advance(_row('A', 7));
    expect(c.valueOf('doubled'), const JetNumber(14));
  });

  test('the first row never reports a break', () {
    final VariableCalculator c = _calc()..start();
    c.advance(_row('A', 1));
    expect(c.brokenGroups, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/aggregate/variable_calculator_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/aggregate/variable_calculator.dart`:

```dart
/// One-pass variable & aggregate calculator (spec 005b).
library;

import '../../data/data_row.dart';
import '../../domain/report_group.dart';
import '../../domain/report_variable.dart';
import '../eval_context.dart';
import '../expression.dart';
import '../function_registry.dart';
import '../value.dart';
import 'variable_accumulator.dart';

/// Computes report variables row-by-row, folding aggregates and resetting
/// group-scoped variables on group breaks.
///
/// Usage (the Fill stage drives this): call [start], then [advance] once per
/// data row in order; read [valueOf]/[values] after each advance to feed
/// element-expression evaluation, and [brokenGroups] to drive group footers
/// (008). Variables fold in declaration order; a variable's expression sees the
/// current [values] (updated for earlier-declared variables this row) via
/// `$V{}`.
class VariableCalculator {
  /// Creates a calculator over [variables] and [groups] (outermost first),
  /// compiling each expression once with [functions].
  VariableCalculator({
    required List<ReportVariable> variables,
    required List<ReportGroup> groups,
    required JetFunctionRegistry functions,
  })  : _variables = List<ReportVariable>.unmodifiable(variables),
        _groups = List<ReportGroup>.unmodifiable(groups),
        _functions = functions,
        _varExprs = <Expression>[
          for (final ReportVariable v in variables) Expression.parse(v.expression),
        ],
        _accumulators = <VariableAccumulator>[
          for (final ReportVariable v in variables)
            VariableAccumulator(v.calculation),
        ],
        _groupExprs = <Expression>[
          for (final ReportGroup g in groups) Expression.parse(g.expression),
        ];

  final List<ReportVariable> _variables;
  final List<ReportGroup> _groups;
  final JetFunctionRegistry _functions;
  final List<Expression> _varExprs;
  final List<VariableAccumulator> _accumulators;
  final List<Expression> _groupExprs;

  final Map<String, JetValue> _values = <String, JetValue>{};
  List<JetValue>? _prevKeys;
  Set<String> _brokenGroups = const <String>{};

  /// (Re)initializes all accumulators and clears group state.
  void start() {
    for (final VariableAccumulator a in _accumulators) {
      a.reset();
    }
    _values.clear();
    for (final ReportVariable v in _variables) {
      _values[v.name] = const JetNull();
    }
    _prevKeys = null;
    _brokenGroups = const <String>{};
  }

  /// Processes one [row] (with optional [params]), updating all variable values.
  void advance(DataRow row, {Map<String, Object?> params = const <String, Object?>{}}) {
    EvalContext ctx() => RowEvalContext(
          row: row,
          params: params,
          variables: _values,
          functions: _functions,
        );

    // 1. Evaluate this row's group keys.
    final List<JetValue> keys = <JetValue>[
      for (final Expression e in _groupExprs) e.evaluate(ctx()),
    ];

    // 2. Detect the outermost broken group; all inner groups break too.
    _brokenGroups = <String>{};
    final List<JetValue>? prev = _prevKeys;
    if (prev != null) {
      for (int i = 0; i < _groups.length; i++) {
        if (keys[i] != prev[i]) {
          for (int j = i; j < _groups.length; j++) {
            _brokenGroups.add(_groups[j].name);
          }
          break;
        }
      }
    }

    // 3. Reset group-scoped variables whose group broke (before folding).
    if (_brokenGroups.isNotEmpty) {
      for (int k = 0; k < _variables.length; k++) {
        final ReportVariable v = _variables[k];
        if (v.resetScope == VariableResetScope.group &&
            v.resetGroup != null &&
            _brokenGroups.contains(v.resetGroup)) {
          _accumulators[k].reset();
          _values[v.name] = _accumulators[k].value;
        }
      }
    }

    // 4. Fold each variable in declaration order; $V{} sees updated _values.
    for (int k = 0; k < _variables.length; k++) {
      final JetValue input = _varExprs[k].evaluate(ctx());
      _accumulators[k].fold(input);
      _values[_variables[k].name] = _accumulators[k].value;
    }

    _prevKeys = keys;
  }

  /// The current value of [variableName] (or [JetNull] if undeclared).
  JetValue valueOf(String variableName) =>
      _values[variableName] ?? const JetNull();

  /// All current variable values (for building an element-evaluation context).
  Map<String, JetValue> get values => Map<String, JetValue>.unmodifiable(_values);

  /// The group names that broke on the most recent [advance] (empty on the
  /// first row). Drives group footers/headers in the layout stage (008).
  Set<String> get brokenGroups => _brokenGroups;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/aggregate/variable_calculator_test.dart`
Expected: PASS — group reset on break, grand total running, `$V{}` cross-reference, first-row no-break.

- [ ] **Step 5: Format + analyze + commit**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/aggregate/variable_calculator.dart packages/jet_print/test/expression/aggregate/variable_calculator_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add VariableCalculator (group-break detection + resets)"
```

---

### Task 13: End-to-end integration

Drive the calculator over a realistic grouped dataset and evaluate an element expression that references `$V{}` + `$F{}` + a built-in function — the shape the Fill stage (007) will use.

**Files:**
- Test: `packages/jet_print/test/expression/aggregate/integration_test.dart`

- [ ] **Step 1: Write the test**

Create `packages/jet_print/test/expression/aggregate/integration_test.dart`:

```dart
// End-to-end: calculator + element expression with $V{} (spec 005b).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/variable_calculator.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/built_in_functions.dart';
import 'package:jet_print/src/expression/value.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('category', type: JetFieldType.string),
  FieldDef('amount', type: JetFieldType.double),
];

DataRow _row(String cat, double amt) => DataRow(
      fields: _schema,
      values: <String, Object?>{'category': cat, 'amount': amt},
    );

void main() {
  test('group subtotals, grand total, and a $V-formatted element value', () {
    final JetFunctionRegistry fns = JetFunctionRegistry();
    registerBuiltInFunctions(fns);

    final VariableCalculator calc = VariableCalculator(
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'catTotal',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.group,
          resetGroup: 'category',
        ),
        ReportVariable(
          name: 'grand',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
        ),
        ReportVariable(
          name: 'rowCount',
          expression: '1',
          calculation: JetCalculation.count,
        ),
      ],
      groups: const <ReportGroup>[
        ReportGroup(name: 'category', expression: r'$F{category}'),
      ],
      functions: fns,
    )..start();

    final List<DataRow> rows = <DataRow>[
      _row('A', 10),
      _row('A', 5),
      _row('B', 20),
    ];

    // An element expression a designer might bind to a footer cell.
    final Expression footer =
        Expression.parse(r"CONCAT('Subtotal: ', FORMAT($V{catTotal}, '#,##0.00'))");

    final List<String> footerValues = <String>[];
    for (final DataRow row in rows) {
      calc.advance(row);
      final JetValue v = footer.evaluate(RowEvalContext(
        row: row,
        variables: calc.values,
        functions: fns,
      ));
      footerValues.add((v as JetString).value);
    }

    // Running subtotals: A=10, A=15, then B resets to 20.
    expect(footerValues, <String>[
      'Subtotal: 10.00',
      'Subtotal: 15.00',
      'Subtotal: 20.00',
    ]);
    expect(calc.valueOf('grand'), const JetNumber(35)); // 10+5+20
    expect(calc.valueOf('rowCount'), const JetNumber(3));
  });
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/aggregate/integration_test.dart`
Expected: PASS — the full pipeline (calculator → variable values → element expression with `$V{}` + `FORMAT` + `CONCAT`) produces the running subtotals and grand total.

- [ ] **Step 3: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/test/expression/aggregate/integration_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "test(expr): end-to-end calculator + \$V{} element expression"
```

---

### Task 14: CHANGELOG + full gate

The layer-boundary test already covers the `expression` and `domain` seams; the new files import only allowed seams (`domain`, `data`, `intl`, `dart:` libs), so no architecture-test change is needed — but verify it stays green. Add the CHANGELOG entry and run the full gate.

**Files:**
- Modify: `packages/jet_print/CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

In `packages/jet_print/CHANGELOG.md`, under `## Unreleased` → `### Added`, append after the spec-005a bullet:

```markdown
- Aggregates & variables (spec 005b): `ReportVariable` (with `JetCalculation`
  SUM/COUNT/AVG/MIN/MAX/FIRST/LAST or a plain expression, and report/group reset
  scopes), `ReportGroup`, and typed `ReportParameter` declarations join
  `ReportTemplate` and serialize sparsely (still schema v1 — additive). The
  expression engine gains `$V{}` variable references, and a one-pass
  `VariableCalculator` folds per-row values into running/group-scoped
  accumulators with group-break detection (outermost-changed group cascades to
  inner groups). `JetFieldType` moved to the `domain` seam (re-exported from
  `data`) so parameters and fields share one value-type taxonomy. Page/column
  reset scopes are deferred to 008 (pagination).
```

- [ ] **Step 2: Run the full quality gate**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test`
Expected: PASS — all suites green (the 288 from 005a plus the new 005b tests; no regressions in `report_codec_test`, the data tests, or the architecture/encapsulation tests). Report the final count.

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/architecture/layer_boundaries_test.dart`
Expected: PASS — domain, data, and expression seam groups all green (the calculator imports `domain`/`data` only; `value_type.dart` in domain imports nothing).

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format --output=none --set-exit-if-changed lib/src test`
Expected: exit 0. If it reports changes, run `dart format lib/src test` and re-run.

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter analyze`
Expected: `No issues found!`.

- [ ] **Step 3: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/CHANGELOG.md
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "docs(expr): changelog for spec 005b aggregates & variables"
```

---

## Self-Review (completed before handoff)

**Spec coverage** (blueprint §4 #1 model, §4 #4 calculator):
- `ReportVariable` + `JetCalculation` (all 8) + reset scopes → Task 4. `ReportGroup` → Task 3. `ReportParameter` → Task 2. Template wiring + serialization → Task 5. `$V{}` lex/parse/eval → Tasks 7–10. Aggregate folding → Task 11. One-pass calculator + group resets + running totals → Task 12. End-to-end → Task 13. `JetFieldType` relocation enabling shared param/field types → Task 1. Page/column resets explicitly deferred to 008 (stated up front).

**Placeholder scan:** none — every code step has complete source. The Task 8 note about the transient non-exhaustive-switch (resolved in Task 10) is a sequencing explanation, not a placeholder.

**Type consistency:** `JetFieldType` (domain), `ReportParameter{name,type,defaultValue}`, `ReportGroup{name,expression}`, `ReportVariable{name,expression,calculation,resetScope,resetGroup}` + `JetCalculation`/`VariableResetScope`, `ReportTemplate{...,parameters,variables,groups}`, `jetCompare`, `TokenType.variableRef`, `VariableRefExpr`, `EvalContext.resolveVariable`, `RowEvalContext({...,variables})`, `VariableAccumulator(calculation)` + `fold`/`value`/`reset`, `VariableCalculator({variables,groups,functions})` + `start`/`advance`/`valueOf`/`values`/`brokenGroups` — names and signatures are consistent across every task.

**Convention checks:** relative imports ordered; value-type equality + `toJson`/`fromJson` mirror `src/domain`; sparse-at-default serialization matches the 003 style; no schema-version bump (additive); the `JetFieldType` relocation is zero-churn via re-export (Task 1 runs the full suite to prove it); the calculator stays within `expression → domain/data` (enforced by the unchanged layer test); the public facade `jet_print.dart` is intentionally untouched (deferred export). No new package dependencies.

**Cross-task sequencing pinned for reviewers:** Tasks 8 (AST node) → 9 (parser) → 10 (evaluator case) deliberately leave the evaluator's sealed `switch` non-exhaustive *between* commits; the full analyzer/suite is only asserted green again at Task 10. Each task's own targeted test passes at its own step. This is the one place the "every task independently green under the FULL analyzer" property is relaxed, by necessity of adding a sealed-type variant across three files.
