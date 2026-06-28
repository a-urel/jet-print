// The ledger sample definition + schema (spec 040). Authored through the public
// API only; this pins the schema and the summary aggregates.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/ledger_sample.dart';

void main() {
  group('ledger sample', () {
    test('schema declares the seven transaction fields, typed', () {
      expect(ledgerSchema.fields, const <FieldDef>[
        FieldDef('time', type: JetFieldType.string),
        FieldDef('receiptNo', type: JetFieldType.string),
        FieldDef('item', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('unitPrice', type: JetFieldType.double),
        FieldDef('amount', type: JetFieldType.double),
        FieldDef('status', type: JetFieldType.string),
      ]);
    });

    test('the report title is a body.title band, not in the page header', () {
      final ReportDefinition def = ledgerSampleDefinition();

      final Band? title = def.body.title;
      expect(title, isNotNull, reason: 'the report header exists');
      expect(title!.type, BandType.title);
      expect(
        title.elements
            .whereType<TextElement>()
            .any((TextElement e) => e.text == 'Sales Ledger'),
        isTrue,
        reason: 'the title text lives on the report header',
      );

      // The page header no longer carries the title element.
      final Set<String> headerIds = def.furniture.pageHeader!.elements
          .map((ReportElement e) => e.id)
          .toSet();
      expect(headerIds.contains('title'), isFalse);
    });

    test('has a single detail band and a summary with the grand totals', () {
      final ReportDefinition def = ledgerSampleDefinition();
      // Exactly one per-row (detail) band under the root scope.
      final List<ScopeNode> children = def.body.root.children;
      expect(children.whereType<BandNode>().length, 1);
      final BandNode detail = children.whereType<BandNode>().single;
      expect(detail.band.type, BandType.detail);
      expect(detail.band.id, 'txn');

      // The summary band exists with the two aggregate elements.
      final Band? summary = def.body.summary;
      expect(summary, isNotNull);
      expect(summary!.type, BandType.summary);
      final Map<String, String?> exprById = <String, String?>{
        for (final ReportElement e in summary.elements)
          if (e is TextElement) e.id: e.expression,
      };
      expect(exprById['txnCount'], r'COUNT($F{receiptNo})');
      expect(exprById['grandSum'], r'SUM($F{amount})');
    });
  });
}
