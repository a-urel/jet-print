// lib/src/rendering/text/jet_font.dart
/// Public host-font value types (spec 022): the bytes-in descriptors a host
/// hands the library to make its own fonts selectable in every picker and
/// rendered identically across canvas, preview, PDF, and PNG.
///
/// A face is a plain descriptor; a [JetFontFamily] is the unit a host
/// registers and the point where bad bytes are caught — it validates its faces
/// **eagerly and synchronously** at construction (FR-010 / SC-006), so a host
/// detects a malformed/empty/regular-less font at the natural point (assembling
/// it) and nothing can throw later inside a widget `build()` or a `render()`.
library;

import 'dart:typed_data';

import '../../domain/styles/text_style.dart';
import 'font_format_exception.dart';
import 'ttf/ttf_metrics.dart';

/// One typeface a host contributes: its raw TTF/OTF [bytes] and the
/// [weight]/[italic] slot they fill within a [JetFontFamily].
///
/// The [bytes] **are the input** — the host loads them however it likes (asset,
/// file, network) and the library measures, paints, and embeds from exactly
/// these bytes. Value equality is over `(bytes identity, weight, italic)`:
/// large buffers are compared by identity (hosts reuse instances), not content.
class JetFontFace {
  /// Describes a face from its raw font [bytes], defaulting to the regular
  /// slot ([JetFontWeight.normal], upright).
  const JetFontFace({
    required this.bytes,
    this.weight = JetFontWeight.normal,
    this.italic = false,
  });

  /// The face's raw TTF/OTF program bytes (host-sourced).
  final Uint8List bytes;

  /// The weight slot this face fills (defaults to [JetFontWeight.normal]).
  final JetFontWeight weight;

  /// Whether this face is the italic slot (defaults to `false`).
  final bool italic;

  @override
  bool operator ==(Object other) =>
      other is JetFontFace &&
      identical(other.bytes, bytes) &&
      other.weight == weight &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(identityHashCode(bytes), weight, italic);
}

/// A named family of host [faces] selectable by [name] in every picker (and
/// stored in reports under that name).
///
/// Construction validates **eagerly and synchronously** (catchable in a host
/// `try/catch`):
///
/// * [name] must be non-empty (else [ArgumentError]).
/// * the family must include at least one **regular** face
///   (`weight == JetFontWeight.normal && !italic`) — bold/italic are optional
///   and fall back to regular when absent (FR-001 / FR-005); otherwise a
///   [FontFormatException] naming the family is thrown.
/// * every face's [JetFontFace.bytes] must parse as font metrics; a malformed
///   or empty face throws a [FontFormatException] naming the family and the
///   offending weight/italic.
/// * no two faces may share the same `(weight, italic)` slot (else
///   [ArgumentError]).
///
/// Register the family **before** building a designer or rendering (see
/// `RenderOptions.fonts` and `JetReportDesigner.fonts`); duplicate family names
/// resolve last-registration-wins. Pass the **same** `List<JetFontFamily>` to
/// both the designer and `RenderOptions` so the picker and the render chain
/// agree.
class JetFontFamily {
  /// Creates and validates a family named [name] from [faces] (see the class
  /// doc for the eager validation rules).
  JetFontFamily({required this.name, required this.faces}) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final Set<String> slots = <String>{};
    bool hasRegular = false;
    for (final JetFontFace face in faces) {
      final String slot = '${face.weight.name}|${face.italic}';
      if (!slots.add(slot)) {
        throw ArgumentError('Font family "$name" has duplicate faces for '
            '${_describe(face)}; each (weight, italic) slot must be unique.');
      }
      if (face.weight == JetFontWeight.normal && !face.italic) {
        hasRegular = true;
      }
      try {
        parseTtfMetrics(face.bytes);
      } on FontFormatException catch (e) {
        throw FontFormatException(
            'Font family "$name" has an unreadable ${_describe(face)} face: '
            '${e.message}');
      }
    }
    if (!hasRegular) {
      throw FontFormatException('Font family "$name" needs a regular face '
          '(weight: normal, italic: false).');
    }
  }

  /// The display name shown in pickers and stored in reports (e.g. `"Acme
  /// Brand"`).
  final String name;

  /// The family's faces; at least one is a regular face. Order is preserved.
  final List<JetFontFace> faces;

  static String _describe(JetFontFace face) =>
      'weight: ${face.weight.name}, italic: ${face.italic}';
}
