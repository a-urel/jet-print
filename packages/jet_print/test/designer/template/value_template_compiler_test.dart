/// Tests for the value-field template compiler (013, T003) — the bidirectional
/// projection between the single value field and `TextElement.expression`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/template/value_template_compiler.dart';

void main() {
  group('parseValueField — the three forms', () {
    test('empty value is an empty literal', () {
      expect(parseValueField(''), const LiteralValue(''));
    });

    test('plain text is a literal', () {
      expect(parseValueField('sample text'), const LiteralValue('sample text'));
    });

    test('a whole-value [field] token is a simple binding', () {
      expect(parseValueField('[customerName]'),
          const BindingValue(r'$F{customerName}'));
    });

    test('whitespace inside the token is trimmed', () {
      expect(parseValueField('[ customerName ]'),
          const BindingValue(r'$F{customerName}'));
    });

    test('brackets mid-text stay literal (no braces)', () {
      expect(parseValueField('Total: [qty] of [n]'),
          const LiteralValue('Total: [qty] of [n]'));
    });

    test('an escaped bracket is literal text', () {
      expect(parseValueField(r'\[draft]'), const LiteralValue('[draft]'));
    });

    test('escaped braces are literal text', () {
      expect(parseValueField(r'\{not a template\}'),
          const LiteralValue('{not a template}'));
    });

    test('a single-field template normalizes to the simple form', () {
      // {[name]} ≡ [name] ≡ $F{name}
      expect(parseValueField('{[name]}'), const BindingValue(r'$F{name}'));
    });

    test('a function template compiles to a call', () {
      expect(parseValueField('{upper[name]}'),
          const BindingValue(r'UPPER($F{name})'));
    });

    test('a multi-field template compiles to CONCAT with the literal run', () {
      expect(parseValueField('{[firstName] [lastName]}'),
          const BindingValue(r'CONCAT($F{firstName}, " ", $F{lastName})'));
    });

    test('literal text inside a template is quoted', () {
      expect(parseValueField('{Total: [qty]}'),
          const BindingValue(r'CONCAT("Total: ", $F{qty})'));
    });

    test('a malformed template falls back to literal', () {
      expect(parseValueField('{[a} text {b]}'),
          const LiteralValue('{[a} text {b]}'));
    });
  });

  group('reverseCompile — expression → display token', () {
    test('a simple field becomes a bare [field] token, editable', () {
      final ValueDisplay d = reverseCompile(r'$F{customerName}');
      expect(d.text, '[customerName]');
      expect(d.editable, isTrue);
    });

    test('a function call becomes {func[field]}', () {
      expect(reverseCompile(r'UPPER($F{name})').text, '{upper[name]}');
    });

    test('a CONCAT becomes a {…} template with the literal run', () {
      expect(reverseCompile(r'CONCAT($F{firstName}, " ", $F{lastName})').text,
          '{[firstName] [lastName]}');
    });

    test('an out-of-grammar expression is shown read-only', () {
      final ValueDisplay d = reverseCompile(r'$F{a} + $F{b}');
      expect(d.editable, isFalse);
    });

    test('an unparseable expression is shown read-only', () {
      expect(reverseCompile(r'$F{a} +').editable, isFalse);
    });
  });

  group('round-trip stability on the supported subset', () {
    for (final String value in <String>[
      '[customerName]',
      '{upper[name]}',
      '{[firstName] [lastName]}',
      '{Total: [qty]}',
    ]) {
      test('"$value" survives parse → reverse', () {
        final ValueParse parsed = parseValueField(value);
        parsed as BindingValue;
        expect(reverseCompile(parsed.expression).text, value);
      });
    }

    test('{[name]} canonicalizes to [name] on the round-trip', () {
      final ValueParse parsed = parseValueField('{[name]}');
      parsed as BindingValue;
      expect(reverseCompile(parsed.expression).text, '[name]');
    });
  });

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

    test('a parenthesized operand round-trips losslessly', () {
      const stored = r'SUM(($F{a} + $F{b}) * $F{c})';
      final display = reverseCompile(stored);
      expect(display, const ValueDisplay('{SUM(([a] + [b]) * [c])}'));
      expect(parseValueField(display.text), const BindingValue(stored));
    });

    test('a malformed aggregate falls back to literal', () {
      // Unterminated paren and two adjacent field tokens (no operator) are not
      // valid templates/expressions → the whole value is treated as literal.
      expect(parseValueField('{SUM([a}'), const LiteralValue('{SUM([a}'));
      expect(parseValueField('{SUM([a][b])}'),
          const LiteralValue('{SUM([a][b])}'));
    });
  });
}
