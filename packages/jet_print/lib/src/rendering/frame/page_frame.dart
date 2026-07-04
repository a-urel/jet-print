/// A painted page's display list (spec 006): a flat, immutable list of
/// positioned primitives plus the page geometry. The WYSIWYG hand-off to paint.
library;

import '../../domain/page_format.dart';
import '../../domain/value_equality.dart';
import 'primitive.dart';

/// An immutable page frame: [primitives] positioned on [page].
class PageFrame with ValueEquality {
  /// Creates a page frame; [primitives] is copied into an unmodifiable list.
  PageFrame({required this.page, required List<FramePrimitive> primitives})
      : primitives = List<FramePrimitive>.unmodifiable(primitives);

  /// The physical page.
  final PageFormat page;

  /// The positioned primitives, in paint order.
  final List<FramePrimitive> primitives;

  @override
  List<Object?> get props => <Object?>[page, primitives];

  @override
  String toString() => 'PageFrame(${primitives.length} primitives)';
}
