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

  // 020 — the additive value-type surface backing the shape gallery: copyWith
  // (per-field, with an explicit clearUnknownForm flag) and an unknownForm field
  // threaded through equality/hashCode/withBounds/toString.
  group('ShapeElement.copyWith (020)', () {
    const ShapeElement base = ShapeElement(
      id: 's',
      bounds: JetRect(x: 1, y: 2, width: 30, height: 40),
      kind: ShapeKind.rectangle,
      style: JetBoxStyle(stroke: JetColor(0xFF000000)),
      flipDiagonal: true,
    );

    test('changes each field independently, preserving the rest', () {
      expect(base.copyWith(kind: ShapeKind.hexagon).kind, ShapeKind.hexagon);
      expect(base.copyWith(kind: ShapeKind.hexagon).bounds, base.bounds);
      expect(base.copyWith(kind: ShapeKind.hexagon).style, base.style);
      expect(base.copyWith(kind: ShapeKind.hexagon).flipDiagonal, isTrue);

      const JetRect moved = JetRect(x: 9, y: 9, width: 5, height: 5);
      expect(base.copyWith(bounds: moved).bounds, moved);
      expect(base.copyWith(bounds: moved).kind, base.kind);

      const JetBoxStyle filled = JetBoxStyle(fill: JetColor(0x22000000));
      expect(base.copyWith(style: filled).style, filled);

      expect(base.copyWith(flipDiagonal: false).flipDiagonal, isFalse);
      expect(base.copyWith().flipDiagonal, isTrue); // omitted ⇒ unchanged
    });

    test('a plain copyWith preserves a non-null unknownForm', () {
      const ShapeElement unknown = ShapeElement(
        id: 's',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        kind: ShapeKind.rectangle,
        unknownForm: 'octagon',
      );
      // Editing an unrelated field leaves the preserved form name intact.
      expect(unknown.copyWith(bounds: JetRect.zero).unknownForm, 'octagon');
      expect(unknown.copyWith().unknownForm, 'octagon');
    });

    test('clearUnknownForm: true nulls unknownForm (a deliberate pick)', () {
      const ShapeElement unknown = ShapeElement(
        id: 's',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        kind: ShapeKind.rectangle,
        unknownForm: 'octagon',
      );
      final ShapeElement picked =
          unknown.copyWith(kind: ShapeKind.star, clearUnknownForm: true);
      expect(picked.kind, ShapeKind.star);
      expect(picked.unknownForm, isNull);
    });
  });

  group('ShapeElement equality + identity carry unknownForm (020)', () {
    const JetRect b = JetRect(x: 0, y: 0, width: 10, height: 10);

    test('== / hashCode distinguish a preserved unknownForm', () {
      const ShapeElement plain =
          ShapeElement(id: 's', bounds: b, kind: ShapeKind.rectangle);
      const ShapeElement unknown = ShapeElement(
          id: 's',
          bounds: b,
          kind: ShapeKind.rectangle,
          unknownForm: 'octagon');
      expect(plain == unknown, isFalse);
      expect(plain.hashCode == unknown.hashCode, isFalse);
      expect(
        unknown ==
            const ShapeElement(
                id: 's',
                bounds: b,
                kind: ShapeKind.rectangle,
                unknownForm: 'octagon'),
        isTrue,
      );
    });

    test('withBounds preserves unknownForm', () {
      const ShapeElement unknown = ShapeElement(
          id: 's',
          bounds: b,
          kind: ShapeKind.rectangle,
          unknownForm: 'octagon');
      const JetRect moved = JetRect(x: 4, y: 4, width: 2, height: 2);
      expect(unknown.withBounds(moved).bounds, moved);
      expect(unknown.withBounds(moved).unknownForm, 'octagon');
    });

    test('toString surfaces a preserved unknownForm', () {
      const ShapeElement unknown = ShapeElement(
          id: 's',
          bounds: b,
          kind: ShapeKind.rectangle,
          unknownForm: 'octagon');
      expect(unknown.toString(), contains('octagon'));
    });
  });
}
