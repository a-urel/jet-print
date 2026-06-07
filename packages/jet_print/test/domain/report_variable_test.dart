// ReportVariable value type + serialization (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_variable.dart';

void main() {
  group('ReportVariable', () {
    test('round-trips a group-scoped sum', () {
      const ReportVariable v = ReportVariable(
        name: 'catTotal',
        expression: r'$F{amount}',
        calculation: JetCalculation.sum,
        resetScope: VariableResetScope.group,
        resetGroup: 'category',
      );
      expect(ReportVariable.fromJson(v.toJson()), v);
    });

    test('defaults are sparse (none / report / no group)', () {
      const ReportVariable v = ReportVariable(name: 'v', expression: '1');
      final Map<String, Object?> json = v.toJson();
      expect(json.containsKey('calculation'), isFalse);
      expect(json.containsKey('resetScope'), isFalse);
      expect(json.containsKey('resetGroup'), isFalse);
      expect(ReportVariable.fromJson(json), v);
      expect(v.calculation, JetCalculation.none);
      expect(v.resetScope, VariableResetScope.report);
      expect(v.resetGroup, isNull);
    });

    test('round-trips a report-scoped grand total', () {
      const ReportVariable v = ReportVariable(
        name: 'grand',
        expression: r'$F{amount}',
        calculation: JetCalculation.sum,
      );
      expect(ReportVariable.fromJson(v.toJson()), v);
      expect(v.toJson().containsKey('resetScope'), isFalse); // report = default
    });

    test('has value equality and a consistent hash code', () {
      expect(const ReportVariable(name: 'a', expression: '1'),
          const ReportVariable(name: 'a', expression: '1'));
      expect(const ReportVariable(name: 'a', expression: '1').hashCode,
          const ReportVariable(name: 'a', expression: '1').hashCode);
      expect(
          const ReportVariable(
                  name: 'a',
                  expression: '1',
                  calculation: JetCalculation.sum) ==
              const ReportVariable(name: 'a', expression: '1'),
          isFalse);
    });
  });
}
