// test/rendering/frame/primitive_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  test('primitives are value-equal and carry an optional elementId', () {
    const TextLine line =
        TextLine(text: 'Hi', width: 6.0, top: 0, baseline: 10, height: 13);
    final TextRunPrimitive a = TextRunPrimitive(
      bounds: const JetRect(x: 1, y: 2, width: 30, height: 13),
      lines: const <TextLine>[line],
      style: JetTextStyle.fallback,
      fontFamily: 'JetSans',
      elementId: 'e1',
    );
    final TextRunPrimitive b = TextRunPrimitive(
      bounds: const JetRect(x: 1, y: 2, width: 30, height: 13),
      lines: const <TextLine>[line],
      style: JetTextStyle.fallback,
      fontFamily: 'JetSans',
      elementId: 'e1',
    );
    expect(a, b);
    expect(a.elementId, 'e1');
  });

  test('rect/line/path primitives compare by value', () {
    const RectPrimitive r1 = RectPrimitive(
        bounds: JetRect(x: 0, y: 0, width: 10, height: 4),
        fill: JetColor(0xFF112233));
    const RectPrimitive r2 = RectPrimitive(
        bounds: JetRect(x: 0, y: 0, width: 10, height: 4),
        fill: JetColor(0xFF112233));
    expect(r1, r2);

    const PathPrimitive p1 = PathPrimitive(
      bounds: JetRect(x: 0, y: 0, width: 5, height: 5),
      commands: <PathCommand>[
        MoveTo(JetOffset(0, 0)),
        LineTo(JetOffset(5, 5)),
        ClosePath()
      ],
      stroke: JetColor.black,
    );
    const PathPrimitive p2 = PathPrimitive(
      bounds: JetRect(x: 0, y: 0, width: 5, height: 5),
      commands: <PathCommand>[
        MoveTo(JetOffset(0, 0)),
        LineTo(JetOffset(5, 5)),
        ClosePath()
      ],
      stroke: JetColor.black,
    );
    expect(p1, p2);
  });

  test('image primitive compares its bytes by value', () {
    final ImagePrimitive i1 = ImagePrimitive(
        bounds: const JetRect(x: 0, y: 0, width: 8, height: 8),
        bytes: Uint8List.fromList(<int>[1, 2, 3]));
    final ImagePrimitive i2 = ImagePrimitive(
        bounds: const JetRect(x: 0, y: 0, width: 8, height: 8),
        bytes: Uint8List.fromList(<int>[1, 2, 3]));
    expect(i1, i2);
  });
}
