// test/domain/element_visible_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';

const _b = JetRect(x: 0, y: 0, width: 10, height: 10);
const _b2 = JetRect(x: 1, y: 1, width: 5, height: 5);
const _vis = BoolProperty(value: false, expression: 'show');

void main() {
  final List<ReportElement> samples = <ReportElement>[
    const TextElement(id: 't', bounds: _b, text: 'x', visible: _vis),
    const ShapeElement(
        id: 's', bounds: _b, kind: ShapeKind.rectangle, visible: _vis),
    const ImageElement(
        id: 'i', bounds: _b, source: FieldImageSource(''), visible: _vis),
    const BarcodeElement(
        id: 'c',
        bounds: _b,
        symbology: BarcodeSymbology.auto,
        data: '1',
        visible: _vis),
  ];

  for (final ReportElement e in samples) {
    group('${e.runtimeType} preserves visible', () {
      test('default is visible', () {
        // A fresh element with no visible arg defaults to the visible default.
        expect(
            e.withVisible(const BoolProperty()).visible, const BoolProperty());
      });
      test('withBounds preserves visible', () {
        expect(e.withBounds(_b2).visible, _vis);
      });
      test('withName preserves visible', () {
        expect(e.withName('n').visible, _vis);
      });
      test('withVisible replaces only visible', () {
        final ReportElement r = e.withVisible(const BoolProperty(value: true));
        expect(r.visible, const BoolProperty(value: true));
        expect(r.id, e.id);
        expect(r.bounds, e.bounds);
      });
      test('equality distinguishes visible', () {
        expect(e, isNot(e.withVisible(const BoolProperty())));
      });
    });
  }
}
