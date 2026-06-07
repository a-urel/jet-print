/// Maps element `type` keys to their [ElementRenderer]s and dispatches (007a).
/// Unregistered types (including a round-tripped `UnknownElement`) resolve to the
/// built-in [UnknownElementRenderer] placeholder. Registration is last-write-wins
/// (matching `ElementCodecRegistry`), so a consumer can override a built-in.
library;

import '../../domain/report_element.dart';
import 'element_renderer.dart';
import 'renderers/unknown_element_renderer.dart';

/// A registry of element renderers keyed by `typeKey`.
class ElementRendererRegistry {
  final Map<String, ElementRenderer<ReportElement>> _renderers =
      <String, ElementRenderer<ReportElement>>{};

  static const ElementRenderer<ReportElement> _unknown =
      UnknownElementRenderer();

  /// Registers [renderer] for elements whose `typeKey` equals [typeKey]
  /// (last-write-wins).
  void register(String typeKey, ElementRenderer<ReportElement> renderer) {
    _renderers[typeKey] = renderer;
  }

  /// The renderer for [element]'s `typeKey`, or the Unknown placeholder renderer
  /// when no renderer is registered for it.
  ElementRenderer<ReportElement> rendererFor(ReportElement element) =>
      _renderers[element.typeKey] ?? _unknown;
}
