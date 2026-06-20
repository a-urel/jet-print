// Rendered-barcode example: data source + render through
// `package:jet_print/jet_print.dart` only. Confirms the synthetic products are a
// flat list (one per master row), that each SKU is a genuinely valid EAN-13
// (correct mod-10 check digit, so the barcode scans and matches its number), and
// that they render as a clean, multi-page, 2-column product-label sheet via the
// detail band's native ColumnLayout.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/rendered_barcode_example.dart';

/// Recomputes the EAN-13 check digit for the leading 12 digits of [ean13] and
/// returns whether the 13th digit matches — the standard scanner validity test.
bool _isValidEan13(String ean13) {
  if (ean13.length != 13) return false;
  int sum = 0;
  for (int i = 0; i < 12; i++) {
    final int digit = ean13.codeUnitAt(i) - 0x30;
    sum += digit * (i.isEven ? 1 : 3);
  }
  final int check = (10 - (sum % 10)) % 10;
  return check == ean13.codeUnitAt(12) - 0x30;
}

void main() {
  group('rendered barcode example', () {
    test('ships flat product rows, each with a valid 13-digit EAN-13 SKU', () {
      final DataSet ds = barcodeDataSource().open();
      int rows = 0;
      while (ds.moveNext()) {
        // Each row is a single product (flat fields).
        expect(ds.current.field('product'), isNotNull,
            reason: 'each row is one product');
        final String sku = ds.current.field('sku')! as String;
        expect(sku.length, 13);
        expect(_isValidEan13(sku), isTrue,
            reason: 'every SKU is a genuinely valid, scannable EAN-13: $sku');
        rows++;
      }
      ds.close();
      expect(rows, barcodeRecordCount);
      expect(rows, 28);
    });

    test('renders the label sheet across multiple pages without diagnostics',
        () {
      final RenderedReport report = renderBarcodeDefinition();
      // 28 cells ÷ (2 cols × 7 rows = 14 per page) → 2 pages.
      expect(report.pageCount, greaterThan(1));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
        reason: 'a fully-bound, valid-EAN-13 label definition + matching data '
            'renders cleanly',
      );
    });
  });
}
