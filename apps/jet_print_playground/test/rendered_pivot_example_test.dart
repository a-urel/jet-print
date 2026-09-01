// Renders the pivot sample through the public engine and confirms the
// heading prints exactly once — the shipped bug printed it once per data row
// (16 times, spread across two pages), so a mere presence check would still
// pass with the bug; only a count distinguishes "printed once" from "printed
// per row". Public API only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/rendered_pivot_example.dart';

/// Every text run's joined text, across every page's primitives.
List<String> _allRunTexts(RenderedReport r) => <String>[
      for (int i = 0; i < r.pageCount; i++)
        for (final TextRunPrimitive p
            in r.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          p.lines.map((TextLine l) => l.text).join(),
    ];

void main() {
  group('rendered pivot example', () {
    test('the heading prints exactly once', () {
      final RenderedReport report = renderPivotDefinition();
      final int occurrences = _allRunTexts(report)
          .where((String t) => t == 'Sales by Region and Quarter')
          .length;
      expect(occurrences, 1,
          reason: 'the heading is a report-title band: once per report, '
              'never once per data row');
    });

    test('renders with no error diagnostics', () {
      final RenderedReport report = renderPivotDefinition();
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });
  });
}
