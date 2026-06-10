// Rendered-invoice example (011 — US2; FR-019 / SC-008). The example is an
// EXTERNAL consumer: data source + render + preview through
// `package:jet_print/jet_print.dart` only (the encapsulation test enforces
// "no src/"). Value-level rendering assertions (line totals, sums) live in
// the library's engine tests; here the example itself is exercised
// end-to-end: clean render, consistent data, working paginated preview.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/main.dart';
import 'package:jet_print_playground/rendered_invoice_example.dart';

void main() {
  test('the example renders the invoice without any diagnostic', () {
    final RenderedReport report = renderInvoice();
    expect(report.pageCount, greaterThanOrEqualTo(1));
    expect(report.pageAt(0).frame, isNotNull);
    expect(
      report.diagnostics.entries,
      isEmpty,
      reason: 'a fully-bound template + matching data must render cleanly: '
          '${report.diagnostics.entries}',
    );
  });

  test('the sample data is consistent: total equals the sum of line totals',
      () {
    final DataSet ds = invoiceDataSource().open();
    expect(ds.moveNext(), isTrue);
    final DataRow invoice = ds.current;
    final List<Object?> lines = invoice.field('lines')! as List<Object?>;
    expect(lines, hasLength(3), reason: 'each line item appears once');
    final double sum = lines
        .cast<Map<String, Object?>>()
        .map((Map<String, Object?> l) => (l['lineTotal']! as num).toDouble())
        .fold(0, (double a, double b) => a + b);
    expect(invoice.field('total'), sum);
    expect(ds.moveNext(), isFalse);
    ds.close();
  });

  test(
      'in-memory, JSON, and object-backed variants render identically '
      '(SC-006)', () {
    final RenderedReport inMemory = renderInvoice();
    final RenderedReport json = renderInvoice(source: invoiceJsonDataSource());
    final RenderedReport objects =
        renderInvoice(source: invoiceObjectDataSource());
    expect(json.pageCount, inMemory.pageCount);
    expect(objects.pageCount, inMemory.pageCount);
    for (int i = 0; i < inMemory.pageCount; i++) {
      expect(json.pageAt(i).frame, inMemory.pageAt(i).frame);
      expect(objects.pageAt(i).frame, inMemory.pageAt(i).frame);
    }
  });

  testWidgets('the example opens a navigable paginated preview', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const JetPrintPlaygroundApp());
    await tester.pumpAndSettle();

    // The designer's top-bar Preview action opens the rendered-invoice example.
    await tester.tap(find
        .byKey(const ValueKey<String>('jet_print.designer.action.preview')));
    await tester.pumpAndSettle();

    expect(find.byType(RenderedInvoiceExample), findsOneWidget);
    expect(find.byType(JetReportPreview), findsOneWidget);
    // The one-invoice sample fits a single A4 page; navigation is bounded.
    expect(find.text('Page 1 of 1'), findsOneWidget);

    // The preview toolbar's back button returns to the designer.
    await tester
        .tap(find.byKey(const ValueKey<String>('jet_print.preview.back')));
    await tester.pumpAndSettle();
    expect(find.byType(JetReportDesigner), findsOneWidget);
  });
}
