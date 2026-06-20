// emitImagePlaceholder: an image-glyph (frame + mountain + sun) for the
// source-less image placeholder — no text label.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/placeholder.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

void main() {
  const JetColor grey = JetColor(0xFF999999);

  test('normal box: outline + frame rects and sun + mountain paths, no text',
      () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    emitImagePlaceholder(out, const JetRect(x: 0, y: 0, width: 50, height: 40),
        elementId: 'img1');
    final List<FramePrimitive> prims = out.build().primitives;

    // No text label any more.
    expect(prims.whereType<TextRunPrimitive>(), isEmpty);

    final List<RectPrimitive> rects = prims.whereType<RectPrimitive>().toList();
    final List<PathPrimitive> paths = prims.whereType<PathPrimitive>().toList();
    expect(rects, hasLength(2)); // full-bounds outline + glyph frame
    expect(paths, hasLength(2)); // sun + mountain

    // Everything is tagged with the element id.
    for (final FramePrimitive p in prims) {
      expect(p.elementId, 'img1');
    }

    // Outline covers the full element bounds, stroke-only, grey.
    final RectPrimitive outline = rects[0];
    expect(outline.bounds, const JetRect(x: 0, y: 0, width: 50, height: 40));
    expect(outline.stroke, grey);
    expect(outline.fill, isNull);

    // Glyph frame is a centered square sized by `side = min(50,40)*0.55 = 22`.
    final RectPrimitive frame = rects[1];
    expect(frame.bounds.width, closeTo(22, 0.001));
    expect(frame.bounds.height, closeTo(22, 0.001));
    expect(frame.bounds.x + frame.bounds.width / 2, closeTo(25, 0.001));
    expect(frame.bounds.y + frame.bounds.height / 2, closeTo(20, 0.001));
    expect(frame.stroke, grey);
    expect(frame.fill, isNull); // frame is stroke-only

    // Sun + mountain are filled grey, closed sub-paths (the PDF parity check
    // relies on each ending in a ClosePath).
    for (final PathPrimitive p in paths) {
      expect(p.fill, grey);
      expect(p.commands.last, isA<ClosePath>());
    }
  });

  test('tiny box (side < 8): only the full-bounds outline is emitted', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    emitImagePlaceholder(out, const JetRect(x: 1, y: 1, width: 6, height: 6),
        elementId: 'i');
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims, hasLength(1));
    expect(prims.single, isA<RectPrimitive>());
    expect(prims.single.bounds, const JetRect(x: 1, y: 1, width: 6, height: 6));
  });
}
