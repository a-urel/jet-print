/// Versioned JSON (de)serialization for [ReportTemplate] (Constitution V).
library;

import '../page_format.dart';
import '../report_band.dart';
import '../report_element.dart';
import '../report_template.dart';
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
  };
}

Map<String, Object?> _encodeBand(
  ReportBand band,
  ElementCodecRegistry registry,
) {
  return <String, Object?>{
    'type': band.type.name,
    'height': band.height,
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
