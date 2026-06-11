// Format property applied at resolve time (013 / T020): a bound value is
// formatted before stringify; literals are unaffected; bad patterns fall back.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/built_in_functions.dart';
import 'package:jet_print/src/rendering/fill/element_resolver.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 10, height: 5);

ElementResolver _resolver() {
  final JetFunctionRegistry f = JetFunctionRegistry();
  registerBuiltInFunctions(f);
  return ElementResolver(functions: f, diagnostics: ReportDiagnostics());
}

DataRow _row(Map<String, Object?> values) => DataRow(
      fields: <FieldDef>[for (final String k in values.keys) FieldDef(k)],
      values: values,
    );

void main() {
  test('a numeric pattern formats the resolved value', () {
    const TextElement el = TextElement(
        id: 't',
        bounds: _r,
        text: '',
        expression: r'$F{amount}',
        format: '#,##0.00');
    final TextElement out =
        _resolver().resolve(el, row: _row(<String, Object?>{'amount': 1234.5}))
            as TextElement;
    expect(out.text, '1,234.50');
  });

  test('no format leaves the value as the engine stringifies it', () {
    const TextElement el =
        TextElement(id: 't', bounds: _r, text: '', expression: r'$F{amount}');
    final TextElement out =
        _resolver().resolve(el, row: _row(<String, Object?>{'amount': 1234.5}))
            as TextElement;
    expect(out.text, '1234.5');
  });

  test('a literal label is unaffected by a format', () {
    const TextElement el =
        TextElement(id: 't', bounds: _r, text: 'Paid', format: '#,##0.00');
    expect(_resolver().resolve(el, row: _row(<String, Object?>{})), same(el));
  });

  test('a pattern that does not fit the value renders unformatted, never !ERR',
      () {
    const TextElement el = TextElement(
        id: 't',
        bounds: _r,
        text: '',
        expression: r'$F{name}',
        format: '#,##0.00');
    final TextElement out =
        _resolver().resolve(el, row: _row(<String, Object?>{'name': 'Ada'}))
            as TextElement;
    expect(out.text, 'Ada');
  });
}
