// DiagnosticBudget: row-tagging, within-row dedup, cap + suppression (spec E2).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/rendering/fill/diagnostic_budget.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';

void main() {
  test('prefixes the recorded message with the current row position', () {
    final ReportDiagnostics sink = ReportDiagnostics();
    final DiagnosticBudget b = DiagnosticBudget(sink)..row = 7;
    b.recordRowIssue('k', 'something is off', elementId: 'e1');
    expect(sink.entries, hasLength(1));
    expect(sink.entries.single.message, 'Row 7: something is off');
    expect(sink.entries.single.severity, DiagnosticSeverity.warning);
    expect(sink.entries.single.elementId, 'e1');
  });

  test('dedups by key within a row but re-allows it after the row advances',
      () {
    final ReportDiagnostics sink = ReportDiagnostics();
    final DiagnosticBudget b = DiagnosticBudget(sink)..row = 1;
    b.recordRowIssue('field:x', 'x missing');
    b.recordRowIssue('field:x', 'x missing'); // same key, same row -> ignored
    expect(sink.entries, hasLength(1));
    b.row = 2;
    b.recordRowIssue('field:x', 'x missing'); // new row -> recorded again
    expect(sink.entries, hasLength(2));
    expect(sink.entries.last.message, 'Row 2: x missing');
  });

  test('caps at kMaxPerRowDataDiagnostics and summarizes the remainder', () {
    final ReportDiagnostics sink = ReportDiagnostics();
    final DiagnosticBudget b = DiagnosticBudget(sink);
    const int over = DiagnosticBudget.kMaxPerRowDataDiagnostics + 25;
    for (int i = 0; i < over; i++) {
      b.row = i + 1; // distinct key per row, so dedup never blocks
      b.recordRowIssue('agg', 'skip');
    }
    // Only the cap many are recorded so far (no summary until finish()).
    expect(sink.entries, hasLength(DiagnosticBudget.kMaxPerRowDataDiagnostics));
    b.finish();
    final Diagnostic summary = sink.entries.last;
    expect(summary.severity, DiagnosticSeverity.info);
    expect(summary.message, contains('25 more'));
    expect(summary.message, contains('suppressed'));
  });

  test('finish() is a no-op when nothing was suppressed', () {
    final ReportDiagnostics sink = ReportDiagnostics();
    final DiagnosticBudget b = DiagnosticBudget(sink)..row = 1;
    b.recordRowIssue('k', 'one');
    b.finish();
    expect(sink.entries, hasLength(1));
  });
}
