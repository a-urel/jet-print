# Expression Engine — Core (spec 005a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `src/expression/` seam — a synchronous, headless expression language (value model → lexer → AST → parser → evaluator) plus a pluggable function registry and four built-in function families, evaluating expressions like `$F{qty} * $F{price}` and `FORMAT($F{total}, '#,##0.00')` against a `DataRow` + parameter map.

**Architecture:** The expression seam is the third inward ring (`expression → domain, data`; may import the data seam's `DataRow` and `intl` for formatting, but never Flutter/`dart:ui`/rendering/designer). The pipeline is four pure stages: **tokenize** (`String → List<Token>`), **parse** (`List<Token> → Expr` AST via recursive descent with C-like precedence), **evaluate** (`Expr × EvalContext → JetValue`). The value model is a **sealed `JetValue`** (null/bool/number/string/date/**error**) where numbers are always `double` and **errors are themselves values** — so the evaluator is one exhaustive, total `switch` with no `try/catch`: a bad operation yields a `JetError` that propagates up the tree (render-don't-crash, §7). Only *parse* errors throw (`ExpressionException`, a structural fault). A `JetFunctionRegistry` is the fourth engine extension point; `RowEvalContext` bridges the data seam (resolving `$F{}` from a `DataRow`, `$P{}` from a params map).

**Tech Stack:** Dart 3 sealed classes + exhaustive `switch` (already used for `JetImageSource`), `intl` (already a dependency) for `FORMAT`. No new package dependencies. Tests use `flutter_test` with absolute `package:jet_print/src/expression/...` imports (white-box seam tests).

---

## Design Decisions (settled before planning)

- **Scope = the language core.** This plan ships the per-row expression language + function registry + `$F{}`/`$P{}` references. The **aggregate/variable calculator** (SUM/COUNT/AVG, running totals, group resets) and the `ReportVariable`/`ReportGroup` domain types + `$V{}` references are deferred to a stacked **005b**. Each is independently shippable/testable (mirrors the 003 Part 1/Part 2 split). The lexer in 005a does NOT recognize `$V{}` — a `$V{...}` reference is a parse error until 005b.
- **All numbers are `double`.** The numeric value type is `JetNumber(double)`; an `int` field value lifts to `JetNumber(5.0)`. Arithmetic is double arithmetic; a `COUNT` or quantity renders `5.0` unless `FORMAT`-ted. (Simplest model; the user accepted the `5.0` tradeoff.)
- **Strict, non-throwing evaluation.** A null operand or type mismatch produces a `JetError` *value* (carrying a human-readable reason), which propagates and renders `!ERR` + a diagnostic at the render stage (007). The evaluator NEVER throws. A missing `$F{}`/`$P{}` reference resolves to `JetNull` (a warning at render, not an error). Division/modulo by zero is a `JetError`.
- **Parse errors DO throw** `ExpressionException` (structural fault, consistent with `ReportFormatException` and §7 "malformed → throw"). The parse/eval boundary IS the throw/value-error boundary.
- **Functions: Math, String, Logic, Format.** Built-ins ship in those four families; the registry is the public extension point (consumers register more). Function names are case-sensitive UPPERCASE by convention. Built-ins receive only non-error args (the evaluator auto-propagates any `JetError` argument before calling a function), so each built-in only validates types/arity.
- **No serialization in this seam.** Expressions are compiled at runtime from the strings already stored in elements (003); the seam adds no codecs. (An element storing an expression string is a 007 concern.)
- **Not exported from `jet_print.dart` yet.** Like the 003/004 seams, this stays under `src/` and is exercised by white-box tests; the facade export is batched later. The encapsulation allowlist is widened for `/test/expression/` (Task 1) and the layer-boundary test gains an `expression`-seam group (Task 14).

## Value & error model (reference — pinned semantics)

`JetValue` variants: `JetNull` (singleton-ish, all equal), `JetBool(bool)`, `JetNumber(double)`, `JetString(String)`, `JetDate(DateTime)`, `JetError(String message)`.

- **Lift** `JetValue.from(Object?)`: `null→JetNull`; `bool→JetBool`; `int/double/num→JetNumber(toDouble)`; `String→JetString`; `DateTime→JetDate`; an existing `JetValue→itself`; anything else `→JetError('Unsupported value type: <runtimeType>')`.
- **Arithmetic** `+ - * / %` (both `JetNumber`): double math; `/` and `%` with a `0` right operand → `JetError`. `+` with both `JetString` → concatenation. Any other operand combo (incl. null) → `JetError`.
- **Comparison** `== !=`: total over all types — different variants are unequal (never an error); `null == null` is `true`. `< <= > >=`: same orderable type only (`JetNumber`/`JetString`/`JetDate`); otherwise `JetError`.
- **Logical** `&& || !`: operands must be `JetBool` (else `JetError`); `&&`/`||` short-circuit on the left operand. `?:` ternary: condition must be `JetBool` (else `JetError`, branches not evaluated), then only the taken branch is evaluated.
- **Error propagation**: any binary/unary/ternary/call sub-expression that has a `JetError` operand yields a `JetError` (the first one encountered). This makes the evaluator total.

## File Structure

All library files: **pure Dart**, **relative imports** (ordered `dart:` → `package:` → relative, each alphabetical), **dartdoc on every public symbol**, value-type idioms from `src/domain/`/`src/data/`.

- Create: `packages/jet_print/lib/src/expression/value.dart` — sealed `JetValue` + variants + `JetValue.from` + `jetStringify`.
- Create: `packages/jet_print/lib/src/expression/expression_exception.dart` — `ExpressionException` (thrown on parse/lex errors).
- Create: `packages/jet_print/lib/src/expression/token.dart` — `TokenType` enum + `Token` (internal).
- Create: `packages/jet_print/lib/src/expression/lexer.dart` — `tokenize(String) → List<Token>` (internal).
- Create: `packages/jet_print/lib/src/expression/ast.dart` — sealed `Expr` nodes + canonical `toString` (internal).
- Create: `packages/jet_print/lib/src/expression/parser.dart` — `Parser` (tokens → `Expr`, recursive descent) (internal).
- Create: `packages/jet_print/lib/src/expression/function_registry.dart` — `JetExprFn` typedef + `JetFunctionRegistry`.
- Create: `packages/jet_print/lib/src/expression/eval_context.dart` — abstract `EvalContext` + `RowEvalContext` (bridges `data`).
- Create: `packages/jet_print/lib/src/expression/evaluator.dart` — `evaluate(Expr, EvalContext) → JetValue` (internal).
- Create: `packages/jet_print/lib/src/expression/expression.dart` — `Expression` facade (`parse` + `evaluate`).
- Create: `packages/jet_print/lib/src/expression/functions/math_functions.dart` — `registerMathFunctions`.
- Create: `packages/jet_print/lib/src/expression/functions/string_functions.dart` — `registerStringFunctions`.
- Create: `packages/jet_print/lib/src/expression/functions/logic_functions.dart` — `registerLogicFunctions`.
- Create: `packages/jet_print/lib/src/expression/functions/format_functions.dart` — `registerFormatFunctions` (uses `intl`).
- Create: `packages/jet_print/lib/src/expression/functions/built_in_functions.dart` — `registerBuiltInFunctions` (cascades all four).
- Modify: `packages/jet_print/test/encapsulation_test.dart` — allow `/test/expression/` white-box tests.
- Modify: `packages/jet_print/test/architecture/layer_boundaries_test.dart` — add an `expression`-seam group.
- Modify: `packages/jet_print/CHANGELOG.md` — spec-005a "Added" bullet.
- Tests under `packages/jet_print/test/expression/...` (one per task, see each task).

**Build order:** Task 1 widens the encapsulation allowlist first (so later `/test/expression/` files pass under the full suite). Tasks 2→13 build bottom-up: value model → tokens/lexer → AST/parser → context/registry → evaluator+facade → function families → integration. Task 14 adds the layer-boundary `expression` group last (non-vacuous once the seam has files) + CHANGELOG + full gate.

---

### Task 1: Seam guard — allow `/test/expression/` white-box tests

**Files:**
- Modify: `packages/jet_print/test/encapsulation_test.dart` (the `_isWhiteBoxSeamTest` function)

- [ ] **Step 1: Extend the white-box allowlist**

In `packages/jet_print/test/encapsulation_test.dart`, update the doc comment's first sentence and the `_isWhiteBoxSeamTest` body:

```dart
/// White-box seam tests legitimately import the library's own internals to
/// exercise the un-exported `domain`/`data`/`expression`/`rendering` types in
/// isolation (SC-004).
/// They are the package's OWN tests, not external consumers, so the `src` ban
/// (which protects external consumers per SC-007) does not apply to them. The
/// allowlist is intentionally narrow: every other test stays default-deny.
bool _isWhiteBoxSeamTest(File file) {
  final String path = file.path.replaceAll(r'\', '/');
  return path.contains('/test/domain/') ||
      path.contains('/test/data/') ||
      path.contains('/test/expression/') ||
      path.contains('/test/rendering/');
}
```

- [ ] **Step 2: Verify the encapsulation suite still passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/encapsulation_test.dart`
Expected: PASS (the allowlist widens; no `/test/expression/` files exist yet).

- [ ] **Step 3: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/test/encapsulation_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "test(expr): allow /test/expression white-box seam tests to import src"
```

---

### Task 2: `JetValue` model + lift + stringify

The sealed runtime value type. Numbers are always `double`; `JetError` is a value variant so it propagates through the evaluator. `JetValue.from` lifts a raw `Object?` (e.g. a `DataRow` field) into the model; `jetStringify` renders a value to text for `CONCAT`/display.

**Files:**
- Create: `packages/jet_print/lib/src/expression/value.dart`
- Test: `packages/jet_print/test/expression/value_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/value_test.dart`:

```dart
// JetValue sealed model: lift, equality, stringify (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/value.dart';

void main() {
  group('JetValue.from', () {
    test('lifts null/bool/int/double/String/DateTime', () {
      expect(JetValue.from(null), isA<JetNull>());
      expect(JetValue.from(true), const JetBool(true));
      expect(JetValue.from(5), const JetNumber(5)); // int -> double
      expect(JetValue.from(2.5), const JetNumber(2.5));
      expect(JetValue.from('hi'), const JetString('hi'));
      final DateTime d = DateTime(2026, 6, 7);
      expect(JetValue.from(d), JetDate(d));
    });

    test('is idempotent on an existing JetValue', () {
      expect(JetValue.from(const JetNumber(1)), const JetNumber(1));
    });

    test('maps an unsupported runtime type to a JetError', () {
      expect(JetValue.from(<int>[1]), isA<JetError>());
    });
  });

  group('JetValue equality', () {
    test('JetNull values are all equal', () {
      expect(const JetNull(), const JetNull());
      expect(const JetNull().hashCode, const JetNull().hashCode);
    });

    test('value variants compare by contained value', () {
      expect(const JetNumber(3), const JetNumber(3));
      expect(const JetNumber(3) == const JetNumber(4), isFalse);
      expect(const JetString('a') == const JetString('b'), isFalse);
      expect(const JetBool(true) == const JetBool(false), isFalse);
    });

    test('different variants are never equal', () {
      expect(const JetNumber(1) == const JetString('1'), isFalse);
      expect(const JetNull() == const JetBool(false), isFalse);
    });

    test('JetError compares by message', () {
      expect(const JetError('x'), const JetError('x'));
      expect(const JetError('x') == const JetError('y'), isFalse);
    });
  });

  group('jetStringify', () {
    test('renders each variant', () {
      expect(jetStringify(const JetNull()), '');
      expect(jetStringify(const JetBool(true)), 'true');
      expect(jetStringify(const JetNumber(5)), '5.0'); // all-double model
      expect(jetStringify(const JetString('hi')), 'hi');
      expect(jetStringify(JetDate(DateTime(2026, 6, 7))),
          DateTime(2026, 6, 7).toIso8601String());
      expect(jetStringify(const JetError('boom')), '!ERR');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/value_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jet_print/src/expression/value.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/value.dart`:

```dart
/// The runtime value model of the expression engine (spec 005a).
///
/// [JetValue] is a sealed type with one variant per supported value kind, plus
/// a [JetError] variant. Errors are values: a failed operation yields a
/// [JetError] that propagates through the evaluator, so evaluation never throws
/// (render-don't-crash). Numbers are always `double` (the all-double model).
library;

/// A runtime expression value.
sealed class JetValue {
  const JetValue();

  /// Lifts a raw Dart value (e.g. a `DataRow` field) into a [JetValue].
  ///
  /// `null`→[JetNull]; `bool`→[JetBool]; `int`/`double`→[JetNumber] (ints widen
  /// to `double`); `String`→[JetString]; `DateTime`→[JetDate]; an existing
  /// [JetValue] is returned unchanged. Any other runtime type yields a
  /// [JetError] (the strict model surfaces unsupported data rather than
  /// guessing).
  factory JetValue.from(Object? raw) {
    if (raw is JetValue) return raw;
    if (raw == null) return const JetNull();
    if (raw is bool) return JetBool(raw);
    if (raw is num) return JetNumber(raw.toDouble());
    if (raw is String) return JetString(raw);
    if (raw is DateTime) return JetDate(raw);
    return JetError('Unsupported value type: ${raw.runtimeType}');
  }
}

/// The absence of a value.
final class JetNull extends JetValue {
  /// Creates the null value.
  const JetNull();

  @override
  bool operator ==(Object other) => other is JetNull;

  @override
  int get hashCode => (JetNull).hashCode;

  @override
  String toString() => 'JetNull()';
}

/// A boolean value.
final class JetBool extends JetValue {
  /// Creates a boolean value.
  const JetBool(this.value);

  /// The wrapped boolean.
  final bool value;

  @override
  bool operator ==(Object other) => other is JetBool && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'JetBool($value)';
}

/// A numeric value. Always `double` (the all-double model).
final class JetNumber extends JetValue {
  /// Creates a numeric value.
  const JetNumber(this.value);

  /// The wrapped number.
  final double value;

  @override
  bool operator ==(Object other) => other is JetNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'JetNumber($value)';
}

/// A string value.
final class JetString extends JetValue {
  /// Creates a string value.
  const JetString(this.value);

  /// The wrapped string.
  final String value;

  @override
  bool operator ==(Object other) => other is JetString && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'JetString($value)';
}

/// A timestamp value.
final class JetDate extends JetValue {
  /// Creates a timestamp value.
  const JetDate(this.value);

  /// The wrapped timestamp.
  final DateTime value;

  @override
  bool operator ==(Object other) => other is JetDate && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'JetDate($value)';
}

/// A failed evaluation, carrying a human-readable [message].
///
/// A value, not an exception: it propagates through the evaluator and is
/// rendered as `!ERR` (plus a diagnostic) by the render stage.
final class JetError extends JetValue {
  /// Creates an error value with the given [message].
  const JetError(this.message);

  /// Why evaluation failed.
  final String message;

  @override
  bool operator ==(Object other) => other is JetError && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'JetError($message)';
}

/// Renders a [JetValue] to display text (used by `CONCAT` and direct display).
///
/// [JetNull]→`''`; [JetBool]→`'true'`/`'false'`; [JetNumber]→`double.toString()`
/// (so `5.0` prints `5.0` — use `FORMAT` for presentation); [JetString]→its
/// text; [JetDate]→ISO 8601; [JetError]→`'!ERR'`.
String jetStringify(JetValue value) => switch (value) {
      JetNull() => '',
      JetBool(value: final bool v) => v.toString(),
      JetNumber(value: final double v) => v.toString(),
      JetString(value: final String v) => v,
      JetDate(value: final DateTime v) => v.toIso8601String(),
      JetError() => '!ERR',
    };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/value_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: analyzer `No issues found!` (re-run the test if the formatter reflows anything).

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/value.dart packages/jet_print/test/expression/value_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add sealed JetValue model with lift and stringify"
```

---

### Task 3: `ExpressionException` + tokens

The structural-error type thrown on lex/parse failures, and the token vocabulary the lexer emits / the parser consumes.

**Files:**
- Create: `packages/jet_print/lib/src/expression/expression_exception.dart`
- Create: `packages/jet_print/lib/src/expression/token.dart`
- Test: `packages/jet_print/test/expression/token_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/token_test.dart`:

```dart
// Token vocabulary + ExpressionException (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression_exception.dart';
import 'package:jet_print/src/expression/token.dart';

void main() {
  test('ExpressionException carries a message and is an Exception', () {
    const ExpressionException e = ExpressionException('bad');
    expect(e, isA<Exception>());
    expect(e.message, 'bad');
    expect(e.toString(), contains('bad'));
  });

  test('Token exposes type, lexeme and optional literal', () {
    const Token t = Token(TokenType.number, '5', 5.0);
    expect(t.type, TokenType.number);
    expect(t.lexeme, '5');
    expect(t.literal, 5.0);
    expect(t.toString(), contains('number'));
  });

  test('TokenType enumerates the operator and literal kinds', () {
    // A representative spread — the lexer/parser depend on these existing.
    expect(TokenType.values, containsAll(<TokenType>[
      TokenType.number,
      TokenType.string,
      TokenType.fieldRef,
      TokenType.paramRef,
      TokenType.identifier,
      TokenType.plus,
      TokenType.andAnd,
      TokenType.question,
      TokenType.eof,
    ]));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/token_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/expression_exception.dart`:

```dart
/// Thrown when an expression string cannot be lexed or parsed (spec 005a).
///
/// A *structural* fault (malformed syntax), thrown at compile time — distinct
/// from a runtime evaluation failure, which is a [JetError] value rather than an
/// exception. Mirrors the domain's `ReportFormatException` policy.
library;

/// Signals a malformed expression (lex or parse error).
class ExpressionException implements Exception {
  /// Creates an exception describing why the expression is malformed.
  const ExpressionException(this.message);

  /// Human-readable description of the fault.
  final String message;

  @override
  String toString() => 'ExpressionException: $message';
}
```

Create `packages/jet_print/lib/src/expression/token.dart`:

```dart
/// Lexical tokens for the expression language (spec 005a). Internal to the
/// expression seam — not part of the public API.
library;

/// The kind of a lexical [Token].
enum TokenType {
  /// A numeric literal, e.g. `5` or `2.5` (literal is a `double`).
  number,

  /// A string literal, e.g. `'hi'` (literal is a `String`).
  string,

  /// The keyword `true`.
  trueLiteral,

  /// The keyword `false`.
  falseLiteral,

  /// The keyword `null`.
  nullLiteral,

  /// A field reference `$F{name}` (literal is the field name `String`).
  fieldRef,

  /// A parameter reference `$P{name}` (literal is the param name `String`).
  paramRef,

  /// A bare identifier (a function name), e.g. `ROUND`.
  identifier,

  /// `+`
  plus,

  /// `-`
  minus,

  /// `*`
  star,

  /// `/`
  slash,

  /// `%`
  percent,

  /// `==`
  equalEqual,

  /// `!=`
  bangEqual,

  /// `<`
  less,

  /// `<=`
  lessEqual,

  /// `>`
  greater,

  /// `>=`
  greaterEqual,

  /// `&&`
  andAnd,

  /// `||`
  orOr,

  /// `!`
  bang,

  /// `?`
  question,

  /// `:`
  colon,

  /// `,`
  comma,

  /// `(`
  leftParen,

  /// `)`
  rightParen,

  /// End of input.
  eof,
}

/// A lexical token: its [type], source [lexeme], and an optional decoded
/// [literal] (a `double` for numbers, a `String` for strings/field/param refs).
class Token {
  /// Creates a token.
  const Token(this.type, this.lexeme, [this.literal]);

  /// The token kind.
  final TokenType type;

  /// The exact source text of the token.
  final String lexeme;

  /// The decoded literal value, if any (number → `double`; string/ref → name).
  final Object? literal;

  @override
  String toString() => 'Token(${type.name}, "$lexeme"'
      '${literal == null ? '' : ', $literal'})';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/token_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/expression_exception.dart packages/jet_print/lib/src/expression/token.dart packages/jet_print/test/expression/token_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add ExpressionException and token vocabulary"
```

---

### Task 4: Lexer (`tokenize`)

Scans an expression string into tokens: `$F{...}`/`$P{...}` refs, number/string/bool/null literals, identifiers, and one- or two-character operators. Throws `ExpressionException` on an unexpected character or an unterminated string/reference.

**Files:**
- Create: `packages/jet_print/lib/src/expression/lexer.dart`
- Test: `packages/jet_print/test/expression/lexer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/lexer_test.dart`:

```dart
// Lexer: String -> List<Token> (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression_exception.dart';
import 'package:jet_print/src/expression/lexer.dart';
import 'package:jet_print/src/expression/token.dart';

List<TokenType> _types(String src) =>
    tokenize(src).map((Token t) => t.type).toList();

void main() {
  group('tokenize', () {
    test('emits an eof token for empty input', () {
      expect(_types(''), <TokenType>[TokenType.eof]);
    });

    test('lexes field and param references with their names', () {
      final List<Token> tokens = tokenize(r'$F{qty} $P{tax}');
      expect(tokens[0].type, TokenType.fieldRef);
      expect(tokens[0].literal, 'qty');
      expect(tokens[1].type, TokenType.paramRef);
      expect(tokens[1].literal, 'tax');
      expect(tokens.last.type, TokenType.eof);
    });

    test('lexes number literals as doubles', () {
      expect(tokenize('5').first.literal, 5.0);
      expect(tokenize('2.5').first.literal, 2.5);
    });

    test('lexes single- and double-quoted strings with escapes', () {
      expect(tokenize("'hi'").first.literal, 'hi');
      expect(tokenize('"a\\"b"').first.literal, 'a"b');
    });

    test('lexes boolean and null keywords', () {
      expect(_types('true false null'),
          <TokenType>[TokenType.trueLiteral, TokenType.falseLiteral,
              TokenType.nullLiteral, TokenType.eof]);
    });

    test('lexes identifiers (function names)', () {
      final Token t = tokenize('ROUND').first;
      expect(t.type, TokenType.identifier);
      expect(t.lexeme, 'ROUND');
    });

    test('lexes one- and two-character operators', () {
      expect(_types('+ - * / % == != < <= > >= && || ! ? : , ( )'),
          <TokenType>[
            TokenType.plus, TokenType.minus, TokenType.star, TokenType.slash,
            TokenType.percent, TokenType.equalEqual, TokenType.bangEqual,
            TokenType.less, TokenType.lessEqual, TokenType.greater,
            TokenType.greaterEqual, TokenType.andAnd, TokenType.orOr,
            TokenType.bang, TokenType.question, TokenType.colon, TokenType.comma,
            TokenType.leftParen, TokenType.rightParen, TokenType.eof,
          ]);
    });

    test('skips whitespace between tokens', () {
      expect(_types('  5\t+\n6 '), <TokenType>[
        TokenType.number, TokenType.plus, TokenType.number, TokenType.eof,
      ]);
    });

    test('throws on an unterminated string', () {
      expect(() => tokenize("'oops"), throwsA(isA<ExpressionException>()));
    });

    test('throws on an unterminated reference', () {
      expect(() => tokenize(r'$F{qty'), throwsA(isA<ExpressionException>()));
    });

    test('throws on an unexpected character', () {
      expect(() => tokenize('5 @ 6'), throwsA(isA<ExpressionException>()));
    });

    test('throws on a bad reference sigil (e.g. unsupported \$V in 005a)', () {
      expect(() => tokenize(r'$V{total}'), throwsA(isA<ExpressionException>()));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/lexer_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/lexer.dart`:

```dart
/// The expression lexer: turns a source string into a list of [Token]s
/// (spec 005a). Internal to the expression seam.
library;

import 'expression_exception.dart';
import 'token.dart';

/// Tokenizes [source] into a list ending with a [TokenType.eof] token.
///
/// Throws [ExpressionException] on an unterminated string/reference or an
/// unexpected character. In 005a only `$F{...}` and `$P{...}` references are
/// recognized; any other `$X{...}` sigil (e.g. `$V`) is an error.
List<Token> tokenize(String source) => _Lexer(source).scanAll();

class _Lexer {
  _Lexer(this._src);

  final String _src;
  int _pos = 0;
  final List<Token> _tokens = <Token>[];

  List<Token> scanAll() {
    while (!_isAtEnd) {
      _skipWhitespace();
      if (_isAtEnd) break;
      _scanToken();
    }
    _tokens.add(const Token(TokenType.eof, ''));
    return _tokens;
  }

  bool get _isAtEnd => _pos >= _src.length;
  String get _peek => _src[_pos];
  String _peekAt(int offset) =>
      _pos + offset < _src.length ? _src[_pos + offset] : '';

  void _skipWhitespace() {
    while (!_isAtEnd && _peek.trim().isEmpty) {
      _pos++;
    }
  }

  void _scanToken() {
    final String c = _peek;
    if (c == r'$') {
      _scanReference();
    } else if (_isDigit(c) || (c == '.' && _isDigit(_peekAt(1)))) {
      _scanNumber();
    } else if (c == "'" || c == '"') {
      _scanString(c);
    } else if (_isAlpha(c)) {
      _scanIdentifier();
    } else {
      _scanOperator();
    }
  }

  void _scanReference() {
    // $F{name} or $P{name}
    final String sigil = _peekAt(1);
    final TokenType type;
    if (sigil == 'F') {
      type = TokenType.fieldRef;
    } else if (sigil == 'P') {
      type = TokenType.paramRef;
    } else {
      throw ExpressionException(
        'Unsupported reference "\$$sigil" at position $_pos '
        '(expected \$F{...} or \$P{...})',
      );
    }
    if (_peekAt(2) != '{') {
      throw ExpressionException('Expected "{" after "\$$sigil" at position $_pos');
    }
    final int start = _pos;
    _pos += 3; // consume $, sigil, {
    final StringBuffer name = StringBuffer();
    while (!_isAtEnd && _peek != '}') {
      name.write(_peek);
      _pos++;
    }
    if (_isAtEnd) {
      throw ExpressionException('Unterminated reference starting at $start');
    }
    _pos++; // consume }
    _tokens.add(Token(type, _src.substring(start, _pos), name.toString()));
  }

  void _scanNumber() {
    final int start = _pos;
    while (!_isAtEnd && _isDigit(_peek)) {
      _pos++;
    }
    if (!_isAtEnd && _peek == '.' && _isDigit(_peekAt(1))) {
      _pos++; // consume .
      while (!_isAtEnd && _isDigit(_peek)) {
        _pos++;
      }
    }
    final String lexeme = _src.substring(start, _pos);
    _tokens.add(Token(TokenType.number, lexeme, double.parse(lexeme)));
  }

  void _scanString(String quote) {
    final int start = _pos;
    _pos++; // consume opening quote
    final StringBuffer value = StringBuffer();
    while (!_isAtEnd && _peek != quote) {
      if (_peek == r'\') {
        _pos++;
        if (_isAtEnd) break;
        final String esc = _peek;
        value.write(switch (esc) {
          'n' => '\n',
          't' => '\t',
          r'\' => r'\',
          "'" => "'",
          '"' => '"',
          _ => esc,
        });
        _pos++;
      } else {
        value.write(_peek);
        _pos++;
      }
    }
    if (_isAtEnd) {
      throw ExpressionException('Unterminated string starting at $start');
    }
    _pos++; // consume closing quote
    _tokens.add(
        Token(TokenType.string, _src.substring(start, _pos), value.toString()));
  }

  void _scanIdentifier() {
    final int start = _pos;
    while (!_isAtEnd && _isAlphaNumeric(_peek)) {
      _pos++;
    }
    final String lexeme = _src.substring(start, _pos);
    final TokenType type = switch (lexeme) {
      'true' => TokenType.trueLiteral,
      'false' => TokenType.falseLiteral,
      'null' => TokenType.nullLiteral,
      _ => TokenType.identifier,
    };
    _tokens.add(Token(type, lexeme));
  }

  void _scanOperator() {
    final String c = _peek;
    final String next = _peekAt(1);
    Token two(TokenType t) => Token(t, _src.substring(_pos, _pos + 2));
    Token one(TokenType t) => Token(t, c);

    final Token token;
    switch (c) {
      case '+':
        token = one(TokenType.plus);
      case '-':
        token = one(TokenType.minus);
      case '*':
        token = one(TokenType.star);
      case '/':
        token = one(TokenType.slash);
      case '%':
        token = one(TokenType.percent);
      case ',':
        token = one(TokenType.comma);
      case '(':
        token = one(TokenType.leftParen);
      case ')':
        token = one(TokenType.rightParen);
      case '?':
        token = one(TokenType.question);
      case ':':
        token = one(TokenType.colon);
      case '=' when next == '=':
        token = two(TokenType.equalEqual);
      case '!' when next == '=':
        token = two(TokenType.bangEqual);
      case '!':
        token = one(TokenType.bang);
      case '<' when next == '=':
        token = two(TokenType.lessEqual);
      case '<':
        token = one(TokenType.less);
      case '>' when next == '=':
        token = two(TokenType.greaterEqual);
      case '>':
        token = one(TokenType.greater);
      case '&' when next == '&':
        token = two(TokenType.andAnd);
      case '|' when next == '|':
        token = two(TokenType.orOr);
      default:
        throw ExpressionException(
            'Unexpected character "$c" at position $_pos');
    }
    _pos += token.lexeme.length;
    _tokens.add(token);
  }

  static bool _isDigit(String c) => c.isNotEmpty && c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  static bool _isAlpha(String c) {
    if (c.isEmpty) return false;
    final int u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || c == '_';
  }
  static bool _isAlphaNumeric(String c) => _isAlpha(c) || _isDigit(c);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/lexer_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/lexer.dart packages/jet_print/test/expression/lexer_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add lexer (tokenize)"
```

---

### Task 5: AST nodes (`Expr`)

The sealed AST the parser builds and the evaluator walks. Each node carries a canonical `toString` (an S-expression) so the parser can be tested by inspecting structure without an evaluator.

**Files:**
- Create: `packages/jet_print/lib/src/expression/ast.dart`
- Test: `packages/jet_print/test/expression/ast_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/ast_test.dart`:

```dart
// AST nodes + canonical toString (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/ast.dart';
import 'package:jet_print/src/expression/value.dart';

void main() {
  test('nodes render a canonical S-expression', () {
    // (qty * price)  ->  (* (field qty) (field price))
    final Expr e = BinaryExpr(
      BinaryOp.multiply,
      FieldRefExpr('qty'),
      FieldRefExpr('price'),
    );
    expect(e.toString(), '(* (field qty) (field price))');
  });

  test('literal, param, unary, conditional and call render canonically', () {
    expect(LiteralExpr(const JetNumber(5)).toString(), '5.0');
    expect(ParamRefExpr('tax').toString(), '(param tax)');
    expect(UnaryExpr(UnaryOp.negate, LiteralExpr(const JetNumber(1))).toString(),
        '(- 1.0)');
    expect(
        ConditionalExpr(LiteralExpr(const JetBool(true)),
                LiteralExpr(const JetNumber(1)), LiteralExpr(const JetNumber(2)))
            .toString(),
        '(if true 1.0 2.0)');
    expect(
        CallExpr('ROUND',
            <Expr>[FieldRefExpr('x'), LiteralExpr(const JetNumber(2))]).toString(),
        '(call ROUND (field x) 2.0)');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/ast_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/ast.dart`:

```dart
/// The expression abstract syntax tree (spec 005a). Internal to the expression
/// seam: the parser builds these nodes and the evaluator walks them.
library;

import 'value.dart';

/// A unary operator.
enum UnaryOp {
  /// Arithmetic negation `-x`.
  negate,

  /// Logical not `!x`.
  not,
}

/// A binary operator.
enum BinaryOp {
  /// `+`
  add,

  /// `-`
  subtract,

  /// `*`
  multiply,

  /// `/`
  divide,

  /// `%`
  modulo,

  /// `==`
  equal,

  /// `!=`
  notEqual,

  /// `<`
  less,

  /// `<=`
  lessEqual,

  /// `>`
  greater,

  /// `>=`
  greaterEqual,

  /// `&&`
  and,

  /// `||`
  or,
}

/// A node in the expression AST.
sealed class Expr {
  const Expr();
}

/// A constant literal value.
final class LiteralExpr extends Expr {
  /// Creates a literal node.
  const LiteralExpr(this.value);

  /// The literal value.
  final JetValue value;

  @override
  String toString() => value is JetString
      ? "'${(value as JetString).value}'"
      : jetStringify(value);
}

/// A field reference `$F{name}`.
final class FieldRefExpr extends Expr {
  /// Creates a field reference node.
  const FieldRefExpr(this.name);

  /// The field name.
  final String name;

  @override
  String toString() => '(field $name)';
}

/// A parameter reference `$P{name}`.
final class ParamRefExpr extends Expr {
  /// Creates a parameter reference node.
  const ParamRefExpr(this.name);

  /// The parameter name.
  final String name;

  @override
  String toString() => '(param $name)';
}

/// A unary operation.
final class UnaryExpr extends Expr {
  /// Creates a unary node.
  const UnaryExpr(this.op, this.operand);

  /// The operator.
  final UnaryOp op;

  /// The operand.
  final Expr operand;

  @override
  String toString() => '(${_unarySymbol(op)} $operand)';
}

/// A binary operation.
final class BinaryExpr extends Expr {
  /// Creates a binary node.
  const BinaryExpr(this.op, this.left, this.right);

  /// The operator.
  final BinaryOp op;

  /// The left operand.
  final Expr left;

  /// The right operand.
  final Expr right;

  @override
  String toString() => '(${_binarySymbol(op)} $left $right)';
}

/// A conditional `cond ? then : otherwise`.
final class ConditionalExpr extends Expr {
  /// Creates a conditional node.
  const ConditionalExpr(this.condition, this.thenBranch, this.elseBranch);

  /// The boolean condition.
  final Expr condition;

  /// The value when the condition is true.
  final Expr thenBranch;

  /// The value when the condition is false.
  final Expr elseBranch;

  @override
  String toString() => '(if $condition $thenBranch $elseBranch)';
}

/// A function call `NAME(args...)`.
final class CallExpr extends Expr {
  /// Creates a call node.
  const CallExpr(this.name, this.arguments);

  /// The function name.
  final String name;

  /// The argument expressions.
  final List<Expr> arguments;

  @override
  String toString() =>
      '(call $name${arguments.map((Expr a) => ' $a').join()})';
}

String _unarySymbol(UnaryOp op) => switch (op) {
      UnaryOp.negate => '-',
      UnaryOp.not => '!',
    };

String _binarySymbol(BinaryOp op) => switch (op) {
      BinaryOp.add => '+',
      BinaryOp.subtract => '-',
      BinaryOp.multiply => '*',
      BinaryOp.divide => '/',
      BinaryOp.modulo => '%',
      BinaryOp.equal => '==',
      BinaryOp.notEqual => '!=',
      BinaryOp.less => '<',
      BinaryOp.lessEqual => '<=',
      BinaryOp.greater => '>',
      BinaryOp.greaterEqual => '>=',
      BinaryOp.and => '&&',
      BinaryOp.or => '||',
    };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/ast_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/ast.dart packages/jet_print/test/expression/ast_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add AST nodes with canonical toString"
```

---

### Task 6: Parser (recursive descent)

Turns tokens into an `Expr` AST with C-like precedence (lowest→highest: ternary → `||` → `&&` → equality → comparison → additive → multiplicative → unary → primary). Throws `ExpressionException` on syntax errors. Tested via the AST's canonical `toString`.

**Files:**
- Create: `packages/jet_print/lib/src/expression/parser.dart`
- Test: `packages/jet_print/test/expression/parser_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/parser_test.dart`:

```dart
// Parser: tokens -> Expr, tested via canonical toString (spec 005a).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression_exception.dart';
import 'package:jet_print/src/expression/lexer.dart';
import 'package:jet_print/src/expression/parser.dart';

String _parse(String src) => Parser(tokenize(src)).parseExpression().toString();

void main() {
  group('Parser', () {
    test('parses a primary literal/reference', () {
      expect(_parse('5'), '5.0');
      expect(_parse(r'$F{qty}'), '(field qty)');
      expect(_parse(r'$P{tax}'), '(param tax)');
      expect(_parse("'hi'"), "'hi'");
      expect(_parse('true'), 'true');
      expect(_parse('null'), 'JetNull()');
    });

    test('multiplicative binds tighter than additive', () {
      expect(_parse('1 + 2 * 3'), '(+ 1.0 (* 2.0 3.0))');
    });

    test('parentheses override precedence', () {
      expect(_parse('(1 + 2) * 3'), '(* (+ 1.0 2.0) 3.0)');
    });

    test('left-associates same-precedence operators', () {
      expect(_parse('1 - 2 - 3'), '(- (- 1.0 2.0) 3.0)');
    });

    test('parses unary minus and not', () {
      expect(_parse('-5'), '(- 5.0)');
      expect(_parse('!true'), '(! true)');
    });

    test('comparison and equality precedence', () {
      expect(_parse('1 < 2 == true'), '(== (< 1.0 2.0) true)');
    });

    test('logical and binds tighter than or', () {
      expect(_parse('a() || b() && c()'),
          '(|| (call a) (&& (call b) (call c)))');
    });

    test('ternary is lowest precedence and right-associative', () {
      expect(_parse('true ? 1 : false ? 2 : 3'),
          '(if true 1.0 (if false 2.0 3.0))');
    });

    test('parses function calls with zero, one and many args', () {
      expect(_parse('NOW()'), '(call NOW)');
      expect(_parse('ABS(-5)'), '(call ABS (- 5.0))');
      expect(_parse('MAX(1, 2, 3)'), '(call MAX 1.0 2.0 3.0)');
    });

    test('parses a realistic expression', () {
      expect(_parse(r'ROUND($F{qty} * $F{price}, 2)'),
          '(call ROUND (* (field qty) (field price)) 2.0)');
    });

    test('throws on a trailing operator', () {
      expect(() => _parse('1 +'), throwsA(isA<ExpressionException>()));
    });

    test('throws on an unbalanced parenthesis', () {
      expect(() => _parse('(1 + 2'), throwsA(isA<ExpressionException>()));
    });

    test('throws on trailing tokens after a complete expression', () {
      expect(() => _parse('1 2'), throwsA(isA<ExpressionException>()));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/parser_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/parser.dart`:

```dart
/// The expression parser: recursive descent over [Token]s producing an [Expr]
/// AST (spec 005a). Internal to the expression seam.
library;

import 'ast.dart';
import 'expression_exception.dart';
import 'token.dart';
import 'value.dart';

/// Parses a token stream into an [Expr] tree.
///
/// Grammar (lowest to highest precedence):
/// `ternary → or → and → equality → comparison → additive → multiplicative →
/// unary → primary`. Throws [ExpressionException] on any syntax error,
/// including tokens left over after a complete expression.
class Parser {
  /// Creates a parser over [_tokens] (which must end with a [TokenType.eof]).
  Parser(this._tokens);

  final List<Token> _tokens;
  int _pos = 0;

  Token get _peek => _tokens[_pos];
  Token get _previous => _tokens[_pos - 1];
  bool get _isAtEnd => _peek.type == TokenType.eof;

  /// Parses a single complete expression, requiring all input to be consumed.
  Expr parseExpression() {
    final Expr expr = _ternary();
    if (!_isAtEnd) {
      throw ExpressionException(
          'Unexpected token "${_peek.lexeme}" after expression');
    }
    return expr;
  }

  bool _match(TokenType type) {
    if (_peek.type == type) {
      _pos++;
      return true;
    }
    return false;
  }

  Token _consume(TokenType type, String message) {
    if (_peek.type == type) {
      _pos++;
      return _previous;
    }
    throw ExpressionException('$message (got "${_peek.lexeme}")');
  }

  Expr _ternary() {
    final Expr condition = _or();
    if (_match(TokenType.question)) {
      final Expr thenBranch = _ternary();
      _consume(TokenType.colon, 'Expected ":" in conditional');
      final Expr elseBranch = _ternary();
      return ConditionalExpr(condition, thenBranch, elseBranch);
    }
    return condition;
  }

  Expr _or() {
    Expr expr = _and();
    while (_match(TokenType.orOr)) {
      expr = BinaryExpr(BinaryOp.or, expr, _and());
    }
    return expr;
  }

  Expr _and() {
    Expr expr = _equality();
    while (_match(TokenType.andAnd)) {
      expr = BinaryExpr(BinaryOp.and, expr, _equality());
    }
    return expr;
  }

  Expr _equality() {
    Expr expr = _comparison();
    while (true) {
      if (_match(TokenType.equalEqual)) {
        expr = BinaryExpr(BinaryOp.equal, expr, _comparison());
      } else if (_match(TokenType.bangEqual)) {
        expr = BinaryExpr(BinaryOp.notEqual, expr, _comparison());
      } else {
        return expr;
      }
    }
  }

  Expr _comparison() {
    Expr expr = _additive();
    while (true) {
      if (_match(TokenType.less)) {
        expr = BinaryExpr(BinaryOp.less, expr, _additive());
      } else if (_match(TokenType.lessEqual)) {
        expr = BinaryExpr(BinaryOp.lessEqual, expr, _additive());
      } else if (_match(TokenType.greater)) {
        expr = BinaryExpr(BinaryOp.greater, expr, _additive());
      } else if (_match(TokenType.greaterEqual)) {
        expr = BinaryExpr(BinaryOp.greaterEqual, expr, _additive());
      } else {
        return expr;
      }
    }
  }

  Expr _additive() {
    Expr expr = _multiplicative();
    while (true) {
      if (_match(TokenType.plus)) {
        expr = BinaryExpr(BinaryOp.add, expr, _multiplicative());
      } else if (_match(TokenType.minus)) {
        expr = BinaryExpr(BinaryOp.subtract, expr, _multiplicative());
      } else {
        return expr;
      }
    }
  }

  Expr _multiplicative() {
    Expr expr = _unary();
    while (true) {
      if (_match(TokenType.star)) {
        expr = BinaryExpr(BinaryOp.multiply, expr, _unary());
      } else if (_match(TokenType.slash)) {
        expr = BinaryExpr(BinaryOp.divide, expr, _unary());
      } else if (_match(TokenType.percent)) {
        expr = BinaryExpr(BinaryOp.modulo, expr, _unary());
      } else {
        return expr;
      }
    }
  }

  Expr _unary() {
    if (_match(TokenType.minus)) {
      return UnaryExpr(UnaryOp.negate, _unary());
    }
    if (_match(TokenType.bang)) {
      return UnaryExpr(UnaryOp.not, _unary());
    }
    return _primary();
  }

  Expr _primary() {
    final Token token = _peek;
    switch (token.type) {
      case TokenType.number:
        _pos++;
        return LiteralExpr(JetNumber(token.literal! as double));
      case TokenType.string:
        _pos++;
        return LiteralExpr(JetString(token.literal! as String));
      case TokenType.trueLiteral:
        _pos++;
        return const LiteralExpr(JetBool(true));
      case TokenType.falseLiteral:
        _pos++;
        return const LiteralExpr(JetBool(false));
      case TokenType.nullLiteral:
        _pos++;
        return const LiteralExpr(JetNull());
      case TokenType.fieldRef:
        _pos++;
        return FieldRefExpr(token.literal! as String);
      case TokenType.paramRef:
        _pos++;
        return ParamRefExpr(token.literal! as String);
      case TokenType.identifier:
        return _call();
      case TokenType.leftParen:
        _pos++;
        final Expr expr = _ternary();
        _consume(TokenType.rightParen, 'Expected ")" after expression');
        return expr;
      default:
        throw ExpressionException(
            'Expected an expression but found "${token.lexeme}"');
    }
  }

  Expr _call() {
    final String name = _consume(TokenType.identifier, 'Expected a name').lexeme;
    _consume(TokenType.leftParen, 'Expected "(" after function name "$name"');
    final List<Expr> args = <Expr>[];
    if (_peek.type != TokenType.rightParen) {
      args.add(_ternary());
      while (_match(TokenType.comma)) {
        args.add(_ternary());
      }
    }
    _consume(TokenType.rightParen, 'Expected ")" after arguments to "$name"');
    return CallExpr(name, args);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/parser_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/parser.dart packages/jet_print/test/expression/parser_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add recursive-descent parser"
```

---

### Task 7: `EvalContext` + function registry + `RowEvalContext`

The evaluation environment: resolves `$F{}`/`$P{}` references to `JetValue`s and provides the function registry. `RowEvalContext` bridges the `data` seam — fields from a `DataRow`, params from a map — and is where the `expression → data` dependency lives.

**Files:**
- Create: `packages/jet_print/lib/src/expression/function_registry.dart`
- Create: `packages/jet_print/lib/src/expression/eval_context.dart`
- Test: `packages/jet_print/test/expression/eval_context_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/eval_context_test.dart`:

```dart
// EvalContext + function registry + RowEvalContext (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

DataRow _row() => DataRow(
      fields: const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('note', type: JetFieldType.string),
      ],
      values: <String, Object?>{'qty': 3, 'note': null},
    );

void main() {
  group('JetFunctionRegistry', () {
    test('registers and looks up functions; unknown is null', () {
      final JetFunctionRegistry r = JetFunctionRegistry();
      JetValue fn(List<JetValue> a, EvalContext c) => const JetNumber(42);
      r.register('ANSWER', fn);
      expect(r.lookup('ANSWER'), same(fn));
      expect(r.lookup('MISSING'), isNull);
    });

    test('register overwrites an existing name', () {
      final JetFunctionRegistry r = JetFunctionRegistry();
      r.register('F', (List<JetValue> a, EvalContext c) => const JetNumber(1));
      r.register('F', (List<JetValue> a, EvalContext c) => const JetNumber(2));
      expect(r.lookup('F')!(<JetValue>[], _CtxStub()), const JetNumber(2));
    });
  });

  group('RowEvalContext', () {
    test('resolves a field to its lifted value (int -> JetNumber)', () {
      final RowEvalContext ctx =
          RowEvalContext(row: _row(), functions: JetFunctionRegistry());
      expect(ctx.resolveField('qty'), const JetNumber(3));
    });

    test('resolves a declared-null field to JetNull', () {
      final RowEvalContext ctx =
          RowEvalContext(row: _row(), functions: JetFunctionRegistry());
      expect(ctx.resolveField('note'), const JetNull());
    });

    test('resolves a missing field to JetNull (render-blank policy)', () {
      final RowEvalContext ctx =
          RowEvalContext(row: _row(), functions: JetFunctionRegistry());
      expect(ctx.resolveField('absent'), const JetNull());
    });

    test('resolves params from the map; missing param is JetNull', () {
      final RowEvalContext ctx = RowEvalContext(
        row: _row(),
        params: <String, Object?>{'tax': 0.2},
        functions: JetFunctionRegistry(),
      );
      expect(ctx.resolveParam('tax'), const JetNumber(0.2));
      expect(ctx.resolveParam('missing'), const JetNull());
    });

    test('resolves fields to JetNull when there is no row', () {
      final RowEvalContext ctx =
          RowEvalContext(functions: JetFunctionRegistry());
      expect(ctx.resolveField('qty'), const JetNull());
    });

    test('exposes its function registry', () {
      final JetFunctionRegistry r = JetFunctionRegistry();
      expect(RowEvalContext(functions: r).functions, same(r));
    });
  });
}

class _CtxStub implements EvalContext {
  @override
  JetFunctionRegistry get functions => JetFunctionRegistry();
  @override
  JetValue resolveField(String name) => const JetNull();
  @override
  JetValue resolveParam(String name) => const JetNull();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/eval_context_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/function_registry.dart`:

```dart
/// The expression function registry — engine extension point #4 (spec 005a).
library;

import 'eval_context.dart';
import 'value.dart';

/// A callable expression function: receives already-evaluated [args] and the
/// [context], and returns a [JetValue].
///
/// The evaluator auto-propagates a [JetError] argument before calling a
/// function, so implementations only ever see non-error [args] — they validate
/// arity and types and return a [JetError] on a violation.
typedef JetExprFn = JetValue Function(List<JetValue> args, EvalContext context);

/// A mutable name→function table consulted by the evaluator for call nodes.
///
/// This is the public extension point: consumers `register` custom functions
/// with zero core edits. Built-in names are UPPERCASE by convention and lookup
/// is case-sensitive.
class JetFunctionRegistry {
  final Map<String, JetExprFn> _functions = <String, JetExprFn>{};

  /// Registers [fn] under [name], replacing any existing entry.
  void register(String name, JetExprFn fn) => _functions[name] = fn;

  /// Returns the function registered under [name], or `null` if none.
  JetExprFn? lookup(String name) => _functions[name];
}
```

Create `packages/jet_print/lib/src/expression/eval_context.dart`:

```dart
/// The expression evaluation environment (spec 005a).
library;

import '../data/data_row.dart';
import 'function_registry.dart';
import 'value.dart';

/// Resolves references and exposes functions during evaluation.
///
/// A reference that cannot be resolved (a missing field or parameter) returns
/// [JetNull] rather than an error — the render stage treats a null field as
/// blank with a warning (§7), not a hard failure.
abstract class EvalContext {
  /// Resolves a `$F{name}` field reference.
  JetValue resolveField(String name);

  /// Resolves a `$P{name}` parameter reference.
  JetValue resolveParam(String name);

  /// The function registry consulted for call nodes.
  JetFunctionRegistry get functions;
}

/// The default [EvalContext]: fields from a [DataRow], params from a map.
///
/// This is the bridge from the expression seam to the data seam. A field that
/// the row does not declare (or whose value is null) resolves to [JetNull];
/// other values are lifted via [JetValue.from].
class RowEvalContext implements EvalContext {
  /// Creates a context over an optional [row] and [params].
  RowEvalContext({
    DataRow? row,
    Map<String, Object?> params = const <String, Object?>{},
    required JetFunctionRegistry functions,
  })  : _row = row,
        _params = params,
        _functions = functions;

  final DataRow? _row;
  final Map<String, Object?> _params;
  final JetFunctionRegistry _functions;

  @override
  JetFunctionRegistry get functions => _functions;

  @override
  JetValue resolveField(String name) {
    final DataRow? row = _row;
    if (row == null || !row.hasField(name)) return const JetNull();
    return JetValue.from(row.field(name));
  }

  @override
  JetValue resolveParam(String name) =>
      _params.containsKey(name) ? JetValue.from(_params[name]) : const JetNull();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/eval_context_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/function_registry.dart packages/jet_print/lib/src/expression/eval_context.dart packages/jet_print/test/expression/eval_context_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add EvalContext, function registry, and RowEvalContext"
```

---

### Task 8: Evaluator + `Expression` facade

Walks the `Expr` AST against an `EvalContext`, producing a `JetValue` and never throwing: a bad operation yields a `JetError` that propagates. Implements the pinned semantics (all-double arithmetic, string `+` concat, total equality, same-type ordering, short-circuit logic/ternary, div/mod-by-zero error, auto error-propagation into calls). The `Expression` facade ties lexer+parser (`parse`) and evaluator (`evaluate`) into the one public handle.

**Files:**
- Create: `packages/jet_print/lib/src/expression/evaluator.dart`
- Create: `packages/jet_print/lib/src/expression/expression.dart`
- Test: `packages/jet_print/test/expression/evaluator_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/evaluator_test.dart`:

```dart
// Evaluator semantics via the Expression facade (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src, {DataRow? row, Map<String, Object?>? params}) {
  final RowEvalContext ctx = RowEvalContext(
    row: row,
    params: params ?? const <String, Object?>{},
    functions: JetFunctionRegistry(),
  );
  return Expression.parse(src).evaluate(ctx);
}

DataRow _row() => DataRow(
      fields: const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('price', type: JetFieldType.double),
        FieldDef('note', type: JetFieldType.string),
      ],
      values: <String, Object?>{'qty': 3, 'price': 4.0, 'note': null},
    );

void main() {
  group('literals & references', () {
    test('evaluates literals', () {
      expect(_eval('5'), const JetNumber(5));
      expect(_eval("'hi'"), const JetString('hi'));
      expect(_eval('true'), const JetBool(true));
      expect(_eval('null'), const JetNull());
    });

    test('resolves field and param refs', () {
      expect(_eval(r'$F{qty}', row: _row()), const JetNumber(3));
      expect(_eval(r'$P{tax}', params: <String, Object?>{'tax': 0.2}),
          const JetNumber(0.2));
    });
  });

  group('arithmetic (all-double)', () {
    test('adds, subtracts, multiplies, divides', () {
      expect(_eval('1 + 2'), const JetNumber(3));
      expect(_eval('5 - 1'), const JetNumber(4));
      expect(_eval('2 * 3'), const JetNumber(6));
      expect(_eval('7 / 2'), const JetNumber(3.5));
      expect(_eval('7 % 3'), const JetNumber(1));
    });

    test('computes field arithmetic', () {
      expect(_eval(r'$F{qty} * $F{price}', row: _row()), const JetNumber(12));
    });

    test('unary minus negates', () {
      expect(_eval('-(2 + 3)'), const JetNumber(-5));
    });

    test('division and modulo by zero are errors', () {
      expect(_eval('1 / 0'), isA<JetError>());
      expect(_eval('1 % 0'), isA<JetError>());
    });

    test('arithmetic with null or wrong type is an error', () {
      expect(_eval(r'$F{note} + 1', row: _row()), isA<JetError>());
      expect(_eval("'x' * 2"), isA<JetError>());
    });
  });

  group('string concatenation', () {
    test('+ concatenates two strings', () {
      expect(_eval("'a' + 'b'"), const JetString('ab'));
    });

    test('+ on string and number is an error (use CONCAT)', () {
      expect(_eval("'a' + 1"), isA<JetError>());
    });
  });

  group('comparison & equality', () {
    test('numeric comparisons', () {
      expect(_eval('1 < 2'), const JetBool(true));
      expect(_eval('2 <= 2'), const JetBool(true));
      expect(_eval('3 > 5'), const JetBool(false));
    });

    test('equality is total across types', () {
      expect(_eval('1 == 1'), const JetBool(true));
      expect(_eval("1 == '1'"), const JetBool(false));
      expect(_eval('null == null'), const JetBool(true));
      expect(_eval('1 != 2'), const JetBool(true));
    });

    test('ordering across incompatible types is an error', () {
      expect(_eval("1 < 'a'"), isA<JetError>());
      expect(_eval('null < 1'), isA<JetError>());
    });
  });

  group('logical & ternary (short-circuit)', () {
    test('and/or evaluate booleans', () {
      expect(_eval('true && false'), const JetBool(false));
      expect(_eval('false || true'), const JetBool(true));
      expect(_eval('!false'), const JetBool(true));
    });

    test('and short-circuits a failing right operand', () {
      expect(_eval('false && (1 / 0 == 0)'), const JetBool(false));
    });

    test('or short-circuits a failing right operand', () {
      expect(_eval('true || (1 / 0 == 0)'), const JetBool(true));
    });

    test('non-boolean logical operand is an error', () {
      expect(_eval('1 && true'), isA<JetError>());
    });

    test('ternary evaluates only the taken branch', () {
      expect(_eval('true ? 1 : (1 / 0)'), const JetNumber(1));
      expect(_eval('false ? (1 / 0) : 2'), const JetNumber(2));
    });

    test('non-boolean ternary condition is an error', () {
      expect(_eval("'x' ? 1 : 2"), isA<JetError>());
    });
  });

  group('function calls & error propagation', () {
    test('an unknown function is an error', () {
      expect(_eval('NOPE(1)'), isA<JetError>());
    });

    test('a JetError argument propagates without calling the function', () {
      // DOUBLE is unregistered, but the error short-circuits first anyway.
      expect(_eval('DOUBLE(1 / 0)'), isA<JetError>());
    });

    test('calls a registered function', () {
      final RowEvalContext ctx = RowEvalContext(functions: JetFunctionRegistry());
      ctx.functions.register('INC',
          (List<JetValue> a, EvalContext c) => switch (a.first) {
                JetNumber(value: final double v) => JetNumber(v + 1),
                _ => const JetError('INC expects a number'),
              });
      expect(Expression.parse('INC(41)').evaluate(ctx), const JetNumber(42));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/evaluator_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/evaluator.dart`:

```dart
/// The expression evaluator: walks an [Expr] against an [EvalContext] producing
/// a [JetValue] (spec 005a). Internal to the expression seam.
///
/// Total by construction: a failed operation returns a [JetError] (a value)
/// rather than throwing, and an error operand propagates upward. Numbers are
/// `double`; `/` and `%` by zero are errors; `+` concatenates two strings;
/// equality is total across types; ordering requires the same orderable type;
/// `&&`/`||`/`?:` short-circuit.
library;

import 'ast.dart';
import 'eval_context.dart';
import 'value.dart';

/// Evaluates [expr] against [context].
JetValue evaluate(Expr expr, EvalContext context) {
  switch (expr) {
    case LiteralExpr(value: final JetValue v):
      return v;
    case FieldRefExpr(name: final String n):
      return context.resolveField(n);
    case ParamRefExpr(name: final String n):
      return context.resolveParam(n);
    case UnaryExpr(op: final UnaryOp op, operand: final Expr operand):
      return _unary(op, evaluate(operand, context));
    case BinaryExpr(op: final BinaryOp op, left: final Expr l, right: final Expr r):
      return _binary(op, l, r, context);
    case ConditionalExpr(
        condition: final Expr c,
        thenBranch: final Expr t,
        elseBranch: final Expr e,
      ):
      final JetValue cond = evaluate(c, context);
      return switch (cond) {
        JetError() => cond,
        JetBool(value: final bool b) => evaluate(b ? t : e, context),
        _ => const JetError('Condition of "?:" must be boolean'),
      };
    case CallExpr(name: final String name, arguments: final List<Expr> args):
      return _call(name, args, context);
  }
}

JetValue _unary(UnaryOp op, JetValue v) {
  if (v is JetError) return v;
  return switch (op) {
    UnaryOp.negate => v is JetNumber
        ? JetNumber(-v.value)
        : const JetError('Unary "-" requires a number'),
    UnaryOp.not => v is JetBool
        ? JetBool(!v.value)
        : const JetError('Unary "!" requires a boolean'),
  };
}

JetValue _binary(BinaryOp op, Expr leftExpr, Expr rightExpr, EvalContext ctx) {
  // Short-circuiting logical operators evaluate the right side lazily.
  if (op == BinaryOp.and || op == BinaryOp.or) {
    final JetValue left = evaluate(leftExpr, ctx);
    if (left is JetError) return left;
    if (left is! JetBool) {
      return JetError('Operator "${op == BinaryOp.and ? '&&' : '||'}" '
          'requires booleans');
    }
    if (op == BinaryOp.and && !left.value) return const JetBool(false);
    if (op == BinaryOp.or && left.value) return const JetBool(true);
    final JetValue right = evaluate(rightExpr, ctx);
    if (right is JetError) return right;
    if (right is! JetBool) {
      return JetError('Operator "${op == BinaryOp.and ? '&&' : '||'}" '
          'requires booleans');
    }
    return JetBool(right.value);
  }

  final JetValue left = evaluate(leftExpr, ctx);
  if (left is JetError) return left;
  final JetValue right = evaluate(rightExpr, ctx);
  if (right is JetError) return right;

  switch (op) {
    case BinaryOp.equal:
      return JetBool(left == right);
    case BinaryOp.notEqual:
      return JetBool(left != right);
    case BinaryOp.add:
      if (left is JetNumber && right is JetNumber) {
        return JetNumber(left.value + right.value);
      }
      if (left is JetString && right is JetString) {
        return JetString(left.value + right.value);
      }
      return const JetError('Operator "+" requires two numbers or two strings');
    case BinaryOp.subtract:
      return _arith(left, right, '-', (double a, double b) => a - b);
    case BinaryOp.multiply:
      return _arith(left, right, '*', (double a, double b) => a * b);
    case BinaryOp.divide:
      return _arithChecked(left, right, '/', (double a, double b) => a / b);
    case BinaryOp.modulo:
      return _arithChecked(left, right, '%', (double a, double b) => a % b);
    case BinaryOp.less:
      return _order(left, right, (int c) => c < 0, '<');
    case BinaryOp.lessEqual:
      return _order(left, right, (int c) => c <= 0, '<=');
    case BinaryOp.greater:
      return _order(left, right, (int c) => c > 0, '>');
    case BinaryOp.greaterEqual:
      return _order(left, right, (int c) => c >= 0, '>=');
    case BinaryOp.and:
    case BinaryOp.or:
      return const JetError('unreachable'); // handled above
  }
}

JetValue _arith(
    JetValue l, JetValue r, String sym, double Function(double, double) f) {
  if (l is JetNumber && r is JetNumber) return JetNumber(f(l.value, r.value));
  return JetError('Operator "$sym" requires two numbers');
}

JetValue _arithChecked(
    JetValue l, JetValue r, String sym, double Function(double, double) f) {
  if (l is! JetNumber || r is! JetNumber) {
    return JetError('Operator "$sym" requires two numbers');
  }
  if (r.value == 0) return JetError('Division by zero in "$sym"');
  return JetNumber(f(l.value, r.value));
}

JetValue _order(
    JetValue l, JetValue r, bool Function(int) test, String sym) {
  final int? cmp = _compare(l, r);
  if (cmp == null) {
    return JetError('Operator "$sym" requires two comparable values of the '
        'same type');
  }
  return JetBool(test(cmp));
}

/// Returns a sign-of-comparison for two same-typed orderable values, or null if
/// they are not orderable / not the same type.
int? _compare(JetValue l, JetValue r) {
  if (l is JetNumber && r is JetNumber) return l.value.compareTo(r.value);
  if (l is JetString && r is JetString) return l.value.compareTo(r.value);
  if (l is JetDate && r is JetDate) return l.value.compareTo(r.value);
  return null;
}

JetValue _call(String name, List<Expr> argExprs, EvalContext ctx) {
  final List<JetValue> args = <JetValue>[];
  for (final Expr argExpr in argExprs) {
    final JetValue v = evaluate(argExpr, ctx);
    if (v is JetError) return v; // auto-propagate the first error argument
    args.add(v);
  }
  final fn = ctx.functions.lookup(name);
  if (fn == null) return JetError('Unknown function "$name"');
  return fn(args, ctx);
}
```

Create `packages/jet_print/lib/src/expression/expression.dart`:

```dart
/// A compiled, reusable expression (spec 005a).
library;

import 'ast.dart';
import 'eval_context.dart';
import 'evaluator.dart';
import 'expression_exception.dart';
import 'lexer.dart';
import 'parser.dart';
import 'value.dart';

/// A parsed expression that can be evaluated repeatedly against different
/// [EvalContext]s (e.g. once per row during Fill).
///
/// Parsing is eager and throws [ExpressionException] on malformed input;
/// evaluation never throws — a failed operation yields a [JetError] value.
class Expression {
  const Expression._(this._root);

  final Expr _root;

  /// Compiles [source] into an [Expression].
  ///
  /// Throws [ExpressionException] if [source] is not a valid expression.
  factory Expression.parse(String source) =>
      Expression._(Parser(tokenize(source)).parseExpression());

  /// Evaluates this expression against [context], returning a [JetValue]
  /// (possibly a [JetError]).
  JetValue evaluate(EvalContext context) => evaluate_(context);

  // Indirection keeps the imported top-level `evaluate` callable despite the
  // method of the same name.
  JetValue evaluate_(EvalContext context) => _root._evaluatedBy(context);
}

extension on Expr {
  JetValue _evaluatedBy(EvalContext context) => evaluate(this, context);
}
```

> Note: the `evaluate_`/extension indirection avoids a name clash between the public `Expression.evaluate` method and the imported top-level `evaluate` function. If the implementer prefers, import the evaluator with a prefix instead — e.g. `import 'evaluator.dart' as eval;` and define `JetValue evaluate(EvalContext context) => eval.evaluate(_root, context);`. Use whichever is cleaner; the public API (`Expression.parse(...).evaluate(ctx)`) must be unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/evaluator_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/evaluator.dart packages/jet_print/lib/src/expression/expression.dart packages/jet_print/test/expression/evaluator_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add evaluator and Expression facade"
```

> Implementer note on the prefer-prefix alternative (cleaner): make `expression.dart`:
> ```dart
> import 'ast.dart';
> import 'eval_context.dart';
> import 'evaluator.dart' as evaluator;
> import 'expression_exception.dart';
> import 'lexer.dart';
> import 'parser.dart';
> import 'value.dart';
>
> class Expression {
>   const Expression._(this._root);
>   final Expr _root;
>   factory Expression.parse(String source) =>
>       Expression._(Parser(tokenize(source)).parseExpression());
>   JetValue evaluate(EvalContext context) => evaluator.evaluate(_root, context);
> }
> ```
> Prefer this prefixed form — drop the extension and `evaluate_`. (The unused `ExpressionException`/`value` imports must be removed if not referenced, to satisfy the unused-import lint. Keep only the imports actually used: `ast`, `eval_context`, `evaluator`, `lexer`, `parser`, `value` for the return type. Remove `expression_exception` if unreferenced.)

---

### Task 9: Built-in Math functions

`ABS`, `ROUND`, `CEIL`, `FLOOR`, `MIN`, `MAX`. Each operates on `JetNumber` args (errors otherwise); `ROUND` takes an optional digits arg; `MIN`/`MAX` are variadic (≥1).

**Files:**
- Create: `packages/jet_print/lib/src/expression/functions/math_functions.dart`
- Test: `packages/jet_print/test/expression/functions/math_functions_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/functions/math_functions_test.dart`:

```dart
// Built-in math functions (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/math_functions.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerMathFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(functions: r));
}

void main() {
  test('ABS', () {
    expect(_eval('ABS(-5)'), const JetNumber(5));
    expect(_eval('ABS(5)'), const JetNumber(5));
  });

  test('ROUND with default and explicit digits', () {
    expect(_eval('ROUND(2.567)'), const JetNumber(3));
    expect(_eval('ROUND(2.567, 2)'), const JetNumber(2.57));
  });

  test('CEIL and FLOOR', () {
    expect(_eval('CEIL(2.1)'), const JetNumber(3));
    expect(_eval('FLOOR(2.9)'), const JetNumber(2));
  });

  test('MIN and MAX are variadic', () {
    expect(_eval('MIN(3, 1, 2)'), const JetNumber(1));
    expect(_eval('MAX(3, 1, 2)'), const JetNumber(3));
    expect(_eval('MIN(7)'), const JetNumber(7));
  });

  test('non-number args are errors', () {
    expect(_eval("ABS('x')"), isA<JetError>());
    expect(_eval('MIN()'), isA<JetError>());
    expect(_eval('ABS(1, 2)'), isA<JetError>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/functions/math_functions_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/functions/math_functions.dart`:

```dart
/// Built-in math functions for the expression engine (spec 005a).
library;

import 'dart:math' as math;

import '../eval_context.dart';
import '../function_registry.dart';
import '../value.dart';

/// Registers `ABS`, `ROUND`, `CEIL`, `FLOOR`, `MIN`, `MAX` into [registry].
void registerMathFunctions(JetFunctionRegistry registry) {
  registry
    ..register('ABS', _abs)
    ..register('ROUND', _round)
    ..register('CEIL', _ceil)
    ..register('FLOOR', _floor)
    ..register('MIN', _min)
    ..register('MAX', _max);
}

double? _num(JetValue v) => v is JetNumber ? v.value : null;

JetValue _abs(List<JetValue> args, EvalContext ctx) {
  if (args.length != 1) return const JetError('ABS expects 1 argument');
  final double? x = _num(args[0]);
  return x == null ? const JetError('ABS expects a number') : JetNumber(x.abs());
}

JetValue _round(List<JetValue> args, EvalContext ctx) {
  if (args.isEmpty || args.length > 2) {
    return const JetError('ROUND expects 1 or 2 arguments');
  }
  final double? x = _num(args[0]);
  if (x == null) return const JetError('ROUND expects a number');
  int digits = 0;
  if (args.length == 2) {
    final double? d = _num(args[1]);
    if (d == null) return const JetError('ROUND digits must be a number');
    digits = d.toInt();
  }
  final num factor = math.pow(10, digits);
  return JetNumber((x * factor).roundToDouble() / factor);
}

JetValue _ceil(List<JetValue> args, EvalContext ctx) {
  if (args.length != 1) return const JetError('CEIL expects 1 argument');
  final double? x = _num(args[0]);
  return x == null
      ? const JetError('CEIL expects a number')
      : JetNumber(x.ceilToDouble());
}

JetValue _floor(List<JetValue> args, EvalContext ctx) {
  if (args.length != 1) return const JetError('FLOOR expects 1 argument');
  final double? x = _num(args[0]);
  return x == null
      ? const JetError('FLOOR expects a number')
      : JetNumber(x.floorToDouble());
}

JetValue _min(List<JetValue> args, EvalContext ctx) =>
    _reduce(args, 'MIN', math.min);

JetValue _max(List<JetValue> args, EvalContext ctx) =>
    _reduce(args, 'MAX', math.max);

JetValue _reduce(
    List<JetValue> args, String name, double Function(double, double) f) {
  if (args.isEmpty) return JetError('$name expects at least 1 argument');
  double acc;
  final double? first = _num(args[0]);
  if (first == null) return JetError('$name expects numbers');
  acc = first;
  for (int i = 1; i < args.length; i++) {
    final double? x = _num(args[i]);
    if (x == null) return JetError('$name expects numbers');
    acc = f(acc, x);
  }
  return JetNumber(acc);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/functions/math_functions_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/functions/math_functions.dart packages/jet_print/test/expression/functions/math_functions_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add built-in math functions"
```

---

### Task 10: Built-in String functions

`UPPER`, `LOWER`, `TRIM`, `LENGTH`, `CONCAT`, `SUBSTRING`. `CONCAT` stringifies any args (via `jetStringify`); the others require `JetString`.

**Files:**
- Create: `packages/jet_print/lib/src/expression/functions/string_functions.dart`
- Test: `packages/jet_print/test/expression/functions/string_functions_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/functions/string_functions_test.dart`:

```dart
// Built-in string functions (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/string_functions.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerStringFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(functions: r));
}

void main() {
  test('UPPER / LOWER / TRIM', () {
    expect(_eval("UPPER('aB')"), const JetString('AB'));
    expect(_eval("LOWER('aB')"), const JetString('ab'));
    expect(_eval("TRIM('  hi  ')"), const JetString('hi'));
  });

  test('LENGTH returns a number', () {
    expect(_eval("LENGTH('abc')"), const JetNumber(3));
  });

  test('CONCAT stringifies and joins any args', () {
    expect(_eval("CONCAT('a', 'b', 'c')"), const JetString('abc'));
    expect(_eval("CONCAT('n=', 5)"), const JetString('n=5.0'));
    expect(_eval("CONCAT('x', null)"), const JetString('x'));
  });

  test('SUBSTRING with start and optional length, clamped', () {
    expect(_eval("SUBSTRING('abcdef', 1, 3)"), const JetString('bcd'));
    expect(_eval("SUBSTRING('abcdef', 4)"), const JetString('ef'));
    expect(_eval("SUBSTRING('abc', 1, 99)"), const JetString('bc')); // clamped
  });

  test('type errors', () {
    expect(_eval('UPPER(5)'), isA<JetError>());
    expect(_eval("LENGTH(5)"), isA<JetError>());
    expect(_eval("SUBSTRING('abc', 'x')"), isA<JetError>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/functions/string_functions_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/functions/string_functions.dart`:

```dart
/// Built-in string functions for the expression engine (spec 005a).
library;

import '../eval_context.dart';
import '../function_registry.dart';
import '../value.dart';

/// Registers `UPPER`, `LOWER`, `TRIM`, `LENGTH`, `CONCAT`, `SUBSTRING`.
void registerStringFunctions(JetFunctionRegistry registry) {
  registry
    ..register('UPPER', _upper)
    ..register('LOWER', _lower)
    ..register('TRIM', _trim)
    ..register('LENGTH', _length)
    ..register('CONCAT', _concat)
    ..register('SUBSTRING', _substring);
}

JetValue _stringUnary(
    List<JetValue> args, String name, String Function(String) f) {
  if (args.length != 1) return JetError('$name expects 1 argument');
  final JetValue v = args[0];
  return v is JetString
      ? JetString(f(v.value))
      : JetError('$name expects a string');
}

JetValue _upper(List<JetValue> a, EvalContext c) =>
    _stringUnary(a, 'UPPER', (String s) => s.toUpperCase());

JetValue _lower(List<JetValue> a, EvalContext c) =>
    _stringUnary(a, 'LOWER', (String s) => s.toLowerCase());

JetValue _trim(List<JetValue> a, EvalContext c) =>
    _stringUnary(a, 'TRIM', (String s) => s.trim());

JetValue _length(List<JetValue> args, EvalContext c) {
  if (args.length != 1) return const JetError('LENGTH expects 1 argument');
  final JetValue v = args[0];
  return v is JetString
      ? JetNumber(v.value.length.toDouble())
      : const JetError('LENGTH expects a string');
}

JetValue _concat(List<JetValue> args, EvalContext c) =>
    JetString(args.map(jetStringify).join());

JetValue _substring(List<JetValue> args, EvalContext c) {
  if (args.length < 2 || args.length > 3) {
    return const JetError('SUBSTRING expects 2 or 3 arguments');
  }
  final JetValue s = args[0];
  final JetValue start = args[1];
  if (s is! JetString) return const JetError('SUBSTRING expects a string');
  if (start is! JetNumber) {
    return const JetError('SUBSTRING start must be a number');
  }
  final int len = s.value.length;
  final int from = start.value.toInt().clamp(0, len);
  int to = len;
  if (args.length == 3) {
    final JetValue length = args[2];
    if (length is! JetNumber) {
      return const JetError('SUBSTRING length must be a number');
    }
    to = (from + length.value.toInt()).clamp(from, len);
  }
  return JetString(s.value.substring(from, to));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/functions/string_functions_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/functions/string_functions.dart packages/jet_print/test/expression/functions/string_functions_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add built-in string functions"
```

---

### Task 11: Built-in Logic functions

`IF`, `COALESCE`, `ISNULL`. Note: `IF` evaluates all arguments (no short-circuit — use the `?:` operator for that); `COALESCE` returns the first non-null arg.

**Files:**
- Create: `packages/jet_print/lib/src/expression/functions/logic_functions.dart`
- Test: `packages/jet_print/test/expression/functions/logic_functions_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/functions/logic_functions_test.dart`:

```dart
// Built-in logic functions (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/logic_functions.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerLogicFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(functions: r));
}

void main() {
  test('IF returns the chosen branch', () {
    expect(_eval("IF(true, 'a', 'b')"), const JetString('a'));
    expect(_eval("IF(false, 'a', 'b')"), const JetString('b'));
  });

  test('IF with a non-boolean condition is an error', () {
    expect(_eval("IF(1, 'a', 'b')"), isA<JetError>());
    expect(_eval("IF(true, 'a')"), isA<JetError>());
  });

  test('COALESCE returns the first non-null argument', () {
    expect(_eval('COALESCE(null, null, 3)'), const JetNumber(3));
    expect(_eval("COALESCE('x', 'y')"), const JetString('x'));
    expect(_eval('COALESCE(null, null)'), const JetNull());
  });

  test('ISNULL tests for null', () {
    expect(_eval('ISNULL(null)'), const JetBool(true));
    expect(_eval('ISNULL(0)'), const JetBool(false));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/functions/logic_functions_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/functions/logic_functions.dart`:

```dart
/// Built-in logic functions for the expression engine (spec 005a).
library;

import '../eval_context.dart';
import '../function_registry.dart';
import '../value.dart';

/// Registers `IF`, `COALESCE`, `ISNULL`.
///
/// `IF(cond, a, b)` evaluates *all* arguments (functions receive pre-evaluated
/// values); use the `?:` operator when short-circuit evaluation is required.
void registerLogicFunctions(JetFunctionRegistry registry) {
  registry
    ..register('IF', _if)
    ..register('COALESCE', _coalesce)
    ..register('ISNULL', _isNull);
}

JetValue _if(List<JetValue> args, EvalContext c) {
  if (args.length != 3) return const JetError('IF expects 3 arguments');
  final JetValue cond = args[0];
  return switch (cond) {
    JetBool(value: final bool b) => b ? args[1] : args[2],
    _ => const JetError('IF condition must be boolean'),
  };
}

JetValue _coalesce(List<JetValue> args, EvalContext c) {
  for (final JetValue v in args) {
    if (v is! JetNull) return v;
  }
  return const JetNull();
}

JetValue _isNull(List<JetValue> args, EvalContext c) {
  if (args.length != 1) return const JetError('ISNULL expects 1 argument');
  return JetBool(args[0] is JetNull);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/functions/logic_functions_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/functions/logic_functions.dart packages/jet_print/test/expression/functions/logic_functions_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add built-in logic functions"
```

---

### Task 12: Built-in Format function

`FORMAT(value, pattern)` — formats a `JetNumber` via `intl`'s `NumberFormat` or a `JetDate` via `DateFormat`, using the given pattern string.

**Files:**
- Create: `packages/jet_print/lib/src/expression/functions/format_functions.dart`
- Test: `packages/jet_print/test/expression/functions/format_functions_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/functions/format_functions_test.dart`:

```dart
// Built-in FORMAT function via intl (spec 005a). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/format_functions.dart';
import 'package:jet_print/src/expression/value.dart';

JetValue _eval(String src) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerFormatFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(functions: r));
}

void main() {
  test('formats a number with a pattern', () {
    expect(_eval("FORMAT(1234.5, '#,##0.00')"), const JetString('1,234.50'));
  });

  test('formats a date with a pattern', () {
    // 2026-06-07 via a JetDate passed through a param is covered in integration;
    // here use a literal-free check that the function rejects bad input.
    expect(_eval("FORMAT('x', '#,##0')"), isA<JetError>());
  });

  test('arity and pattern-type errors', () {
    expect(_eval('FORMAT(5)'), isA<JetError>());
    expect(_eval('FORMAT(5, 5)'), isA<JetError>());
  });
}
```

> The date-formatting happy path is exercised end-to-end in Task 13's integration test (a `JetDate` from a param), since expression literals have no date syntax in 005a.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/functions/format_functions_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/functions/format_functions.dart`:

```dart
/// Built-in FORMAT function for the expression engine (spec 005a).
library;

import 'package:intl/intl.dart';

import '../eval_context.dart';
import '../function_registry.dart';
import '../value.dart';

/// Registers `FORMAT(value, pattern)`.
///
/// Formats a [JetNumber] via [NumberFormat] or a [JetDate] via [DateFormat]
/// using the ICU [pattern] string. Returns a [JetError] for a missing/invalid
/// pattern, an unsupported value type, or an unparseable pattern.
void registerFormatFunctions(JetFunctionRegistry registry) {
  registry.register('FORMAT', _format);
}

JetValue _format(List<JetValue> args, EvalContext ctx) {
  if (args.length != 2) return const JetError('FORMAT expects 2 arguments');
  final JetValue value = args[0];
  final JetValue pattern = args[1];
  if (pattern is! JetString) {
    return const JetError('FORMAT pattern must be a string');
  }
  try {
    return switch (value) {
      JetNumber(value: final double v) =>
        JetString(NumberFormat(pattern.value).format(v)),
      JetDate(value: final DateTime v) =>
        JetString(DateFormat(pattern.value).format(v)),
      _ => const JetError('FORMAT expects a number or date as its first '
          'argument'),
    };
  } on FormatException catch (e) {
    return JetError('FORMAT failed: ${e.message}');
  }
}
```

> Note: `NumberFormat`/`DateFormat` can throw `FormatException` on a malformed pattern; the `try/catch` converts that to a `JetError` so `FORMAT` honors the non-throwing-evaluation contract.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/functions/format_functions_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/functions/format_functions.dart packages/jet_print/test/expression/functions/format_functions_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add built-in FORMAT function via intl"
```

---

### Task 13: `registerBuiltInFunctions` + end-to-end integration

A single entry point that wires all four families, plus an integration test that compiles a realistic expression with functions and evaluates it against a real `DataRow` + params (including a `JetDate` param to exercise `FORMAT`'s date path).

**Files:**
- Create: `packages/jet_print/lib/src/expression/functions/built_in_functions.dart`
- Test: `packages/jet_print/test/expression/integration_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/integration_test.dart`:

```dart
// End-to-end: parse + evaluate realistic expressions with built-ins (005a).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/expression.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/built_in_functions.dart';
import 'package:jet_print/src/expression/value.dart';

DataRow _invoiceLine() => DataRow(
      fields: const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('price', type: JetFieldType.double),
        FieldDef('name', type: JetFieldType.string),
      ],
      values: <String, Object?>{'qty': 3, 'price': 4.5, 'name': 'Widget'},
    );

JetValue _eval(String src, {DataRow? row, Map<String, Object?>? params}) {
  final JetFunctionRegistry r = JetFunctionRegistry();
  registerBuiltInFunctions(r);
  return Expression.parse(src).evaluate(RowEvalContext(
    row: row,
    params: params ?? const <String, Object?>{},
    functions: r,
  ));
}

void main() {
  test('registerBuiltInFunctions wires all four families', () {
    final JetFunctionRegistry r = JetFunctionRegistry();
    registerBuiltInFunctions(r);
    for (final String name in <String>[
      'ABS', 'ROUND', 'MIN', 'MAX', 'CEIL', 'FLOOR', // math
      'UPPER', 'LOWER', 'TRIM', 'LENGTH', 'CONCAT', 'SUBSTRING', // string
      'IF', 'COALESCE', 'ISNULL', // logic
      'FORMAT', // format
    ]) {
      expect(r.lookup(name), isNotNull, reason: 'missing $name');
    }
  });

  test('computes a formatted line total', () {
    expect(
      _eval(r"FORMAT(ROUND($F{qty} * $F{price}, 2), '#,##0.00')",
          row: _invoiceLine()),
      const JetString('13.50'),
    );
  });

  test('builds a conditional label', () {
    expect(
      _eval(r"CONCAT(UPPER($F{name}), $F{qty} > 1 ? 's' : '')",
          row: _invoiceLine()),
      const JetString('WIDGETs'),
    );
  });

  test('coalesces a null field to a default and formats it', () {
    final DataRow row = DataRow(
      fields: const <FieldDef>[FieldDef('discount', type: JetFieldType.double)],
      values: <String, Object?>{'discount': null},
    );
    expect(_eval(r'COALESCE($F{discount}, 0)', row: row), const JetNumber(0));
  });

  test('formats a date param', () {
    expect(
      _eval(r"FORMAT($P{date}, 'yyyy-MM-dd')",
          params: <String, Object?>{'date': DateTime(2026, 6, 7)}),
      const JetString('2026-06-07'),
    );
  });

  test('a broken sub-expression renders as an error value, not a throw', () {
    expect(_eval(r'$F{qty} / 0', row: _invoiceLine()), isA<JetError>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/integration_test.dart`
Expected: FAIL — `built_in_functions.dart` URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/expression/functions/built_in_functions.dart`:

```dart
/// Wires all built-in expression function families (spec 005a).
library;

import '../function_registry.dart';
import 'format_functions.dart';
import 'logic_functions.dart';
import 'math_functions.dart';
import 'string_functions.dart';

/// Registers every built-in function family (math, string, logic, format) into
/// [registry]. Consumers may register additional functions afterwards, or
/// register families individually via the per-family entry points.
void registerBuiltInFunctions(JetFunctionRegistry registry) {
  registerMathFunctions(registry);
  registerStringFunctions(registry);
  registerLogicFunctions(registry);
  registerFormatFunctions(registry);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/expression/integration_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + analyze**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib/src/expression test/expression && flutter analyze lib/src/expression test/expression`
Expected: `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/expression/functions/built_in_functions.dart packages/jet_print/test/expression/integration_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(expr): add registerBuiltInFunctions + end-to-end integration test"
```

---

### Task 14: Enforce the `expression` seam boundary + finish gates

Extend the layer-boundary test with an `expression`-seam group (expression may import `domain`/`data`/`intl`; must not import rendering/designer/Flutter-UI), add the CHANGELOG entry, and run the full quality gate.

**Files:**
- Modify: `packages/jet_print/test/architecture/layer_boundaries_test.dart`
- Modify: `packages/jet_print/CHANGELOG.md`

- [ ] **Step 1: Add the expression-seam boundary group**

In `packages/jet_print/test/architecture/layer_boundaries_test.dart`, add an `expressionDir` + `expressionFiles()` alongside the existing `dataDir`/`dataFiles()` declarations:

```dart
  final Directory expressionDir =
      Directory('${root.path}/packages/jet_print/lib/src/expression');

  List<File> expressionFiles() => expressionDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((FileSystemEntity f) => f.path.endsWith('.dart'))
      .toList();
```

And add a third group after the `data seam` group's closing `});`:

```dart
  group('layer boundaries — expression seam', () {
    test('the expression seam has source files to check (no false green)', () {
      expect(expressionDir.existsSync(), isTrue,
          reason: 'Missing ${expressionDir.path}');
      expect(expressionFiles(), isNotEmpty,
          reason: 'No .dart files found under ${expressionDir.path}');
    });

    test('expression imports no outer seam and no Flutter UI library', () {
      final List<String> violations = <String>[];
      for (final File file in expressionFiles()) {
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
        reason: 'The expression seam may depend only on domain/data (and intl). '
            'Violations:\n${violations.join('\n')}',
      );
    });
  });
```

> The `expression` seam imports `../data/...` and `package:intl/intl.dart`; neither contains `rendering`/`designer` nor is a Flutter UI library, so the existing `_reachesOtherSeam`/`_isFlutterUi` predicates pass them. The group fails only if a future expression file reaches rendering/designer/Flutter-UI.

- [ ] **Step 2: Run the architecture test to verify the new group passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/architecture/layer_boundaries_test.dart`
Expected: PASS — all three seam groups green.

- [ ] **Step 3: Update the CHANGELOG**

In `packages/jet_print/CHANGELOG.md`, under `## Unreleased` → `### Added`, append after the spec-004 bullet:

```markdown
- Expression engine core (spec 005a): the headless expression language —
  a sealed `JetValue` model (null/bool/number/string/date/error; numbers are
  `double`), a lexer/parser/AST/evaluator pipeline compiling expressions like
  `$F{qty} * $F{price}` and `FORMAT(ROUND($F{total}, 2), '#,##0.00')`, and a
  pluggable `JetFunctionRegistry` (engine extension point) with built-in math,
  string, logic, and format function families. Evaluation never throws — a bad
  operation yields a `JetError` value (rendered `!ERR`); only malformed syntax
  throws `ExpressionException`. `RowEvalContext` resolves `$F{}` from a
  `DataRow` and `$P{}` from a parameter map. The architecture test now enforces
  the `expression → domain/data` boundary. (Aggregates, variables, groups, and
  `$V{}` references follow in 005b.)
```

- [ ] **Step 4: Run the full quality gate**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test`
Expected: PASS — all suites green (the prior 189 plus the new expression tests; no regressions in `encapsulation_test`/`public_api_test`).

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format --output=none --set-exit-if-changed lib/src/expression test/expression test/architecture/layer_boundaries_test.dart test/encapsulation_test.dart`
Expected: exit 0. If it reports changes, run `dart format` on the affected paths and re-run.

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter analyze`
Expected: `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/test/architecture/layer_boundaries_test.dart packages/jet_print/CHANGELOG.md
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "test(expr): enforce expression->domain/data boundary; changelog for spec 005a"
```

---

## Self-Review (completed before handoff)

**Spec coverage** (blueprint §4 #4, §6 contract 4, §11 row 005 — core slice):
- Lexer → Task 4. Parser/AST → Tasks 5–6. Value model → Task 2. Evaluator → Task 8. Function registry (extension point #4) → Task 7. Built-in function families (math/string/logic/format) → Tasks 9–13. `$F{}`/`$P{}` resolution against a row → Task 7 (`RowEvalContext`). Error model (`!ERR` as a value, parse-throws) → Tasks 2/8. Inward dependency (`expression → domain/data`) → Task 14. Aggregates/variables/groups/`$V{}` explicitly deferred to 005b (stated up front).

**Placeholder scan:** none — every code step has complete source. The two implementer notes (Task 8 prefix-import alternative; Task 12 date-path covered in integration) clarify intent, not placeholders.

**Type consistency:** `JetValue`/`JetNull`/`JetBool`/`JetNumber`/`JetString`/`JetDate`/`JetError`, `JetValue.from`, `jetStringify`, `Token`/`TokenType`, `tokenize`, `Expr` + nodes (`LiteralExpr`/`FieldRefExpr`/`ParamRefExpr`/`UnaryExpr`/`BinaryExpr`/`ConditionalExpr`/`CallExpr`), `UnaryOp`/`BinaryOp`, `Parser.parseExpression`, `EvalContext` (`resolveField`/`resolveParam`/`functions`), `RowEvalContext`, `JetExprFn`, `JetFunctionRegistry` (`register`/`lookup`), `evaluate(Expr, EvalContext)`, `Expression.parse`/`.evaluate`, `ExpressionException`, `register{Math,String,Logic,Format,BuiltIn}Functions` — names and signatures are consistent across every task that references them.

**Convention checks:** white-box allowlist extended (Task 1) before any `/test/expression/` test runs under the full suite; relative imports ordered (`dart:` → `package:intl` → relative, alphabetical); value-type equality mirrors `src/domain`/`src/data`; the only new third-party use is `intl` (already a dependency, permitted in the expression seam per §12); the public facade `jet_print.dart` is intentionally untouched (deferred export). `dart:math` (Task 9) and `dart:core` `DateTime` are headless.

**Known evaluator subtlety pinned for reviewers:** the `_binary` switch lists `BinaryOp.and`/`BinaryOp.or` cases that return an `unreachable` error because those operators are fully handled by the short-circuit block above the main switch — this keeps the `switch` exhaustive over the `BinaryOp` enum without a `default`. If the implementer restructures, the exhaustiveness must be preserved (no `default:` that would hide a missing operator).
