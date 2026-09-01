// Confirms the pivot-grid sample is authored correctly: the heading lives in
// the `body.title` slot (not a per-row band under `root.children`, which would
// print once per data row) and the definition is pristine under the library
// validator — the check that would have caught that exact mistake, because
// `report_validation.dart`'s slot check flags a `title`-typed band sitting in
// the detail slot as an error. Public API only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/pivot_sample.dart';

void main() {
  group('pivot sample', () {
    test('the heading is a body.title band, not a per-row band', () {
      final ReportDefinition def = pivotDefinition();

      final Band? title = def.body.title;
      expect(title, isNotNull, reason: 'the heading is a once-per-report band');
      expect(title!.type, BandType.title);
      expect(
        title.elements
            .whereType<TextElement>()
            .any((TextElement e) => e.text == 'Sales by Region and Quarter'),
        isTrue,
        reason: 'the heading text lives on the report title band',
      );

      // The root scope's only child is the crosstab itself — no per-row band
      // duplicates the heading once per master row.
      expect(def.body.root.children, hasLength(1));
      expect(def.body.root.children.single, isA<CrosstabNode>());
    });

    test('validate(pivotDefinition()) reports no errors', () {
      // Asserted on error-severity diagnostics specifically (not `isEmpty` on
      // the whole list): this is the exact check that would have caught the
      // shipped bug — a `title`-typed band in the detail slot is a
      // `slotBand` error — and it should stay narrow enough to survive an
      // unrelated info/warning diagnostic being added to the sample later.
      final List<Diagnostic> errors = validate(pivotDefinition())
          .where((Diagnostic d) => d.severity == DiagnosticSeverity.error)
          .toList();
      expect(errors, isEmpty, reason: errors.map((d) => d.message).join('; '));
    });
  });
}
