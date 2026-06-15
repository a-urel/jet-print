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

  test('no aggregates → definition returned unchanged', () {
    const def = ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(root: DetailScope(id: 'root')));
    expect(expandAggregates(def), def);
  });
}
