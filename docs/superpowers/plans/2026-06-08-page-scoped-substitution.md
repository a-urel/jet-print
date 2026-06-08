# Page-scoped late substitution — Spec 008c Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. If those skills are unavailable in your workspace, the tasks below are self-contained — each is a TDD sequence with complete code, exact commands, and a commit — and can be executed directly, in order.

**Goal:** Evaluate page-scoped expressions (`$V{PAGE_NUMBER}`, `$V{PAGE_COUNT}`, `$P{params}`) in `pageHeader`/`pageFooter` text at layout time, substituting the result at the authored bounds — finishing the post-pagination chrome seam 008a left open.

**Architecture:** Add a static AST reference-collector to the expression seam (`Expression.references`). Carry report parameters into the Fill→Layout IR as a normalized `FilledReport.params` (`Map<String, JetValue>`). In the layouter, a once-per-element compile-and-classify pre-pass parses each chrome text expression, classifies its references (page var / param / field / non-page var) and emits structural diagnostics; a page-aware post-pass evaluates the cached expression per page against a `PageEvalContext` and substitutes the text. Page vars resolve to `JetString` (the all-double model renders a number as `1.0`). Fixed-bounds: no repagination, no chrome box growth.

**Tech Stack:** Dart (pub workspace monorepo), Flutter test harness. Expression seam (+1 read-only API) + `rendering/fill/` (+1 IR field) + `rendering/layout/` (the substitution). Value-type IR with deep equality; TDD with `flutter test`; `PageFrame` data goldens.

**Spec:** `docs/superpowers/specs/2026-06-08-page-scoped-substitution-design.md`.

**Conventions for every task:**
- Run all `flutter` commands from `packages/jet_print/`. Test form: `flutter test test/<path> -r expanded`.
- Run all `git` commands from the repo root `/Users/ahmeturel/Projects/oss/jet-print` (the shell cwd drifts into the package after a `flutter` command — always `cd /Users/ahmeturel/Projects/oss/jet-print` before `git`).
- After each task `flutter analyze` must print `No issues found!` (the analyzer promotes `unused_import`/`unused_local_variable`/`unused_element`/`unused_field`/`dead_code` to **errors**; explicit types are used throughout — keep them; relative imports are ordered `dart:` → `package:` → relative, each group alphabetized by import string).
- Test files use white-box `package:jet_print/src/...` imports.
- New `src/` types are **not** exported from `jet_print.dart` (the public surface is the 011 facade).
- **Schema is NOT bumped** — `FilledReport.params` is internal IR (no `toJson`); consistent with the 008b pre-1.0 additive carve-out.
- Commit messages end with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (omitted below for brevity).
- Branch is already `008c-page-scoped-substitution`.

---

## File Structure

**Modify (`expression/`):**
- `lib/src/expression/expression.dart` — add the read-only `references` getter (AST walk).

**Modify (`rendering/fill/`):**
- `lib/src/rendering/fill/filled_report.dart` — add `FilledReport.params` (`Map<String, JetValue>`).
- `lib/src/rendering/fill/report_filler.dart` — normalize the received `params` into the `FilledReport`.

**Create (`rendering/layout/`):**
- `lib/src/rendering/layout/page_eval_context.dart` — `PageEvalContext`.

**Modify (`rendering/layout/`):**
- `lib/src/rendering/layout/report_layouter.dart` — `JetFunctionRegistry` dependency; compile-and-classify pre-pass; page-aware substitution post-pass; doc comment + imports.

**Tests:**
- `test/expression/expression_references_test.dart` (create).
- `test/rendering/fill/filled_report_test.dart` (extend) — `FilledReport.params`.
- `test/rendering/fill/report_filler_test.dart` (extend) — param normalization.
- `test/rendering/layout/page_eval_context_test.dart` (create).
- `test/rendering/layout/report_layouter_test.dart` (extend + rewrite the 2 chrome tests).
- `test/architecture/layer_boundaries_test.dart` (modify) — relax the layout/expression rule.
- `CHANGELOG.md`.

---

## Task 1: `Expression.references` — static AST reference-collector

**Files:**
- Modify: `lib/src/expression/expression.dart`
- Test: `test/expression/expression_references_test.dart`

Context: The evaluator short-circuits (`?:` walks only the taken branch; `&&`/`||` skip the right side), so evaluating an expression to discover its references is unreliable. A static walk over the sealed `Expr` AST visits every branch/operand/argument and treats string literals as literals (`LiteralExpr`), so it is complete and string-safe.

- [ ] **Step 1: Write the failing test**

Create `test/expression/expression_references_test.dart`:

```dart
// Expression.references: complete, branch-independent reference analysis (008c).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression.dart';

void main() {
  group('Expression.references', () {
    test('collects field, param, and variable references by kind', () {
      final ({Set<String> fields, Set<String> params, Set<String> variables})
          refs = Expression.parse(r'$F{a} + $P{b} + $V{c}').references;
      expect(refs.fields, <String>{'a'});
      expect(refs.params, <String>{'b'});
      expect(refs.variables, <String>{'c'});
    });

    test('walks ALL branches of a conditional (not just the taken one)', () {
      final ({Set<String> fields, Set<String> params, Set<String> variables})
          refs = Expression.parse(r'$V{PAGE_NUMBER} == "1" ? $F{x} : $P{y}')
              .references;
      expect(refs.fields, <String>{'x'});
      expect(refs.params, <String>{'y'});
      expect(refs.variables, <String>{'PAGE_NUMBER'});
    });

    test('walks the short-circuited side of &&', () {
      // `false && $F{x}` never evaluates the RHS at runtime; static analysis
      // still sees the field reference.
      final ({Set<String> fields, Set<String> params, Set<String> variables})
          refs = Expression.parse(r'false && $F{x}').references;
      expect(refs.fields, <String>{'x'});
    });

    test('walks function-call arguments', () {
      final ({Set<String> fields, Set<String> params, Set<String> variables})
          refs = Expression.parse(r'CONCAT($F{a}, $P{b})').references;
      expect(refs.fields, <String>{'a'});
      expect(refs.params, <String>{'b'});
    });

    test('ignores sigil-like text inside a string literal', () {
      final ({Set<String> fields, Set<String> params, Set<String> variables})
          refs = Expression.parse(r"'a $F{x} literal'").references;
      expect(refs.fields, isEmpty);
      expect(refs.params, isEmpty);
      expect(refs.variables, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/expression/expression_references_test.dart -r expanded`
Expected: FAIL — `Expression` has no `references` getter.

- [ ] **Step 3: Add the `references` getter**

In `lib/src/expression/expression.dart`, add this getter inside `class Expression` (after `evaluate`). The `Expr` AST node types are already imported via `import 'ast.dart';`:

```dart
  /// The references this expression makes, grouped by kind (`$F{}` fields,
  /// `$P{}` params, `$V{}` variables). Walks the whole AST — every branch,
  /// operand, and argument — so it is complete and independent of runtime
  /// short-circuiting (unlike evaluation). Text inside a string literal is not a
  /// reference. Used by Layout to validate page-scoped chrome expressions (008c).
  ({Set<String> fields, Set<String> params, Set<String> variables})
      get references {
    final Set<String> fields = <String>{};
    final Set<String> params = <String>{};
    final Set<String> variables = <String>{};
    void walk(Expr node) {
      switch (node) {
        case LiteralExpr():
          break;
        case FieldRefExpr(name: final String n):
          fields.add(n);
        case ParamRefExpr(name: final String n):
          params.add(n);
        case VariableRefExpr(name: final String n):
          variables.add(n);
        case UnaryExpr(operand: final Expr o):
          walk(o);
        case BinaryExpr(left: final Expr l, right: final Expr r):
          walk(l);
          walk(r);
        case ConditionalExpr(
            condition: final Expr c,
            thenBranch: final Expr t,
            elseBranch: final Expr e
          ):
          walk(c);
          walk(t);
          walk(e);
        case CallExpr(arguments: final List<Expr> args):
          for (final Expr a in args) {
            walk(a);
          }
      }
    }

    walk(_root);
    return (fields: fields, params: params, variables: variables);
  }
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/expression/expression_references_test.dart -r expanded && flutter analyze`
Expected: PASS (5 tests); `No issues found!`. (The `switch` over the sealed `Expr` is exhaustive — all 8 node types — so no `default` is needed and the analyzer accepts it.)

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/expression/expression.dart \
  packages/jet_print/test/expression/expression_references_test.dart
git commit -m "feat(expression): Expression.references static reference analysis (008c)"
```

---

## Task 2: `FilledReport.params` + Fill normalization

**Files:**
- Modify: `lib/src/rendering/fill/filled_report.dart`
- Modify: `lib/src/rendering/fill/report_filler.dart`
- Test: `test/rendering/fill/filled_report_test.dart`
- Test: `test/rendering/fill/report_filler_test.dart`

Context: `FilledReport` is the internal Fill→Layout IR (no `toJson`). It is a value-equal snapshot, so params are stored **normalized** as `Map<String, JetValue>` (raw `Object?` would compare by identity and hash unstably). `JetValue.from` maps unsupported types to a stable `JetError` value (never throws). `ReportFiller` already receives `params` at `fill()`; body resolution keeps using the raw map — only the IR snapshot is normalized.

- [ ] **Step 1: Write the failing tests**

In `test/rendering/fill/filled_report_test.dart`, add these tests inside `main()` (after the existing FilledReport tests). Confirm `PageFormat` and `JetString` are imported (the file already imports `filled_report.dart`, `page_format.dart`, and `value.dart` from the 007b/008b tests — add any that is missing):

```dart
  test('FilledReport.params participates in equality and hashCode', () {
    FilledReport report(Map<String, JetValue> params) => FilledReport(
        page: PageFormat.a4Portrait,
        bands: const <FilledBand>[],
        params: params);
    expect(report(<String, JetValue>{'x': const JetString('a')}),
        report(<String, JetValue>{'x': const JetString('a')}));
    expect(report(<String, JetValue>{'x': const JetString('a')}).hashCode,
        report(<String, JetValue>{'x': const JetString('a')}).hashCode);
    expect(
        report(<String, JetValue>{'x': const JetString('a')}) ==
            report(<String, JetValue>{'x': const JetString('b')}),
        isFalse);
  });

  test('FilledReport.params defaults to empty', () {
    final FilledReport r =
        FilledReport(page: PageFormat.a4Portrait, bands: const <FilledBand>[]);
    expect(r.params, isEmpty);
  });

  test('FilledReport.params equality and hash are insertion-order-independent',
      () {
    FilledReport report(Map<String, JetValue> params) => FilledReport(
        page: PageFormat.a4Portrait,
        bands: const <FilledBand>[],
        params: params);
    final FilledReport a = report(<String, JetValue>{
      'a': const JetString('1'),
      'b': const JetString('2'),
    });
    final FilledReport b = report(<String, JetValue>{
      'b': const JetString('2'),
      'a': const JetString('1'),
    });
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('FilledReport freezes its params map', () {
    final FilledReport r = FilledReport(
        page: PageFormat.a4Portrait,
        bands: const <FilledBand>[],
        params: <String, JetValue>{'x': const JetString('a')});
    expect(() => r.params['y'] = const JetString('b'), throwsUnsupportedError);
  });
```

In `test/rendering/fill/report_filler_test.dart`, add this test inside `main()` (the file already has the `t` helper, `JetInMemoryDataSource`/`ReportFiller`, and imports `filled_report.dart` + `value.dart` from 008b — add `JetNumber`/`JetString` usage; they come from `value.dart`):

```dart
  test('fill normalizes params into FilledReport.params (JetValue; stable)', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
      ],
    );
    FillResult run() => ReportFiller().fill(
          tpl,
          JetInMemoryDataSource(<Map<String, Object?>>[<String, Object?>{}]),
          params: <String, Object?>{'n': 3, 's': 'hi', 'bad': <int>[1, 2]},
        );
    final FilledReport a = run().report;
    expect(a.params['n'], const JetNumber(3));
    expect(a.params['s'], const JetString('hi'));
    expect(a.params['bad'], isA<JetError>()); // unsupported type -> stable error
    expect(a, run().report); // normalization is stable -> two fills compare equal
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/rendering/fill/filled_report_test.dart test/rendering/fill/report_filler_test.dart -r expanded`
Expected: FAIL — `FilledReport` has no `params` parameter.

- [ ] **Step 3: Add `FilledReport.params`**

In `lib/src/rendering/fill/filled_report.dart`, update `class FilledReport`. Constructor (add `params` after `bands`):

```dart
  /// Creates a filled report.
  FilledReport({
    required this.page,
    required List<FilledBand> bands,
    Map<String, JetValue> params = const <String, JetValue>{},
  })  : bands = List<FilledBand>.unmodifiable(bands),
        params = Map<String, JetValue>.unmodifiable(params);
```

Add the field after `bands`:

```dart
  /// The report parameters in effect for this fill, normalized to [JetValue]
  /// (008c). Carried so Layout can resolve `$P{}` in page chrome. Not persisted —
  /// this is the internal IR.
  final Map<String, JetValue> params;
```

Update `==` (add the params comparison — reuse the existing `_mapEquals`):

```dart
  @override
  bool operator ==(Object other) =>
      other is FilledReport &&
      other.page == page &&
      _listEquals(other.bands, bands) &&
      _mapEquals(other.params, params);
```

Update `hashCode` (add an order-independent params hash, matching `FilledBand`):

```dart
  @override
  int get hashCode {
    final int paramsHash = Object.hashAllUnordered(
      <int>[
        for (final MapEntry<String, JetValue> e in params.entries)
          Object.hash(e.key, e.value),
      ],
    );
    return Object.hash(page, Object.hashAll(bands), paramsHash);
  }
```

(`_mapEquals` is already defined in this file with the `Map<String, JetValue>` signature — no change needed.)

- [ ] **Step 4: Normalize params in Fill**

In `lib/src/rendering/fill/report_filler.dart`, at the `FilledReport(...)` construction (currently `report: FilledReport(page: template.page, bands: bands),`), pass the normalized params:

```dart
      report: FilledReport(
        page: template.page,
        bands: bands,
        params: <String, JetValue>{
          for (final MapEntry<String, Object?> e in params.entries)
            e.key: JetValue.from(e.value),
        },
      ),
```

(`params` is the `fill()` argument already in scope; `JetValue` is already imported via `'../../expression/value.dart'`.)

- [ ] **Step 5: Run the tests + analyzer**

Run: `flutter test test/rendering/fill/ -r expanded && flutter analyze`
Expected: the new tests PASS; all existing 007b/007c/008b filler tests still PASS (the no-params path defaults to an empty map; existing `FilledReport` equality holds); `No issues found!`.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill/filled_report.dart \
  packages/jet_print/lib/src/rendering/fill/report_filler.dart \
  packages/jet_print/test/rendering/fill/filled_report_test.dart \
  packages/jet_print/test/rendering/fill/report_filler_test.dart
git commit -m "feat(fill): normalized FilledReport.params IR field (008c)"
```

---

## Task 3: `PageEvalContext` — page-scoped value resolver

**Files:**
- Create: `lib/src/rendering/layout/page_eval_context.dart`
- Test: `test/rendering/layout/page_eval_context_test.dart`

Context: A pure value resolver implementing `EvalContext`. `PAGE_NUMBER`/`PAGE_COUNT` resolve to `JetString` of the integer (the all-double model would render a `JetNumber` as `1.0`, and `+` won't mix a string literal with a number — see spec §4). `$P{}` resolves from the normalized params; `$F{}` and non-page `$V{}` resolve to `JetNull`. No diagnostic sinks — diagnostics come from the layouter's static pre-pass.

- [ ] **Step 1: Write the failing test**

Create `test/rendering/layout/page_eval_context_test.dart`:

```dart
// PageEvalContext: page-scoped value resolution for chrome substitution (008c).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/layout/page_eval_context.dart';

void main() {
  group('PageEvalContext', () {
    PageEvalContext ctx({
      int pageNumber = 1,
      int pageCount = 1,
      Map<String, JetValue> params = const <String, JetValue>{},
    }) =>
        PageEvalContext(
          pageNumber: pageNumber,
          pageCount: pageCount,
          params: params,
          functions: JetFunctionRegistry(),
        );

    test('PAGE_NUMBER and PAGE_COUNT resolve as integer strings', () {
      final EvalContext c = ctx(pageNumber: 2, pageCount: 5);
      expect(c.resolveVariable('PAGE_NUMBER'), const JetString('2'));
      expect(c.resolveVariable('PAGE_COUNT'), const JetString('5'));
    });

    test('a non-page variable resolves to null', () {
      expect(ctx().resolveVariable('total'), const JetNull());
    });

    test('params resolve from the map; an absent param is null', () {
      final EvalContext c =
          ctx(params: <String, JetValue>{'title': const JetString('Q1')});
      expect(c.resolveParam('title'), const JetString('Q1'));
      expect(c.resolveParam('missing'), const JetNull());
    });

    test('fields resolve to null (no data row at page scope)', () {
      expect(ctx().resolveField('anything'), const JetNull());
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/layout/page_eval_context_test.dart -r expanded`
Expected: FAIL — `page_eval_context.dart` does not exist.

- [ ] **Step 3: Create `PageEvalContext`**

Create `lib/src/rendering/layout/page_eval_context.dart`:

```dart
/// The page-scoped [EvalContext] (spec 008c): resolves `PAGE_NUMBER`/`PAGE_COUNT`
/// and report `$P{}` parameters for page-chrome text substitution. Pure value
/// resolution — diagnostics are surfaced by the layouter's static pre-pass.
library;

import '../../expression/eval_context.dart';
import '../../expression/function_registry.dart';
import '../../expression/value.dart';

/// An [EvalContext] over a single page's number/count and the report params.
class PageEvalContext implements EvalContext {
  /// Creates a context for page [pageNumber] of [pageCount], with normalized
  /// [params] and the function [functions] registry.
  PageEvalContext({
    required int pageNumber,
    required int pageCount,
    required Map<String, JetValue> params,
    required JetFunctionRegistry functions,
  })  : _pageNumber = pageNumber,
        _pageCount = pageCount,
        _params = params,
        _functions = functions;

  final int _pageNumber;
  final int _pageCount;
  final Map<String, JetValue> _params;
  final JetFunctionRegistry _functions;

  @override
  JetFunctionRegistry get functions => _functions;

  @override
  JetValue resolveField(String name) => const JetNull();

  @override
  JetValue resolveParam(String name) => _params[name] ?? const JetNull();

  @override
  JetValue resolveVariable(String name) {
    // The two page-scoped variable names (kPageScopedVariables, spec 007b §2).
    // Resolved as strings: the engine is all-double, so a JetNumber would render
    // "1.0", and `+` will not concatenate a string literal with a number (008c §4).
    if (name == 'PAGE_NUMBER') return JetString('$_pageNumber');
    if (name == 'PAGE_COUNT') return JetString('$_pageCount');
    return const JetNull();
  }
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/rendering/layout/page_eval_context_test.dart -r expanded && flutter analyze`
Expected: PASS (4 tests); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/layout/page_eval_context.dart \
  packages/jet_print/test/rendering/layout/page_eval_context_test.dart
git commit -m "feat(layout): PageEvalContext page-scoped value resolver (008c)"
```

---

## Task 4: Layouter substitution + layer-boundary relaxation

**Files:**
- Modify: `lib/src/rendering/layout/report_layouter.dart`
- Modify: `test/architecture/layer_boundaries_test.dart`
- Test: `test/rendering/layout/report_layouter_test.dart`

Context: The layouter gains a `JetFunctionRegistry` (default built-ins, mirroring `ReportFiller`). The 008a chrome unresolved-binding scan becomes a **compile-and-classify pre-pass** (parse each chrome text expression once, cache it, emit structural diagnostics once per element via `Expression.references`; the image "not embedded" info stays). The chrome post-pass becomes **page-aware**: chrome `TextElement`s are evaluated per page through a `PageEvalContext` and substituted at the authored bounds. Render follows null-propagation (bare unavailable ref → blank, in-operation → `'!ERR'`). Runtime `JetError`s are reported coarsely (deduped per `(element, message)`) and suppressed for an element that already has a structural diagnostic. Because layout now imports the expression engine, the layer-boundary test is relaxed (kept Flutter-free).

- [ ] **Step 1: Add the failing tests**

In `test/rendering/layout/report_layouter_test.dart`, add two imports near the others (needed for the injected-registry test below). Everything else is already imported by the existing 008a/008b test file — `value.dart` (`JetString`/`JetValue`), `primitive.dart` (`TextRunPrimitive`/`RectPrimitive`), `text_measurer.dart` (`TextLine`), `page_frame.dart` (`PageFrame`), `report_diagnostics.dart` (`Diagnostic`/`DiagnosticSeverity`), and `filled_report.dart` (`FilledReport`/`FilledBand`):

```dart
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
```

Add these helpers just below the existing `_filled` helper (top of the file, in the helper region):

```dart
// A page-chrome band carrying one text element with an optional expression.
ReportBand _chromeText(BandType type, String id, String expression,
        {double height = 20}) =>
    ReportBand(type: type, height: height, elements: <ReportElement>[
      TextElement(
        id: id,
        bounds: JetRect(x: 0, y: 0, width: 180, height: height),
        text: '',
        expression: expression,
      ),
    ]);

// The rendered text of the chrome TextRunPrimitive with [id] on [page].
String _chromeRun(PageFrame page, String id) => page.primitives
    .whereType<TextRunPrimitive>()
    .firstWhere((TextRunPrimitive p) => p.elementId == id)
    .lines
    .map((TextLine l) => l.text)
    .join();
```

Add these tests inside `main()` (after the existing 008a/008b tests):

```dart
  test('Page N of M substitutes the page number and count per page', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn',
          r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}'),
    ]);
    // footer 20 -> bodyTop=10 bodyBottom=70 capacity=60; one body(40) per page.
    final LayoutResult r = ReportLayouter()
        .layout(tpl, _filled(<FilledBand>[_body(40), _body(40), _body(40)]));
    expect(r.pages.length, 3);
    expect(_chromeRun(r.pages[0], 'pn'), 'Page 1 of 3');
    expect(_chromeRun(r.pages[1], 'pn'), 'Page 2 of 3');
    expect(_chromeRun(r.pages[2], 'pn'), 'Page 3 of 3');
  });

  test('a bare PAGE_NUMBER renders an integer, not 1.0', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'$V{PAGE_NUMBER}'),
    ]);
    final LayoutResult r = ReportLayouter()
        .layout(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(r.pages.length, 2);
    expect(_chromeRun(r.pages[0], 'pn'), '1');
    expect(_chromeRun(r.pages[1], 'pn'), '2');
  });

  test('first/last-page conditions work via string equality', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn',
          r'$V{PAGE_NUMBER} == "1" ? "FIRST" : ($V{PAGE_NUMBER} == $V{PAGE_COUNT} ? "LAST" : "MID")'),
    ]);
    final LayoutResult r = ReportLayouter()
        .layout(tpl, _filled(<FilledBand>[_body(40), _body(40), _body(40)]));
    expect(_chromeRun(r.pages[0], 'pn'), 'FIRST');
    expect(_chromeRun(r.pages[1], 'pn'), 'MID');
    expect(_chromeRun(r.pages[2], 'pn'), 'LAST');
  });

  test('a chrome param resolves from FilledReport.params', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'$P{title}'),
    ]);
    final FilledReport filled = FilledReport(
        page: _smallPage,
        bands: <FilledBand>[_body(20)],
        params: <String, JetValue>{'title': const JetString('Q1 Report')});
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 1);
    expect(_chromeRun(r.pages[0], 'pn'), 'Q1 Report');
  });

  test('substitution is fixed-bounds: long text does not add a page', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn',
          r'"this is a very long footer that wraps well beyond the box " + $V{PAGE_NUMBER}'),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(r.pages.length, 1); // wrapped text never repaginates the chrome
  });

  test('a chrome parse error renders !ERR and one error diagnostic', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'$V{PAGE_NUMBER} +'),
    ]);
    final LayoutResult r = ReportLayouter()
        .layout(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(r.pages.length, 2);
    expect(_chromeRun(r.pages[0], 'pn'), '!ERR');
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) =>
                d.severity == DiagnosticSeverity.error && d.elementId == 'pn')
            .length,
        1); // once, not once per page
  });

  test('an unavailable field hidden in an untaken branch still warns once', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn',
          r'$V{PAGE_NUMBER} == "9" ? $F{x} : "ok"'),
    ]);
    final LayoutResult r = ReportLayouter()
        .layout(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(_chromeRun(r.pages[0], 'pn'), 'ok'); // condition false on every page
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) =>
                d.severity == DiagnosticSeverity.warning && d.elementId == 'pn')
            .length,
        1); // static analysis sees $F{x} despite the branch never being taken
  });

  test('a bare unavailable field renders blank; in an operation renders !ERR',
      () {
    final ReportTemplate bare = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'$F{x}'),
    ]);
    final LayoutResult rb =
        ReportLayouter().layout(bare, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(rb.pages[0], 'pn'), ''); // JetNull -> blank
    expect(
        rb.diagnostics.entries
            .where((Diagnostic d) => d.elementId == 'pn')
            .length,
        1); // one structural warning, no extra runtime error

    final ReportTemplate inOp = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'"a" + $F{x}'),
    ]);
    final LayoutResult ro =
        ReportLayouter().layout(inOp, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(ro.pages[0], 'pn'), '!ERR'); // JetNull poisons "+" -> JetError
    expect(
        ro.diagnostics.entries
            .where((Diagnostic d) => d.elementId == 'pn')
            .length,
        1); // structural warning only; runtime error suppressed (already flagged)
  });

  test('an absent param renders blank with no diagnostic', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'$P{missing}'),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages[0], 'pn'), '');
    expect(r.diagnostics.entries.where((Diagnostic d) => d.elementId == 'pn'),
        isEmpty);
  });

  test('page-scoped substitution is deterministic', () {
    ReportTemplate tpl() => _tpl(bands: <ReportBand>[
          _chromeText(BandType.pageFooter, 'pn',
              r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}'),
        ]);
    FilledReport filled() => _filled(<FilledBand>[_body(40), _body(40)]);
    final LayoutResult a = ReportLayouter().layout(tpl(), filled());
    final LayoutResult b = ReportLayouter().layout(tpl(), filled());
    expect(a.pages, b.pages);
    List<(DiagnosticSeverity, String, String?)> proj(LayoutResult r) => r
        .diagnostics.entries
        .map((Diagnostic d) => (d.severity, d.message, d.elementId))
        .toList();
    expect(proj(a), proj(b));
  });

  test('a chrome function (CONCAT) evaluates through the registry', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'CONCAT("Page ", $V{PAGE_NUMBER})'),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages[0], 'pn'), 'Page 1'); // built-in via default registry
  });

  test('an injected function registry is used for chrome evaluation', () {
    // STARS is not a built-in: it can only resolve via the injected registry,
    // proving constructor injection + PageEvalContext.functions are wired.
    final JetFunctionRegistry functions = JetFunctionRegistry()
      ..register('STARS',
          (List<JetValue> args, EvalContext ctx) => const JetString('***'));
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'STARS($V{PAGE_NUMBER})'),
    ]);
    final LayoutResult r = ReportLayouter(functions: functions)
        .layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages[0], 'pn'), '***');
  });

  test('a bare non-page variable warns once and renders blank', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'$V{total}'),
    ]);
    final LayoutResult r = ReportLayouter()
        .layout(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(r.pages.length, 2);
    expect(_chromeRun(r.pages[0], 'pn'), ''); // non-page var -> JetNull -> blank
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) =>
                d.severity == DiagnosticSeverity.warning && d.elementId == 'pn')
            .length,
        1); // once at the pre-pass, NOT once per page
  });

  test('a non-page variable consumed by an operator renders !ERR', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageFooter, 'pn', r'"x" + $V{total}'),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages[0], 'pn'), '!ERR'); // JetNull poisons "+" -> JetError
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) => d.elementId == 'pn')
            .length,
        1); // structural warning only; runtime error suppressed (already flagged)
  });
```

Now **rewrite** the two existing 008a chrome tests in this file (they assert the removed "not evaluated" info). Replace the test `'a chrome text expression renders its literal + an info diagnostic'` with:

```dart
  test('a chrome text expression is evaluated (no "not evaluated" info)', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageHeader, 'pn', r'$V{PAGE_NUMBER}'),
    ]);
    final LayoutResult r =
        ReportLayouter().layout(tpl, _filled(<FilledBand>[_body(20)]));
    expect(_chromeRun(r.pages.single, 'pn'), '1'); // evaluated, not the literal
    expect(r.diagnostics.entries.where((Diagnostic d) => d.elementId == 'pn'),
        isEmpty); // PAGE_NUMBER resolves cleanly -> no diagnostic
  });
```

Replace the test `'a chrome binding is diagnosed once, not once per page'` with (it now uses an illegal `$F{}`, which actually warns — an absent `$P{}` would be silent):

```dart
  test('a chrome binding is diagnosed once, not once per page', () {
    final ReportTemplate tpl = _tpl(bands: <ReportBand>[
      _chromeText(BandType.pageHeader, 'pn', r'$F{x}'),
    ]);
    // header 20 -> bodyTop=30 bodyBottom=90 capacity=60; bodies 40+40 -> 2 pages.
    final LayoutResult r = ReportLayouter()
        .layout(tpl, _filled(<FilledBand>[_body(40), _body(40)]));
    expect(r.pages.length, 2);
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) =>
                d.severity == DiagnosticSeverity.warning && d.elementId == 'pn')
            .length,
        1); // once at the pre-pass, NOT once per page
  });
```

(Keep the existing `'an unresolved chrome image renders a placeholder + an info diagnostic'` test as-is — chrome images are out of 008c scope.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/rendering/layout/report_layouter_test.dart -r expanded`
Expected: FAIL — substitution is not implemented; the two rewritten tests fail against the old "literal + info" behavior.

- [ ] **Step 3: Update the layouter**

In `lib/src/rendering/layout/report_layouter.dart`:

**(3a)** Replace the library doc comment (lines 1-5) — drop the "no expression engine" clause:

```dart
/// The Layout engine (spec 008a/008c): places a resolved [FilledReport] band
/// stream onto pages with repeating page chrome, producing one [PageFrame] per
/// page. Geometry plus page-scoped chrome substitution (008c — `PAGE_NUMBER`/
/// `PAGE_COUNT`/params); no image byte-resolution. INTERNAL; the public surface
/// is the 011 JetReportEngine.
library;
```

**(3b)** Add these imports (keep the relative group alphabetized — `flutter analyze` enforces ordering; `../../expression/...` sorts after `../../domain/...`, `../fill/page_variables.dart` sorts within the `../fill/` group, `page_eval_context.dart` within the same-directory group):

```dart
import '../../expression/expression.dart';
import '../../expression/expression_exception.dart';
import '../../expression/function_registry.dart';
import '../../expression/functions/built_in_functions.dart';
import '../../expression/value.dart';
import '../fill/page_variables.dart';
import 'page_eval_context.dart';
```

**(3c)** Add the `JetFunctionRegistry` dependency to the constructor and fields (alongside `_renderers`/`_measurer`):

```dart
  ReportLayouter({
    ElementRendererRegistry? renderers,
    TextMeasurer? measurer,
    JetFunctionRegistry? functions,
  })  : _renderers = renderers ?? _defaultRenderers(),
        _measurer =
            measurer ?? MetricsTextMeasurer(FontRegistry()..registerDefault()),
        _functions = functions ?? _defaultFunctions();

  final ElementRendererRegistry _renderers;
  final TextMeasurer _measurer;
  final JetFunctionRegistry _functions;
```

And add this static beside `_defaultRenderers` (mirrors `ReportFiller._defaultFunctions`):

```dart
  static JetFunctionRegistry _defaultFunctions() {
    final JetFunctionRegistry r = JetFunctionRegistry();
    registerBuiltInFunctions(r);
    return r;
  }
```

**(3d)** Replace the 008a chrome scan block (the `for (final ReportBand band in <ReportBand>[...headers, ...footers])` loop that emits the `'... was not evaluated in the static layout pass'` info and the image info) with the compile-and-classify pre-pass:

```dart
    // Compile-and-classify chrome text expressions ONCE (008c §5). Parsing and
    // static reference analysis surface page-independent diagnostics here; the
    // post-pass evaluates per page. Images keep the 008a placeholder info.
    final Map<String, Expression> chromeExprs = <String, Expression>{};
    final Set<String> chromeParseFailed = <String>{};
    final Set<String> chromeFlagged = <String>{};
    for (final ReportBand band in <ReportBand>[...headers, ...footers]) {
      for (final ReportElement el in band.elements) {
        if (el is TextElement && el.expression != null) {
          final Expression expr;
          try {
            expr = Expression.parse(el.expression!);
          } on ExpressionException catch (e) {
            diagnostics.error(
                'chrome text on "${el.id}" failed to parse: ${e.message}',
                elementId: el.id);
            chromeParseFailed.add(el.id);
            chromeFlagged.add(el.id);
            continue;
          }
          chromeExprs[el.id] = expr;
          final ({Set<String> fields, Set<String> params, Set<String> variables})
              refs = expr.references;
          if (refs.fields.isNotEmpty) {
            diagnostics.warning(
                'chrome text on "${el.id}" references field(s) '
                '${(refs.fields.toList()..sort()).join(', ')}, which have no '
                'data row at page scope',
                elementId: el.id);
            chromeFlagged.add(el.id);
          }
          final List<String> nonPageVars = refs.variables
              .where((String v) => !kPageScopedVariables.contains(v))
              .toList()
            ..sort();
          if (nonPageVars.isNotEmpty) {
            diagnostics.warning(
                'chrome text on "${el.id}" references non-page variable(s) '
                '${nonPageVars.join(', ')}, unavailable at page scope',
                elementId: el.id);
            chromeFlagged.add(el.id);
          }
        } else if (el is ImageElement && el.source is! BytesImageSource) {
          diagnostics.info(
              'chrome image on "${el.id}" is not embedded; renders a placeholder',
              elementId: el.id);
        }
      }
    }
```

**(3e)** Replace the chrome post-pass (the `for (final FrameBuilder fb in pages)` loop near the end that calls `place(_authoredBoxes(h), y, fb)`) with the page-aware substitution. First, just above that loop, add the substitution closure + runtime-dedup set:

```dart
    // Per-page chrome substitution (008c). Render follows null-propagation:
    // a bare unavailable ref is JetNull -> blank; consumed by an operator/
    // function it poisons to JetError -> '!ERR' (jetStringify of JetError).
    final Set<String> runtimeDiagnosed = <String>{};
    ReportElement substitute(ReportElement el, int pageNumber, int pageCount) {
      if (el is! TextElement || el.expression == null) return el;
      if (chromeParseFailed.contains(el.id)) {
        return TextElement(
            id: el.id, bounds: el.bounds, text: '!ERR', style: el.style);
      }
      final Expression? expr = chromeExprs[el.id];
      if (expr == null) {
        // Unreachable: the pre-pass files every chrome text expression under
        // chromeExprs or chromeParseFailed. Surface a pre/post-pass drift loudly
        // (visible '!ERR' + diagnostic) instead of silently rendering authored text.
        diagnostics.error(
            'internal: no compiled chrome expression for "${el.id}"',
            elementId: el.id);
        return TextElement(
            id: el.id, bounds: el.bounds, text: '!ERR', style: el.style);
      }
      final JetValue value = expr.evaluate(PageEvalContext(
        pageNumber: pageNumber,
        pageCount: pageCount,
        params: filled.params,
        functions: _functions,
      ));
      if (value is JetError && !chromeFlagged.contains(el.id)) {
        if (runtimeDiagnosed.add('${el.id} ${value.message}')) {
          diagnostics.error(
              'chrome text on "${el.id}" failed to evaluate: ${value.message}',
              elementId: el.id);
        }
      }
      return TextElement(
          id: el.id,
          bounds: el.bounds,
          text: jetStringify(value),
          style: el.style);
    }
```

Then the post-pass loop itself:

```dart
    final int pageCount = pages.length;
    for (int p = 0; p < pages.length; p++) {
      final FrameBuilder fb = pages[p];
      final int pageNumber = p + 1;
      double y = top;
      for (final ReportBand h in headers) {
        place(<({ReportElement element, JetRect bounds})>[
          for (final ReportElement el in h.elements)
            (element: substitute(el, pageNumber, pageCount), bounds: el.bounds),
        ], y, fb);
        y += h.height;
      }
      y = bodyBottom;
      for (final ReportBand f in footers) {
        place(<({ReportElement element, JetRect bounds})>[
          for (final ReportElement el in f.elements)
            (element: substitute(el, pageNumber, pageCount), bounds: el.bounds),
        ], y, fb);
        y += f.height;
      }
    }
```

**(3f)** Remove the now-unused `_authoredBoxes` helper method (the `List<({ReportElement element, JetRect bounds})> _authoredBoxes(ReportBand band) => ...` at the bottom of the class) — the substitution loop above replaces it. Leaving it would be an `unused_element` analyzer error.

- [ ] **Step 4: Relax the layer-boundary test**

In `test/architecture/layer_boundaries_test.dart`, replace the test `'the layout/ seam exists, stays Flutter-free, and imports no expression engine'` (the whole `test('the layout/ seam exists, stays Flutter-free, and imports no ' 'expression engine', () { ... });` block) with:

```dart
    test('the layout/ seam exists and stays Flutter-free', () {
      final Directory layoutDir = Directory(
          '${root.path}/packages/jet_print/lib/src/rendering/layout');
      expect(layoutDir.existsSync(), isTrue,
          reason: 'Missing ${layoutDir.path}');
      final List<File> layoutFiles = layoutDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((FileSystemEntity f) => f.path.endsWith('.dart'))
          .toList();
      expect(layoutFiles, isNotEmpty);
      final List<String> violations = <String>[];
      for (final File file in layoutFiles) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          // layout stays headless. Since 008c it MAY import the expression engine
          // (page-scoped chrome substitution): expression is inward of rendering
          // in the dependency DAG, so the import is legal. The Flutter-UI ban
          // remains.
          if (_isFlutterUi(uri)) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'rendering/layout must stay headless (Flutter-free):\n'
              '${violations.join('\n')}');
    });
```

- [ ] **Step 5: Run the tests + analyzer**

Run: `flutter test test/rendering/layout/report_layouter_test.dart test/architecture/layer_boundaries_test.dart -r expanded && flutter analyze`
Expected: PASS — all existing 008a/008b layout tests (their chrome has no text expressions, so behavior is unchanged), the rewritten two chrome tests, the new substitution tests, and the relaxed layer test; `No issues found!`.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/layout/report_layouter.dart \
  packages/jet_print/test/rendering/layout/report_layouter_test.dart \
  packages/jet_print/test/architecture/layer_boundaries_test.dart
git commit -m "feat(layout): page-scoped chrome substitution (008c)"
```

---

## Task 5: CHANGELOG + final verification

**Files:**
- Modify: `packages/jet_print/CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

In `packages/jet_print/CHANGELOG.md`, under the current unreleased `### Added` section (after the 008b entry), add:

```markdown
- **Page-scoped substitution (spec 008c).** `pageHeader`/`pageFooter` text expressions are evaluated
  at layout time and substituted at their authored bounds: `$V{PAGE_NUMBER}`/`$V{PAGE_COUNT}` (as
  integer strings, e.g. `Page 1 of 3`) and report `$P{params}` (threaded through the IR as the
  normalized `FilledReport.params`). A new read-only `Expression.references` gives complete,
  branch-independent reference analysis, so unavailable chrome references (`$F{}`, non-page `$V{}`)
  are diagnosed once per element regardless of short-circuiting. Substitution is fixed-bounds (no
  repagination, no chrome box growth); parse/evaluation failures render `!ERR`. The schema is
  unchanged (`FilledReport.params` is internal IR).
```

- [ ] **Step 2: Run the full suite + analyzer**

Run: `flutter test -r expanded && flutter analyze`
Expected: every test PASSES; `No issues found!`.

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/CHANGELOG.md
git commit -m "docs(layout): changelog for page-scoped substitution (008c)"
```

---

## Done

All of spec 008c is implemented: the static `Expression.references` analyzer, the normalized `FilledReport.params` IR field (+ Fill propagation), the `PageEvalContext` page-scoped value resolver, and the layouter's compile-and-classify pre-pass + page-aware fixed-bounds substitution (page vars as integer strings, params from the IR, diagnostic-rich once-per-element structural diagnostics + coarse runtime errors), with the layout/expression layer-boundary rule relaxed (still Flutter-free). After Task 5, dispatch a final holistic code review over the whole 008c change set, then use `superpowers:finishing-a-development-branch` to merge `008c-page-scoped-substitution` into `main` (or, without the skills: run the full suite + analyzer, do a final review, and merge the branch manually).
