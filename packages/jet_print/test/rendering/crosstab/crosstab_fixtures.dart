// Shared crosstab test fixtures (Tasks 9 and 10): the axis-node builder and a
// one-row-group x one-column-group crosstab, used verbatim by both the
// planner's own tests (`crosstab_planner_test.dart`) and the layout tests
// (`crosstab_layout_test.dart`) that build a `FilledReport` from a
// `CrosstabPlan` by hand. Kept in one place so the two test files cannot
// silently drift apart on what "the base crosstab" means.
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';

/// Builds an axis node labelled [key] (its `key`, `pathKey` and `label` are
/// all [key]), at [depth], with optional [children].
CrosstabAxisNode axisNode(
  String key, {
  int depth = 0,
  List<CrosstabAxisNode> children = const <CrosstabAxisNode>[],
}) =>
    CrosstabAxisNode(
      key: JetString(key),
      pathKey: key,
      label: key,
      depth: depth,
      children: children,
    );

/// A `SUM($F{amount})` measure.
const CrosstabMeasure amountMeasure = CrosstabMeasure(
  id: 'm/a',
  name: 'Amount',
  expression: r'$F{amount}',
  aggregate: JetCalculation.sum,
);

/// The row-axis group `$F{region}`, totals off.
const CrosstabGroup regionGroup = CrosstabGroup(
    id: 'g/r', name: 'Region', expression: r'$F{region}', showTotal: false);

/// The column-axis group `$F{quarter}`, totals off.
const CrosstabGroup quarterGroup = CrosstabGroup(
    id: 'g/q', name: 'Quarter', expression: r'$F{quarter}', showTotal: false);

/// 50pt measure columns, 100pt row labels, 20pt header row, 14pt data row.
const CrosstabStyle crosstabStyle = CrosstabStyle(
  rowLabelWidth: 100,
  rowLabelIndent: 12,
  measureColumnWidth: 50,
  rowHeight: 14,
  headerRowHeight: 20,
);

/// A single-level crosstab: [regionGroup] rows x [quarterGroup] columns,
/// [amountMeasure], styled with [crosstabStyle], no totals.
const Crosstab baseCrosstab = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[regionGroup],
  columnGroups: <CrosstabGroup>[quarterGroup],
  measures: <CrosstabMeasure>[amountMeasure],
  style: crosstabStyle,
);
