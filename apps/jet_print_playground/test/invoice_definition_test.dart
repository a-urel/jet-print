// Confirms the new architecture end to end (spec 024): the invoice authored in
// the reified band model ([invoiceSampleDefinition]) renders through the native
// `renderDefinition` path — all through `package:jet_print/jet_print.dart` only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/invoice_sample.dart';
import 'package:jet_print_playground/rendered_invoice_example.dart';

void main() {
  test('the demo is authored in the reified band model', () {
    final ReportDefinition def = invoiceSampleDefinition();
    // Page chrome lives in furniture (record-blind).
    expect(def.furniture.pageHeader?.type, BandType.pageHeader);
    expect(def.furniture.pageFooter?.type, BandType.pageFooter);
    // One first-class master group owns its key, flags, and header/footer.
    expect(def.body.root.groups, hasLength(1));
    final GroupLevel invoice = def.body.root.groups.single;
    expect(invoice.name, 'invoice');
    expect(invoice.key, r'$F{invoiceNo}');
    expect(invoice.startNewPage, isTrue);
    expect(invoice.keepTogether, isTrue);
    expect(invoice.header?.type, BandType.groupHeader);
    expect(invoice.footer?.type, BandType.groupFooter);
    // Line items are a nested detail scope holding one per-row band.
    expect(def.body.root.children, hasLength(1));
    final ScopeNode node = def.body.root.children.single;
    expect(node, isA<NestedScope>());
    final DetailScope lines = (node as NestedScope).scope;
    expect(lines.collectionField, 'lines');
    expect(lines.children.single, isA<BandNode>());
  });

  test('renderDefinition renders three invoices, one per page, cleanly', () {
    final RenderedReport report = renderInvoiceDefinition();
    expect(report.pageCount, 3, reason: 'startNewPage → one invoice per page');
    expect(
      report.diagnostics.entries
          .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
      isEmpty,
      reason:
          'a fully-bound reified definition + matching data renders cleanly',
    );
  });
}
