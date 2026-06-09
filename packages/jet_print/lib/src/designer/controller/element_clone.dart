/// Clones an element with a fresh id and bounds, for paste/duplicate (FR-015).
///
/// Uses the built-in element codecs to round-trip the element through its JSON
/// form, then overrides `id` and `bounds`. This preserves every type-specific
/// attribute (text/style/symbology/source/…) — and unknown element types — with
/// no per-type clone code, the same way the serialization layer stays open/closed.
library;

import '../../domain/geometry.dart';
import '../../domain/report_element.dart';
import '../../domain/serialization/built_in_element_codecs.dart';
import '../../domain/serialization/element_codec.dart';

final ElementCodecRegistry _registry = _buildRegistry();

ElementCodecRegistry _buildRegistry() {
  final ElementCodecRegistry registry = ElementCodecRegistry();
  registerBuiltInElementCodecs(registry);
  return registry;
}

/// Returns a deep copy of [element] with the given [id] and [bounds], preserving
/// all other attributes.
ReportElement cloneElement(
  ReportElement element, {
  required String id,
  required JetRect bounds,
}) {
  final Map<String, Object?> json = _registry.encode(element);
  json['id'] = id;
  json['bounds'] = bounds.toJson();
  return _registry.decode(json);
}
