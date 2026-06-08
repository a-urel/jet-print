/// Versioned JSON (de)serialization for [ReportTemplate] (Constitution V).
library;

import '../page_format.dart';
import '../report_band.dart';
import '../report_element.dart';
import '../report_group.dart';
import '../report_parameter.dart';
import '../report_template.dart';
import '../report_variable.dart';
import 'element_codec.dart';
import 'migration.dart';
import 'report_format_exception.dart';

/// The report-schema version this build writes. Bump on every schema change and
/// ship a [SchemaMigration] for the previous version.
const int kReportSchemaVersion = 1;

/// Encodes [template] to a JSON-safe map, stamping [kReportSchemaVersion] and
/// routing each element through [registry].
Map<String, Object?> encodeTemplate(
  ReportTemplate template,
  ElementCodecRegistry registry,
) {
  return <String, Object?>{
    'schemaVersion': kReportSchemaVersion,
    'name': template.name,
    'page': template.page.toJson(),
    'bands': <Object?>[
      for (final ReportBand band in template.bands) _encodeBand(band, registry),
    ],
    if (template.parameters.isNotEmpty)
      'parameters': <Object?>[
        for (final ReportParameter p in template.parameters) p.toJson(),
      ],
    if (template.variables.isNotEmpty)
      'variables': <Object?>[
        for (final ReportVariable v in template.variables) v.toJson(),
      ],
    if (template.groups.isNotEmpty)
      'groups': <Object?>[
        for (final ReportGroup g in template.groups) g.toJson(),
      ],
  };
}

Map<String, Object?> _encodeBand(
  ReportBand band,
  ElementCodecRegistry registry,
) {
  return <String, Object?>{
    'type': band.type.name,
    'height': band.height,
    if (band.group != null) 'group': band.group,
    'elements': <Object?>[
      for (final ReportElement element in band.elements)
        registry.encode(element),
    ],
  };
}

/// Decodes a report [json] map. Validates `schemaVersion` (fail-fast if missing
/// or newer than this build), walks older documents forward via [migrations],
/// then parses bands/elements through [registry].
ReportTemplate decodeTemplate(
  Map<String, Object?> json,
  ElementCodecRegistry registry, {
  List<SchemaMigration> migrations = const <SchemaMigration>[],
}) {
  final Object? rawVersion = json['schemaVersion'];
  if (rawVersion is! int) {
    throw const ReportFormatException(
      'Missing or non-integer "schemaVersion".',
    );
  }
  if (rawVersion > kReportSchemaVersion) {
    throw ReportFormatException(
      'Report schemaVersion $rawVersion is newer than this build supports '
      '($kReportSchemaVersion).',
    );
  }
  final Map<String, Object?> upgraded = rawVersion < kReportSchemaVersion
      ? runMigrations(
          json,
          from: rawVersion,
          to: kReportSchemaVersion,
          migrations: migrations,
        )
      : json;

  final Object? bands = upgraded['bands'];
  if (bands is! List) {
    throw const ReportFormatException('"bands" must be a list.');
  }
  return ReportTemplate(
    name: upgraded['name']! as String,
    page: PageFormat.fromJson(
      (upgraded['page']! as Map).cast<String, Object?>(),
    ),
    bands: <ReportBand>[
      for (final Object? band in bands)
        _decodeBand((band! as Map).cast<String, Object?>(), registry),
    ],
    parameters: _decodeList<ReportParameter>(
        upgraded['parameters'], 'parameters', ReportParameter.fromJson),
    variables: _decodeList<ReportVariable>(
        upgraded['variables'], 'variables', ReportVariable.fromJson),
    groups: _decodeList<ReportGroup>(
        upgraded['groups'], 'groups', ReportGroup.fromJson),
  );
}

ReportBand _decodeBand(
  Map<String, Object?> json,
  ElementCodecRegistry registry,
) {
  final Object? elements = json['elements'];
  if (elements is! List) {
    throw const ReportFormatException('Band "elements" must be a list.');
  }
  return ReportBand(
    type: _parseBandType(json['type']),
    height: (json['height']! as num).toDouble(),
    group: json['group'] as String?,
    elements: <ReportElement>[
      for (final Object? element in elements)
        registry.decode((element! as Map).cast<String, Object?>()),
    ],
  );
}

BandType _parseBandType(Object? name) {
  if (name is! String) {
    throw const ReportFormatException('Band "type" must be a string.');
  }
  try {
    return BandType.values.byName(name);
  } on ArgumentError {
    throw ReportFormatException('Unknown band type "$name".');
  }
}

List<T> _decodeList<T>(
  Object? raw,
  String key,
  T Function(Map<String, Object?>) fromJson,
) {
  if (raw == null) return <T>[];
  if (raw is! List) {
    throw ReportFormatException('"$key" must be a list.');
  }
  return <T>[
    for (final Object? entry in raw) _decodeEntry<T>(entry, key, fromJson),
  ];
}

T _decodeEntry<T>(
  Object? entry,
  String key,
  T Function(Map<String, Object?>) fromJson,
) {
  if (entry is! Map) {
    throw ReportFormatException('Each "$key" entry must be a JSON object.');
  }
  try {
    return fromJson(entry.cast<String, Object?>());
  } on ReportFormatException {
    rethrow;
  } catch (error) {
    throw ReportFormatException('Malformed "$key" entry: $error');
  }
}
