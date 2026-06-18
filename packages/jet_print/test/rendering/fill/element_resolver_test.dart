// ElementResolver: per-type resolution + diagnostics (007b).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/functions/built_in_functions.dart';
import 'package:jet_print/src/rendering/fill/element_resolver.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';

const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 5);

ElementResolver resolver(ReportDiagnostics d) {
  final JetFunctionRegistry f = JetFunctionRegistry();
  registerBuiltInFunctions(f);
  return ElementResolver(functions: f, diagnostics: d);
}

DataRow row(Map<String, Object?> values, {Map<String, JetFieldType>? types}) =>
    DataRow(
      fields: <FieldDef>[
        for (final String k in values.keys)
          FieldDef(k, type: types?[k] ?? JetFieldType.string),
      ],
      values: values,
    );

void main() {
  test('text expression resolves to its evaluated value', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const TextElement el = TextElement(
        id: 't',
        bounds: r,
        text: '',
        expression: r'CONCAT($F{first}, " ", $F{last})');
    final TextElement out = resolver(d).resolve(el,
            row: row(<String, Object?>{'first': 'Ada', 'last': 'Lovelace'}))
        as TextElement;
    expect(out.text, 'Ada Lovelace');
    expect(out.expression, isNull); // cleared on resolution
    expect(d.entries, isEmpty);
  });

  test('static text (no expression) passes through unchanged', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const TextElement el = TextElement(id: 't', bounds: r, text: 'literal');
    expect(resolver(d).resolve(el, row: row(<String, Object?>{})), same(el));
  });

  test('a bad-syntax expression yields !ERR + an error diagnostic', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const TextElement el =
        TextElement(id: 't', bounds: r, text: '', expression: r'CONCAT($F{a},');
    final TextElement out = resolver(d)
        .resolve(el, row: row(<String, Object?>{'a': 'x'})) as TextElement;
    expect(out.text, '!ERR');
    expect(d.hasErrors, isTrue);
  });

  test('an eval error yields !ERR + an error diagnostic', () {
    final ReportDiagnostics d = ReportDiagnostics();
    // Division by zero is a deterministic JetError (evaluator).
    const TextElement el =
        TextElement(id: 't', bounds: r, text: '', expression: r'5 / 0');
    final TextElement out =
        resolver(d).resolve(el, row: row(<String, Object?>{})) as TextElement;
    expect(out.text, '!ERR');
    expect(d.hasErrors, isTrue);
  });

  test('a page-scoped reference is rejected; authored text is preserved', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const TextElement el = TextElement(
        id: 't', bounds: r, text: 'fallback', expression: r'$V{PAGE_NUMBER}');
    final TextElement out =
        resolver(d).resolve(el, row: row(<String, Object?>{})) as TextElement;
    expect(out.text, 'fallback'); // authored text preserved, not blanked
    expect(out.expression, isNull);
    expect(d.hasErrors, isTrue);
  });

  test('a string literal that looks like a page var does NOT trigger rejection',
      () {
    final ReportDiagnostics d = ReportDiagnostics();
    const TextElement el = TextElement(
        id: 't', bounds: r, text: '', expression: r'"$V{PAGE_NUMBER}"');
    final TextElement out =
        resolver(d).resolve(el, row: row(<String, Object?>{})) as TextElement;
    expect(out.text, r'$V{PAGE_NUMBER}'); // the literal string
    expect(d.hasErrors, isFalse);
  });

  test('image FieldImageSource resolves to bytes', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
    const ImageElement el =
        ImageElement(id: 'i', bounds: r, source: FieldImageSource('photo'));
    final ImageElement out =
        resolver(d).resolve(el, row: row(<String, Object?>{'photo': bytes}))
            as ImageElement;
    expect(out.source, isA<BytesImageSource>());
    expect((out.source as BytesImageSource).bytes, bytes);
    expect(d.entries, isEmpty);
  });

  test('an unresolvable image field warns and passes through', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const ImageElement el =
        ImageElement(id: 'i', bounds: r, source: FieldImageSource('photo'));
    final ReportElement out =
        resolver(d).resolve(el, row: row(<String, Object?>{}));
    expect(out, same(el));
    expect(d.entries.single.severity, DiagnosticSeverity.warning);
  });

  test('image field as List<int> resolves to bytes (defensively copied)', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final List<int> raw = <int>[9, 8, 7];
    const ImageElement el =
        ImageElement(id: 'i', bounds: r, source: FieldImageSource('photo'));
    final ImageElement out = resolver(d)
        .resolve(el, row: row(<String, Object?>{'photo': raw})) as ImageElement;
    final BytesImageSource src = out.source as BytesImageSource;
    expect(src.bytes, <int>[9, 8, 7]);
    // Mutating the original list must NOT affect the resolved snapshot.
    raw[0] = 0;
    expect(src.bytes[0], 9);
    expect(d.entries, isEmpty);
  });

  test('image field as a valid base64 string resolves to bytes', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final String encoded = base64Encode(<int>[1, 2, 3, 4]);
    const ImageElement el =
        ImageElement(id: 'i', bounds: r, source: FieldImageSource('photo'));
    final ImageElement out =
        resolver(d).resolve(el, row: row(<String, Object?>{'photo': encoded}))
            as ImageElement;
    expect((out.source as BytesImageSource).bytes, <int>[1, 2, 3, 4]);
    expect(d.entries, isEmpty);
  });

  test('an invalid base64 image string warns distinctly and passes through',
      () {
    final ReportDiagnostics d = ReportDiagnostics();
    const ImageElement el =
        ImageElement(id: 'i', bounds: r, source: FieldImageSource('photo'));
    final ReportElement out = resolver(d)
        .resolve(el, row: row(<String, Object?>{'photo': 'not!!base64!!'}));
    expect(out, same(el)); // passthrough on bad data
    expect(d.entries.single.severity, DiagnosticSeverity.warning);
    expect(d.entries.single.message, contains('base64'));
  });

  test('a shape element passes through', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const ShapeElement el =
        ShapeElement(id: 's', bounds: r, kind: ShapeKind.rectangle);
    expect(resolver(d).resolve(el, row: row(<String, Object?>{})), same(el));
  });

  // --- BarcodeElement resolution (036) ---

  test('barcode dataField resolves to the row value (flattened)', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const BarcodeElement el = BarcodeElement(
        id: 'b1',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        symbology: BarcodeSymbology.code128,
        data: '',
        dataField: 'sku');
    final BarcodeElement resolved = resolver(d).resolve(
      el,
      row: row(<String, Object?>{'sku': 'ABC-123'}),
    ) as BarcodeElement;
    expect(resolved.data, 'ABC-123');
    expect(resolved.dataField, isNull);
    expect(d.entries, isEmpty);
  });

  test('unknown dataField warns once and resolves empty', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final JetFunctionRegistry f = JetFunctionRegistry();
    registerBuiltInFunctions(f);
    final ElementResolver res = ElementResolver(
      functions: f,
      diagnostics: d,
      knownFields: <String>{'sku'},
    );
    const BarcodeElement el = BarcodeElement(
        id: 'b1',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        symbology: BarcodeSymbology.code128,
        data: '',
        dataField: 'bogus');
    final BarcodeElement resolved = res.resolve(
      el,
      row: row(<String, Object?>{'sku': 'x'}),
    ) as BarcodeElement;
    expect(resolved.data, '');
    expect(resolved.dataField, isNull);
    expect(d.entries.where((Diagnostic m) => m.elementId == 'b1'), isNotEmpty);
  });

  test('literal data passes through (no dataField)', () {
    final ReportDiagnostics d = ReportDiagnostics();
    const BarcodeElement el = BarcodeElement(
        id: 'b1',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        symbology: BarcodeSymbology.code128,
        data: 'HELLO');
    expect((resolver(d).resolve(el) as BarcodeElement).data, 'HELLO');
  });
}
