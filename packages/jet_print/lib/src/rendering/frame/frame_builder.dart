/// Write-side builder for a [PageFrame] (spec 006): renderers append primitives,
/// then [build] snapshots them into an immutable frame.
library;

import '../../domain/page_format.dart';
import 'page_frame.dart';
import 'primitive.dart';

/// Accumulates [FramePrimitive]s for one [page].
class FrameBuilder {
  /// Creates a builder for [page].
  FrameBuilder(this.page);

  /// The page being built.
  final PageFormat page;

  final List<FramePrimitive> _primitives = <FramePrimitive>[];

  /// Appends [primitive] in paint order.
  void add(FramePrimitive primitive) => _primitives.add(primitive);

  /// Snapshots the accumulated primitives into an immutable [PageFrame].
  PageFrame build() => PageFrame(page: page, primitives: _primitives);
}
