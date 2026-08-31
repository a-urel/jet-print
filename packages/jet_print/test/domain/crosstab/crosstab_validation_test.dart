import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_validation.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;

const CrosstabGroup _row =
    CrosstabGroup(id: 'g/r', name: 'R', expression: r'$F{region}');
const CrosstabGroup _col =
    CrosstabGroup(id: 'g/c', name: 'C', expression: r'$F{quarter}');
const CrosstabMeasure _m = CrosstabMeasure(
  id: 'm/a',
  name: 'Amount',
  expression: r'$F{amount}',
  aggregate: JetCalculation.sum,
);
const Crosstab _ok = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[_row],
  columnGroups: <CrosstabGroup>[_col],
  measures: <CrosstabMeasure>[_m],
);

/// Wraps [ct] at the root, or one level down when [nested] is true.
ReportDefinition _def(Crosstab ct, {bool nested = false}) => ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            if (nested)
              NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                children: <ScopeNode>[CrosstabNode(ct)],
              ))
            else
              CrosstabNode(ct),
          ],
        ),
      ),
    );

Iterable<String> _messages(ReportDefinition def, DiagnosticSeverity s) =>
    validate(def)
        .where((Diagnostic d) => d.severity == s)
        .map((Diagnostic d) => d.message);

void main() {
  group('crosstab validation', () {
    test('a well-formed root crosstab is clean', () {
      expect(
        validate(_def(_ok)).where((Diagnostic d) => d.elementId == 'ct1'),
        isEmpty,
      );
    });

    test('empty axes and measures are errors', () {
      expect(
        _messages(_def(_ok.copyWith(rowGroups: <CrosstabGroup>[])),
            DiagnosticSeverity.error),
        anyElement(contains('no row groups')),
      );
      expect(
        _messages(_def(_ok.copyWith(columnGroups: <CrosstabGroup>[])),
            DiagnosticSeverity.error),
        anyElement(contains('no column groups')),
      );
      expect(
        _messages(_def(_ok.copyWith(measures: <CrosstabMeasure>[])),
            DiagnosticSeverity.error),
        anyElement(contains('no measures')),
      );
    });

    test('calculation "none" is rejected for a measure', () {
      final Crosstab bad = _ok.copyWith(measures: <CrosstabMeasure>[
        _m.copyWith(aggregate: JetCalculation.none),
      ]);
      expect(_messages(_def(bad), DiagnosticSeverity.error),
          anyElement(contains('none')));
    });

    test('an unparseable expression is an error', () {
      final Crosstab bad = _ok.copyWith(
        rowGroups: <CrosstabGroup>[_row.copyWith(expression: r'$F{')],
      );
      expect(_messages(_def(bad), DiagnosticSeverity.error),
          anyElement(contains('does not parse')));
    });

    test('a crosstab in a nested scope is rejected in Spec A', () {
      expect(_messages(_def(_ok, nested: true), DiagnosticSeverity.error),
          anyElement(contains('root scope')));
    });

    test('non-positive metrics are errors', () {
      final Crosstab bad =
          _ok.copyWith(style: const CrosstabStyle(rowHeight: 0));
      expect(_messages(_def(bad), DiagnosticSeverity.error),
          anyElement(contains('non-positive')));
    });

    test('a crosstab too wide for the body warns', () {
      final Crosstab wide =
          _ok.copyWith(style: const CrosstabStyle(measureColumnWidth: 900));
      expect(_messages(_def(wide), DiagnosticSeverity.warning),
          anyElement(contains('wider than the page body')));
    });

    test('a field reference in visible warns (a crosstab has no row)', () {
      final Crosstab bad =
          _ok.copyWith(visible: const BoolProperty(expression: r'$F{flag}'));
      expect(_messages(_def(bad), DiagnosticSeverity.warning),
          anyElement(contains('visibility cannot use fields')));
    });
  });
}
