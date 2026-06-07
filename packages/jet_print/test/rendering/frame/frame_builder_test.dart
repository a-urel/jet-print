// test/rendering/frame/frame_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

void main() {
  const RectPrimitive rect = RectPrimitive(
      bounds: JetRect(x: 0, y: 0, width: 10, height: 4), fill: JetColor.black);

  test('FrameBuilder accumulates primitives into an immutable PageFrame', () {
    final FrameBuilder b = FrameBuilder(PageFormat.a4Portrait)..add(rect);
    final PageFrame frame = b.build();
    expect(frame.page, PageFormat.a4Portrait);
    expect(frame.primitives, <Object>[rect]);
    expect(() => frame.primitives.add(rect), throwsUnsupportedError);
  });

  test('PageFrame is value-equal over page + primitives', () {
    final PageFrame a =
        (FrameBuilder(PageFormat.a4Portrait)..add(rect)).build();
    final PageFrame b =
        (FrameBuilder(PageFormat.a4Portrait)..add(rect)).build();
    expect(a, b);
  });
}
