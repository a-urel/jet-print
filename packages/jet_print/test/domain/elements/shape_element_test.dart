import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/shape_element_codec.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('shape', const ShapeElementCodec());

void main() {
  group('ShapeElement', () {
    test('is a ReportElement with the "shape" type key', () {
      const ShapeElement s = ShapeElement(
        id: 's',
        bounds: JetRect(x: 0, y: 0, width: 100, height: 0),
        kind: ShapeKind.line,
      );
      expect(s, isA<ReportElement>());
      expect(s.typeKey, 'shape');
      expect(s.style, JetBoxStyle.none);
      expect(s.flipDiagonal, isFalse);
    });

    test('round-trips a rectangle with a box style', () {
      final ElementCodecRegistry registry = _registry();
      const ShapeElement s = ShapeElement(
        id: 'box',
        bounds: JetRect(x: 1, y: 2, width: 50, height: 30),
        kind: ShapeKind.rectangle,
        style: JetBoxStyle(
          fill: JetColor(0x11000000),
          stroke: JetColor(0xFF000000),
          strokeWidth: 2,
        ),
      );
      expect(registry.decode(registry.encode(s)), s);
    });

    test('round-trips a flipped line', () {
      final ElementCodecRegistry registry = _registry();
      const ShapeElement s = ShapeElement(
        id: 'rule',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        kind: ShapeKind.line,
        flipDiagonal: true,
      );
      expect(registry.decode(registry.encode(s)), s);
    });
  });
}
