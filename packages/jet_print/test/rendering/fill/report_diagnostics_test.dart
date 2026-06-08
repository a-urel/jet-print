// ReportDiagnostics: a collected info/warning/error list (render-don't-crash).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';

void main() {
  test('collects entries by severity and reports hasErrors', () {
    final ReportDiagnostics d = ReportDiagnostics();
    expect(d.hasErrors, isFalse);
    d.info('opened');
    d.warning('field "x" missing', elementId: 'e1');
    expect(d.hasErrors, isFalse);
    d.error('bad expression', elementId: 'e2');
    expect(d.hasErrors, isTrue);

    expect(d.entries.length, 3);
    expect(d.entries[1].severity, DiagnosticSeverity.warning);
    expect(d.entries[1].message, 'field "x" missing');
    expect(d.entries[1].elementId, 'e1');
    expect(d.entries[2].severity, DiagnosticSeverity.error);
  });
}
