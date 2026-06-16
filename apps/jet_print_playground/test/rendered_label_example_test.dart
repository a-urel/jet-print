// Rendered-label example: data source + render through
// `package:jet_print/jet_print.dart` only. Confirms the 100 synthetic
// addresses chunk into rows of three and render as a clean, multi-page label
// sheet.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/label_sample.dart';
import 'package:jet_print_playground/rendered_label_example.dart';

void main() {
  group('rendered label example', () {
    test('chunks 100 addresses into 34 rows of up to three cells', () {
      final DataSet ds = labelDataSource().open();
      int rows = 0;
      while (ds.moveNext()) {
        // Every row fills its first cell; only the trailing row may be partial.
        expect(ds.current.field('c0Name'), isNotNull,
            reason: 'each row carries at least one label');
        rows++;
      }
      ds.close();
      // 100 ÷ 3 = 33 full rows + 1 partial.
      expect(rows, (labelRecordCount / labelColumns).ceil());
      expect(rows, 34);
    });

    test('renders the label sheet across multiple pages without diagnostics',
        () {
      final RenderedReport report = renderLabelDefinition();
      // 34 rows ÷ 8 per page → 5 pages.
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
