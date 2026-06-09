// Invoice sample (US4 / FR-020, FR-021). The playground defines the invoice
// data structure + a bound master/detail template through the library's public
// API only (the encapsulation test enforces "no src/"), and the app attaches
// the schema so it shows in the Data Source panel.
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/invoice_sample.dart';
import 'package:jet_print_playground/main.dart';

void main() {
  test('invoiceSchema is a master record with a nested lines collection', () {
    expect(invoiceSchema.name, 'Invoice');
    final FieldDef lines =
        invoiceSchema.fields.firstWhere((FieldDef f) => f.name == 'lines');
    expect(lines.type, JetFieldType.collection);
    expect(
      lines.fields.map((FieldDef f) => f.name),
      containsAll(<String>['description', 'qty', 'unitPrice', 'lineTotal']),
    );
  });

  test('the sample template is a master/detail layout with bound tokens', () {
    final ReportTemplate t = invoiceSampleTemplate();

    // A detail band bound to the lines collection, its elements bound to line
    // fields (child scope).
    final ReportBand detail =
        t.bands.firstWhere((ReportBand b) => b.collectionField == 'lines');
    expect(detail.type, BandType.detail);
    final Iterable<String?> lineExprs = detail.elements
        .whereType<TextElement>()
        .map((TextElement e) => e.expression);
    expect(lineExprs, contains(r'$F{description}'));

    // Master fields live outside the collection-bound band.
    final Iterable<String?> masterExprs = t.bands
        .where((ReportBand b) => b.collectionField == null)
        .expand((ReportBand b) => b.elements)
        .whereType<TextElement>()
        .map((TextElement e) => e.expression);
    expect(masterExprs, contains(r'$F{customerName}'));
    expect(masterExprs, contains(r'$F{total}'));

    // Round-trips losslessly through the public file format.
    final ReportTemplate decoded =
        JetReportFormat.decodeJson(JetReportFormat.encodeJson(t));
    expect(
      JetReportFormat.encodeJson(decoded),
      JetReportFormat.encodeJson(t),
    );
  });

  testWidgets('the app attaches the schema (Data Source panel shows it)', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const JetPrintPlaygroundApp());
    await tester.pumpAndSettle();

    // Data Source is the default tab; the attached invoice schema is displayed.
    expect(find.text('Invoice'), findsWidgets); // dataset root
    expect(find.text('customerName'), findsOneWidget); // a schema field
    expect(find.text('lines'), findsOneWidget); // the nested collection node
  });
}
