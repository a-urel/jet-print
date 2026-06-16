library;

import 'package:flutter_test/flutter_test.dart';
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

TextElement _agg(String id, String expr) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 100, height: 16),
      text: id,
      expression: expr,
    );

void main() {
  test('a summary aggregate synthesizes a report-scoped variable', () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        summary: Band(
            id: 's',
            type: BandType.summary,
            height: 16,
            elements: <ReportElement>[_agg('g', r'SUM($F{customerTotal})')]),
        root: const DetailScope(id: 'root'),
      ),
    );
    final out = expandAggregates(def);
    expect(out.variables, hasLength(1));
    final v = out.variables.single;
    expect(v.calculation, JetCalculation.sum);
    expect(v.expression, r'$F{customerTotal}');
    expect(v.resetScope, VariableResetScope.report);
    final el = out.body.summary!.elements.single as TextElement;
    expect(el.expression, '\$V{${v.name}}');
  });

  test('a group-footer aggregate synthesizes a group-scoped variable', () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', groups: <GroupLevel>[
          GroupLevel(
              id: 'cust',
              name: 'cust',
              key: r'$F{code}',
              footer: Band(
                  id: 'f',
                  type: BandType.groupFooter,
                  height: 16,
                  elements: <ReportElement>[_agg('t', r'SUM($F{amount})')])),
        ]),
      ),
    );
    final v = expandAggregates(def).variables.single;
    expect(v.resetScope, VariableResetScope.group);
    expect(v.resetGroup, 'cust');
    expect(v.expression, r'$F{amount}');
  });

  test('identical aggregates in one scope de-dup to one variable', () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
          summary: Band(
              id: 's',
              type: BandType.summary,
              height: 16,
              elements: <ReportElement>[
                _agg('a', r'SUM($F{x})'),
                _agg('b', r'SUM($F{x})')
              ]),
          root: const DetailScope(id: 'root')),
    );
    expect(expandAggregates(def).variables, hasLength(1));
  });

  test('an expression-argument aggregate uses the whole inner as the var expr',
      () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
          summary: Band(
              id: 's',
              type: BandType.summary,
              height: 16,
              elements: <ReportElement>[
                _agg('p', r'SUM($F{qty} * $F{unitPrice})')
              ]),
          root: const DetailScope(id: 'root')),
    );
    expect(expandAggregates(def).variables.single.expression,
        r'$F{qty} * $F{unitPrice}');
  });

  test('an aggregate inside a larger expression is lifted in place (032 #2)',
      () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
          summary: Band(
              id: 's',
              type: BandType.summary,
              height: 16,
              elements: <ReportElement>[
                _agg('g', r'SUM($F{customerTotal}) + 50000')
              ]),
          root: const DetailScope(id: 'root')),
    );
    final out = expandAggregates(def);
    expect(out.variables, hasLength(1));
    final v = out.variables.single;
    expect(v.calculation, JetCalculation.sum);
    expect(v.expression, r'$F{customerTotal}');
    final el = out.body.summary!.elements.single as TextElement;
    expect(el.expression, '\$V{${v.name}} + 50000');
  });

  test('two aggregates in one expression lift to two variables (032 #2)', () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
          summary: Band(
              id: 's',
              type: BandType.summary,
              height: 16,
              elements: <ReportElement>[_agg('g', r'SUM($F{a}) - SUM($F{b})')]),
          root: const DetailScope(id: 'root')),
    );
    final out = expandAggregates(def);
    expect(out.variables, hasLength(2));
    final el = out.body.summary!.elements.single as TextElement;
    expect(el.expression, r'$V{__agg0} - $V{__agg1}');
  });

  test('an aggregate nested in a scalar call is lifted, call kept (032 #2)',
      () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
          summary: Band(
              id: 's',
              type: BandType.summary,
              height: 16,
              elements: <ReportElement>[_agg('g', r'ROUND(SUM($F{x}), 2)')]),
          root: const DetailScope(id: 'root')),
    );
    final out = expandAggregates(def);
    expect(out.variables, hasLength(1));
    expect(out.variables.single.expression, r'$F{x}');
    final el = out.body.summary!.elements.single as TextElement;
    expect(el.expression, r'ROUND($V{__agg0}, 2)');
  });

  test('an aggregate name inside a string literal is not lifted (032 #2)', () {
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
          summary: Band(
              id: 's',
              type: BandType.summary,
              height: 16,
              elements: <ReportElement>[_agg('g', r'CONCAT("SUM(x)", $F{a})')]),
          root: const DetailScope(id: 'root')),
    );
    final out = expandAggregates(def);
    expect(out.variables, isEmpty,
        reason: 'the SUM( inside the quoted string must not be matched');
    final el = out.body.summary!.elements.single as TextElement;
    expect(el.expression, r'CONCAT("SUM(x)", $F{a})');
  });

  test('no aggregates → definition returned unchanged', () {
    const def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(root: DetailScope(id: 'root')));
    expect(expandAggregates(def), def);
  });

  test('an aggregate in an unsupported band (detail) is left unchanged', () {
    final def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
            root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'd',
              type: BandType.detail,
              height: 16,
              elements: <ReportElement>[_agg('x', r'SUM($F{amount})')])),
        ])));
    final out = expandAggregates(def);
    expect(out.variables, isEmpty);
    final el = (out.body.root.children.single as BandNode).band.elements.single
        as TextElement;
    expect(el.expression, r'SUM($F{amount})',
        reason: 'detail-band aggregates are not expanded in Phase A');
  });

  test('the same aggregate in two different group footers makes two variables',
      () {
    Band footer(String id) => Band(
        id: id,
        type: BandType.groupFooter,
        height: 16,
        elements: <ReportElement>[_agg(id, r'SUM($F{amount})')]);
    final def = ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
          root: DetailScope(id: 'root', groups: <GroupLevel>[
        GroupLevel(id: 'a', name: 'a', key: r'$F{a}', footer: footer('fa')),
        GroupLevel(id: 'b', name: 'b', key: r'$F{b}', footer: footer('fb')),
      ])),
    );
    final vars = expandAggregates(def).variables;
    expect(vars, hasLength(2),
        reason: 'different reset groups must not de-dup');
    expect(vars.map((v) => v.resetGroup).toSet(), <String>{'a', 'b'});
  });
}
