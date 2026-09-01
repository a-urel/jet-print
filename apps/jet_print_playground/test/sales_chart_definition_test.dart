// Confirms the sales-chart sample is authored correctly: the heading lives in
// the `body.title` slot (not a per-row band under `root.children`, where a
// band's role comes from the slot it occupies rather than its `BandType` tag,
// so it would reprint once per master row) and the definition is pristine
// under the library validator. The bug this guards is LATENT here — the sample
// data has a single master row, so a misplaced title still prints once — which
// is exactly why the validator, not the rendered output, is the check that
// catches it. Public API only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/sales_chart_sample.dart';

void main() {
  group('sales chart sample', () {
    test('the heading is a body.title band, not a per-row band', () {
      final ReportDefinition def = salesChartDefinition();

      final Band? title = def.body.title;
      expect(title, isNotNull, reason: 'the heading is a once-per-report band');
      expect(title!.type, BandType.title);
      expect(
        title.elements
            .whereType<TextElement>()
            .any((TextElement e) => e.text == 'Monthly Sales'),
        isTrue,
        reason: 'the heading text lives on the report title band',
      );

      // Only the three chart bands remain per-row; no title band among them.
      expect(
        def.body.root.children
            .whereType<BandNode>()
            .map((BandNode n) => n.band.id),
        <String>['barBand', 'lineBand', 'pieBand'],
      );
    });

    test('validate(salesChartDefinition()) reports no errors', () {
      // Error-severity only (not `isEmpty` on the whole list): this is the
      // exact check that flags a `title`-typed band in the detail slot, and it
      // should survive an unrelated info/warning being added to the sample.
      final List<Diagnostic> errors = validate(salesChartDefinition())
          .where((Diagnostic d) => d.severity == DiagnosticSeverity.error)
          .toList();
      expect(errors, isEmpty,
          reason: errors.map((Diagnostic d) => d.message).join('; '));
    });
  });
}
