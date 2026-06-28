// Rendered sales-ledger example (spec 040): a JetPagedDataSource drives a
// multi-page render whose grand totals equal the deterministic feed's sums, and
// the paged source renders identically to an in-memory source over the same rows.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/ledger_sample.dart';
import 'package:jet_print_playground/rendered_ledger_example.dart';

/// The rendered text of [elementId] on a single [pageIndex], runs joined.
List<String> _runsOnPage(RenderedReport r, int pageIndex, String elementId) =>
    <String>[
      for (final TextRunPrimitive p
          in r.pageAt(pageIndex).frame.primitives.whereType<TextRunPrimitive>())
        if (p.elementId == elementId)
          p.lines.map((TextLine l) => l.text).join(),
    ];

/// Every text run across all pages, tagged by page + element, for parity.
List<String> _allRuns(RenderedReport r) => <String>[
      for (int i = 0; i < r.pageCount; i++)
        for (final TextRunPrimitive p
            in r.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          '$i|${p.elementId}|${p.lines.map((TextLine l) => l.text).join()}',
    ];

void main() {
  group('rendered sales-ledger example', () {
    test('renders many pages with no error diagnostics', () {
      final RenderedReport report = renderLedgerDefinition();
      expect(report.pageCount, greaterThan(1));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });

    test('the report title renders once (first page only)', () {
      final RenderedReport report = renderLedgerDefinition();
      final List<int> pagesWithTitle = <int>[
        for (int i = 0; i < report.pageCount; i++)
          if (_runsOnPage(report, i, 'title').isNotEmpty) i,
      ];
      expect(pagesWithTitle, <int>[0],
          reason: 'the report header prints once at the very start');
    });

    test('grand totals equal the deterministic feed sums', () {
      final RenderedReport report = renderLedgerDefinition();
      double sum = 0;
      for (int i = 0; i < kLedgerRowCount; i++) {
        sum += ledgerAmountAt(i);
      }
      final int last = report.pageCount - 1; // summary prints once, at the end
      expect(_runsOnPage(report, last, 'grandSum'),
          <String>[NumberFormat(r'#,##0.00').format(sum)]);
      expect(_runsOnPage(report, last, 'txnCount'),
          <String>[NumberFormat(r'#,##0').format(kLedgerRowCount)]);
    });

    test('paged source renders identically to in-memory over the same rows',
        () {
      final List<Map<String, Object?>> fixture = <Map<String, Object?>>[
        for (int i = 0; i < 5; i++) ledgerRowAt(i),
      ];
      const int pageSize = 2;
      final JetDataSource paged = JetPagedDataSource(
        fields: ledgerSchema.fields,
        pageSize: pageSize,
        fetchPage: (int p) {
          final int start = p * pageSize;
          if (start >= fixture.length) return const <Map<String, Object?>>[];
          final int end = (start + pageSize) > fixture.length
              ? fixture.length
              : start + pageSize;
          return fixture.sublist(start, end);
        },
      );
      final JetDataSource inMemory =
          JetInMemoryDataSource(fixture, fields: ledgerSchema.fields);

      final RenderedReport a = renderLedgerDefinition(source: paged);
      final RenderedReport b = renderLedgerDefinition(source: inMemory);
      expect(a.pageCount, b.pageCount);
      expect(_allRuns(a), _allRuns(b));
    });
  });
}
