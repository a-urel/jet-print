// 50k-row stress-to-failure (spec E2, Pillar 3): a large dataset with
// scattered wrong-type data must not crash, must keep diagnostics bounded, and
// must still isolate the bad rows (clean rows sum correctly). Time/RSS are
// logged ADVISORY only — there is no perf gate (resilience-only).
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/fill/diagnostic_budget.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

// Keep this CI-stable: a flat report (no images) over N rows. If wall time on
// the dev/CI machine exceeds a few seconds, lower N and record the value in the
// E2 findings doc — do NOT add a time assertion.
const int _n = 50000;
const int _dirtyEvery = 100; // every 100th row has a wrong-type amount

ReportDefinition _def() => ReportDefinition(
      name: 'stress',
      page: PageFormat.a4Portrait,
      variables: const <ReportVariable>[
        ReportVariable(
          name: 'total',
          expression: r'$F{amount}',
          calculation: JetCalculation.sum,
          resetScope: VariableResetScope.report,
        ),
      ],
      body: ReportBody(
        summary: Band(
          id: 'body/summary',
          type: BandType.summary,
          height: 16,
          elements: <ReportElement>[
            TextElement(
                id: 'total',
                bounds: const JetRect(x: 0, y: 0, width: 240, height: 16),
                text: '',
                expression: r'$V{total}'),
          ],
        ),
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 16,
              elements: <ReportElement>[
                TextElement(
                    id: 'name',
                    bounds: const JetRect(x: 0, y: 0, width: 240, height: 16),
                    text: '',
                    expression: r'$F{name}'),
              ])),
        ]),
      ),
    );

JetInMemoryDataSource _dirtyRows(int n) =>
    JetInMemoryDataSource(<Map<String, Object?>>[
      for (int i = 0; i < n; i++)
        <String, Object?>{
          'name': 'row $i',
          // Every _dirtyEvery-th row has a string amount (skipped from SUM).
          'amount': (i % _dirtyEvery == 0) ? 'NaN' : 1.0,
        },
    ]);

String _summaryText(RenderedReport r) {
  for (int p = 0; p < r.pageCount; p++) {
    for (final TextRunPrimitive prim
        in r.pageAt(p).frame.primitives.whereType<TextRunPrimitive>()) {
      if (prim.elementId == 'total') {
        return prim.lines.map((TextLine l) => l.text).join();
      }
    }
  }
  return '<not found>';
}

void main() {
  test(
      '50k rows with scattered wrong-type data: no crash, bounded '
      'diagnostics, clean rows still sum (per-row isolation at scale)', () {
    final int rssBefore = ProcessInfo.currentRss;
    final Stopwatch watch = Stopwatch()..start();

    final RenderedReport report =
        const JetReportEngine().renderDefinition(_def(), _dirtyRows(_n));
    final int pageCount = report.pageCount;
    final List<Diagnostic> entries = report.diagnostics.entries;
    // Force the summary page to build (the last page carries the summary band).
    final String total = _summaryText(report);

    watch.stop();
    final int rssAfter = ProcessInfo.currentRss;
    // ignore: avoid_print
    print('[advisory][E2 stress] N=$_n -> $pageCount pages, '
        '${entries.length} diagnostics, total=$total in '
        '${watch.elapsedMilliseconds} ms, '
        'rssΔ=${((rssAfter - rssBefore) / (1024 * 1024)).round()} MB');

    // Invariant 1: it did not throw (reaching here proves it) and produced pages.
    expect(pageCount, greaterThan(0));

    // Invariant 2: diagnostics are BOUNDED — per-row data warnings cannot exceed
    // the cap, and the suppression summary is present (dirty rows >> cap).
    final int warnings = entries
        .where((Diagnostic d) => d.severity == DiagnosticSeverity.warning)
        .length;
    expect(warnings,
        lessThanOrEqualTo(DiagnosticBudget.kMaxPerRowDataDiagnostics));
    expect(
        entries.any((Diagnostic d) =>
            d.severity == DiagnosticSeverity.info &&
            d.message.contains('suppressed')),
        isTrue,
        reason: 'more than $warnings dirty rows -> a suppression summary');

    // Invariant 3: per-row isolation — the clean rows summed correctly; only the
    // dirty rows (every _dirtyEvery-th) were skipped.
    final int dirty = (_n / _dirtyEvery).ceil(); // i = 0,100,200,...
    final double expectedTotal = (_n - dirty) * 1.0;
    expect(total, '$expectedTotal');
  });
}
