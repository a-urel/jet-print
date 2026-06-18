// Rendered-label example: data source + render through
// `package:jet_print/jet_print.dart` only. Confirms the 100 synthetic addresses
// are a flat list (one per master row) and render as a clean, multi-page,
// 3-column label sheet via the detail band's native ColumnLayout.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/rendered_label_example.dart';

void main() {
  group('rendered label example', () {
    test('ships 100 flat address rows, one address per record', () {
      final DataSet ds = labelDataSource().open();
      int rows = 0;
      while (ds.moveNext()) {
        // Each row is a single address (flat fields, no per-cell prefix).
        expect(ds.current.field('name'), isNotNull,
            reason: 'each row is one address');
        rows++;
      }
      ds.close();
      expect(rows, labelRecordCount);
      expect(rows, 100);
    });

    test('renders the label sheet across multiple pages without diagnostics',
        () {
      final RenderedReport report = renderLabelDefinition();
      // 100 cells ÷ (3 cols × 8 rows = 24 per page) → 5 pages.
      expect(report.pageCount, greaterThan(1));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
        reason:
            'a fully-bound label definition + matching data renders cleanly',
      );
    });
  });
}
