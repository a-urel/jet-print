import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/rendering/paint/image_fit.dart';

void main() {
  const JetRect bounds = JetRect(x: 0, y: 0, width: 100, height: 100);

  test('fill maps the full image to the full bounds', () {
    final ImageFit f = computeImageFit(JetBoxFit.fill, bounds, 200, 100);
    expect(f.src, const JetRect(x: 0, y: 0, width: 200, height: 100));
    expect(f.dst, bounds);
  });

  test('contain letterboxes the image centered', () {
    final ImageFit f = computeImageFit(JetBoxFit.contain, bounds, 200, 100);
    expect(f.src, const JetRect(x: 0, y: 0, width: 200, height: 100));
    expect(f.dst, const JetRect(x: 0, y: 25, width: 100, height: 50));
  });

  test('cover crops the image centered', () {
    final ImageFit f = computeImageFit(JetBoxFit.cover, bounds, 200, 100);
    expect(f.src, const JetRect(x: 50, y: 0, width: 100, height: 100));
    expect(f.dst, bounds);
  });

  test('none draws at intrinsic size, centered and clipped', () {
    final ImageFit f = computeImageFit(JetBoxFit.none, bounds, 40, 20);
    expect(f.src, const JetRect(x: 0, y: 0, width: 40, height: 20));
    expect(f.dst, const JetRect(x: 30, y: 40, width: 40, height: 20));
  });

  test('a degenerate image falls back to fill', () {
    final ImageFit f = computeImageFit(JetBoxFit.contain, bounds, 0, 0);
    expect(f.dst, bounds);
  });
}
