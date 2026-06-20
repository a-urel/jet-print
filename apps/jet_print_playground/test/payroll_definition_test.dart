// Confirms the payroll sample (Employee ▸ earnings / deductions) is authored as
// a department-grouped, dual-nested tree in the reified band model: two parallel
// nested collections under the employee, master-scope subtotals/grand totals as
// inline aggregates, a verification QR — pristine under the validator. All
// through `package:jet_print/jet_print.dart` only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/payroll_sample.dart';

void main() {
  group('payroll sample', () {
    test('schema is Employee ▸ earnings / deductions with stored measures', () {
      final FieldDef earnings =
          payrollSchema.fields.firstWhere((FieldDef f) => f.name == 'earnings');
      final FieldDef deductions = payrollSchema.fields
          .firstWhere((FieldDef f) => f.name == 'deductions');
      expect(earnings.type, JetFieldType.collection);
      expect(deductions.type, JetFieldType.collection);
      expect(
        earnings.fields.firstWhere((FieldDef f) => f.name == 'earnAmount').type,
        JetFieldType.double,
      );
      expect(
        deductions.fields
            .firstWhere((FieldDef f) => f.name == 'dedAmount')
            .type,
        JetFieldType.double,
      );
      // Authoritative employee-level totals are stored, too.
      for (final String name in <String>[
        'grossPay',
        'totalDeductions',
        'netPay'
      ]) {
        expect(
            payrollSchema.fields
                .firstWhere((FieldDef f) => f.name == name)
                .type,
            JetFieldType.double);
      }
    });

    test('is grouped department ▸ employee with two parallel nested scopes',
        () {
      final ReportDefinition def = payrollDefinition();
      final DetailScope root = def.body.root;

      // Master scope iterates employees (no collectionField on root).
      expect(root.collectionField, isNull);

      // Two group levels, outermost first: department then employee.
      expect(root.groups, hasLength(2));
      expect(root.groups[0].key, r'$F{department}');
      expect(root.groups[1].key, r'$F{empNo}');
      expect(root.groups[0].header?.type, BandType.groupHeader);
      expect(root.groups[0].footer?.type, BandType.groupFooter);
      expect(root.groups[1].header?.type, BandType.groupHeader);
      expect(root.groups[1].footer?.type, BandType.groupFooter);

      // Employee scope holds exactly two NestedScopes (no per-row bands) —
      // earnings and deductions in order.
      expect(root.children.whereType<BandNode>(), isEmpty);
      final List<DetailScope> nested = root.children
          .whereType<NestedScope>()
          .map((NestedScope n) => n.scope)
          .toList();
      expect(nested.map((DetailScope s) => s.collectionField),
          <String>['earnings', 'deductions']);
      // Each nested scope has exactly one per-row band and a footer.
      for (final DetailScope s in nested) {
        expect(s.children.whereType<BandNode>(), hasLength(1));
        expect((s.children.single as BandNode).band.type, BandType.detail);
        expect(s.footer?.type, BandType.groupFooter);
      }
    });

    test('totals are inline aggregates in legal sinks; net is arithmetic', () {
      final ReportDefinition def = payrollDefinition();
      expect(def.variables, isEmpty);
      final DetailScope root = def.body.root;
      final DetailScope earnings = root.children
          .whereType<NestedScope>()
          .firstWhere((NestedScope n) => n.scope.collectionField == 'earnings')
          .scope;
      final DetailScope deductions = root.children
          .whereType<NestedScope>()
          .firstWhere(
              (NestedScope n) => n.scope.collectionField == 'deductions')
          .scope;

      TextElement el(Band b, String id) =>
          b.elements.firstWhere((ReportElement e) => e.id == id) as TextElement;

      // Section folds (same-scope, spec 029).
      expect(el(earnings.footer!, 'grossValue').expression,
          r'SUM($F{earnAmount})');
      expect(el(deductions.footer!, 'totalDedValue').expression,
          r'SUM($F{dedAmount})');

      // Net pay = field arithmetic in the employee group footer.
      expect(el(root.groups[1].footer!, 'netValue').expression,
          r'$F{grossPay} - $F{totalDeductions}');

      // Department subtotals (master-scope, spec 028) and grand totals (summary).
      expect(
          el(root.groups[0].footer!, 'deptNet').expression, r'SUM($F{netPay})');
      expect(
          el(def.body.summary!, 'grandGross').expression, r'SUM($F{grossPay})');
      expect(el(def.body.summary!, 'grandNet').expression, r'SUM($F{netPay})');
    });

    test('the verification code is a QR bound to verifyToken', () {
      final ReportDefinition def = payrollDefinition();
      final BarcodeElement qr = def.body.root.groups[1].header!.elements
              .firstWhere((ReportElement e) => e.id == 'verifyQr')
          as BarcodeElement;
      expect(qr.symbology, BarcodeSymbology.qrCode);
      expect(qr.dataField, 'verifyToken');
      expect(qr.data, isNotEmpty);
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(payrollDefinition()), isEmpty);
    });
  });
}
