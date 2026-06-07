/// A painted page's display list (spec 006): a flat, immutable list of
/// positioned primitives plus the page geometry. The WYSIWYG hand-off to paint.
library;

import '../../domain/page_format.dart';
import 'primitive.dart';

/// An immutable page frame: [primitives] positioned on [page].
class PageFrame {
  /// Creates a page frame; [primitives] is copied into an unmodifiable list.
  PageFrame({required this.page, required List<FramePrimitive> primitives})
      : primitives = List<FramePrimitive>.unmodifiable(primitives);

  /// The physical page.
  final PageFormat page;

  /// The positioned primitives, in paint order.
  final List<FramePrimitive> primitives;

  @override
  bool operator ==(Object other) {
    if (other is! PageFrame ||
        other.page != page ||
        other.primitives.length != primitives.length) {
      return false;
    }
    for (var i = 0; i < primitives.length; i++) {
      if (other.primitives[i] != primitives[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(page, Object.hashAll(primitives));

  @override
  String toString() => 'PageFrame(${primitives.length} primitives)';
}
