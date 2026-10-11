// `hasErrors` on any collection of diagnostics (#98): the author-time list
// `validate` returns gets the same predicate the render-time carrier has.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/diagnostic.dart';

const Diagnostic _info = Diagnostic(DiagnosticSeverity.info, 'i');
const Diagnostic _warning = Diagnostic(DiagnosticSeverity.warning, 'w');
const Diagnostic _error = Diagnostic(DiagnosticSeverity.error, 'e');

void main() {
  test('an empty collection has no errors', () {
    expect(const <Diagnostic>[].hasErrors, isFalse);
  });

  test('info and warnings are not errors', () {
    expect(const <Diagnostic>[_info, _warning].hasErrors, isFalse);
  });

  test('one error anywhere is enough', () {
    expect(const <Diagnostic>[_info, _error, _warning].hasErrors, isTrue);
  });

  test('works on any iterable, not only a list', () {
    expect(<Diagnostic>{_warning, _error}.hasErrors, isTrue);
    expect(const <Diagnostic>[_error].where((Diagnostic d) => false).hasErrors,
        isFalse);
  });
}
