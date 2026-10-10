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
/// JSON file format, with the built-in element codecs and
/// schema migrations **pre-wired** — a consumer never assembles a codec
/// registry.
///
/// This is the save/open contract a host owns: the library itself
/// performs no filesystem I/O. Encode a definition to text with
/// [encodeDefinitionJson], write it however the host prefers; read text back
/// and [decodeDefinitionJson] it.
///
/// The round-trip is lossless (`decodeDefinition(encodeDefinition(d))`
/// re-encodes identically), including element types this build does not
/// recognize (preserved as [UnknownElement]) and the full
/// parameter/variable/group payload — there is no attribute loss and no
/// reordering. A legacy v1 (flat-band) document is walked forward by
/// the 1→2 migration on [decodeDefinition].
abstract final class JetReportFormat {
  /// The report schema version this build writes: the value of the
  /// `schemaVersion` key that [encodeDefinition] stamps first in every
  /// document.
  ///
  /// [decodeDefinition] reads any document up to this version, migrating an
  /// older one forward, and rejects a newer one. A host that stores reports can
  /// keep this beside each one — a `schema_version` column, say — to find the
  /// documents written before an upgrade without parsing them. It is the
  /// schema's number, not the package's: that is `jetPrintVersion`.
  static const int schemaVersion = defcodec.kReportDefinitionSchemaVersion;

  /// The pre-wired registry of built-in element codecs (`text`, `shape`,
  /// `image`, `barcode`, `chart`). Built once and reused; never mutated.
  static final ElementCodecRegistry _registry = _buildRegistry();

  /// Forward migrations for the reified [ReportDefinition] format:
  /// the 1→2 flat-bands → tree migration walks legacy v1 documents forward.
  static final List<SchemaMigration> _definitionMigrations = <SchemaMigration>[
    V1ToV2Migration()
  ];

  static ElementCodecRegistry _buildRegistry() {
    final ElementCodecRegistry registry = ElementCodecRegistry();
    registerBuiltInElementCodecs(registry);
    return registry;
  }

  // --- Reified model (schema v2) -------------------------------
  // The same pre-wired element registry serves both formats. A v1 document
  // (schemaVersion 1) is walked forward by the 1→2 migration into a
  // [ReportDefinition]; a v2 document decodes the section tree directly.

  /// Encodes [definition] to a JSON-safe map, stamped with [schemaVersion].
  static Map<String, Object?> encodeDefinition(ReportDefinition definition) =>
      defcodec.encodeDefinition(definition, _registry);

  /// Decodes a report [json] map into a [ReportDefinition], migrating a legacy
  /// v1 (flat-band) document forward when needed. Throws [ReportFormatException]
  /// on malformed input or a `schemaVersion` newer than this build — and only
  /// that: see [_asFormatError].
  static ReportDefinition decodeDefinition(Map<String, Object?> json) =>
      _asFormatError(() => defcodec.decodeDefinition(json, _registry,
          migrations: _definitionMigrations));

  /// Encodes [definition] to a UTF-8 JSON string (convenience over
  /// [encodeDefinition]).
  static String encodeDefinitionJson(ReportDefinition definition) =>
      jsonEncode(encodeDefinition(definition));

  /// Decodes a UTF-8 JSON [source] string into a [ReportDefinition]
  /// (convenience over [decodeDefinition]). Throws [ReportFormatException] when
  /// the text is not a JSON object.
  static ReportDefinition decodeDefinitionJson(String source) {
    final Object? decoded = _asFormatError(() => jsonDecode(source));
    if (decoded is! Map) {
      throw const ReportFormatException('Report JSON must be a JSON object.');
    }
    return decodeDefinition(decoded.cast<String, Object?>());
  }

  /// Runs [decode], turning anything a malformed document can raise into a
  /// [ReportFormatException], so a host needs exactly one `catch`.
  ///
  /// The codecs check the shapes they expect explicitly where a message helps,
  /// but a document can be wrong in more places than are worth a hand-written
  /// check: a `!`/`as` cast meets the wrong type (`TypeError`), an enum name is
  /// unknown (`ArgumentError` from `values.byName`), a string is not a number,
  /// a colour or JSON (`FormatException`), or an index is out of range
  /// (`RangeError`, an `ArgumentError`). Each is the document's fault, so each
  /// is reported as one, keeping the underlying message.
  static T _asFormatError<T>(T Function() decode) {
    try {
      return decode();
    } on ReportFormatException {
      rethrow;
    } on FormatException catch (e) {
      throw ReportFormatException('Malformed report: ${e.message}');
    } on TypeError catch (e) {
      throw ReportFormatException('Malformed report: $e');
    } on ArgumentError catch (e) {
      throw ReportFormatException('Malformed report: ${e.message}: '
          '${e.invalidValue}');
    }
  }
}
