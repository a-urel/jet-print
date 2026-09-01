// The layouter honouring a crosstab's synthetic groups (Task 10): reprint on
// every page, a real page break between horizontal slices via startNewPage,
// and the closing footer stopping the reprint for whatever follows.
//
// These tests build a FilledReport by hand from a CrosstabPlan (Task 9) — no
// filler involved yet — so the layouter is exercised in isolation from the
// aggregator/fill seam.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_planner.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

// ---------------------------------------------------------------------------
// Fixtures — a one-level-by-one-level crosstab, sized for pagination tests.
// ---------------------------------------------------------------------------

CrosstabAxisNode _n(String key) =>
    CrosstabAxisNode(key: JetString(key), pathKey: key, label: key, depth: 0);

const CrosstabMeasure _amount = CrosstabMeasure(
  id: 'm/a',
  name: 'Amount',
  expression: r'$F{amount}',
  aggregate: JetCalculation.sum,
);

const CrosstabGroup _gRegion = CrosstabGroup(
    id: 'g/r', name: 'Region', expression: r'$F{region}', showTotal: false);
const CrosstabGroup _gQuarter = CrosstabGroup(
    id: 'g/q', name: 'Quarter', expression: r'$F{quarter}', showTotal: false);

/// 50pt measure columns, 100pt row labels, 20pt header row, 14pt data row.
const CrosstabStyle _style = CrosstabStyle(
  rowLabelWidth: 100,
  rowLabelIndent: 12,
  measureColumnWidth: 50,
  rowHeight: 14,
  headerRowHeight: 20,
);

const Crosstab _ct = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[_gRegion],
  columnGroups: <CrosstabGroup>[_gQuarter],
  measures: <CrosstabMeasure>[_amount],
  style: _style,
);

/// A crosstab with [n] row leaves and a single column leaf labelled 'Q1' —
/// wide enough that `sliceColumns` never splits it, so only vertical
/// pagination is exercised.
CrosstabPlan _planWithRows(int n) {
  final CrosstabMatrix m = CrosstabMatrix(
    rowAxis: <CrosstabAxisNode>[for (int i = 0; i < n; i++) _n('R$i')],
    columnAxis: <CrosstabAxisNode>[_n('Q1')],
    measures: const <CrosstabMeasure>[_amount],
    cells: <CrosstabCellKey, JetValue>{
      for (int i = 0; i < n; i++)
        CrosstabCellKey(<String>['R$i'], const <String>['Q1'], 'm/a'):
            JetNumber(i.toDouble()),
    },
  );
  return planCrosstab(_ct, m, availableWidth: 500);
}

/// A single-row crosstab with four column leaves, packed two-per-slice at
/// [availableWidth] (budget = availableWidth - 100, leaf width 50). One row
/// means each slice's own content (one 20pt header band + one 14pt detail
/// row = 34pt) is tiny next to a full page's body capacity, so slice 0 leaves
/// plenty of room to spare — only a real `startNewPage` can put slice 1 on
/// the next page.
CrosstabPlan _planWithSlices({required double availableWidth}) {
  final CrosstabMatrix m = CrosstabMatrix(
    rowAxis: <CrosstabAxisNode>[_n('OnlyRow')],
    columnAxis: <CrosstabAxisNode>[for (int i = 0; i < 4; i++) _n('C$i')],
    measures: const <CrosstabMeasure>[_amount],
    cells: <CrosstabCellKey, JetValue>{
      for (int i = 0; i < 4; i++)
        CrosstabCellKey(const <String>['OnlyRow'], <String>['C$i'], 'm/a'):
            JetNumber(i.toDouble()),
    },
  );
  return planCrosstab(_ct, m, availableWidth: availableWidth);
}

/// A small crosstab (2 rows, header 'Q1') followed by [n] plain, groupless
/// detail bands — as if ordinary report content followed the crosstab in the
/// same scope.
CrosstabPlan _planThenDetailRun(int n) {
  final CrosstabPlan base = _planWithRows(2);
  final List<FilledBand> extra = <FilledBand>[
    for (int i = 0; i < n; i++)
      FilledBand(
        type: BandType.detail,
        height: 14,
        elements: const <ReportElement>[],
        variables: const <String, JetValue>{},
      ),
  ];
  return CrosstabPlan(
    bands: <FilledBand>[...base.bands, ...extra],
    syntheticGroups: base.syntheticGroups,
    diagnostics: base.diagnostics,
  );
}

// ---------------------------------------------------------------------------
// Layout + reading helpers
// ---------------------------------------------------------------------------

/// Lays out a plan as if the filler had produced it, with no definition
/// groups — pinning that the layouter's group table comes entirely from the
/// plan's synthetic group.
LayoutResult _layout(CrosstabPlan plan, {double pageWidth = 595}) {
  final ReportDefinition def = ReportDefinition(
    name: 'R',
    page: PageFormat.a4Portrait.copyWith(width: pageWidth),
    body: const ReportBody(root: DetailScope(id: 'root')),
  );
  final FilledReport filled = FilledReport(
    page: def.page,
    bands: plan.bands,
    syntheticGroups: plan.syntheticGroups,
  );
  return ReportLayouter().layoutDefinition(def, filled);
}

/// Every string drawn on [page].
Iterable<String> _texts(PageFrame page) => page.primitives
    .whereType<TextRunPrimitive>()
    .expand((TextRunPrimitive p) => p.lines.map((TextLine l) => l.text));

/// Every originating element id drawn on [page] (chrome primitives, which
/// carry no id, are excluded).
Iterable<String> _ids(PageFrame page) =>
    page.primitives.map((FramePrimitive p) => p.elementId).whereType<String>();

void main() {
  group('crosstab pagination', () {
    test('the column header reprints on every page of a long crosstab', () {
      // A crosstab with enough rows to fill two pages.
      final LayoutResult r = _layout(_planWithRows(120));
      expect(r.pages, hasLength(greaterThan(1)));
      for (final PageFrame page in r.pages) {
        expect(_texts(page), contains('Q1'),
            reason: 'every page repeats the column header');
      }
    });

    test('slice 1 starts on a new page', () {
      // Narrow page -> two slices. Slice 0 fits on page 1 with room to spare;
      // slice 1 must still begin on page 2, from startNewPage.
      final LayoutResult r = _layout(_planWithSlices(availableWidth: 220));
      final int firstPageWithSlice1 = r.pages.indexWhere(
          (PageFrame p) => _ids(p).any((String i) => i.contains('/s1/')));
      final int lastPageWithSlice0 = r.pages.lastIndexWhere(
          (PageFrame p) => _ids(p).any((String i) => i.contains('/s0/')));
      expect(firstPageWithSlice1, greaterThan(lastPageWithSlice0));
    });

    test('the closing footer stops the reprint for later detail bands', () {
      // crosstab, then 200 plain detail bands. The crosstab header must not
      // appear on the pages those detail bands occupy.
      final LayoutResult r = _layout(_planThenDetailRun(200));
      final PageFrame last = r.pages.last;
      expect(_texts(last), isNot(contains('Q1')));
    });

    test('a synthetic group raises no "reprint but no header" info', () {
      final LayoutResult r = _layout(_planWithRows(10));
      expect(
        r.diagnostics.entries.map((Diagnostic d) => d.message),
        isNot(anyElement(contains('reprintHeaderOnEachPage'))),
      );
    });
  });
}
