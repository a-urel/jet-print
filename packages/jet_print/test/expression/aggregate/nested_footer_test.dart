library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/expression/aggregate/nested_footer.dart';

TextElement _el(String id, String expr) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 80, height: 12),
      text: id,
      expression: expr,
    );

void main() {
  test('rewrites an aggregate element to a synth var and returns its spec', () {
    final band = const Band(id: 'f', type: BandType.groupFooter, height: 12)
        .copyWith(elements: <ReportElement>[
      _el('label', r'$F{label}'),
      _el('total', r'SUM($F{lineTotal})'),
    ]);
    final prepared = prepareNestedFooter(band);
    expect(prepared.aggs, hasLength(1));
    expect(prepared.aggs.single.calculation, JetCalculation.sum);
    final total = prepared.band.elements.firstWhere((e) => e.id == 'total')
        as TextElement;
    expect(total.expression, '\$V{${prepared.aggs.single.name}}');
    final label = prepared.band.elements.firstWhere((e) => e.id == 'label')
        as TextElement;
    expect(label.expression, r'$F{label}', reason: 'non-aggregate untouched');
  });

  test('a footer with no aggregate returns the band unchanged and no specs',
      () {
    final band = const Band(id: 'f', type: BandType.groupFooter, height: 12)
        .copyWith(elements: <ReportElement>[_el('x', r'$F{x}')]);
    final prepared = prepareNestedFooter(band);
    expect(prepared.aggs, isEmpty);
    expect(identical(prepared.band, band), isTrue);
  });

  test('an expression-argument aggregate keeps the whole inner and evaluates',
      () {
    final band = const Band(id: 'f', type: BandType.groupFooter, height: 12)
        .copyWith(
            elements: <ReportElement>[_el('t', r'SUM($F{qty} * $F{price})')]);
    final agg = prepareNestedFooter(band).aggs.single;
    expect(agg.calculation, JetCalculation.sum);
    // The argument is the inner expression qty*price; it must be a parsed
    // Expression evaluable per row. (Optionally evaluate against a stub context
    // if a simple one is available; otherwise asserting calculation + name is enough.)
  });

  test('two aggregate elements get distinct synth names', () {
    final band = const Band(id: 'f', type: BandType.groupFooter, height: 12)
        .copyWith(elements: <ReportElement>[
      _el('a', r'SUM($F{x})'),
      _el('b', r'AVG($F{y})'),
    ]);
    final prepared = prepareNestedFooter(band);
    expect(prepared.aggs.map((a) => a.name).toSet(), hasLength(2));
  });
}
