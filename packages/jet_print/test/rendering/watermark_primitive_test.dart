// packages/jet_print/test/rendering/watermark_primitive_test.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/watermark.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/watermark_primitive.dart';

void main() {
  final measurer = MetricsTextMeasurer(FontRegistry()..registerDefault());
  const page =
      PageFormat(width: 400, height: 600, margins: JetEdgeInsets.all(20));

  test('text watermark → centered, rotated, alpha-scaled TextRunPrimitive', () {
    const wm = Watermark(
        text: 'DRAFT',
        opacity: 0.5,
        angleDegrees: -45,
        textStyle: JetTextStyle(fontSize: 80, color: JetColor(0xFF000000)));
    final p = buildWatermarkPrimitive(wm, page, measurer)! as TextRunPrimitive;
    expect(p.bounds.width, page.width); // full-width box → align centers it
    expect(p.style.align, JetTextAlign.center);
    expect(p.rotation, closeTo(-45 * math.pi / 180, 1e-9));
    // 0xFF alpha × 0.5 = 0x80
    expect((p.style.color.argb >> 24) & 0xff, 0x80);
  });

  test('image watermark → centered ImagePrimitive carrying opacity & fit', () {
    final wm = Watermark(
        imageBytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        imageFit: JetBoxFit.cover,
        opacity: 0.2,
        angleDegrees: 0);
    final p = buildWatermarkPrimitive(wm, page, measurer)! as ImagePrimitive;
    expect(p.opacity, 0.2);
    expect(p.fit, JetBoxFit.cover);
    expect(p.rotation, 0);
    // centered box
    expect(p.bounds.x + p.bounds.width / 2, closeTo(page.width / 2, 1e-9));
    expect(p.bounds.y + p.bounds.height / 2, closeTo(page.height / 2, 1e-9));
  });

  test('opacity 0 → null', () {
    expect(
        buildWatermarkPrimitive(
            const Watermark(text: 'x', opacity: 0), page, measurer),
        isNull);
  });

  test('empty/whitespace text and no image → null', () {
    expect(
        buildWatermarkPrimitive(const Watermark(text: '   '), page, measurer),
        isNull);
    expect(buildWatermarkPrimitive(const Watermark(), page, measurer), isNull);
  });

  test('both text and image set → text wins', () {
    final wm = Watermark(
        text: 'DRAFT', imageBytes: Uint8List.fromList(<int>[1, 2, 3]));
    expect(
        buildWatermarkPrimitive(wm, page, measurer), isA<TextRunPrimitive>());
  });
}
