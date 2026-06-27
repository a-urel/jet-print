import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';

void main() {
  const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 10);

  test('name defaults to null on every element type', () {
    expect(const TextElement(id: 't', bounds: r, text: 'x').name, isNull);
    expect(
        const ShapeElement(id: 's', bounds: r, kind: ShapeKind.rectangle).name,
        isNull);
    expect(
        const BarcodeElement(
                id: 'b', bounds: r, symbology: BarcodeSymbology.auto, data: 'x')
            .name,
        isNull);
  });

  test('withName sets and clears name, preserving type and other fields', () {
    const TextElement t = TextElement(id: 't', bounds: r, text: 'hi');
    final ReportElement named = t.withName('Greeting');
    expect(named, isA<TextElement>());
    expect(named.name, 'Greeting');
    expect((named as TextElement).text, 'hi');
    expect(named.id, 't');
    expect(named.withName(null).name, isNull);
  });

  test('name participates in equality', () {
    const TextElement a = TextElement(id: 't', bounds: r, text: 'hi');
    final ReportElement b = a.withName('Greeting');
    expect(a == b, isFalse);
    expect(a.withName('Greeting') == b, isTrue);
  });

  test('constructor accepts name', () {
    const ShapeElement s = ShapeElement(
        id: 's', bounds: r, kind: ShapeKind.rectangle, name: 'Line');
    expect(s.name, 'Line');
  });
}
