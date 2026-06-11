// Unresolved-binding token (013 / FR-007, T006): in a schema-aware context an
// unknown field renders the token; with no schema, behavior is unchanged.
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

ElementResolver _resolver(
  ReportDiagnostics d, {
  Set<String>? knownFields,
  String unresolvedFieldToken = '#ERROR',
}) {
  final JetFunctionRegistry f = JetFunctionRegistry();
  registerBuiltInFunctions(f);
  return ElementResolver(
    functions: f,
    diagnostics: d,
    knownFields: knownFields,
    unresolvedFieldToken: unresolvedFieldToken,
  );
}

DataRow _row(Map<String, Object?> values) => DataRow(
      fields: <FieldDef>[
        for (final String k in values.keys) FieldDef(k),
      ],
      values: values,
    );

void main() {
  test('schema-aware: an unknown field renders the token', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const TextElement el =
        TextElement(id: 't', bounds: _r, text: '', expression: r'$F{unknown}');
    final TextElement out = _resolver(d, knownFields: <String>{'qty'}).resolve(
      el,
      row: _row(<String, Object?>{'qty': 1}),
    ) as TextElement;
    expect(out.text, '#ERROR');
  });

  test('schema-aware: a known field resolves normally', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const TextElement el =
        TextElement(id: 't', bounds: _r, text: '', expression: r'$F{name}');
    final TextElement out = _resolver(d, knownFields: <String>{'name'}).resolve(
      el,
      row: _row(<String, Object?>{'name': 'Ada'}),
    ) as TextElement;
    expect(out.text, 'Ada');
  });

  test('no schema: a missing field stays empty (no regression)', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const TextElement el =
        TextElement(id: 't', bounds: _r, text: '', expression: r'$F{unknown}');
    final TextElement out = _resolver(d).resolve(
      el,
      row: _row(<String, Object?>{'qty': 1}),
    ) as TextElement;
    expect(out.text, '');
  });

  test('the token is configurable (designer passes a localized value)', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const TextElement el =
        TextElement(id: 't', bounds: _r, text: '', expression: r'$F{unknown}');
    final TextElement out = _resolver(d,
            knownFields: <String>{'qty'}, unresolvedFieldToken: '#HATA')
        .resolve(el, row: _row(<String, Object?>{'qty': 1})) as TextElement;
    expect(out.text, '#HATA');
  });

  test('deterministic: same inputs → same output', () {
    TextElement run() {
      final ReportDiagnostics d = ReportDiagnostics();
      const TextElement el = TextElement(
          id: 't', bounds: _r, text: '', expression: r'$F{unknown}');
      return _resolver(d, knownFields: <String>{'qty'})
          .resolve(el, row: _row(<String, Object?>{'qty': 1})) as TextElement;
    }

    expect(run().text, run().text);
  });
}
