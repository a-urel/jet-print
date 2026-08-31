import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_schema.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
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

Iterable<String> _messages(ReportDefinition def, DiagnosticSeverity s,
        {JetDataSchema? schema}) =>
    validate(def, schema: schema)
        .where((Diagnostic d) => d.severity == s)
        .map((Diagnostic d) => d.message);

/// A schema for the schema-aware field-resolution tests: root fields `region`,
/// `quarter`, `amount`, plus a `lines` collection whose only child is `qty`.
const JetDataSchema _schema = JetDataSchema(
  name: 'S',
  fields: <FieldDef>[
    FieldDef('region', type: JetFieldType.string),
    FieldDef('quarter', type: JetFieldType.string),
    FieldDef('amount', type: JetFieldType.double),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('qty', type: JetFieldType.integer),
    ]),
  ],
);

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

    test('a crosstab id colliding with a band id is a duplicate-id error', () {
      final ReportDefinition def = ReportDefinition(
        name: 'R',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          title: const Band(id: 'dup', type: BandType.title, height: 10),
          root: DetailScope(id: 'root', children: <ScopeNode>[
            CrosstabNode(_ok.copyWith(id: 'dup')),
          ]),
        ),
      );
      expect(
        validate(def).map((Diagnostic d) => d.message),
        anyElement(equals('duplicate id "dup" (2 uses)')),
      );
    });
  });

  group('crosstab validation — schema-aware field resolution', () {
    test('a measure referencing an unknown field warns', () {
      final Crosstab bad = _ok.copyWith(
        measures: <CrosstabMeasure>[_m.copyWith(expression: r'$F{bogus}')],
      );
      expect(
        _messages(_def(bad), DiagnosticSeverity.warning, schema: _schema),
        anyElement(contains('references unknown field "bogus"')),
      );
    });

    test('the same unresolved name across expressions warns only once', () {
      final Crosstab bad = _ok.copyWith(measures: <CrosstabMeasure>[
        _m.copyWith(expression: r'$F{bogus}'),
        const CrosstabMeasure(
          id: 'm/b',
          name: 'B',
          expression: r'$F{bogus}',
          aggregate: JetCalculation.sum,
        ),
      ]);
      final Iterable<String> warnings =
          _messages(_def(bad), DiagnosticSeverity.warning, schema: _schema)
              .where((String m) => m.contains('bogus'));
      expect(warnings, hasLength(1));
    });

    test(
        'a crosstab with collectionField resolves fields against the child '
        'schema', () {
      final Crosstab ct = _ok.copyWith(
        collectionField: () => 'lines',
        rowGroups: <CrosstabGroup>[_row.copyWith(expression: r'$F{qty}')],
        columnGroups: <CrosstabGroup>[_col.copyWith(expression: r'$F{qty}')],
        measures: <CrosstabMeasure>[_m.copyWith(expression: r'$F{amount}')],
      );
      final Iterable<String> warnings =
          _messages(_def(ct), DiagnosticSeverity.warning, schema: _schema);
      // `qty` lives only in the child `lines` collection — resolves, no warn.
      expect(warnings, isNot(anyElement(contains('"qty"'))));
      // `amount` lives only at the root — unresolved once scoped to `lines`.
      expect(
          warnings, anyElement(contains('references unknown field "amount"')));
    });

    test(
        'an unresolvable collectionField warns once and skips per-name '
        'checks', () {
      final Crosstab ct = _ok.copyWith(collectionField: () => 'nope');
      final Iterable<String> warnings =
          _messages(_def(ct), DiagnosticSeverity.warning, schema: _schema);
      expect(
        warnings.where((String m) => m.contains('collection field "nope"')),
        hasLength(1),
      );
      expect(warnings, isNot(anyElement(contains('references unknown field'))));
    });

    test('without a schema, no field-resolution warnings are produced', () {
      final Crosstab bad = _ok.copyWith(
        measures: <CrosstabMeasure>[_m.copyWith(expression: r'$F{bogus}')],
      );
      expect(_messages(_def(bad), DiagnosticSeverity.warning),
          isNot(anyElement(contains('bogus'))));
    });
  });
}
