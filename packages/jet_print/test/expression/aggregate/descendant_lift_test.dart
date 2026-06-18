library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/aggregate_synthesizer.dart';

const List<FieldDef> _root = <FieldDef>[
  FieldDef('customerCode', type: JetFieldType.string),
  FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('lineTotal', type: JetFieldType.double),
    ]),
  ]),
];

TextElement _el(String id, String expr) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 80, height: 12),
      text: id,
      expression: expr,
    );

ReportDefinition _def({Band? summary, Band? customerFooter}) => ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: summary,
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            if (customerFooter != null)
              GroupLevel(
                id: 'customer',
                name: 'customer',
                key: r'$F{customerCode}',
                footer: customerFooter,
              ),
          ],
        ),
      ),
    );

void main() {
  test('lifts a descendant aggregate in the summary to a __dagg var', () {
    final ReportDefinition def = _def(
      summary: const Band(id: 'summary', type: BandType.summary, height: 20)
          .copyWith(elements: <ReportElement>[_el('g', r'SUM($F{lineTotal})')]),
    );
    final DescendantLift lift = liftDescendantAggregates(def, _root);
    expect(lift.aggregates, hasLength(1));
    final DescendantAggregate a = lift.aggregates.single;
    expect(a.calculation, JetCalculation.sum);
    expect(a.path, <String>['orders', 'lines']);
    expect(a.resetScope, VariableResetScope.report);
    expect(a.resetGroup, isNull);
    expect(a.ambiguous, isFalse);
    final TextElement g = lift.definition.body.summary!.elements.single
        as TextElement;
    expect(g.expression, '\$V{${a.name}}');
  });

  test('lifts a descendant aggregate in a root group footer with group reset',
      () {
    final ReportDefinition def = _def(
      customerFooter:
          const Band(id: 'cf', type: BandType.groupFooter, height: 20)
              .copyWith(elements: <ReportElement>[_el('t', r'SUM($F{lineTotal})')]),
    );
    final DescendantLift lift = liftDescendantAggregates(def, _root);
    expect(lift.aggregates.single.resetScope, VariableResetScope.group);
    expect(lift.aggregates.single.resetGroup, 'customer');
    expect(lift.aggregates.single.path, <String>['orders', 'lines']);
  });

  test('leaves a same-scope aggregate untouched for expandAggregates', () {
    final ReportDefinition def = _def(
      summary: const Band(id: 'summary', type: BandType.summary, height: 20)
          .copyWith(elements: <ReportElement>[_el('g', r'SUM($F{customerCode})')]),
    );
    final DescendantLift lift = liftDescendantAggregates(def, _root);
    expect(lift.aggregates, isEmpty);
    expect(lift.definition.body.summary!.elements.single,
        isA<TextElement>().having((TextElement e) => e.expression, 'expr',
            r'SUM($F{customerCode})'));
  });

  test('marks an ambiguous operand and clears its path', () {
    const List<FieldDef> ambig = <FieldDef>[
      FieldDef('a', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
      FieldDef('b', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
    ];
    final ReportDefinition def = _def(
      summary: const Band(id: 'summary', type: BandType.summary, height: 20)
          .copyWith(elements: <ReportElement>[_el('g', r'SUM($F{amount})')]),
    );
    final DescendantLift lift = liftDescendantAggregates(def, ambig);
    expect(lift.aggregates.single.ambiguous, isTrue);
    expect(lift.aggregates.single.path, isEmpty);
  });
}
