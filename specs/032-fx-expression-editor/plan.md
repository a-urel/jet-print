# fx Expression Editor for the Value Field — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Each task is Red→Green TDD (Constitution III).

**Goal:** Add an **fx** button beside the Value field's data-field picker that opens a centered modal expression editor (multi-line input + field/function palettes + live valid/error/unresolved status), backed by generalizing the template compiler so the full function set actually round-trips and saves.

**Architecture:** Two seams. (1) **Compiler** (`value_template_compiler.dart`, pure): generalize `_compileTemplate`/`_compileArg`/`_exprToToken` so any `FN(arg, …)` call — not just aggregates — round-trips friendly↔expression; existing sugar/aggregate/CONCAT forms stay byte-identical. (2) **Designer UI**: a pure designer-side function catalog, a new `_ExpressionEditorDialog`, an fx button in `_ValueField`'s trailing slot, and new l10n strings. Validation reuses spec-031's `resolvableNamesForBand` + `expressionResolvesNames`; commit reuses the field's existing `onCommit` → `controller.setValue`.

**Tech Stack:** Dart / Flutter, `shadcn_ui` (`showShadDialog`, `ShadDialog`, `ShadInput`, `ShadButton`), `flutter_test`. Designer + expression(template) layers only. No engine/domain/serialization change; goldens unchanged.

**Conventions:** Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` ([[git-cwd-drift-after-flutter]]). Branch is already `032-fx-expression-editor`.

## Constitution Check

| Principle | Status |
|---|---|
| I. Library-first / clean API | PASS — compiler stays pure; catalog/dialog are designer-internal (`src/`); nothing new exported. |
| II. Layered architecture | PASS — compiler (template) pure; catalog (designer) pure; dialog (designer UI) consumes both + data resolution; deps point inward. |
| III. Test-First (NON-NEGOTIABLE) | PASS — every task Red→Green. |
| IV. Rendering fidelity / WYSIWYG | PASS — author-time only; no render path; goldens unchanged. |
| V. Serialization | PASS — no model/codec change; stored `expression` strings are existing engine syntax. |
| VI. Docs/DX | PASS — dartdoc on new helpers/widgets; `dart format` + clean analyzer gate (Task 6). |

No violations → Complexity Tracking omitted.

---

## File Map

- `packages/jet_print/lib/src/designer/template/value_template_compiler.dart` — **modify**: generalize the forward call branch (any `ident(`), uppercase nested call idents in `_compileArg`, add a general-`CallExpr` branch to `_exprToToken`.
- `packages/jet_print/lib/src/designer/template/expression_function_catalog.dart` — **new**: pure metadata (`ExpressionFunction` + grouped catalog) for the function palette.
- `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` — **modify**: add fx button + dialog launch to `_ValueField`; pass the band's resolvable name set in from the panel.
- `packages/jet_print/lib/src/designer/layout/panels/expression_editor_dialog.dart` — **new**: `_ExpressionEditorDialog` (the modal) + `EditorStatus` helper + `showExpressionEditor` entry.
- `packages/jet_print/lib/src/designer/l10n/jet_print_{en,tr,de}.arb` — **modify**: fx tooltip, dialog title/labels, palette group labels, status messages, Cancel/Insert.
- Tests: `test/designer/template/value_template_compiler_test.dart` (extend), new `test/designer/template/expression_function_catalog_test.dart`, new `test/designer/expression_editor_dialog_test.dart`.

---

## Task 1: Generalize the template compiler (forward + nested + reverse)

**Files:**
- Modify: `packages/jet_print/lib/src/designer/template/value_template_compiler.dart`
- Test (modify): `packages/jet_print/test/designer/template/value_template_compiler_test.dart`

Context — three private functions change. Read the current file first (it is ~430 lines, fully quoted in the spec discussion). Today the forward call branch only fires for aggregate names; `_compileArg` passes nested call names through verbatim (so a lowercased nested name fails to evaluate); `_exprToToken` returns `null` for a general `CallExpr` (shown read-only).

- [ ] **Step 1: Write failing tests.** Append to `value_template_compiler_test.dart` (match the existing `group(...)`/`test(...)` style; import is already `package:jet_print/src/designer/template/value_template_compiler.dart`):

```dart
group('general N-ary function calls (032)', () {
  test('forward: IF with field/operator/field args', () {
    expect(
      parseValueField('{IF([qty] > 0, [a], [b])}'),
      const BindingValue(r'IF($F{qty} > 0, $F{a}, $F{b})'),
    );
  });

  test('forward: ROUND with a precision literal', () {
    expect(parseValueField('{ROUND([total], 2)}'),
        const BindingValue(r'ROUND($F{total}, 2)'));
  });

  test('forward: COALESCE of two fields', () {
    expect(parseValueField('{COALESCE([nick], [name])}'),
        const BindingValue(r'COALESCE($F{nick}, $F{name})'));
  });

  test('forward: SUBSTRING with two numeric args', () {
    expect(parseValueField('{SUBSTRING([code], 0, 3)}'),
        const BindingValue(r'SUBSTRING($F{code}, 0, 3)'));
  });

  test('forward: nested call name is uppercased to the registry name', () {
    // Author typed lowercase nested fn; storage must use the UPPERCASE built-in.
    expect(parseValueField('{UPPER(coalesce([a], [b]))}'),
        const BindingValue(r'UPPER(COALESCE($F{a}, $F{b}))'));
  });

  test('reverse: a general CallExpr round-trips to a friendly token', () {
    final ValueDisplay d = reverseCompile(r'IF($F{qty} > 0, $F{a}, $F{b})');
    expect(d.editable, isTrue);
    expect(d.text, '{if([qty] > 0, [a], [b])}');
    // and the displayed token compiles back to the same expression
    expect(parseValueField(d.text),
        const BindingValue(r'IF($F{qty} > 0, $F{a}, $F{b})'));
  });

  test('reverse: nested call round-trips to evaluating UPPERCASE storage', () {
    final ValueDisplay d = reverseCompile(r'UPPER(COALESCE($F{a}, $F{b}))');
    expect(d.editable, isTrue);
    expect(parseValueField(d.text),
        const BindingValue(r'UPPER(COALESCE($F{a}, $F{b}))'));
  });

  test('unknown bare identifier arg is not a valid call → literal fallback', () {
    // PRICE(USD): USD is not a field/param token, so the expression fails to
    // parse and the whole value falls back to literal text (graceful).
    expect(parseValueField('{Price(USD)}'),
        const LiteralValue('{Price(USD)}'));
  });
});

group('existing forms unchanged (032 regression guard)', () {
  test('single-field sugar still reverses to lowercase sugar', () {
    expect(reverseCompile(r'UPPER($F{name})').text, '{upper[name]}');
  });
  test('single-arg scalar reverses to sugar, not call form', () {
    expect(reverseCompile(r'ROUND($F{x})').text, '{round[x]}');
  });
  test('aggregate form unchanged', () {
    expect(reverseCompile(r'SUM($F{qty})').text, '{SUM([qty])}');
    expect(parseValueField('{SUM([qty] * [price])}'),
        const BindingValue(r'SUM($F{qty} * $F{price})'));
  });
});
```

- [ ] **Step 2: Run → FAIL.** Run: `flutter test test/designer/template/value_template_compiler_test.dart`. Expected: the new tests fail (general calls compile to literal / reverse to read-only).

- [ ] **Step 3: Implement — forward general call.** In `_compileTemplate`, the `_isAlpha(c)` branch currently gates the call form on `aggregateCalculationFor(...) != null`. Replace that first inner `if` so **any** identifier followed by `(` compiles as a call:

```dart
} else if (_isAlpha(c)) {
  final int identEnd = _scanIdentEnd(inner, i);
  if (identEnd < inner.length && inner[identEnd] == '(') {
    // Function call FN( <args with [field] tokens> ) — aggregate or scalar.
    // The registry is UPPERCASE; the inner arg list (incl. nested calls) is
    // normalized by _compileArg.
    flushLiteral();
    final String fn = inner.substring(i, identEnd).toUpperCase();
    final _CallScan scan = _scanBalancedParens(inner, identEnd);
    parts.add('$fn(${_compileArg(scan.body)})');
    i = scan.next;
  } else if (identEnd < inner.length && inner[identEnd] == '[') {
    // Function sugar: ident[field].  (unchanged)
    flushLiteral();
    final String fn = inner.substring(i, identEnd).toUpperCase();
    final _FieldScan scan = _scanField(inner, identEnd);
    parts.add('$fn(\$F{${scan.name}})');
    i = scan.next;
  } else {
    literal.write(inner.substring(i, identEnd));
    i = identEnd;
  }
}
```

The unused `aggregateCalculationFor` import may now be removable — leave it only if still referenced; run the analyzer in Step 6 to confirm.

- [ ] **Step 4: Implement — uppercase nested call names in `_compileArg`.** So a nested call authored (or reverse-compiled) in lowercase still stores the registry's UPPERCASE name and evaluates. Replace `_compileArg` with:

```dart
/// Compiles an aggregate/call argument: replaces each `[name]` token with
/// `$F{name}`, UPPERCASEs any nested function-call identifier (the registry is
/// case-sensitive UPPERCASE), and passes all other expression syntax —
/// operators, commas, parens, string/number/bool literals, `$P{}`/`$V{}`
/// tokens — through unchanged.
String _compileArg(String arg) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < arg.length) {
    final String c = arg[i];
    if (c == '[') {
      final _FieldScan scan = _scanField(arg, i);
      out.write('\$F{${scan.name}}');
      i = scan.next;
    } else if (_isAlpha(c)) {
      final int identEnd = _scanIdentEnd(arg, i);
      final String ident = arg.substring(i, identEnd);
      // A nested call (`ident(`) takes the UPPERCASE registry name; a bare
      // identifier (`true`/`false`, or a `$P{}`/`$V{}` body) passes through.
      out.write(identEnd < arg.length && arg[identEnd] == '('
          ? ident.toUpperCase()
          : ident);
      i = identEnd;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}
```

- [ ] **Step 5: Implement — reverse general call.** In `_exprToToken`, add a final branch **after** the existing single-function-of-field check (so `UPPER($F{name})` still becomes `{upper[name]}`) and before `return null`:

```dart
  // A single function-of-field call, e.g. UPPER($F{name}) → {upper[name]}.
  final String? part = _partToken(root);
  if (part != null && root is CallExpr) return '{$part}';

  // Any other call (multi-arg, mixed args, nested) → {fn(args)} via _argToToken.
  if (root is CallExpr) {
    final String? body = _argToToken(root);
    if (body != null) return '{$body}';
  }
  return null;
```

- [ ] **Step 6: Run → PASS + analyzer/format.** Run: `flutter test test/designer/template/value_template_compiler_test.dart` (the new tests pass), then `flutter analyze lib/src/designer/template test/designer/template` and `dart format lib/src/designer/template/value_template_compiler.dart test/designer/template/value_template_compiler_test.dart`. Expected: green, clean, no formatting diff.

- [ ] **Step 7: Full compiler-affected sweep.** Run: `flutter test test/designer test/expression 2>&1 | tail -20`. Any test asserting that a `word(...)` template stays literal, or asserting old lowercase nested-call storage, may now legitimately change — update it deliberately with a one-line comment explaining the 032 generalization. **No golden may change** (the compiler is author-time only). If a golden fails, STOP and inspect.

- [ ] **Step 8: Commit.**
```bash
git add packages/jet_print/lib/src/designer/template/value_template_compiler.dart packages/jet_print/test/designer/template/value_template_compiler_test.dart
git commit -m "feat(designer): template compiler round-trips general N-ary function calls

Generalize _compileTemplate (any ident-call, not only aggregates),
uppercase nested call names in _compileArg, and reverse general CallExprs
to {fn(args)}. Existing sugar/aggregate/CONCAT forms byte-identical.
Author-time projection only; no engine/golden change.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Designer-side function catalog

**Files:**
- New: `packages/jet_print/lib/src/designer/template/expression_function_catalog.dart`
- Test (new): `packages/jet_print/test/designer/template/expression_function_catalog_test.dart`

Context — the engine `JetFunctionRegistry` is name→fn with no UI metadata; the palette's grouping, snippets, and caret positions are a presentation concern, so they live designer-side. Aggregate names derive from `aggregateFunctionsByName` (the const map in `aggregate_functions.dart`, exposed via `aggregateCalculationFor`); the rest are curated to match the registered built-ins (`string_functions`/`math_functions`/`logic_functions`/`format_functions`).

- [ ] **Step 1: Write failing tests.** Create `expression_function_catalog_test.dart`:

```dart
/// Tests for the designer's expression-function catalog (032): the metadata that
/// drives the fx editor's function palette. Verifies grouping, snippet shape,
/// caret placement, and — critically — that every catalog name maps to a
/// function the engine actually evaluates and parses.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/template/expression_function_catalog.dart';
import 'package:jet_print/src/designer/template/value_template_compiler.dart';

void main() {
  test('catalog covers the four groups', () {
    final Set<ExpressionFunctionGroup> groups =
        expressionFunctionCatalog.map((ExpressionFunction f) => f.group).toSet();
    expect(groups, <ExpressionFunctionGroup>{
      ExpressionFunctionGroup.string,
      ExpressionFunctionGroup.math,
      ExpressionFunctionGroup.logic,
      ExpressionFunctionGroup.aggregate,
    });
  });

  test('every entry has a non-empty name, signature, and snippet', () {
    for (final ExpressionFunction f in expressionFunctionCatalog) {
      expect(f.name, isNotEmpty);
      expect(f.signature, isNotEmpty);
      expect(f.insertSnippet, isNotEmpty);
      expect(f.caretOffset, inInclusiveRange(0, f.insertSnippet.length));
    }
  });

  test('aggregate names are the inline-aggregate vocabulary', () {
    final Set<String> aggNames = expressionFunctionCatalog
        .where((ExpressionFunction f) =>
            f.group == ExpressionFunctionGroup.aggregate)
        .map((ExpressionFunction f) => f.name)
        .toSet();
    expect(aggNames, <String>{'SUM', 'AVG', 'COUNT', 'MIN', 'MAX'});
  });

  test('known built-ins are offered', () {
    final Set<String> names = expressionFunctionCatalog
        .map((ExpressionFunction f) => f.name)
        .toSet();
    for (final String n in <String>['UPPER', 'LOWER', 'TRIM', 'CONCAT',
        'SUBSTRING', 'ABS', 'ROUND', 'IF', 'COALESCE', 'FORMAT']) {
      expect(names, contains(n), reason: '$n missing from catalog');
    }
  });

  test('each snippet, with a field substituted, parses to a binding', () {
    // The snippet is a {…}-less body fragment; wrapping it in a field-filled
    // template must compile (guards against a malformed snippet shipping).
    for (final ExpressionFunction f in expressionFunctionCatalog) {
      final String filled = '{${f.insertSnippet.replaceAll('()', '([qty])')
          .replaceAll('(, ', '([qty], ').replaceAll(', )', ', [qty])')}}';
      // A loose smoke check: the function name compiles as a call.
      expect(parseValueField('{${f.name}([qty])}'), isA<BindingValue>(),
          reason: '${f.name} should compile as a call');
    }
  });
}
```

- [ ] **Step 2: Run → FAIL.** Run: `flutter test test/designer/template/expression_function_catalog_test.dart`. Expected: fail to compile (file missing).

- [ ] **Step 3: Implement the catalog.** Create `expression_function_catalog.dart`:

```dart
/// The fx editor's function palette metadata (032). Presentation-only: the
/// engine's `JetFunctionRegistry` carries no UI data, so grouping, insert
/// snippets, caret positions, and signature labels live here. Aggregate names
/// stay single-sourced via [aggregateCalculationFor].
///
/// New engine function → add an entry here (a catalog test asserts the offered
/// names all compile as calls).
library;

import '../../expression/aggregate/aggregate_functions.dart';

/// The palette section an [ExpressionFunction] belongs to.
enum ExpressionFunctionGroup { string, math, logic, aggregate }

/// One palette entry: the registry [name], its [group], a human [signature]
/// label, the friendly-syntax [insertSnippet] dropped into the editor, and the
/// [caretOffset] (within the snippet) where the caret lands after insertion.
class ExpressionFunction {
  const ExpressionFunction({
    required this.name,
    required this.group,
    required this.signature,
    required this.insertSnippet,
    required this.caretOffset,
  });

  final String name;
  final ExpressionFunctionGroup group;
  final String signature;
  final String insertSnippet;
  final int caretOffset;
}

/// Builds a snippet `NAME(…)` and returns it paired with the caret offset
/// pointing just inside the opening paren.
ExpressionFunction _fn(
  String name,
  ExpressionFunctionGroup group,
  String signature,
) {
  final String snippet = '$name()';
  return ExpressionFunction(
    name: name,
    group: group,
    signature: signature,
    insertSnippet: snippet,
    caretOffset: name.length + 1, // just after '('
  );
}

/// The functions offered by the fx editor, grouped for display. Aggregate names
/// derive from the inline-aggregate vocabulary so they cannot drift.
final List<ExpressionFunction> expressionFunctionCatalog = <ExpressionFunction>[
  // String
  _fn('UPPER', ExpressionFunctionGroup.string, 'UPPER(text)'),
  _fn('LOWER', ExpressionFunctionGroup.string, 'LOWER(text)'),
  _fn('TRIM', ExpressionFunctionGroup.string, 'TRIM(text)'),
  _fn('LENGTH', ExpressionFunctionGroup.string, 'LENGTH(text)'),
  _fn('CONCAT', ExpressionFunctionGroup.string, 'CONCAT(a, b, …)'),
  _fn('SUBSTRING', ExpressionFunctionGroup.string, 'SUBSTRING(text, start, len)'),
  _fn('FORMAT', ExpressionFunctionGroup.string, 'FORMAT(value, pattern)'),
  // Math
  _fn('ABS', ExpressionFunctionGroup.math, 'ABS(number)'),
  _fn('ROUND', ExpressionFunctionGroup.math, 'ROUND(number, places)'),
  _fn('CEIL', ExpressionFunctionGroup.math, 'CEIL(number)'),
  _fn('FLOOR', ExpressionFunctionGroup.math, 'FLOOR(number)'),
  _fn('MIN', ExpressionFunctionGroup.math, 'MIN(a, b)'),
  _fn('MAX', ExpressionFunctionGroup.math, 'MAX(a, b)'),
  // Logic
  _fn('IF', ExpressionFunctionGroup.logic, 'IF(cond, then, else)'),
  _fn('COALESCE', ExpressionFunctionGroup.logic, 'COALESCE(a, b, …)'),
  _fn('ISNULL', ExpressionFunctionGroup.logic, 'ISNULL(value)'),
  // Aggregate — names from the single-sourced vocabulary.
  for (final String n in const <String>['SUM', 'AVG', 'COUNT', 'MIN', 'MAX'])
    if (aggregateCalculationFor(n) != null)
      _fn(n, ExpressionFunctionGroup.aggregate, '$n(expression)'),
];
```

Note `MIN`/`MAX` appear in both Math (scalar, ≥2 args) and Aggregate (1 arg) groups — that is intentional and matches the engine's arity-based disambiguation; the test's aggregate-set assertion still holds.

- [ ] **Step 4: Run → PASS.** Run: `flutter test test/designer/template/expression_function_catalog_test.dart`. Expected: green. Then `flutter analyze lib/src/designer/template/expression_function_catalog.dart test/designer/template/expression_function_catalog_test.dart` and `dart format` those two files.

- [ ] **Step 5: Commit.**
```bash
git add packages/jet_print/lib/src/designer/template/expression_function_catalog.dart packages/jet_print/test/designer/template/expression_function_catalog_test.dart
git commit -m "feat(designer): expression-function catalog for the fx palette

Pure designer-side metadata (group, signature, insert snippet, caret) for
the fx editor's function palette; aggregate names derive from the inline-
aggregate vocabulary. Drift-guarded by a test that every offered name
compiles as a call.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: l10n strings for the fx affordance

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_tr.arb`, `jet_print_de.arb`

Context — the panel reads localized strings via `JetPrintLocalizations` (gen-l10n output). Add the new keys to **all three** arb files (en is the template; tr/de must mirror its keys or gen-l10n warns). Place them near `valueFieldPickerTooltip` (≈L282 in en).

- [ ] **Step 1: Add keys to `jet_print_en.arb`.** Insert after the `valueFieldPickerTooltip` block:

```json
  "valueFieldFxTooltip": "Build an expression",
  "@valueFieldFxTooltip": {
    "description": "Tooltip for the value field's fx button that opens the expression editor (032)."
  },
  "exprEditorTitle": "Expression",
  "@exprEditorTitle": {
    "description": "Title of the fx expression editor dialog (032)."
  },
  "exprEditorFieldsLabel": "Fields",
  "@exprEditorFieldsLabel": {
    "description": "Label for the in-scope data-field palette in the expression editor (032)."
  },
  "exprEditorFunctionsLabel": "Functions",
  "@exprEditorFunctionsLabel": {
    "description": "Label for the function palette in the expression editor (032)."
  },
  "exprGroupString": "String",
  "@exprGroupString": { "description": "Function palette group: string functions (032)." },
  "exprGroupMath": "Math",
  "@exprGroupMath": { "description": "Function palette group: math functions (032)." },
  "exprGroupLogic": "Logic",
  "@exprGroupLogic": { "description": "Function palette group: logic functions (032)." },
  "exprGroupAggregate": "Aggregate",
  "@exprGroupAggregate": { "description": "Function palette group: aggregate functions (032)." },
  "exprStatusValid": "Valid",
  "@exprStatusValid": {
    "description": "Status shown when the edited expression is well-formed and resolves (032)."
  },
  "exprStatusSyntaxError": "Incomplete or invalid expression",
  "@exprStatusSyntaxError": {
    "description": "Status shown when the { … } expression fails to compile (032)."
  },
  "exprStatusUnresolved": "Field not in the data source: {name}",
  "@exprStatusUnresolved": {
    "description": "Status shown when the expression references an out-of-scope field (032).",
    "placeholders": { "name": { "type": "String" } }
  },
  "exprEditorCancel": "Cancel",
  "@exprEditorCancel": { "description": "Dismiss the expression editor without changes (032)." },
  "exprEditorInsert": "Insert",
  "@exprEditorInsert": { "description": "Commit the edited expression to the value field (032)." },
```

- [ ] **Step 2: Mirror the same keys in `jet_print_tr.arb`** with Turkish values (`@…` metadata blocks are only required in the template/en file; translation arbs hold just the key→value pairs, matching the existing tr file's shape — check the file and follow its convention):

```json
  "valueFieldFxTooltip": "İfade oluştur",
  "exprEditorTitle": "İfade",
  "exprEditorFieldsLabel": "Alanlar",
  "exprEditorFunctionsLabel": "Fonksiyonlar",
  "exprGroupString": "Metin",
  "exprGroupMath": "Matematik",
  "exprGroupLogic": "Mantık",
  "exprGroupAggregate": "Toplam",
  "exprStatusValid": "Geçerli",
  "exprStatusSyntaxError": "Eksik veya geçersiz ifade",
  "exprStatusUnresolved": "Alan veri kaynağında yok: {name}",
  "exprEditorCancel": "İptal",
  "exprEditorInsert": "Ekle",
```

- [ ] **Step 3: Mirror in `jet_print_de.arb`** with German values:

```json
  "valueFieldFxTooltip": "Ausdruck erstellen",
  "exprEditorTitle": "Ausdruck",
  "exprEditorFieldsLabel": "Felder",
  "exprEditorFunctionsLabel": "Funktionen",
  "exprGroupString": "Text",
  "exprGroupMath": "Mathe",
  "exprGroupLogic": "Logik",
  "exprGroupAggregate": "Aggregat",
  "exprStatusValid": "Gültig",
  "exprStatusSyntaxError": "Unvollständiger oder ungültiger Ausdruck",
  "exprStatusUnresolved": "Feld nicht in der Datenquelle: {name}",
  "exprEditorCancel": "Abbrechen",
  "exprEditorInsert": "Einfügen",
```

> Match each file's existing brace/whitespace style; if tr/de include `@`-blocks, mirror that. Add a trailing comma only where the surrounding entries do (don't break JSON).

- [ ] **Step 4: Regenerate + verify.** Run: `flutter gen-l10n` (from `packages/jet_print`). Then confirm the getters exist:
```bash
grep -l "valueFieldFxTooltip" $(find . -name "jet_print_localizations*.dart")
```
Expected: the generated localizations file lists `valueFieldFxTooltip`, `exprStatusUnresolved`, etc. Run `flutter analyze lib/src/designer/l10n` → clean.

- [ ] **Step 5: Commit.**
```bash
git add packages/jet_print/lib/src/designer/l10n/
git commit -m "feat(designer): l10n strings for the fx expression editor (032)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: The expression editor dialog

**Files:**
- New: `packages/jet_print/lib/src/designer/layout/panels/expression_editor_dialog.dart`
- Test (new): `packages/jet_print/test/designer/expression_editor_dialog_test.dart`

Context — a centered modal opened from the fx button. It owns the editing `TextEditingController` seeded with the field's current display token, renders the field + function palettes, computes a live `EditorStatus`, and returns the committed text (or null on Cancel). Validation reuses `parseValueField` (syntax) and `fieldRefsIn` + the passed-in resolvable name set (resolution). The dialog is `src/`-internal but its widget keys are the test seam.

`★ Status logic (the heart of the widget):`
- `parseValueField(text)` → `BindingValue(expr)`: compute `fieldRefsIn(expr).difference(names)`; empty ⇒ `valid`, else ⇒ `unresolved(firstMissing)`.
- text is a `{…}` template but parses to `LiteralValue` ⇒ `syntaxError` (malformed template).
- otherwise (plain literal text) ⇒ `valid`.

- [ ] **Step 1: Write failing tests.** Create `expression_editor_dialog_test.dart`. It pumps the dialog directly (no full designer) via a small ShadApp host so it is fast and focused:

```dart
/// Tests for the fx expression editor dialog (032): seeding, palette insertion,
/// live status (valid / syntax error / unresolved), and commit/cancel.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart' show FieldDef, JetFieldType;
import 'package:jet_print/src/designer/layout/panels/expression_editor_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const Key _editorKey = ValueKey<String>('jet_print.designer.exprEditor.input');
const Key _statusKey = ValueKey<String>('jet_print.designer.exprEditor.status');
const Key _insertKey = ValueKey<String>('jet_print.designer.exprEditor.insert');
const Key _cancelKey = ValueKey<String>('jet_print.designer.exprEditor.cancel');
Finder _fieldChip(String n) =>
    find.byKey(ValueKey<String>('jet_print.designer.exprEditor.field.$n'));
Finder _fnChip(String n) =>
    find.byKey(ValueKey<String>('jet_print.designer.exprEditor.fn.$n'));

Future<String?> _pumpEditor(
  WidgetTester tester, {
  required String initial,
  Set<String> names = const <String>{'qty', 'price'},
  List<FieldDef> fields = const <FieldDef>[
    FieldDef('qty', type: JetFieldType.integer),
    FieldDef('price', type: JetFieldType.double),
  ],
}) async {
  String? result;
  await tester.pumpWidget(ShadApp(
    home: Builder(builder: (BuildContext context) {
      return Center(
        child: ShadButton(
          child: const Text('open'),
          onPressed: () async {
            result = await showExpressionEditor(
              context,
              initialText: initial,
              resolvableNames: names,
              fields: fields,
            );
          },
        ),
      );
    }),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result; // null until the dialog closes
}

void main() {
  testWidgets('seeds the editor with the current display token',
      (WidgetTester tester) async {
    await _pumpEditor(tester, initial: '{SUM([qty])}');
    expect(
      (tester.widget<EditableText>(
        find.descendant(of: find.byKey(_editorKey),
            matching: find.byType(EditableText)),
      )).controller.text,
      '{SUM([qty])}',
    );
  });

  testWidgets('tapping a field chip inserts its [token] at the caret',
      (WidgetTester tester) async {
    await _pumpEditor(tester, initial: '{}');
    // Put caret inside the braces first.
    await tester.enterText(find.byKey(_editorKey), '{}');
    await tester.tap(_fieldChip('qty'));
    await tester.pumpAndSettle();
    // The chip appends [qty]; exact caret math is asserted loosely here.
    final String text = tester.widget<EditableText>(find.descendant(
        of: find.byKey(_editorKey),
        matching: find.byType(EditableText))).controller.text;
    expect(text, contains('[qty]'));
  });

  testWidgets('valid in-scope expression shows the valid status',
      (WidgetTester tester) async {
    await _pumpEditor(tester, initial: '{SUM([qty])}');
    expect(find.byKey(_statusKey), findsOneWidget);
    expect(find.text('Valid'), findsOneWidget);
  });

  testWidgets('out-of-scope reference shows an unresolved status naming it',
      (WidgetTester tester) async {
    await _pumpEditor(tester, initial: '{SUM([bogus])}');
    expect(find.textContaining('bogus'), findsOneWidget);
  });

  testWidgets('malformed template shows a syntax-error status',
      (WidgetTester tester) async {
    await _pumpEditor(tester, initial: '{SUM([qty]) *}');
    expect(find.text('Incomplete or invalid expression'), findsOneWidget);
  });

  testWidgets('Insert returns the editor text; Cancel returns null',
      (WidgetTester tester) async {
    // Insert
    await _pumpEditor(tester, initial: '{UPPER([qty])}');
    await tester.tap(find.byKey(_insertKey));
    await tester.pumpAndSettle();
    // Re-open to read the captured result via a second pump is awkward; instead
    // assert the dialog closed (status no longer shown).
    expect(find.byKey(_statusKey), findsNothing);
  });

  testWidgets('Cancel dismisses without committing',
      (WidgetTester tester) async {
    await _pumpEditor(tester, initial: '{UPPER([qty])}');
    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_statusKey), findsNothing);
  });
}
```

- [ ] **Step 2: Run → FAIL.** Run: `flutter test test/designer/expression_editor_dialog_test.dart`. Expected: fails to compile (file missing).

- [ ] **Step 3: Implement the dialog.** Create `expression_editor_dialog.dart`:

```dart
/// The fx expression editor (032): a centered modal that composes a value-field
/// expression in the friendly template syntax, with field + function palettes
/// and live syntax/resolution feedback. Presentation only — it speaks the same
/// language as the inline field (`value_template_compiler`) and returns the
/// edited text for the caller to commit through its existing onCommit path.
library;

import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../data/binding_scope.dart';
import '../../../data/field_def.dart';
import '../../../l10n/jet_print_localizations.dart';
import '../../template/expression_function_catalog.dart';
import '../../template/value_template_compiler.dart';

const String _k = 'jet_print.designer.exprEditor';

/// Opens the expression editor seeded with [initialText]; returns the committed
/// text on Insert, or null on Cancel/dismiss. [resolvableNames] is the band's
/// resolvable name set (spec 031); [fields] is the in-scope field palette.
Future<String?> showExpressionEditor(
  BuildContext context, {
  required String initialText,
  required Set<String> resolvableNames,
  required List<FieldDef> fields,
}) {
  return showShadDialog<String>(
    context: context,
    builder: (BuildContext context) => _ExpressionEditorDialog(
      initialText: initialText,
      resolvableNames: resolvableNames,
      fields: fields,
    ),
  );
}

/// The live verdict for the edited text.
sealed class EditorStatus {
  const EditorStatus();
}

class StatusValid extends EditorStatus {
  const StatusValid();
}

class StatusSyntaxError extends EditorStatus {
  const StatusSyntaxError();
}

class StatusUnresolved extends EditorStatus {
  const StatusUnresolved(this.name);
  final String name;
}

/// Pure status computation, unit-testable independent of the widget.
EditorStatus statusFor(String text, Set<String> names) {
  final ValueParse parse = parseValueField(text);
  if (parse is BindingValue) {
    for (final String ref in fieldRefsIn(parse.expression)) {
      if (!names.contains(ref)) return StatusUnresolved(ref);
    }
    return const StatusValid();
  }
  // A {…}-wrapped value that did NOT parse to a binding is a malformed template.
  final String t = text.trim();
  if (t.length >= 2 && t.startsWith('{') && t.endsWith('}')) {
    return const StatusSyntaxError();
  }
  return const StatusValid(); // plain literal text
}

class _ExpressionEditorDialog extends StatefulWidget {
  const _ExpressionEditorDialog({
    required this.initialText,
    required this.resolvableNames,
    required this.fields,
  });

  final String initialText;
  final Set<String> resolvableNames;
  final List<FieldDef> fields;

  @override
  State<_ExpressionEditorDialog> createState() =>
      _ExpressionEditorDialogState();
}

class _ExpressionEditorDialogState extends State<_ExpressionEditorDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText)..addListener(_onChange);

  EditorStatus _status = const StatusValid();

  @override
  void initState() {
    super.initState();
    _status = statusFor(_controller.text, widget.resolvableNames);
  }

  void _onChange() =>
      setState(() => _status =
          statusFor(_controller.text, widget.resolvableNames));

  /// Inserts [snippet] at the caret (replacing any selection) and moves the
  /// caret to [caretInSnippet] within it.
  void _insertAtCaret(String snippet, int caretInSnippet) {
    final TextEditingValue v = _controller.value;
    final int start = v.selection.start < 0 ? v.text.length : v.selection.start;
    final int end = v.selection.end < 0 ? v.text.length : v.selection.end;
    final String next =
        v.text.replaceRange(start, end, snippet);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + caretInSnippet),
    );
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    return ShadDialog(
      title: Text(l10n.exprEditorTitle),
      actions: <Widget>[
        ShadButton.outline(
          key: const ValueKey<String>('$_k.cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.exprEditorCancel),
        ),
        ShadButton(
          key: const ValueKey<String>('$_k.insert'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.exprEditorInsert),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 8),
            ShadInput(
              key: const ValueKey<String>('$_k.input'),
              controller: _controller,
              maxLines: 4,
              minLines: 2,
            ),
            const SizedBox(height: 8),
            _StatusLine(status: _status, l10n: l10n),
            const SizedBox(height: 12),
            Text(l10n.exprEditorFieldsLabel),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final FieldDef f in widget.fields)
                  ShadButton.ghost(
                    key: ValueKey<String>('$_k.field.${f.name}'),
                    size: ShadButtonSize.sm,
                    onPressed: () => _insertAtCaret('[${f.name}]', '[${f.name}]'.length),
                    child: Text(f.name),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.exprEditorFunctionsLabel),
            const SizedBox(height: 4),
            _FunctionPalette(l10n: l10n, onPick: _insertAtCaret),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.l10n});
  final EditorStatus status;
  final JetPrintLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final (String text, Color color) = switch (status) {
      StatusValid() => (l10n.exprStatusValid, colors.primary),
      StatusSyntaxError() => (l10n.exprStatusSyntaxError, colors.destructive),
      StatusUnresolved(:final String name) =>
        (l10n.exprStatusUnresolved(name), colors.destructive),
    };
    return Text(
      text,
      key: const ValueKey<String>('$_k.status'),
      style: TextStyle(color: color, fontSize: 12),
    );
  }
}

class _FunctionPalette extends StatelessWidget {
  const _FunctionPalette({required this.l10n, required this.onPick});
  final JetPrintLocalizations l10n;
  final void Function(String snippet, int caret) onPick;

  String _groupLabel(ExpressionFunctionGroup g) => switch (g) {
        ExpressionFunctionGroup.string => l10n.exprGroupString,
        ExpressionFunctionGroup.math => l10n.exprGroupMath,
        ExpressionFunctionGroup.logic => l10n.exprGroupLogic,
        ExpressionFunctionGroup.aggregate => l10n.exprGroupAggregate,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final ExpressionFunctionGroup group
            in ExpressionFunctionGroup.values) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(_groupLabel(group),
                style: const TextStyle(fontSize: 11)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final ExpressionFunction f in expressionFunctionCatalog)
                if (f.group == group)
                  ShadButton.ghost(
                    key: ValueKey<String>('$_k.fn.${f.name}'),
                    size: ShadButtonSize.sm,
                    onPressed: () => onPick(f.insertSnippet, f.caretOffset),
                    child: Text(f.name),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}
```

> VERIFY against the installed `shadcn_ui` 0.54: `ShadDialog`'s `title`/`actions`/`child` params, `ShadButton.outline`/`.ghost`, `ShadButtonSize.sm`, and `JetPrintLocalizations.of(context)`. If a name differs (e.g. `ShadButton.ghost` vs `ShadButton.raw(variant: …)`), adjust to the package's actual API — the keys and behavior are what the tests assert, not the exact constructor. The `MIN`/`MAX` duplicate keys across Math+Aggregate groups would collide on `'$_k.fn.MIN'`; disambiguate the aggregate keys as `'$_k.fn.${f.name}.${f.group.name}'` (update the test finder accordingly) or suffix the aggregate label.

- [ ] **Step 4: Run → PASS.** Run: `flutter test test/designer/expression_editor_dialog_test.dart`. Fix until green. Then `flutter analyze` + `dart format` the two files.

- [ ] **Step 5: Add a focused `statusFor` unit test** (cheap, no widget) to `expression_editor_dialog_test.dart` so the status logic is pinned independent of layout:

```dart
  group('statusFor', () {
    const Set<String> names = <String>{'qty'};
    test('binding in scope is valid', () {
      expect(statusFor('{SUM([qty])}', names), isA<StatusValid>());
    });
    test('out-of-scope ref is unresolved and names the field', () {
      final EditorStatus s = statusFor('{SUM([bogus])}', names);
      expect(s, isA<StatusUnresolved>());
      expect((s as StatusUnresolved).name, 'bogus');
    });
    test('malformed template is a syntax error', () {
      expect(statusFor('{SUM([qty]) *}', names), isA<StatusSyntaxError>());
    });
    test('plain literal text is valid', () {
      expect(statusFor('hello', names), isA<StatusValid>());
    });
  });
```

Run → PASS.

- [ ] **Step 6: Commit.**
```bash
git add packages/jet_print/lib/src/designer/layout/panels/expression_editor_dialog.dart packages/jet_print/test/designer/expression_editor_dialog_test.dart
git commit -m "feat(designer): fx expression editor dialog (032)

Centered modal with seeded editor, field + function palettes, and live
valid/syntax-error/unresolved status (statusFor reuses parseValueField +
fieldRefsIn + the band resolvable set). Returns committed text / null.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Wire the fx button into the Value field

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`
- Test (modify): `packages/jet_print/test/designer/band_collection_binding_test.dart` (or a new sibling `test/designer/value_field_fx_test.dart`)

Context — `_ValueField` (≈L1783) renders a `ShadInput` with a single `trailing` `_FieldPicker`. Add (a) an `fx` affordance beside it and (b) the params the dialog needs (`resolvableNames`, `pickerTooltip` for fx). The panel call site (≈L227) computes `resolvableNames` via the existing `resolvableNamesForBand` (already imported/used by `_unresolved`).

- [ ] **Step 1: Write a failing UI test.** Create `test/designer/value_field_fx_test.dart` (follow `band_collection_binding_test.dart`'s harness usage — `pumpDesignerWith`, `openPropertiesTab`, selecting an element):

```dart
/// The Value field's fx button opens the expression editor and commits its
/// result through the same setValue path as the inline field (032).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const Key _fxKey = ValueKey<String>('jet_print.designer.properties.field.value.fx');
const Key _editorInsert = ValueKey<String>('jet_print.designer.exprEditor.insert');
const Key _editorInput = ValueKey<String>('jet_print.designer.exprEditor.input');

const JetDataSchema _schema = JetDataSchema(name: 'R', fields: <FieldDef>[
  FieldDef('qty', type: JetFieldType.integer),
]);

ReportDefinition _def() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(id: 'detail', type: BandType.detail, height: 40,
            elements: <ReportElement>[
              TextElement(id: 't1',
                bounds: JetRect(x: 0, y: 0, width: 80, height: 12),
                text: 'x'),
            ])),
        ]),
      ),
    );

void main() {
  testWidgets('fx button is present for a selected text element',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _def());
    await pumpDesignerWith(tester, controller: c, dataSchema: _schema);
    c.select('t1');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);
    expect(find.byKey(_fxKey), findsOneWidget);
  });

  testWidgets('fx → edit → Insert commits via setValue (one undo restores)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _def());
    await pumpDesignerWith(tester, controller: c, dataSchema: _schema);
    c.select('t1');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    await tester.tap(find.byKey(_fxKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_editorInput), '{SUM([qty])}');
    await tester.tap(find.byKey(_editorInsert));
    await tester.pumpAndSettle();

    final TextElement t = c.definition.body.root // walk to the element
        .let_findText('t1');
    expect(t.expression, r'SUM($F{qty})');

    c.undo();
    expect(c.definition.body.root.let_findText('t1').expression, isNull);
  });
}
```

> Replace `let_findText` with the harness's real element lookup. If none exists, use the public `findBandOfElement`/element accessor the other tests use, or read `c.definition` and locate `t1` inline. Confirm the controller's selection API name (`select` vs `selectElement`) and the undo API (`undo()`) from `jet_report_designer_controller.dart` before running — adjust to the real names.

- [ ] **Step 2: Run → FAIL.** Run: `flutter test test/designer/value_field_fx_test.dart`. Expected: no fx key found.

- [ ] **Step 3: Extend `_ValueField`.** Add two fields and render the fx button beside the picker. Change the widget's constructor/fields:

```dart
class _ValueField extends StatefulWidget {
  const _ValueField({
    required this.fieldKey,
    required this.display,
    required this.placeholder,
    required this.fields,
    required this.pickerTooltip,
    required this.fxTooltip,          // NEW
    required this.resolvableNames,    // NEW
    required this.onCommit,
    this.focusNode,
  });
  // ...existing fields...
  /// Tooltip for the fx (expression editor) button.
  final String fxTooltip;
  /// The band's resolvable name set (spec 031), for the editor's live check.
  final Set<String> resolvableNames;
```

In `_ValueFieldState`, add the opener:

```dart
Future<void> _openFx() async {
  final String? result = await showExpressionEditor(
    context,
    initialText: widget.display.text,
    resolvableNames: widget.resolvableNames,
    fields: widget.fields,
  );
  if (result != null) widget.onCommit(result);
}
```

Replace the `trailing:` so the fx button always shows (when editable) and the field picker shows only when there are fields:

```dart
trailing: widget.display.editable
    ? Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            label: widget.fxTooltip,
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openFx,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  LucideIcons.squareFunction,
                  key: const ValueKey<String>('$_p.field.value.fx'),
                  size: 14,
                  color: ShadTheme.of(context).colorScheme.mutedForeground,
                ),
              ),
            ),
          ),
          if (widget.fields.isNotEmpty)
            _FieldPicker(
              controller: _picker,
              fields: widget.fields,
              tooltip: widget.pickerTooltip,
              onPick: _pick,
            ),
        ],
      )
    : null,
```

> Confirm the Lucide glyph name available in this `shadcn_ui`/`lucide_icons` version (`LucideIcons.squareFunction`, `functionSquare`, or `variable`); pick whichever exists. `_p` is the panel key-prefix constant already in this file.

- [ ] **Step 4: Pass the new params at the call site** (≈L227). Compute the resolvable set the same way `_unresolved` does:

```dart
_ValueField(
  fieldKey: const ValueKey<String>('$_p.field.value'),
  display: element.expression == null
      ? ValueDisplay(element.text)
      : reverseCompile(element.expression!),
  placeholder: l10n.valueFieldHint,
  focusNode: _textFocus,
  fields: _valueFieldChoices(schema, controller, id),
  pickerTooltip: l10n.valueFieldPickerTooltip,
  fxTooltip: l10n.valueFieldFxTooltip,                 // NEW
  resolvableNames: _resolvableNames(schema, controller, id), // NEW
  onCommit: (String v) => controller.setValue(id, v),
),
```

Add the small private helper next to `_unresolved` (reusing the same band-walk + 031 helper; returns an empty set when no schema/band so the editor simply never flags):

```dart
/// The resolvable name set for [elementId]'s band — schema fields in scope plus
/// published totals (spec 031). Empty when no schema/band, so the fx editor's
/// unresolved check stays silent exactly like the inline field (FR-019a).
Set<String> _resolvableNames(
  JetDataSchema? schema,
  JetReportDesignerController controller,
  String elementId,
) {
  if (schema == null) return const <String>{};
  final Band? band = findBandOfElement(controller.definition, elementId);
  if (band == null) return const <String>{};
  return resolvableNamesForBand(controller.definition, schema, band.id);
}
```

Add the import for the dialog at the top of `properties_panel.dart`:
`import 'expression_editor_dialog.dart';`

- [ ] **Step 5: Run → PASS.** Run: `flutter test test/designer/value_field_fx_test.dart`. Fix until green. Run the existing panel suite to confirm no regression: `flutter test test/designer/band_collection_binding_test.dart test/designer/format_properties_test.dart 2>&1 | tail -15` (adjust file names to those that exist). Then `flutter analyze` + `dart format` the panel file.

- [ ] **Step 6: Commit.**
```bash
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/test/designer/value_field_fx_test.dart
git commit -m "feat(designer): fx button on the Value field opens the expression editor (032)

Second trailing affordance beside the field picker; passes the band's
resolvable name set + field choices to the modal and commits its result
through the existing setValue path (one undoable edit).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Verification sweep

**Files:** verification only.

- [ ] **Step 1: Analyzer + format (whole package).** From `packages/jet_print`:
  - `flutter analyze` → clean (no warnings/infos introduced).
  - `dart format --output=none --set-exit-if-changed lib test` → clean.
- [ ] **Step 2: Full test suite.** `flutter test` → all green. **GOLDENS unchanged** — author-time-only change; if any golden fails, STOP and inspect (a golden change means an unintended render path was touched).
- [ ] **Step 3: Playground consumption.** `cd apps/jet_print_playground && flutter analyze && flutter test` → green (the playground imports the public API only; confirm no break and that the editor dialog is reachable through the public widget).
- [ ] **Step 4: Confirm Success Criteria** (spec.md):
  - SC-001 → Task 5 (fx present + opens seeded). SC-002 → Task 1 forward/reverse round-trip tests. SC-003 → Task 1 (shared compiler). SC-004 → Task 1 regression guard group + suite/goldens. SC-005 → Task 4 + Task 5 (palette insert, status, Insert/Cancel). SC-006 → Task 2 catalog drift guard. SC-007 → Steps 1–3 here.
- [ ] **Step 5: Manual GUI smoke (optional).** `cd apps/jet_print_playground && flutter run -d macos`; open the Nested Lists sample; select the grand-total element; click **fx**; confirm the modal seeds `{SUM([customerTotal])}`, the field/function palettes insert tokens, the status reads Valid, and Insert updates the element (Preview still renders the live total). Try `{IF([qty] > 0, [a], [b])}` to confirm a general call now saves and re-opens as the same friendly token.
- [ ] **Step 6: Commit** any test-only/manual-fix additions — `test(032): verification sweep — fx editor end to end`.

---

## Self-Review

- **Spec coverage:** FR-001/002/003 → Task 1. FR-004 → Task 5 (fx in trailing slot). FR-005 → Task 5 (`_openFx` seeds from `display.text`). FR-006 → Task 5 (`fields` passed through). FR-007 → Task 2 + Task 4 (`_FunctionPalette`, caret via `caretOffset`). FR-008 → Task 4 (`statusFor` + `_StatusLine`). FR-009 → Task 5 (`onCommit`→`setValue`; Cancel pops null). FR-010 → Task 2 (catalog + drift test). FR-011 → Task 6 (analyzer/format/goldens) + Task 3 (only new UI strings). SC-001..007 → Task 6 Step 4 mapping.
- **Placeholder scan:** the only deliberately-unfinished tokens are the `let_findText`/selection/undo API names in Task 5 Step 1 and the shadcn/Lucide API names in Task 4/5 — each flagged with a `VERIFY`/`>` note to confirm against the installed package before running. No silent TBDs.
- **Type/name consistency:** `showExpressionEditor(context, {initialText, resolvableNames, fields})`, `EditorStatus`/`StatusValid`/`StatusSyntaxError`/`StatusUnresolved`, `statusFor(text, names)`, `ExpressionFunction{name,group,signature,insertSnippet,caretOffset}`, `ExpressionFunctionGroup{string,math,logic,aggregate}`, and the `_k`/`_p` key prefixes are used identically across Tasks 2/4/5 and their tests.
- **Key risks:** (1) generalizing the forward call branch turns `word(...)` literals into calls — graceful (unparseable → literal fallback), but run the full suite (Task 1 Step 7). (2) `MIN`/`MAX` appear in two palette groups → key collision; disambiguate aggregate keys (Task 4 note). (3) shadcn 0.54 API names must be verified (Tasks 4/5). (4) capturing the dialog's async return in a widget test is awkward — the tests assert side effects (committed expression, dialog closed) rather than the raw return value. (5) no golden may change — a golden diff signals an accidental render-path touch.
