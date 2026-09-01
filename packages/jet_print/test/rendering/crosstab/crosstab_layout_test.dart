// The layouter honouring a crosstab's synthetic groups (Task 10): reprint on
// every page, a real page break between horizontal slices via startNewPage,
// and the closing footer stopping the reprint for whatever follows.
//
// These tests build a FilledReport by hand from a CrosstabPlan (Task 9) — no
// filler involved yet — so the layouter is exercised in isolation from the
// aggregator/fill seam.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_planner.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

import 'crosstab_fixtures.dart';

// ---------------------------------------------------------------------------
// Plan builders — pagination-specific, over the shared base crosstab
// (`baseCrosstab`/`axisNode`/`amountMeasure`, see crosstab_fixtures.dart).
// ---------------------------------------------------------------------------

/// A crosstab with [n] row leaves and a single column leaf labelled 'Q1' —
/// wide enough that `sliceColumns` never splits it, so only vertical
/// pagination is exercised.
CrosstabPlan _planWithRows(int n) {
  final CrosstabMatrix m = CrosstabMatrix(
    rowAxis: <CrosstabAxisNode>[for (int i = 0; i < n; i++) axisNode('R$i')],
    columnAxis: <CrosstabAxisNode>[axisNode('Q1')],
    measures: const <CrosstabMeasure>[amountMeasure],
    cells: <CrosstabCellKey, JetValue>{
      for (int i = 0; i < n; i++)
        CrosstabCellKey(<String>['R$i'], const <String>['Q1'], 'm/a'):
            JetNumber(i.toDouble()),
    },
  );
  return planCrosstab(baseCrosstab, m, availableWidth: 500);
}

/// A single-row crosstab with four column leaves, packed two-per-slice at
/// [availableWidth] (budget = availableWidth - 100, leaf width 50). One row
/// means each slice's own content (one 20pt header band + one 14pt detail
/// row = 34pt) is tiny next to a full page's body capacity, so slice 0 leaves
/// plenty of room to spare — only a real `startNewPage` can put slice 1 on
/// the next page.
CrosstabPlan _planWithSlices({required double availableWidth}) {
  final CrosstabMatrix m = CrosstabMatrix(
    rowAxis: <CrosstabAxisNode>[axisNode('OnlyRow')],
    columnAxis: <CrosstabAxisNode>[
      for (int i = 0; i < 4; i++) axisNode('C$i'),
    ],
    measures: const <CrosstabMeasure>[amountMeasure],
    cells: <CrosstabCellKey, JetValue>{
      for (int i = 0; i < 4; i++)
        CrosstabCellKey(const <String>['OnlyRow'], <String>['C$i'], 'm/a'):
            JetNumber(i.toDouble()),
    },
  );
  return planCrosstab(baseCrosstab, m, availableWidth: availableWidth);
}

/// A crosstab with [rows] row leaves (header 'Q1') followed by [extraDetail]
/// plain, groupless detail bands — as if ordinary report content followed the
/// crosstab in the same scope. [rows] must be large enough that the crosstab
/// itself spans multiple pages on its own (see [_planWithRows]): otherwise a
/// test built on this fixture cannot tell "reprint never happened" apart from
/// "reprint happened and then correctly stopped" — both leave the header
/// printed nowhere but the crosstab's own first page.
CrosstabPlan _planThenDetailRun({required int rows, required int extraDetail}) {
  final CrosstabPlan base = _planWithRows(rows);
  final List<FilledBand> extra = <FilledBand>[
    for (int i = 0; i < extraDetail; i++)
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

/// Whether [page] carries any element the crosstab itself emitted (a header
/// cell or a row/cell of `baseCrosstab`'s bands) — as opposed to only the
/// plain, id-less detail bands appended after it.
bool _hasCrosstabContent(PageFrame page) =>
    _ids(page).any((String i) => i.startsWith('ct1/'));

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

    test(
        'the header reprints on every page the crosstab spans, and stops '
        'once its footer closes the group', () {
      // A crosstab with enough rows to span multiple pages on its own (as in
      // the reprint test above — this is what makes "reprint never happens"
      // and "reprint happens, then correctly stops" observably different),
      // followed by a long run of plain detail bands.
      final LayoutResult r =
          _layout(_planThenDetailRun(rows: 120, extraDetail: 200));
      final List<PageFrame> crosstabPages =
          r.pages.where(_hasCrosstabContent).toList(growable: false);
      final List<PageFrame> detailOnlyPages = r.pages
          .where((PageFrame p) => !_hasCrosstabContent(p))
          .toList(growable: false);

      // Sanity on the fixture itself: it must actually exercise both halves,
      // or the assertions below would pass vacuously.
      expect(crosstabPages, hasLength(greaterThan(1)),
          reason: 'the crosstab must span multiple pages for this test to '
              'distinguish "never reprinted" from "reprinted, then stopped"');
      expect(detailOnlyPages, isNotEmpty,
          reason: 'the detail run must reach at least one page with no '
              'crosstab content of its own — if every page still carries a '
              'crosstab id, the closing footer never actually closed the '
              'group and the reprint never stopped');

      for (final PageFrame page in crosstabPages) {
        expect(_texts(page), contains('Q1'),
            reason: 'every page carrying crosstab content reprints the '
                'column header');
      }
      for (final PageFrame page in detailOnlyPages) {
        expect(_texts(page), isNot(contains('Q1')),
            reason: 'the closing footer must stop the reprint once the '
                'crosstab has finished');
      }
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
