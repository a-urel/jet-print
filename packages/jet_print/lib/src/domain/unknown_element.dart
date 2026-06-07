/// Preserves an element whose type is not registered in this build.
library;

import 'geometry.dart';
import 'report_element.dart';

/// A [ReportElement] standing in for a type-key this build does not recognize.
///
/// It keeps the element's original JSON verbatim ([rawJson]) so the template
/// round-trips **losslessly** (Constitution V) — a report authored in a newer
/// build, or by a plugin, is never silently dropped when opened here. It exposes
/// best-effort [id]/[bounds] (if present in the JSON) so it can still render a
/// visible placeholder.
class UnknownElement extends ReportElement {
  /// Wraps [rawJson] for the unrecognized [typeKey].
  UnknownElement({required this.typeKey, required this.rawJson})
      : super(
          id: rawJson['id'] is String ? rawJson['id']! as String : '',
          bounds: _readBounds(rawJson['bounds']),
        );

  @override
  final String typeKey;

  /// The element's original JSON, preserved byte-for-byte for round-tripping.
  final Map<String, Object?> rawJson;

  static JetRect _readBounds(Object? bounds) => bounds is Map
      ? JetRect.fromJson(bounds.cast<String, Object?>())
      : JetRect.zero;

  @override
  String toString() => 'UnknownElement($typeKey)';
}
