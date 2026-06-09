// FillEvalContext: missing-field warnings (deduped) + page-scoped ref recording.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/fill_eval_context.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';

DataRow rowWith(String field, Object? value) => DataRow(
      fields: <FieldDef>[FieldDef(field, type: JetFieldType.string)],
      values: <String, Object?>{field: value},
    );

FillEvalContext ctx({
  DataRow? row,
  required ReportDiagnostics diagnostics,
  Set<String>? warned,
  Set<String>? pageRefs,
  String? elementId,
}) =>
    FillEvalContext(
      row: row,
      functions: JetFunctionRegistry(),
      diagnostics: diagnostics,
      warnedFields: warned ?? <String>{},
      pageRefs: pageRefs ?? <String>{},
      elementId: elementId,
    );

void main() {
  test('an absent field warns once (deduped) and resolves to null', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final Set<String> warned = <String>{};
    final FillEvalContext c = ctx(
        row: rowWith('present', 'v'),
        diagnostics: d,
        warned: warned,
        elementId: 'e1');
    expect(c.resolveField('missing'), const JetNull());
    expect(c.resolveField('missing'), const JetNull()); // again
    expect(
        d.entries.where((e) => e.severity == DiagnosticSeverity.warning).length,
        1);
    expect(d.entries.first.elementId, 'e1');
  });

  test('a declared field (even null) does not warn', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final FillEvalContext c =
        ctx(row: rowWith('present', null), diagnostics: d);
    expect(c.resolveField('present'), const JetNull()); // declared-null
    expect(d.entries, isEmpty);
  });

  test('no row never warns on field access', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final FillEvalContext c = ctx(row: null, diagnostics: d);
    expect(c.resolveField('anything'), const JetNull());
    expect(d.entries, isEmpty);
  });

  test('a reserved page-scoped variable is recorded; others resolve normally',
      () {
    final ReportDiagnostics d = ReportDiagnostics();
    final Set<String> pageRefs = <String>{};
    final FillEvalContext c = ctx(diagnostics: d, pageRefs: pageRefs);
    expect(c.resolveVariable('PAGE_NUMBER'), const JetNull());
    expect(pageRefs, contains('PAGE_NUMBER'));
    expect(c.resolveVariable('other'),
        const JetNull()); // undeclared, not recorded
    expect(pageRefs, isNot(contains('other')));
  });

  test('dedup spans multiple contexts sharing one warnedFields sink', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final Set<String> warned = <String>{};
    // Two separate contexts (as the resolver builds one per element) sharing the
    // same caller-owned warnedFields set: the same missing field warns only once.
    ctx(
            row: rowWith('present', 'v'),
            diagnostics: d,
            warned: warned,
            elementId: 'e1')
        .resolveField('missing');
    ctx(
            row: rowWith('present', 'v'),
            diagnostics: d,
            warned: warned,
            elementId: 'e2')
        .resolveField('missing');
    expect(
        d.entries.where((e) => e.severity == DiagnosticSeverity.warning).length,
        1);
  });

  test('a declared variable resolves to its value and is not recorded', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final Set<String> pageRefs = <String>{};
    final FillEvalContext c = FillEvalContext(
      functions: JetFunctionRegistry(),
      diagnostics: d,
      warnedFields: <String>{},
      pageRefs: pageRefs,
      variables: const <String, JetValue>{'myVar': JetNumber(7)},
    );
    expect(c.resolveVariable('myVar'), const JetNumber(7));
    expect(pageRefs, isEmpty);
  });
}
