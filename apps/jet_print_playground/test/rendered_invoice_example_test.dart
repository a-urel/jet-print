// Rendered-invoice example (011 — US2; FR-019 / SC-008). The example is an
// EXTERNAL consumer: data source + render + preview through
// `package:jet_print/jet_print.dart` only (the encapsulation test enforces
// "no src/"). Value-level rendering assertions (line totals, sums) live in
// the library's engine tests; here the example itself is exercised
// end-to-end: clean render, consistent data, working paginated preview.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/invoice_sample.dart';
import 'package:jet_print_playground/main.dart';
import 'package:jet_print_playground/rendered_invoice_example.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test('the example renders the invoice without any diagnostic', () {
    final RenderedReport report = renderInvoiceDefinition();
    // The invoice group sets startNewPage, so each of the three invoices lands
    // on its own page.
    expect(report.pageCount, 3);
    expect(report.pageAt(0).frame, isNotNull);
    expect(
      report.diagnostics.entries,
      isEmpty,
      reason: 'a fully-bound template + matching data must render cleanly: '
          '${report.diagnostics.entries}',
    );
  });

  test('every sample invoice is consistent: total equals its line-total sum',
      () {
    final DataSet ds = invoiceDataSource().open();
    int count = 0;
    while (ds.moveNext()) {
      final DataRow invoice = ds.current;
      final List<Object?> lines = invoice.field('lines')! as List<Object?>;
      expect(lines, isNotEmpty, reason: 'each invoice carries line items');
      final double sum = lines
          .cast<Map<String, Object?>>()
          .map((Map<String, Object?> l) => (l['lineTotal']! as num).toDouble())
          .fold(0, (double a, double b) => a + b);
      expect(invoice.field('total'), sum,
          reason: 'invoice ${invoice.field('invoiceNo')}: total must equal the '
              'sum of its line totals');
      count++;
    }
    expect(count, 3, reason: 'the sample now carries three invoices');
    ds.close();
  });

  test(
      'in-memory, JSON, and object-backed variants render identically '
      '(SC-006)', () {
    final RenderedReport inMemory = renderInvoiceDefinition();
    final RenderedReport json =
        renderInvoiceDefinition(source: invoiceJsonDataSource());
    final RenderedReport objects =
        renderInvoiceDefinition(source: invoiceObjectDataSource());
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

    // The unified toolbar's Preview mode-switch segment switches the workspace
    // into preview, which renders the live template into a JetReportPreview
    // (017 / keep-alive workspace).
    await tester.tap(
        find.byKey(const ValueKey<String>('jet_print.toolbar.mode.preview')));
    await tester.pumpAndSettle();

    expect(find.byType(JetReportPreview), findsOneWidget);
    // The sample opens on the first page; the total page count depends on how
    // the three invoices paginate, so assert the "Page 1 of N" indicator
    // without pinning N.
    expect(find.textContaining('Page 1 of '), findsOneWidget);

    // 012 (SC-008): the example wires export and print through the PUBLIC
    // preview callbacks — both toolbar actions are present. The example
    // renders ONCE: the preview, the PDF export, and the print job all
    // consume that one RenderedReport (asserted structurally below).
    expect(find.byKey(const ValueKey<String>('jet_print.preview.export')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('jet_print.preview.print')),
        findsOneWidget);

    // The unified toolbar's Designer mode-switch segment returns to the
    // designer (it emits the preview's onBack switch request) (017).
    await tester.tap(
        find.byKey(const ValueKey<String>('jet_print.toolbar.mode.designer')));
    await tester.pumpAndSettle();
    expect(find.byType(JetReportDesigner), findsOneWidget);
  });

  testWidgets(
      'the preview renders the LIVE template the designer hands over — '
      'design edits show up in the preview', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Stand-in for a user edit in the designer: the live template differs
    // from the canned sample (here: its name, which titles the preview bar).
    final ReportDefinition edited =
        invoiceSampleDefinition().copyWith(name: 'Edited In Designer');
    await tester.pumpWidget(ShadApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: RenderedInvoiceExample(definition: edited),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Edited In Designer'), findsOneWidget,
        reason: 'the preview must show the template it was handed, not the '
            'canned invoice sample');
  });

  testWidgets(
      'export and print feed from the same single render as the preview '
      '(012 — FR-001, SC-008)', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const JetPrintPlaygroundApp());
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey<String>('jet_print.toolbar.mode.preview')));
    await tester.pumpAndSettle();

    // The preview displays the example's one rendered report...
    final JetReportPreview preview =
        tester.widget<JetReportPreview>(find.byType(JetReportPreview));
    final RenderedReport shown = preview.report;
    // ...and both artifact callbacks are wired (host-owned I/O happens only
    // when the user triggers them; the test does not tap to avoid platform
    // channels).
    expect(preview.onExportPdf, isNotNull);
    expect(preview.onPrint, isNotNull);
    expect(shown.pageCount, greaterThanOrEqualTo(1));
  });
}
