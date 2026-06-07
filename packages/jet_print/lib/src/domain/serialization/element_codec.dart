/// The element serialization extension point.
library;

import '../report_element.dart';
import '../unknown_element.dart';
import 'report_format_exception.dart';

/// Serializes a single element type [E] to/from JSON. Register one per element
/// type so custom types persist with zero core edits (Constitution II/V).
///
/// `toJson` takes a `covariant ReportElement` (not `E`) so that
/// `ElementCodec<E>` stays a subtype of `ElementCodec<ReportElement>` and can be
/// held in [ElementCodecRegistry]; the registry only calls it after matching the
/// element's `typeKey`, so the cast is always sound.
abstract class ElementCodec<E extends ReportElement> {
  /// Const base constructor.
  const ElementCodec();

  /// Builds an [E] from its field map (the same map [toJson] produced, plus the
  /// `type` key, which implementations may ignore).
  E fromJson(Map<String, Object?> json);

  /// Returns the element's fields as a JSON-safe map **without** the `type`
  /// key — the registry adds `type` from [ReportElement.typeKey].
  Map<String, Object?> toJson(covariant ReportElement element);
}

/// Maps element `type` keys to their [ElementCodec]s and performs dispatch.
class ElementCodecRegistry {
  final Map<String, ElementCodec<ReportElement>> _codecs =
      <String, ElementCodec<ReportElement>>{};

  /// Registers [codec] for elements whose `typeKey` equals [typeKey].
  void register(String typeKey, ElementCodec<ReportElement> codec) {
    _codecs[typeKey] = codec;
  }

  /// Encodes [element] to a JSON-safe map. [UnknownElement]s are emitted from
  /// their preserved raw JSON; all others are `{'type': typeKey, ...fields}`.
  Map<String, Object?> encode(ReportElement element) {
    if (element is UnknownElement) {
      return _deepCopyJsonMap(element.rawJson);
    }
    final ElementCodec<ReportElement>? codec = _codecs[element.typeKey];
    if (codec == null) {
      throw StateError(
        'No ElementCodec registered for type "${element.typeKey}".',
      );
    }
    return <String, Object?>{'type': element.typeKey, ...codec.toJson(element)};
  }

  /// Decodes a JSON [json] map into a [ReportElement]. Unknown `type`s decode to
  /// a lossless [UnknownElement]; a missing/non-string `type` is a hard error.
  ReportElement decode(Map<String, Object?> json) {
    final Object? typeKey = json['type'];
    if (typeKey is! String) {
      throw const ReportFormatException('Element JSON missing string "type".');
    }
    final ElementCodec<ReportElement>? codec = _codecs[typeKey];
    if (codec == null) {
      return UnknownElement(
        typeKey: typeKey,
        rawJson: _deepCopyJsonMap(json),
      );
    }
    return codec.fromJson(json);
  }
}

/// Recursively copies a JSON-safe value so stored maps are immune to later
/// mutation of the source — preserving [UnknownElement]'s byte-for-byte
/// round-trip guarantee even if the caller mutates the original decoded map.
Object? _deepCopyJson(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        entry.key! as String: _deepCopyJson(entry.value),
    };
  }
  if (value is List) {
    return <Object?>[for (final Object? item in value) _deepCopyJson(item)];
  }
  return value;
}

Map<String, Object?> _deepCopyJsonMap(Map<String, Object?> json) =>
    _deepCopyJson(json)! as Map<String, Object?>;
