// Rendered payroll example: data source + render through
// `package:jet_print/jet_print.dart` only. Confirms the run fills cleanly and
// that the live section folds, the net figure, the department subtotals and the
// company grand total all equal the sums of the SAME sample data — so the proof
// and the render can never silently drift apart.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/jet_print.dart';
// Implementation imports for the rendered-run proof — the same reach-in the
// engine's own tests use (cf. rendered_packing_slip_example_test.dart).
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/rendered_payroll_example.dart';

final NumberFormat _money = NumberFormat('#,##0.00');

List<Map<String, Object?>> _coll(Map<String, Object?> emp, String key) =>
    (emp[key]! as List<Object?>).cast<Map<String, Object?>>();

double _sum(List<Map<String, Object?>> rows, String field) => rows.fold<double>(
    0, (double s, Map<String, Object?> r) => s + (r[field]! as num));

void main() {
  group('rendered payroll example', () {
    test('has four employees across two departments, ordered by department',
        () {
      expect(kSamplePayroll, hasLength(4));
      final List<String> depts = <String>[
        for (final Map<String, Object?> e in kSamplePayroll)
          e['department']! as String,
      ];
      // Sorted-by-department invariant: equal departments are contiguous.
      final List<String> sorted = (depts.toSet().toList()
            ..sort((String a, String b) =>
                depts.indexOf(a).compareTo(depts.indexOf(b))))
          .expand((String d) => depts.where((String x) => x == d))
          .toList();
      expect(depts, sorted);
      expect(depts.toSet(), hasLength(2));
    });

    test('stored employee totals equal the live line-item sums', () {
      for (final Map<String, Object?> e in kSamplePayroll) {
        final double gross = _sum(_coll(e, 'earnings'), 'earnAmount');
        final double ded = _sum(_coll(e, 'deductions'), 'dedAmount');
        expect((e['grossPay']! as num).toDouble(), closeTo(gross, 0.001),
            reason: '${e['empNo']} grossPay equals its earnings sum');
        expect((e['totalDeductions']! as num).toDouble(), closeTo(ded, 0.001),
            reason: '${e['empNo']} totalDeductions equals its deductions sum');
        expect((e['netPay']! as num).toDouble(), closeTo(gross - ded, 0.001),
            reason: '${e['empNo']} netPay equals gross - deductions');
      }
    });

    test('renders cleanly (no error diagnostics)', () {
      final RenderedReport report = renderPayrollDefinition();
      expect(report.pageCount, greaterThan(0));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });

    test('per-employee gross / deductions / net equal the live sums', () {
      final RenderedReport report = renderPayrollDefinition();
      final List<String> expectedGross = <String>[
        for (final Map<String, Object?> e in kSamplePayroll)
          _money.format(_sum(_coll(e, 'earnings'), 'earnAmount')),
      ];
      final List<String> expectedDed = <String>[
        for (final Map<String, Object?> e in kSamplePayroll)
          _money.format(_sum(_coll(e, 'deductions'), 'dedAmount')),
      ];
      final List<String> expectedNet = <String>[
        for (final Map<String, Object?> e in kSamplePayroll)
          _money
              .format((e['grossPay']! as num) - (e['totalDeductions']! as num)),
      ];
      expect(_runsForId(report, 'grossValue'), expectedGross);
      expect(_runsForId(report, 'totalDedValue'), expectedDed);
      expect(_runsForId(report, 'netValue'), expectedNet);
    });

    test('department subtotals and company grand total equal the live sums',
        () {
      final RenderedReport report = renderPayrollDefinition();

      // Group employees by department in document order.
      final Map<String, List<Map<String, Object?>>> byDept =
          <String, List<Map<String, Object?>>>{};
      for (final Map<String, Object?> e in kSamplePayroll) {
        byDept
            .putIfAbsent(
                e['department']! as String, () => <Map<String, Object?>>[])
            .add(e);
      }
      final List<String> expectedDeptNet = <String>[
        for (final List<Map<String, Object?>> emps in byDept.values)
          _money.format(emps.fold<double>(0,
              (double s, Map<String, Object?> e) => s + (e['netPay']! as num))),
      ];
      expect(_runsForId(report, 'deptNet'), expectedDeptNet);

      final double grandGross = kSamplePayroll.fold<double>(
          0, (double s, Map<String, Object?> e) => s + (e['grossPay']! as num));
      final double grandNet = kSamplePayroll.fold<double>(
          0, (double s, Map<String, Object?> e) => s + (e['netPay']! as num));
      expect(_runsForId(report, 'grandGross'),
          <String>[_money.format(grandGross)]);
      expect(_runsForId(report, 'grandNet'), <String>[_money.format(grandNet)]);
    });
  });
}

/// The rendered text runs of [elementId], in paint order across all pages.
List<String> _runsForId(RenderedReport report, String elementId) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          if (p.elementId == elementId)
            p.lines.map((TextLine l) => l.text).join(),
    ];
