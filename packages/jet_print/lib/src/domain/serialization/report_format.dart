/// The public, versioned file-format facade for [ReportTemplate].
library;

import 'dart:convert';

import '../report_definition.dart';
import 'built_in_element_codecs.dart';
import 'element_codec.dart';
import 'migration.dart';
import 'migrations/v1_to_v2.dart';
import 'report_definition_codec.dart' as defcodec;
import 'report_format_exception.dart';

/// Encodes and decodes a [ReportDefinition] to/from the library's versioned
/// JSON file format (Constitution V), with the built-in element codecs and
/// schema migrations **pre-wired** — a consumer never assembles a codec
/// registry.
///
/// This is the save/open contract a host owns (FR-022): the library itself
/// performs no filesystem I/O. Encode a definition to text with
/// [encodeDefinitionJson], write it however the host prefers; read text back
/// and [decodeDefinitionJson] it.
///
/// The round-trip is lossless (`decodeDefinition(encodeDefinition(d))`
/// re-encodes identically), including element types this build does not
/// recognize (preserved as [UnknownElement]) and the full
/// parameter/variable/group payload — there is no attribute loss and no
/// reordering (SC-002). A legacy v1 (flat-band) document is walked forward by
/// the 1→2 migration on [decodeDefinition].
abstract final class JetReportFormat {
  /// The pre-wired registry of built-in element codecs (`text`, `shape`,
  /// `image`, `barcode`). Built once and reused; never mutated.
  static final ElementCodecRegistry _registry = _buildRegistry();

  /// Forward migrations for the reified [ReportDefinition] format (spec 024):
  /// the 1→2 flat-bands → tree migration walks legacy v1 documents forward.
  static final List<SchemaMigration> _definitionMigrations = <SchemaMigration>[
    V1ToV2Migration()
  ];

  static ElementCodecRegistry _buildRegistry() {
    final ElementCodecRegistry registry = ElementCodecRegistry();
    registerBuiltInElementCodecs(registry);
    return registry;
  }

  // --- Reified model (spec 024, schema v2) -------------------------------
  // The same pre-wired element registry serves both formats. A v1 document
  // (schemaVersion 1) is walked forward by the 1→2 migration into a
  // [ReportDefinition]; a v2 document decodes the section tree directly.

  /// Encodes [definition] to a JSON-safe map, stamped `schemaVersion: 2`.
  static Map<String, Object?> encodeDefinition(ReportDefinition definition) =>
      defcodec.encodeDefinition(definition, _registry);

  /// Decodes a report [json] map into a [ReportDefinition], migrating a legacy
  /// v1 (flat-band) document forward when needed. Throws [ReportFormatException]
  /// on malformed input or a `schemaVersion` newer than this build.
  static ReportDefinition decodeDefinition(Map<String, Object?> json) =>
      defcodec.decodeDefinition(json, _registry,
          migrations: _definitionMigrations);

  /// Encodes [definition] to a UTF-8 JSON string (convenience over
  /// [encodeDefinition]).
  static String encodeDefinitionJson(ReportDefinition definition) =>
      jsonEncode(encodeDefinition(definition));

  /// Decodes a UTF-8 JSON [source] string into a [ReportDefinition]
  /// (convenience over [decodeDefinition]). Throws [ReportFormatException] when
  /// the text is not a JSON object.
  static ReportDefinition decodeDefinitionJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const ReportFormatException('Report JSON must be a JSON object.');
    }
    return decodeDefinition(decoded.cast<String, Object?>());
  }
}
