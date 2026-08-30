import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;

const CrosstabGroup _region = CrosstabGroup(
  id: 'g/region',
  name: 'Region',
  expression: r'$F{region}',
);
const CrosstabMeasure _amount = CrosstabMeasure(
  id: 'm/amount',
  name: 'Amount',
  expression: r'$F{qty} * $F{price}',
  aggregate: JetCalculation.sum,
);
const Crosstab _ct = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[_region],
  columnGroups: <CrosstabGroup>[
    CrosstabGroup(id: 'g/q', name: 'Quarter', expression: r'$F{quarter}'),
  ],
  measures: <CrosstabMeasure>[_amount],
);

void main() {
  group('crosstab model', () {
    test('is a value type over its whole shape', () {
      expect(_ct, equals(_ct.copyWith()));
      expect(_ct.hashCode, equals(_ct.copyWith().hashCode));
      expect(
        _ct.copyWith(measures: <CrosstabMeasure>[
          _amount.copyWith(aggregate: JetCalculation.average),
        ]),
        isNot(equals(_ct)),
      );
    });

    test('defaults: no collection binding, totals on, ascending sort', () {
      expect(_ct.collectionField, isNull);
      expect(_region.showTotal, isTrue);
      expect(_region.sort, CrosstabSort.ascending);
      expect(_ct.style, const CrosstabStyle());
    });

    test('copyWith clears the nullable name via a thunk', () {
      final Crosstab named = _ct.copyWith(name: () => 'Sales pivot');
      expect(named.name, 'Sales pivot');
      expect(named.copyWith(name: () => null).name, isNull);
      expect(named.copyWith().name, 'Sales pivot');
    });

    test('style defaults are the documented point sizes', () {
      const CrosstabStyle s = CrosstabStyle();
      expect(s.rowLabelWidth, 110);
      expect(s.rowLabelIndent, 12);
      expect(s.measureColumnWidth, 64);
      expect(s.rowHeight, 14);
      expect(s.headerRowHeight, 14);
    });
  });
}
