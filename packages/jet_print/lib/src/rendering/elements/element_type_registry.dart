/// The unified element-type extension point (spec 007a): binds an element type's
/// codec (persist) and renderer (draw) under one `typeKey`. COMPOSES — does not
/// replace — the domain `ElementCodecRegistry` ([codecs]), which `report_codec`
/// consumes for save/load; [renderers] is used for render-time dispatch.
library;

import '../../domain/report_element.dart';
import '../../domain/serialization/element_codec.dart';
import 'element_renderer.dart';
import 'element_renderer_registry.dart';

/// Pairs codec and renderer registries behind one typed `register` call.
class ElementTypeRegistry {
  /// Creates a registry, defaulting each half to a fresh empty registry.
  ElementTypeRegistry({
    ElementCodecRegistry? codecs,
    ElementRendererRegistry? renderers,
  })  : codecs = codecs ?? ElementCodecRegistry(),
        renderers = renderers ?? ElementRendererRegistry();

  /// The codec registry (consumed by `encodeTemplate`/`decodeTemplate`).
  final ElementCodecRegistry codecs;

  /// The renderer registry (consumed by render-time dispatch).
  final ElementRendererRegistry renderers;

  /// Registers [codec] and [renderer] for [typeKey] (last-write-wins on both).
  ///
  /// The shared type parameter [E] pairs the two; passing an explicit type
  /// argument (as the built-ins do) rejects a mismatched pair. Dart's covariant
  /// generics allow an *inferred* call to widen [E] to `ReportElement` and
  /// compile a mismatch, so this enforces pairing, it does not fully prevent it
  /// — the same trade-off `ElementCodec`'s `covariant ReportElement` documents.
  void register<E extends ReportElement>(
    String typeKey,
    ElementCodec<E> codec,
    ElementRenderer<E> renderer,
  ) {
    codecs.register(typeKey, codec);
    renderers.register(typeKey, renderer);
  }
}
