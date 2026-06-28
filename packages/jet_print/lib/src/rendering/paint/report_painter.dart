/// The paint-backend abstraction (spec 006): backends implement these calls over
/// the frame's primitives. [prepare] does async asset resolution (font load,
/// image decode) so the synchronous draw walk stays backend-agnostic.
library;

import '../../domain/geometry.dart';
import '../../domain/page_format.dart';
import '../frame/page_frame.dart';
import '../frame/primitive.dart';

/// A backend that paints a [PageFrame]'s primitives.
abstract class ReportPainter {
  /// Resolves async assets for [frame] before painting (default: no-op).
  Future<void> prepare(PageFrame frame) async {}

  /// Begins a page of size [format].
  void beginPage(PageFormat format);

  /// Pushes a rotation of [radians] about [center] (page points). Paired with
  /// [popTransform]. Backends save/restore their own graphics state.
  void pushTransform(JetOffset center, double radians);

  /// Restores the state saved by the matching [pushTransform].
  void popTransform();

  /// Draws a text run.
  void drawTextRun(TextRunPrimitive primitive);

  /// Draws an image.
  void drawImage(ImagePrimitive primitive);

  /// Draws a line.
  void drawLine(LinePrimitive primitive);

  /// Draws a rectangle.
  void drawRect(RectPrimitive primitive);

  /// Draws a path.
  void drawPath(PathPrimitive primitive);

  /// Ends the page.
  void endPage();
}

/// Paints [frame] with [painter]: prepare → beginPage → primitives → endPage.
/// The switch is exhaustive (no `default`) so a new primitive is a compile error
/// until every backend handles it.
Future<void> paintFrame(PageFrame frame, ReportPainter painter) async {
  await painter.prepare(frame);
  painter.beginPage(frame.page);
  for (final FramePrimitive primitive in frame.primitives) {
    final bool rotated = primitive.rotation != 0;
    if (rotated) {
      final JetRect b = primitive.bounds;
      painter.pushTransform(
          JetOffset(b.x + b.width / 2, b.y + b.height / 2), primitive.rotation);
    }
    switch (primitive) {
      case TextRunPrimitive():
        painter.drawTextRun(primitive);
      case ImagePrimitive():
        painter.drawImage(primitive);
      case LinePrimitive():
        painter.drawLine(primitive);
      case RectPrimitive():
        painter.drawRect(primitive);
      case PathPrimitive():
        painter.drawPath(primitive);
    }
    if (rotated) painter.popTransform();
  }
  painter.endPage();
}
