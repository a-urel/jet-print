// test/rendering/fill/visibility_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/rendering/fill/fill_eval_context.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/fill/visibility.dart';

bool _run(BoolProperty p, ReportDiagnostics d) {
  final refs = <String>{};
  final ctx = FillEvalContext(
    functions: JetFunctionRegistry(), // no .standard() factory — plain ctor
    diagnostics: d,
    warnedFields: <String>{},
    pageRefs: refs,
    elementId: 'x',
  );
  return resolveVisibility(p, ctx, d, id: 'x', pageRefs: refs);
}

void main() {
  test('static true / false', () {
    expect(_run(const BoolProperty(), ReportDiagnostics()), isTrue);
    expect(
        _run(const BoolProperty(value: false), ReportDiagnostics()), isFalse);
  });

  test('boolean expression true / false', () {
    expect(_run(const BoolProperty(expression: '1 == 1'), ReportDiagnostics()),
        isTrue);
    expect(_run(const BoolProperty(expression: '1 == 2'), ReportDiagnostics()),
        isFalse);
  });

  test('parse error -> visible + diagnostic', () {
    final d = ReportDiagnostics();
    expect(_run(const BoolProperty(expression: '1 +'), d), isTrue);
    expect(d.entries, isNotEmpty); // accessor is .entries, not .messages
  });

  test('non-boolean result -> visible + diagnostic', () {
    final d = ReportDiagnostics();
    expect(_run(const BoolProperty(expression: '1 + 1'), d), isTrue);
    expect(d.entries, isNotEmpty);
  });
}
