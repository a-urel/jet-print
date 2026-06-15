// Confirms the nested-list sample (Customer ▸ Order ▸ Line) is authored as a
// genuinely nested tree in the reified band model (spec 024): two collection
// scopes deep, with per-record chrome expressed the supported way (a customer
// GroupLevel) so the definition is pristine under the library validator, and
// rendering it through the native renderDefinition path is clean — all through
// `package:jet_print/jet_print.dart` only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/nested_list_sample.dart';
import 'package:jet_print_playground/rendered_nested_list_example.dart';

void main() {
  group('nested-list sample', () {
    test('is authored Customer ▸ Order ▸ Line, two nested scopes deep', () {
      final ReportDefinition def = nestedListsDefinition();

      // Page chrome lives in record-blind furniture.
      expect(def.furniture.pageHeader?.type, BandType.pageHeader);
      expect(def.furniture.pageFooter?.type, BandType.pageFooter);

      // The master scope iterates customers (a root scope carries no
      // collectionField).
      final DetailScope root = def.body.root;
      expect(root.collectionField, isNull);

      // The customer is a first-class group owning its header/footer chrome —
      // the supported home for per-record header+footer (cf. the invoice).
      expect(root.groups, hasLength(1));
      final GroupLevel customer = root.groups.single;
      expect(customer.key, r'$F{customerCode}');
      expect(customer.header?.type, BandType.groupHeader);
      expect(customer.footer?.type, BandType.groupFooter);

      // List #1: orders nested under the customer.
      expect(root.children, hasLength(1));
      final DetailScope orders = (root.children.single as NestedScope).scope;
      expect(orders.collectionField, 'orders');

      // Each order emits one per-order band (the reified per-row `detail` slot)
      // followed by its lines.
      expect(orders.children.first, isA<BandNode>());
      expect((orders.children.first as BandNode).band.type, BandType.detail);

      // List #2: lines nested under each order — a list within a list.
      final DetailScope lines =
          orders.children.whereType<NestedScope>().single.scope;
      expect(lines.collectionField, 'lines');
      expect(lines.children.single, isA<BandNode>());
      expect((lines.children.single as BandNode).band.type, BandType.detail);
    });

    test('declares a report-scoped grand total over the customer totals', () {
      final ReportDefinition def = nestedListsDefinition();
      expect(def.variables, hasLength(1));
      final ReportVariable grand = def.variables.single;
      expect(grand.calculation, JetCalculation.sum);
      expect(grand.resetScope, VariableResetScope.report);
      expect(grand.expression, r'$F{customerTotal}');
      // Surfaced once at the end, in the summary band.
      expect(def.body.summary?.type, BandType.summary);
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(nestedListsDefinition()), isEmpty);
    });

    test('renderDefinition fills the nested customers/orders/lines cleanly',
        () {
      final RenderedReport report = renderNestedListsDefinition();
      expect(report.pageCount, greaterThan(0));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
        reason:
            'a fully-bound nested definition + matching data renders cleanly',
      );
    });
  });
}
