# Inline Aggregates (Phase A, master scope) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is Red→Green TDD (Constitution III).

**Goal:** An author writes `{SUM([customerTotal])}` in a value field instead of declaring a `ReportVariable` + `{$V{grandTotal}}`. The aggregate's scope is inferred from its band (Summary → report, Group Footer → that group). A pure fill-time transform expands the inline aggregate into a hidden, band-scoped `ReportVariable`, so the entire existing variable/accumulator pipeline runs unchanged. SUM/AVG/COUNT/MIN/MAX, expression arguments. Nested-collection aggregation is **Phase B** (out of scope).

**Architecture (one pure transform + a compiler extension):**
- Authored/stored form of an inline aggregate is a normal expression string: `SUM($F{customerTotal})`. It is single-sourced in `TextElement.expression` (Constitution IV) and round-trips to `{SUM([customerTotal])}` in the value field.
- `AggregateSynthesizer.expand(def) → def'` (NEW, pure): scans the **summary band** (→ report scope) and each **root group footer** (→ that group), finds top-level aggregate calls, synthesizes one hidden `ReportVariable` per distinct `(calculation, expression, scope)`, rewrites the element's expression to `$V{__agg<n>}`, and appends the synthesized variables. The `$V{__agg<n>}` form is **transient** — never serialized; the designer only ever sees the `SUM(...)` sugar.
- `ReportFiller.fillDefinition` calls `expand()` as its first line; synthesized variables fold over master rows through the unchanged `VariableCalculator`.

**Tech Stack:** Dart / Flutter, `flutter_test`. Pure-domain + expression + fill layers (no UI). Mirrors the existing variable machinery (spec 005b) and the value-template compiler (spec 013).

**Conventions:** Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (the `flutter` tool leaves cwd inside the package — see [[git-cwd-drift-after-flutter]]). Branch is already `028-inline-aggregates`.

## Constitution Check

| Principle | Status |
|---|---|
| I. Library-first / clean API | PASS — new types live under `src/`; nothing new exported. Authoring is via the existing value field. |
| II. Layered architecture | PASS — `aggregate_functions.dart` + `aggregate_synthesizer.dart` sit in the expression/aggregate seam; the domain model is untouched except a schema-less validation rule; no inward dependency violations. |
| III. Test-First (NON-NEGOTIABLE) | PASS — every task is Red→Green with unit/integration tests before code. |
| IV. Rendering fidelity / WYSIWYG | PASS — no parallel render path; the aggregate compiles to a variable the one renderer already handles. SC-001 proves byte-identical output. |
| V. Serialization | PASS — stored form is an ordinary expression string; no schema/version change. Synthesized `$V{__agg<n>}` is transient and never serialized. |
| VI. Docs/DX | PASS — dartdoc on new public-within-`src` symbols; `dart format` + clean analyzer gate in Task 7. |

No violations → Complexity Tracking omitted.

---

## File Map

- `packages/jet_print/lib/src/expression/aggregate/aggregate_functions.dart` — **new**: the single `{SUM,AVG,COUNT,MIN,MAX}→JetCalculation` table; `aggregateCalculationFor(String)`; `topLevelAggregate(Expr)` detector.
- `packages/jet_print/lib/src/expression/aggregate/aggregate_synthesizer.dart` — **new**: `expandAggregates(ReportDefinition) → ReportDefinition` pure transform.
- `packages/jet_print/lib/src/designer/template/value_template_compiler.dart` — **modify**: forward-compile `{FN([expr])}` → `FN(<expr>)`; reverse-render a top-level aggregate call back to `{FN([…])}` (with an argument AST→template renderer).
- `packages/jet_print/lib/src/rendering/fill/report_filler.dart` — **modify**: one line — expand aggregates before building the calculator.
- `packages/jet_print/lib/src/domain/report_validation.dart` — **modify**: emit an error for a top-level aggregate call in an unsupported band.
- `apps/jet_print_playground/lib/nested_list_sample.dart` — **modify**: drop the `grandTotal` variable; the summary element's `expression` becomes `SUM($F{customerTotal})`.
- Tests (new/modify): `aggregate_functions_test.dart`, `aggregate_synthesizer_test.dart`, `value_template_compiler_test.dart` (extend), `jet_report_engine_test.dart` (extend — inline-aggregate integration + equivalence), `report_validation_test.dart` (extend), `apps/jet_print_playground/test/nested_list_definition_test.dart` (update).

---

## Task 1: Shared aggregate-function table + detector

**Files:**
- New: `packages/jet_print/lib/src/expression/aggregate/aggregate_functions.dart`
- Test (new): `packages/jet_print/test/expression/aggregate/aggregate_functions_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/aggregate_functions.dart';
import 'package:jet_print/src/expression/expression.dart';

void main() {
  test('maps the five aggregate names (case-insensitive) to calculations', () {
    expect(aggregateCalculationFor('SUM'), JetCalculation.sum);
    expect(aggregateCalculationFor('avg'), JetCalculation.average);
    expect(aggregateCalculationFor('Count'), JetCalculation.count);
    expect(aggregateCalculationFor('MIN'), JetCalculation.min);
    expect(aggregateCalculationFor('max'), JetCalculation.max);
    expect(aggregateCalculationFor('UPPER'), isNull);
  });

  test('detects a single-arg top-level aggregate call', () {
    final agg = topLevelAggregate(Expression.parse(r'SUM($F{x})').root);
    expect(agg, isNotNull);
    expect(agg!.calculation, JetCalculation.sum);
  });

  test('a multi-arg MIN/MAX is NOT an aggregate (scalar function)', () {
    expect(topLevelAggregate(Expression.parse(r'MIN($F{a}, $F{b})').root),
        isNull);
  });

  test('a non-top-level aggregate (nested in arithmetic) is not detected', () {
    expect(topLevelAggregate(Expression.parse(r'SUM($F{x}) + 1').root), isNull);
  });
}
```

NOTE: this test reads `Expression.parse(...).root`. `Expression` currently keeps `_root` private. Add a public getter in `expression.dart` (Step 3a) — `Expr get root => _root;` — used by the synthesizer and compiler too.

- [ ] **Step 2: Run → FAIL** (`flutter test test/expression/aggregate/aggregate_functions_test.dart`) — file/symbols do not exist.

- [ ] **Step 3a: Expose the parsed AST root**

In `packages/jet_print/lib/src/expression/expression.dart`, add to `Expression`:
```dart
  /// The parsed AST root (internal seam — used by the aggregate synthesizer and
  /// the value-template compiler to inspect/rewrite expressions).
  Expr get root => _root;
```
(Import of `ast.dart`'s `Expr` already present in that file.)

- [ ] **Step 3b: Create `aggregate_functions.dart`**

```dart
/// The inline-aggregate vocabulary (spec 028): the five aggregate function
/// names an author may write inline (`SUM`/`AVG`/`COUNT`/`MIN`/`MAX`) and the
/// rule that recognizes a *top-level* aggregate call. Shared by the value
/// template compiler, the aggregate synthesizer, and validation so the surface
/// stays single-sourced.
library;

import '../../domain/report_variable.dart';
import '../ast.dart';

/// The aggregate function names mapped to their fold strategy. `MIN`/`MAX`
/// collide with the scalar math functions of the same name; disambiguation is
/// by arity + band (see [topLevelAggregate] and the synthesizer).
const Map<String, JetCalculation> _aggregates = <String, JetCalculation>{
  'SUM': JetCalculation.sum,
  'AVG': JetCalculation.average,
  'COUNT': JetCalculation.count,
  'MIN': JetCalculation.min,
  'MAX': JetCalculation.max,
};

/// The calculation for aggregate-function [name] (case-insensitive), or null if
/// [name] is not an aggregate function.
JetCalculation? aggregateCalculationFor(String name) =>
    _aggregates[name.toUpperCase()];

/// A recognized inline aggregate: its [calculation] and single [argument].
class AggregateCall {
  const AggregateCall(this.calculation, this.argument);
  final JetCalculation calculation;
  final Expr argument;
}

/// Recognizes [expr] as a top-level inline aggregate: a [CallExpr] whose name is
/// an aggregate function with exactly one argument. Returns null otherwise (a
/// multi-arg `MIN`/`MAX` is the scalar function; an aggregate nested inside other
/// syntax is not top-level). The single-arg + band rule is the disambiguation
/// from the scalar `MIN`/`MAX` math functions (FR-005).
AggregateCall? topLevelAggregate(Expr expr) {
  if (expr is! CallExpr || expr.arguments.length != 1) return null;
  final JetCalculation? calc = aggregateCalculationFor(expr.name);
  if (calc == null) return null;
  return AggregateCall(calc, expr.arguments.single);
}
```

- [ ] **Step 4: Run → PASS**.
- [ ] **Step 5: Analyzer clean** (`dart analyze lib/src/expression/aggregate/aggregate_functions.dart lib/src/expression/expression.dart`).
- [ ] **Step 6: Commit** — `feat(expr): inline-aggregate function table + top-level detector`.

---

## Task 2: Value-template compiler — `{FN([expr])}` forward + reverse

**Files:**
- Modify: `packages/jet_print/lib/src/designer/template/value_template_compiler.dart`
- Test (modify): `packages/jet_print/test/designer/template/value_template_compiler_test.dart`

- [ ] **Step 1: Write failing tests** (append to the existing `main()`):

```dart
  group('inline aggregates (028)', () {
    test('a single-field aggregate compiles to a call', () {
      expect(parseValueField('{SUM([customerTotal])}'),
          const BindingValue(r'SUM($F{customerTotal})'));
    });

    test('an expression-argument aggregate compiles', () {
      expect(parseValueField('{SUM([qty] * [unitPrice])}'),
          const BindingValue(r'SUM($F{qty} * $F{unitPrice})'));
    });

    test('case-insensitive function name normalizes to upper', () {
      expect(parseValueField('{avg([orderTotal])}'),
          const BindingValue(r'AVG($F{orderTotal})'));
    });

    test('reverse-compiles a stored aggregate back to the sugar', () {
      expect(reverseCompile(r'SUM($F{customerTotal})'),
          const ValueDisplay('{SUM([customerTotal])}'));
    });

    test('round-trips an expression-argument aggregate', () {
      const stored = r'SUM($F{qty} * $F{unitPrice})';
      final display = reverseCompile(stored);
      expect(display, const ValueDisplay('{SUM([qty] * [unitPrice])}'));
      expect(parseValueField(display.text), const BindingValue(stored));
    });
  });
```

- [ ] **Step 2: Run → FAIL** — today `{SUM([x])}` mis-compiles to `CONCAT("SUM(", $F{x}, ")")` (the `SUM(` is not recognized; `SUM` is followed by `(`, not `[`).

- [ ] **Step 3a: Forward — recognize `IDENT( … )` aggregate calls**

In `_compileTemplate`, the `else if (_isAlpha(c))` branch currently handles only `ident[field]` (ident immediately followed by `[`). Add the parenthesized-call case **before** the existing `inner[identEnd] == '['` check:

```dart
    } else if (_isAlpha(c)) {
      final int identEnd = _scanIdentEnd(inner, i);
      if (identEnd < inner.length && inner[identEnd] == '(' &&
          aggregateCalculationFor(inner.substring(i, identEnd)) != null) {
        // Inline aggregate: FN( <expr with [field] tokens> ).
        flushLiteral();
        final String fn = inner.substring(i, identEnd).toUpperCase();
        final _CallScan scan = _scanBalancedParens(inner, identEnd);
        parts.add('$fn(${_compileArg(scan.body)})');
        i = scan.next;
      } else if (identEnd < inner.length && inner[identEnd] == '[') {
        // Function sugar: ident[field].
        ... (unchanged) ...
```

Add helpers (top-level functions in the file):

```dart
class _CallScan {
  const _CallScan(this.body, this.next);
  final String body;   // text between the outer parens
  final int next;      // index just past the closing ')'
}

/// Scans `( … )` starting at the `(` at [open], honoring nested parens; returns
/// the inner text and the index past the matching `)`.
_CallScan _scanBalancedParens(String s, int open) {
  int depth = 0;
  for (int i = open; i < s.length; i++) {
    if (s[i] == '(') depth++;
    else if (s[i] == ')') {
      depth--;
      if (depth == 0) return _CallScan(s.substring(open + 1, i), i + 1);
    }
  }
  throw const _TemplateError();
}

/// Compiles an aggregate argument: replaces each `[name]` token with `$F{name}`
/// and passes all other expression syntax (operators, numbers, parens, calls)
/// through unchanged, then verifies the whole call parses.
String _compileArg(String arg) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < arg.length) {
    if (arg[i] == '[') {
      final _FieldScan scan = _scanField(arg, i);
      out.write('\$F{${scan.name}}');
      i = scan.next;
    } else {
      out.write(arg[i]);
      i++;
    }
  }
  return out.toString();
}
```

Then, after `_compileTemplate` builds the call string, the existing `parts.length == 1 && !_isQuoted(...)` path returns it as the whole expression. Guard the result: a bare aggregate call (single part, unquoted) is returned as-is. To be safe, after constructing the final expression string in `parseValueField`, the existing flow already validates by virtue of `_compileTemplate`; add a parse check for the aggregate path so a malformed arg falls back to literal:

```dart
  if (raw.length >= 2 && raw.startsWith('{') && raw.endsWith('}')) {
    try {
      final String expr = _compileTemplate(raw.substring(1, raw.length - 1));
      // Validate compiled aggregates actually parse (malformed → literal).
      Parser(tokenize(expr)).parseExpression();
      return BindingValue(expr);
    } on _TemplateError {
    } on ExpressionException {
      // Malformed compiled expression → treat whole value as literal.
    }
  }
```

Add the import: `import '../../expression/aggregate/aggregate_functions.dart';` (for `aggregateCalculationFor`).

- [ ] **Step 3b: Reverse — render a top-level aggregate call to `{FN([…])}`**

In `_exprToToken(Expr root)`, before the generic single-call fallback, add:

```dart
  final AggregateCall? agg = topLevelAggregate(root);
  if (agg != null) {
    final String? arg = _argToToken(agg.argument);
    if (arg != null) return '{${_aggName(agg.calculation)}($arg)}';
  }
```

Add an argument AST→template renderer (covers field refs, literals, arithmetic/comparison binaries, unary, params/vars, nested calls; returns null → caller falls back to read-only verbatim display, preserving existing behavior):

```dart
/// Renders an aggregate-argument [Expr] back to `[field]`-token template text,
/// or null if it contains a construct outside the round-trippable grammar.
String? _argToToken(Expr e) {
  if (e is FieldRefExpr) return '[${e.name}]';
  if (e is ParamRefExpr) return '\$P{${e.name}}';
  if (e is VariableRefExpr) return '\$V{${e.name}}';
  if (e is LiteralExpr) {
    final JetValue v = e.value;
    if (v is JetNumber) return _formatNumber(v.value);
    if (v is JetString) return '"${v.value.replaceAll('"', r'\"')}"';
    if (v is JetBool) return v.value ? 'true' : 'false';
    return null;
  }
  if (e is UnaryExpr) {
    final String? operand = _argToToken(e.operand);
    return operand == null ? null : '${e.op == UnaryOp.negate ? '-' : '!'}$operand';
  }
  if (e is BinaryExpr) {
    final String? l = _argToToken(e.left);
    final String? r = _argToToken(e.right);
    final String? op = _binarySymbol(e.op);
    return (l == null || r == null || op == null) ? null : '$l $op $r';
  }
  if (e is CallExpr) {
    final List<String> args = <String>[];
    for (final Expr a in e.arguments) {
      final String? t = _argToToken(a);
      if (t == null) return null;
      args.add(t);
    }
    return '${e.name.toLowerCase()}(${args.join(', ')})';
  }
  return null;
}
```

Plus small helpers `_aggName(JetCalculation)` (`sum→'SUM'`, … reuse the table inverse), `_binarySymbol(BinaryOp)` (`add→'+'`, `multiply→'*'`, `equal→'=='`, …), and `_formatNumber(double)` (integers without trailing `.0`). Imports: `aggregate_functions.dart`, and `ast.dart` already imported.

NOTE on `_aggName`: add `aggregateNameFor(JetCalculation)` to `aggregate_functions.dart` (inverse lookup over the same `_aggregates` map) so the name table stays single-sourced (FR-006).

- [ ] **Step 4: Run → PASS** (all compiler tests, old + new).
- [ ] **Step 5: Analyzer clean**.
- [ ] **Step 6: Commit** — `feat(designer): compile/reverse inline aggregate {FN([expr])} sugar`.

---

## Task 3: AggregateSynthesizer — the pure def→def transform

**Files:**
- New: `packages/jet_print/lib/src/expression/aggregate/aggregate_synthesizer.dart`
- Test (new): `packages/jet_print/test/expression/aggregate/aggregate_synthesizer_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
library;

import 'package:flutter_test/flutter_test.dart';
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

TextElement _agg(String id, String expr) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
      text: id,
      expression: expr,
    );

void main() {
  test('a summary aggregate synthesizes a report-scoped variable', () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(id: 's', type: BandType.summary, height: 16,
            elements: <ReportElement>[_agg('g', r'SUM($F{customerTotal})')]),
        root: const DetailScope(id: 'root'),
      ),
    );
    final out = expandAggregates(def);
    expect(out.variables, hasLength(1));
    final v = out.variables.single;
    expect(v.calculation, JetCalculation.sum);
    expect(v.expression, r'$F{customerTotal}');
    expect(v.resetScope, VariableResetScope.report);
    // The element now references the synthesized variable.
    final el = out.body.summary!.elements.single as TextElement;
    expect(el.expression, '\$V{${v.name}}');
  });

  test('a group-footer aggregate synthesizes a group-scoped variable', () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', groups: <GroupLevel>[
          GroupLevel(id: 'cust', name: 'cust', key: r'$F{code}',
            footer: Band(id: 'f', type: BandType.groupFooter, height: 16,
                elements: <ReportElement>[_agg('t', r'SUM($F{amount})')])),
        ]),
      ),
    );
    final v = expandAggregates(def).variables.single;
    expect(v.resetScope, VariableResetScope.group);
    expect(v.resetGroup, 'cust');
  });

  test('identical aggregates in one scope de-dup to one variable', () {
    final def = ReportDefinition(
      name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(id: 's', type: BandType.summary, height: 16,
            elements: <ReportElement>[
              _agg('a', r'SUM($F{x})'), _agg('b', r'SUM($F{x})')]),
        root: const DetailScope(id: 'root')),
    );
    expect(expandAggregates(def).variables, hasLength(1));
  });

  test('no aggregates → definition returned unchanged', () {
    const def = ReportDefinition(
      name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(root: DetailScope(id: 'root')));
    expect(expandAggregates(def), def);
  });
}
```

- [ ] **Step 2: Run → FAIL** (symbol missing).

- [ ] **Step 3: Create `aggregate_synthesizer.dart`**

Design notes:
- Scopes scanned: `body.summary` → `VariableResetScope.report`; each `body.root.groups[i].footer` → `VariableResetScope.group` with `resetGroup = group.name`. (These are exactly the two render-complete master-scope bands; Phase B extends this to nested scopes.)
- For each `TextElement` whose `expression` parses and `topLevelAggregate` matches: compute the **inner expression source** by reverse-rendering the argument AST to an expression string (reuse a minimal unparser — or, simpler, slice the original stored string: the arg is everything between the first `(` and the last `)` of the stored `FN(...)`). Use the **string-slice** approach to avoid a second unparser: `inner = stored.substring(stored.indexOf('(') + 1, stored.lastIndexOf(')'))`. This yields `$F{customerTotal}` or `$F{qty} * $F{unitPrice}` verbatim — exactly the variable expression we want.
- De-dup key: `'${scope}|${calc}|${inner}'`. Assign names `__agg0`, `__agg1`, … in first-seen order. Map element→`$V{name}`.
- Rebuild only the bands that changed (new `TextElement` via constructor — `copyWith` cannot set `expression`), then `Band.copyWith(elements:)`, `GroupLevel.copyWith(footer:)`, `DetailScope.copyWith(groups:)`, `ReportBody.copyWith(summary:/root:)`, `ReportDefinition.copyWith(variables: [...existing, ...synth], body:)`.
- Non-`TextElement` elements and non-aggregate expressions pass through untouched. If `body.summary`/footers are null or contain no aggregates, return `def` **identical** (the no-op test asserts `==`).

```dart
/// Inline-aggregate expansion (spec 028, Phase A): a pure transform that turns
/// inline aggregate calls (`SUM($F{customerTotal})`) authored in a value field
/// into hidden, band-scoped [ReportVariable]s plus `$V{}` references, so the fill
/// pass computes them through the unchanged variable/accumulator pipeline.
///
/// Scope is inferred from the band: the **summary** band → report scope; a root
/// **group footer** → that group. Only these two render-complete master-scope
/// bands are expanded here; nested-collection aggregation is Phase B. Aggregates
/// in any other band are left in place and flagged by validation
/// (`report_validation`), not expanded.
library;

import '../../domain/band.dart';
import '../../domain/detail_scope.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/group_level.dart';
import '../../domain/report_definition.dart';
import '../../domain/report_element.dart';
import '../../domain/report_variable.dart';
import '../expression.dart';
import '../expression_exception.dart';
import 'aggregate_functions.dart';

/// Returns [def] with every inline aggregate in a summary band or root group
/// footer expanded to a synthesized variable + `$V{}` reference. Returns [def]
/// unchanged (==) when there are none.
ReportDefinition expandAggregates(ReportDefinition def) {
  final List<ReportVariable> synth = <ReportVariable>[];
  final Map<String, String> nameByKey = <String, String>{};

  String? rewriteExpression(String? expr, VariableResetScope scope,
      String? resetGroup) {
    if (expr == null) return null;
    final AggregateCall? agg;
    try {
      agg = topLevelAggregate(Expression.parse(expr).root);
    } on ExpressionException {
      return null;
    }
    if (agg == null) return null;
    final String inner =
        expr.substring(expr.indexOf('(') + 1, expr.lastIndexOf(')'));
    final String key = '${scope.name}|${resetGroup ?? ''}|'
        '${agg.calculation.name}|$inner';
    final String name = nameByKey.putIfAbsent(key, () {
      final String n = '__agg${nameByKey.length}';
      synth.add(ReportVariable(
        name: n,
        expression: inner,
        calculation: agg!.calculation,
        resetScope: scope,
        resetGroup: resetGroup,
      ));
      return n;
    });
    return '\$V{$name}';
  }

  Band? rewriteBand(Band? band, VariableResetScope scope, String? resetGroup) {
    if (band == null) return null;
    bool changed = false;
    final List<ReportElement> els = <ReportElement>[
      for (final ReportElement e in band.elements)
        if (e is TextElement) _maybeRewrite(e, scope, resetGroup, rewriteExpression,
                () => changed = true) else e,
    ];
    return changed ? band.copyWith(elements: els) : band;
  }

  // Summary → report scope.
  final Band? summary = rewriteBand(def.body.summary, VariableResetScope.report, null);

  // Each root group footer → that group.
  final List<GroupLevel> groups = <GroupLevel>[
    for (final GroupLevel g in def.body.root.groups)
      () {
        final Band? footer =
            rewriteBand(g.footer, VariableResetScope.group, g.name);
        return identical(footer, g.footer) ? g : g.copyWith(footer: footer);
      }(),
  ];

  if (synth.isEmpty) return def;

  final DetailScope root = def.body.root.copyWith(groups: groups);
  return def.copyWith(
    variables: <ReportVariable>[...def.variables, ...synth],
    body: def.body.copyWith(summary: summary, root: root),
  );
}

TextElement _maybeRewrite(
  TextElement e,
  VariableResetScope scope,
  String? resetGroup,
  String? Function(String?, VariableResetScope, String?) rewrite,
  void Function() markChanged,
) {
  final String? next = rewrite(e.expression, scope, resetGroup);
  if (next == null) return e;
  markChanged();
  return TextElement(
    id: e.id,
    bounds: e.bounds,
    text: e.text,
    style: e.style,
    expression: next,
    format: e.format,
  );
}
```

(If the `rewriteBand` closure-capturing-`changed` pattern reads awkwardly under the analyzer, hoist `_maybeRewrite` to return a nullable and track change by identity — functionally identical.)

- [ ] **Step 4: Run → PASS**.
- [ ] **Step 5: Analyzer clean**.
- [ ] **Step 6: Commit** — `feat(expr): AggregateSynthesizer expands inline aggregates to scoped variables`.

---

## Task 4: Wire the synthesizer into the filler + integration test

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test (modify): `packages/jet_print/test/rendering/engine/jet_report_engine_test.dart`

- [ ] **Step 1: Write the failing integration test** (append). It mirrors the existing group-subtotal+grand-total test but uses an **inline** summary aggregate, and adds an equivalence assertion:

```dart
  test('an inline summary aggregate renders the same as a hand variable', () {
    // Authored with NO variable; the summary element carries the inline form.
    final inline = ReportDefinition(
      name: 'inline', page: tallPage,
      body: ReportBody(
        summary: Band(id: 'body/summary', type: BandType.summary, height: 18,
          elements: <ReportElement>[
            TextElement(
              id: 'grand',
              bounds: const JetRect(x: 0, y: 0, width: 200, height: 16),
              text: 'grand',
              expression: r'SUM($F{amount})',
            ),
          ]),
        root: const DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(id: 'root/c0', type: BandType.detail, height: 18,
            elements: <ReportElement>[
              TextElement(id: 'amount',
                bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                text: 'amount', expression: r'$F{amount}'),
            ])),
        ]),
      ),
    );
    final source = JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'amount': 10},
      <String, Object?>{'amount': 20},
      <String, Object?>{'amount': 5},
    ]);
    final report = const JetReportEngine().renderDefinition(inline, source);
    expect(runsFor(report, 'grand'), <String>['35.0'],
        reason: 'the inline SUM folds over all master rows at report scope');
  });
```

- [ ] **Step 2: Run → FAIL** — today `SUM($F{amount})` hits the function registry, which has no `SUM`, so it errors instead of summing.

- [ ] **Step 3: Expand before filling**

In `report_filler.dart` `fillDefinition`, make the very first line of the body wrap the input:
```dart
    definition = expandAggregates(definition);
```
Change the parameter to a local (the signature stays; reassign at top): since `definition` is a positional final parameter, introduce `ReportDefinition definition = expandAggregates(rawDefinition);` by renaming the parameter to `rawDefinition` and adding the local — OR keep the name and add `final ReportDefinition def = expandAggregates(definition);` then use `def` throughout. Simplest: rename the parameter to `rawDefinition` and add as the first statement:
```dart
  FillResult fillDefinition(
    ReportDefinition rawDefinition,
    JetDataSource source, { ... }) {
    final ReportDefinition definition = expandAggregates(rawDefinition);
    ...
```
Add import: `import '../../expression/aggregate/aggregate_synthesizer.dart';`

- [ ] **Step 4: Run → PASS** (new test + all existing engine tests — the existing hand-variable tests are unaffected because they contain no inline aggregates, so `expandAggregates` returns them unchanged).

- [ ] **Step 5: Analyzer clean**.
- [ ] **Step 6: Commit** — `feat(fill): expand inline aggregates before the variable calculator`.

---

## Task 5: Validation — aggregate in an unsupported band

**Files:**
- Modify: `packages/jet_print/lib/src/domain/report_validation.dart`
- Test (modify): `packages/jet_print/test/domain/report_validation_test.dart`

- [ ] **Step 1: Write failing tests** — an aggregate in a **detail** band (and in a **group header**, and a **page header**) yields an error diagnostic; an aggregate in **summary**/**group footer** yields none.

```dart
  test('an inline aggregate outside summary/group-footer is an error', () {
    final def = ReportDefinition(
      name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(root: DetailScope(id: 'root', children: <ScopeNode>[
        BandNode(Band(id: 'd', type: BandType.detail, height: 16,
          elements: <ReportElement>[
            TextElement(id: 'bad',
              bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
              text: 'bad', expression: r'SUM($F{amount})'),
          ])),
      ])));
    final errors = validate(def)
        .where((d) => d.severity == DiagnosticSeverity.error)
        .map((d) => d.message);
    expect(errors, anyElement(contains('aggregate')));
  });

  test('an inline aggregate in summary is valid', () {
    final def = ReportDefinition(
      name: 'r', page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(id: 's', type: BandType.summary, height: 16,
          elements: <ReportElement>[
            TextElement(id: 'ok',
              bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
              text: 'ok', expression: r'SUM($F{amount})'),
          ]),
        root: const DetailScope(id: 'root')));
    expect(validate(def).where((d) => d.message.contains('aggregate')), isEmpty);
  });
```

- [ ] **Step 2: Run → FAIL** (no such diagnostic yet).

- [ ] **Step 3: Add the check**

In `validate()`, walk every band NOT in the supported set (everything except `body.summary` and each `root.groups[*].footer`) and, for each `TextElement` whose expression parses to a top-level aggregate, append:
```dart
out.add(Diagnostic(
  DiagnosticSeverity.error,
  'element "${el.id}" uses an aggregate (${name}) in band "${band.id}", which '
  'is not a summary or group footer; aggregates are only computed there',
  elementId: el.id,
));
```
Implementation: add a helper `void aggregateBand(Band? band, {required bool supported})` invoked alongside the existing `slotBand`/`walkScope` traversal — pass `supported: true` for `body.summary` and group footers, `false` for furniture bands, `body.title`, `body.noData`, group headers, and every `BandNode` band in the scope tree. Reuse `topLevelAggregate(Expression.parse(expr).root)` guarded by try/catch (a non-parsing expression is already covered by other diagnostics). Import `aggregate_functions.dart` + `expression.dart`.

NOTE (FR-008, nested fields): explicit nested-field detection needs the data schema, which `validate(def)` does not receive. Phase A relies on the existing **fill-time unresolved-field diagnostic** — a nested field (e.g. `lineTotal`) referenced on a master row resolves to nothing, so `FillEvalContext` emits an unresolved-field warning and the value falls back to the `unresolvedFieldToken`, never a silently-wrong number. Document this in the synthesizer dartdoc; a dedicated schema-aware message is a possible later enhancement and is explicitly out of Phase A scope.

- [ ] **Step 4: Run → PASS**.
- [ ] **Step 5: Analyzer clean**.
- [ ] **Step 6: Commit** — `feat(domain): flag inline aggregates outside summary/group-footer`.

---

## Task 6: Playground sample migration + byte-identical acceptance (SC-001)

**Files:**
- Modify: `apps/jet_print_playground/lib/nested_list_sample.dart`
- Test (modify): `apps/jet_print_playground/test/nested_list_definition_test.dart`

- [ ] **Step 1: Update the sample test (Red)** — assert the NEW authored shape: no declared variable; the summary element carries the inline aggregate; and the render still produces the same grand total.

Replace the existing `'declares a report-scoped grand total over the customer totals'` test with:
```dart
  test('the grand total is authored inline (no declared variable)', () {
    final def = nestedListsDefinition();
    expect(def.variables, isEmpty,
        reason: 'the aggregate is inline in the summary, not a declared variable');
    final el = def.body.summary!.elements
        .firstWhere((e) => e.id == 'grandTotal') as TextElement;
    expect(el.expression, r'SUM($F{customerTotal})');
  });
```
Add (new) an equivalence test proving SC-001 — the inline form renders identically to the prior hand-declared variable form:
```dart
  test('inline grand total renders identically to the hand-declared variable',
      () {
    final inlineReport = renderNestedListsDefinition();
    final legacyReport =
        const JetReportEngine().renderDefinition(_legacyGrandTotalDefinition(), _sampleSource());
    expect(_textRuns(inlineReport), _textRuns(legacyReport),
        reason: 'inline {SUM([customerTotal])} == the prior $V{grandTotal} variable');
  });
```
where `_legacyGrandTotalDefinition()` is a local copy of today's definition (with the `grandTotal` variable + `$V{grandTotal}` summary element) and `_textRuns(RenderedReport)` flattens text primitives to a comparable `List<String>`. (`_sampleSource()`/`renderNestedListsDefinition()` already exist in the test/sample; reuse them. If `renderNestedListsDefinition` lives in the sample lib, add the legacy helper to the test file.)

- [ ] **Step 2: Run → FAIL** (sample still declares the variable).

- [ ] **Step 3: Migrate the sample**

In `nested_list_sample.dart`:
1. Remove the `variables: <ReportVariable>[ ReportVariable(name: 'grandTotal', …) ]` block from `nestedListsDefinition()`.
2. Change the summary `TextElement` `expression: r'$V{grandTotal}'` → `expression: r'SUM($F{customerTotal})'` (keep its `id: 'grandTotal'`, `format: '#,##0.00'`, bounds, text).
3. Update the dartdoc comment that describes "the single aggregate the engine computes live" to say it is now authored inline as `{SUM([customerTotal])}`, expanded at fill time.

- [ ] **Step 4: Run → PASS** (both the shape test and the equivalence test). Confirm `renderDefinition` still reports zero error diagnostics (existing line 67-78 test).

- [ ] **Step 5: Analyzer clean** (`flutter analyze` in both `packages/jet_print` and `apps/jet_print_playground`).
- [ ] **Step 6: Commit** — `feat(playground): author the nested-list grand total inline as SUM([customerTotal])`.

---

## Task 7: Full verification sweep

**Files:** none (verification only).

- [ ] **Step 1: Whole-package analyzer** — `cd packages/jet_print && flutter analyze` → "No issues found!". Repeat in `apps/jet_print_playground`.
- [ ] **Step 2: Format check** — `dart format --output=none --set-exit-if-changed lib test` in `packages/jet_print` (and the sample). Fix if needed.
- [ ] **Step 3: Full test suite** — `cd packages/jet_print && flutter test` → all green. Then `cd apps/jet_print_playground && flutter test` → green. **If any GOLDEN test fails, STOP and inspect** — Phase A changes no rendered output, so goldens MUST be unchanged; a golden diff means the equivalence is broken. Do NOT regenerate goldens blindly (Constitution IV). See [[verify-subagent-committed-state]] — confirm committed git state, don't trust a self-report.
- [ ] **Step 4: Confirm success criteria**
  - SC-001/SC-005 → Task 6 equivalence test green + goldens unchanged.
  - SC-002 → add/confirm a group-footer equivalence in the engine test (inline `SUM` in a footer == a `resetScope: group` variable). (If not already covered by Task 4, add it here.)
  - SC-003 → Task 2 round-trip test green.
  - SC-004 → Task 5 diagnostics green; manually confirm a nested-field `{SUM([lineTotal])}` in the playground summary surfaces an unresolved-field diagnostic (not a wrong number).
- [ ] **Step 5: Manual GUI smoke (optional)** — in the playground, select the Summary value element; confirm it shows `{SUM([customerTotal])}`, edit to `{AVG([customerTotal])}`, Preview, and verify the value changes. (Mirrors prior specs' manual-walk step.)

---

## Self-Review

- **Spec coverage:** FR-001 → Task 2 Step 3a. FR-002 → Task 2 Step 3b. FR-003 → Task 3. FR-004 → Task 4 Step 3. FR-005 → Task 1 (`topLevelAggregate` single-arg rule) + Task 5 (band rule). FR-006 → Task 1 (`aggregate_functions.dart` single source, fwd+inverse). FR-007 → Task 5. FR-008 → Task 5 NOTE (fill-time unresolved-field diagnostic). FR-009 → Task 3 (`__agg<n>` internal names; stored form stays `FN(...)`, reverse-shown as sugar). US1/US2 → Task 4. US3 → Task 2 expression-arg tests. US4 → Task 2 round-trip. US5 → Task 5. SC-001/SC-005 → Task 6 equivalence + Task 7 golden gate. SC-002 → Task 7 Step 4. SC-003 → Task 2. SC-004 → Task 5.
- **Placeholder scan:** none — every task has concrete code or an exact command + expected outcome.
- **Key risks called out:** (1) `TextElement.copyWith` cannot set `expression` → the synthesizer/compiler rebuild via the constructor (Task 3 `_maybeRewrite`). (2) No unparse API → the synthesizer uses **string-slice** for the variable expression (robust) and the reverse-compiler has a **bounded** arg renderer with a verbatim fallback (Task 2). (3) `validate()` has no schema → nested-field guard is the existing fill-time diagnostic, documented, not silently dropped. (4) `MIN`/`MAX` scalar-function collision → resolved by single-arg + supported-band rule (FR-005).
- **No new exports / no schema-version bump:** stored form is an ordinary expression string; synthesized variables are transient. Constitution V/IV intact.
