/// The public, versioned file-format facade for [ReportTemplate].
library;

import 'dart:convert';

import '../report_template.dart';
import 'built_in_element_codecs.dart';
import 'element_codec.dart';
import 'migration.dart';
import 'report_codec.dart';
import 'report_format_exception.dart';

/// Encodes and decodes a [ReportTemplate] to/from the library's versioned JSON
/// file format (Constitution V), with the built-in element codecs and schema
/// migrations **pre-wired** — a consumer never assembles a codec registry.
///
/// This is the save/open contract a host owns (FR-022): the library itself
/// performs no filesystem I/O. Encode a template to text with [encodeJson],
/// write it however the host prefers; read text back and [decodeJson] it.
///
/// The round-trip is lossless (`decode(encode(t))` re-encodes identically),
/// including element types this build does not recognize (preserved as
/// [UnknownElement]) and the full parameter/variable/group payload — there is
/// no attribute loss and no reordering (SC-002).
abstract final class JetReportFormat {
  /// The pre-wired registry of built-in element codecs (`text`, `shape`,
  /// `image`, `barcode`). Built once and reused; never mutated.
  static final ElementCodecRegistry _registry = _buildRegistry();

  /// Forward migrations from older schema versions. Empty today (the schema is
  /// at version 1); each future schema bump appends one migration here.
  static const List<SchemaMigration> _migrations = <SchemaMigration>[];

  static ElementCodecRegistry _buildRegistry() {
    final ElementCodecRegistry registry = ElementCodecRegistry();
    registerBuiltInElementCodecs(registry);
    return registry;
  }

  /// Encodes [template] to a JSON-safe map, stamped with the current
  /// `schemaVersion`.
  static Map<String, Object?> encode(ReportTemplate template) =>
      encodeTemplate(template, _registry);

  /// Decodes a report [json] map: validates `schemaVersion` (throwing
  /// [ReportFormatException] when missing/non-int or newer than this build),
  /// runs forward migrations, then parses bands and elements.
  static ReportTemplate decode(Map<String, Object?> json) =>
      decodeTemplate(json, _registry, migrations: _migrations);

  /// Encodes [template] to a UTF-8 JSON string (convenience over [encode]).
  static String encodeJson(ReportTemplate template) =>
      jsonEncode(encode(template));

  /// Decodes a UTF-8 JSON [source] string into a [ReportTemplate]
  /// (convenience over [decode]). Throws [ReportFormatException] when the text
  /// is not a JSON object.
  static ReportTemplate decodeJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const ReportFormatException('Report JSON must be a JSON object.');
    }
    return decode(decoded.cast<String, Object?>());
  }
}
