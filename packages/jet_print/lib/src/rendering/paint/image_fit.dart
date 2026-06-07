// lib/src/rendering/paint/image_fit.dart
/// Pure image-fit math (spec 006): source (image px) and destination (page pt)
/// rects for drawing an image under a [JetBoxFit]. No `dart:ui`.
library;

import '../../domain/elements/image_source.dart';
import '../../domain/geometry.dart';

/// A source rect (image pixels) and destination rect (page points).
class ImageFit {
  /// Creates a src/dst pair.
  const ImageFit(this.src, this.dst);

  /// The region of the source image to sample.
  final JetRect src;

  /// Where to draw it on the page.
  final JetRect dst;

  @override
  bool operator ==(Object other) =>
      other is ImageFit && other.src == src && other.dst == dst;

  @override
  int get hashCode => Object.hash(src, dst);

  @override
  String toString() => 'ImageFit(src: $src, dst: $dst)';
}

/// Computes the src/dst rects to render a [srcWidth]×[srcHeight] image into
/// [bounds] under [fit]. A degenerate image (non-positive size) falls back to
/// fill.
ImageFit computeImageFit(
    JetBoxFit fit, JetRect bounds, double srcWidth, double srcHeight) {
  final JetRect fullSrc =
      JetRect(x: 0, y: 0, width: srcWidth, height: srcHeight);
  if (srcWidth <= 0 || srcHeight <= 0) return ImageFit(fullSrc, bounds);

  switch (fit) {
    case JetBoxFit.fill:
      return ImageFit(fullSrc, bounds);
    case JetBoxFit.contain:
      final double scale =
          _min(bounds.width / srcWidth, bounds.height / srcHeight);
      final double w = srcWidth * scale;
      final double h = srcHeight * scale;
      return ImageFit(
          fullSrc,
          JetRect(
              x: bounds.x + (bounds.width - w) / 2,
              y: bounds.y + (bounds.height - h) / 2,
              width: w,
              height: h));
    case JetBoxFit.cover:
      final double scale =
          _max(bounds.width / srcWidth, bounds.height / srcHeight);
      final double sw = bounds.width / scale;
      final double sh = bounds.height / scale;
      return ImageFit(
          JetRect(
              x: (srcWidth - sw) / 2,
              y: (srcHeight - sh) / 2,
              width: sw,
              height: sh),
          bounds);
    case JetBoxFit.none:
      final double w = _min(srcWidth, bounds.width);
      final double h = _min(srcHeight, bounds.height);
      return ImageFit(
          JetRect(
              x: (srcWidth - w) / 2,
              y: (srcHeight - h) / 2,
              width: w,
              height: h),
          JetRect(
              x: bounds.x + (bounds.width - w) / 2,
              y: bounds.y + (bounds.height - h) / 2,
              width: w,
              height: h));
  }
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;
