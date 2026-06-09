/// The zoom + pan transform mapping page points to/from screen points.
library;

import '../../domain/geometry.dart';

/// An immutable view transform: uniform [scale] (zoom) plus a [pan] translation,
/// in screen pixels. Page coordinates are in points; screen coordinates are in
/// the canvas widget's local pixels.
///
/// `screen = page * scale + pan`. Keeping this invertible and in one place is
/// what makes placement and hit-testing pointer-accurate at every zoom level
/// (FR-020 / SC-006).
class CanvasViewTransform {
  /// Creates a transform; identity by default.
  const CanvasViewTransform(
      {this.scale = 1.0, this.pan = const JetOffset(0, 0)});

  /// The zoom factor (1.0 == 100%).
  final double scale;

  /// The pan offset, in screen pixels.
  final JetOffset pan;

  /// Maps a page point to a screen point.
  JetOffset pageToScreen(JetOffset page) =>
      JetOffset(page.dx * scale + pan.dx, page.dy * scale + pan.dy);

  /// Maps a screen point back to a page point (exact inverse of [pageToScreen]).
  JetOffset screenToPage(JetOffset screen) =>
      JetOffset((screen.dx - pan.dx) / scale, (screen.dy - pan.dy) / scale);

  /// Maps a page rect to its screen rect.
  JetRect pageRectToScreen(JetRect r) => JetRect(
        x: r.x * scale + pan.dx,
        y: r.y * scale + pan.dy,
        width: r.width * scale,
        height: r.height * scale,
      );

  /// Returns a copy with [scale] and/or [pan] replaced.
  CanvasViewTransform copyWith({double? scale, JetOffset? pan}) =>
      CanvasViewTransform(scale: scale ?? this.scale, pan: pan ?? this.pan);

  @override
  bool operator ==(Object other) =>
      other is CanvasViewTransform && other.scale == scale && other.pan == pan;

  @override
  int get hashCode => Object.hash(scale, pan);

  @override
  String toString() => 'CanvasViewTransform(scale: $scale, pan: $pan)';
}
