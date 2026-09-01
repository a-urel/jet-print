// The crosstab canvas placeholder's design-time height (Task 13 / review
// fix): it must include the measure-name header row whenever a crosstab has
// 2+ measures, exactly as `crosstab_planner.dart`'s `headerBands` does at
// render time — otherwise the designer's placeholder is one header row
// shorter than what actually prints.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/design_time_layout.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;

const CrosstabStyle _style = CrosstabStyle(headerRowHeight: 20, rowHeight: 14);

const CrosstabGroup _row =
    CrosstabGroup(id: 'g-r', name: 'Region', expression: r'$F{region}');
const CrosstabGroup _col =
    CrosstabGroup(id: 'g-c', name: 'Year', expression: r'$F{year}');
const CrosstabMeasure _qty = CrosstabMeasure(
  id: 'm-q',
  name: 'Qty',
  expression: r'$F{qty}',
  aggregate: JetCalculation.sum,
);
const CrosstabMeasure _amt = CrosstabMeasure(
  id: 'm-a',
  name: 'Amount',
  expression: r'$F{amount}',
  aggregate: JetCalculation.sum,
);

ReportDefinition _defWith(Crosstab ct) => ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[CrosstabNode(ct)]),
      ),
    );

double _placeholderHeight(Crosstab ct) =>
    DesignTimeLayout.of(_defWith(ct)).crosstabs.single.rect.height;

void main() {
  test('a single-measure crosstab reserves one header row per column level',
      () {
    const Crosstab single = Crosstab(
      id: 'ct1',
      rowGroups: <CrosstabGroup>[_row],
      columnGroups: <CrosstabGroup>[_col],
      measures: <CrosstabMeasure>[_qty],
      style: _style,
    );
    // 1 column-axis level * 20pt header row + 3 * 14pt data/total rows; no
    // measure-name row (one measure already names its column on the leaf
    // header).
    expect(_placeholderHeight(single), 20 * 1 + 14 * 3);
  });

  test(
      "a multi-measure crosstab's placeholder reserves an EXTRA header row "
      "for the measure names, matching the planner's own headerBands "
      'condition (measures.length > 1)', () {
    const Crosstab multi = Crosstab(
      id: 'ct1',
      rowGroups: <CrosstabGroup>[_row],
      columnGroups: <CrosstabGroup>[_col],
      measures: <CrosstabMeasure>[_qty, _amt],
      style: _style,
    );
    // 1 column-axis level * 20pt + 1 extra 20pt measure-name row + 3 * 14pt.
    expect(_placeholderHeight(multi), 20 * 1 + 20 + 14 * 3);
    // And it is exactly one header row taller than the single-measure case.
    const Crosstab single = Crosstab(
      id: 'ct1',
      rowGroups: <CrosstabGroup>[_row],
      columnGroups: <CrosstabGroup>[_col],
      measures: <CrosstabMeasure>[_qty],
      style: _style,
    );
    expect(_placeholderHeight(multi) - _placeholderHeight(single),
        _style.headerRowHeight);
  });
}
