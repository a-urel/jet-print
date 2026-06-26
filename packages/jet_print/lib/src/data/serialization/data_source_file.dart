/// The public, versioned file-format facade for the designer's data source —
/// a `JetDataSchema` plus optional sample rows (`*.jetreport.datasource`).
library;

import 'dart:convert';

import '../data_schema.dart';
import '../field_def.dart';
import 'data_source_format_exception.dart';

/// A decoded `*.jetreport.datasource` document: the data [schema] the designer
/// binds against, plus optional [sample] rows a host may use for preview
/// (null when the file omits them). Value-equality for round-trip testing.
class JetDataSourceDocument {
  /// Creates a document over [schema] with optional [sample] rows.
  const JetDataSourceDocument({required this.schema, this.sample});

  /// The data-source structure the designer displays and binds against.
  final JetDataSchema schema;

  /// Optional sample rows (plain JSON values), or null when absent.
  final List<Map<String, Object?>>? sample;

  @override
  bool operator ==(Object other) =>
      other is JetDataSourceDocument &&
      other.schema == schema &&
      _sampleEquals(other.sample, sample);

  @override
  int get hashCode => Object.hash(schema, _sampleHash(sample));
}

/// Encodes and decodes a [JetDataSourceDocument] to/from the library's
/// versioned JSON format (Constitution V). The library performs no filesystem
/// I/O: a host reads the text and [decodeJson]s it, or [encodeJson]s a document
/// and writes it. The round-trip is lossless over the schema (including nested
/// collection fields); sample rows pass through as plain JSON values.
abstract final class JetDataSourceFile {
  /// The current document schema version.
  static const int version = 1;

  /// Encodes [doc] to a JSON-safe map stamped `jetDataSource: version`.
  static Map<String, Object?> encode(JetDataSourceDocument doc) =>
      <String, Object?>{
        'jetDataSource': version,
        'schema': _encodeSchema(doc.schema),
        if (doc.sample != null) 'sample': doc.sample,
      };

  /// Decodes a [json] map into a [JetDataSourceDocument]. Throws
  /// [JetDataSourceFormatException] on a missing/too-new version, a malformed
  /// shape, or an unknown field type.
  static JetDataSourceDocument decode(Map<String, Object?> json) {
    final Object? v = json['jetDataSource'];
    if (v is! int) {
      throw const JetDataSourceFormatException(
          'Missing or non-integer "jetDataSource" version.');
    }
    if (v > version) {
      throw JetDataSourceFormatException(
          'Document version $v is newer than this build ($version).');
    }
    final Object? rawSchema = json['schema'];
    if (rawSchema is! Map) {
      throw const JetDataSourceFormatException('Missing "schema" object.');
    }
    final JetDataSchema schema =
        _decodeSchema(rawSchema.cast<String, Object?>());
    final Object? rawSample = json['sample'];
    List<Map<String, Object?>>? sample;
    if (rawSample != null) {
      if (rawSample is! List) {
        throw const JetDataSourceFormatException('"sample" must be a list.');
      }
      sample = <Map<String, Object?>>[
        for (final Object? row in rawSample)
          if (row is Map)
            row.cast<String, Object?>()
          else
            throw const JetDataSourceFormatException(
                '"sample" rows must be objects.'),
      ];
    }
    return JetDataSourceDocument(schema: schema, sample: sample);
  }

  /// Encodes [doc] to a UTF-8 JSON string.
  static String encodeJson(JetDataSourceDocument doc) =>
      jsonEncode(encode(doc));

  /// Decodes a UTF-8 JSON [source] string. Throws [JetDataSourceFormatException]
  /// when the text is not a JSON object.
  static JetDataSourceDocument decodeJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw JetDataSourceFormatException('Invalid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const JetDataSourceFormatException(
          'Data source JSON must be a JSON object.');
    }
    return decode(decoded.cast<String, Object?>());
  }
}

Map<String, Object?> _encodeSchema(JetDataSchema schema) => <String, Object?>{
      'name': schema.name,
      'fields': <Map<String, Object?>>[
        for (final FieldDef f in schema.fields) _encodeField(f),
      ],
    };

JetDataSchema _decodeSchema(Map<String, Object?> json) {
  final Object? name = json['name'];
  if (name is! String) {
    throw const JetDataSourceFormatException('Schema "name" must be a string.');
  }
  final Object? fields = json['fields'];
  if (fields is! List) {
    throw const JetDataSourceFormatException('Schema "fields" must be a list.');
  }
  return JetDataSchema(
    name: name,
    fields: <FieldDef>[
      for (final Object? f in fields)
        if (f is Map)
          _decodeField(f.cast<String, Object?>())
        else
          throw const JetDataSourceFormatException(
              'Each field must be an object.'),
    ],
  );
}

Map<String, Object?> _encodeField(FieldDef field) => <String, Object?>{
      'name': field.name,
      'type': field.type.name,
      if (field.description != null) 'description': field.description,
      if (field.type == JetFieldType.collection)
        'fields': <Map<String, Object?>>[
          for (final FieldDef child in field.fields) _encodeField(child),
        ],
    };

FieldDef _decodeField(Map<String, Object?> json) {
  final Object? name = json['name'];
  if (name is! String) {
    throw const JetDataSourceFormatException('Field "name" must be a string.');
  }
  final Object? typeName = json['type'];
  JetFieldType? type;
  for (final JetFieldType t in JetFieldType.values) {
    if (t.name == typeName) {
      type = t;
      break;
    }
  }
  if (type == null) {
    throw JetDataSourceFormatException('Unknown field type "$typeName".');
  }
  final Object? rawDescription = json['description'];
  if (rawDescription != null && rawDescription is! String) {
    throw const JetDataSourceFormatException(
        'Field "description" must be a string.');
  }
  final Object? children = json['fields'];
  return FieldDef(
    name,
    type: type,
    description: rawDescription as String?,
    fields: <FieldDef>[
      if (children is List)
        for (final Object? c in children)
          if (c is Map)
            _decodeField(c.cast<String, Object?>())
          else
            throw const JetDataSourceFormatException(
                'Each field must be an object.'),
    ],
  );
}

bool _sampleEquals(
    List<Map<String, Object?>>? a, List<Map<String, Object?>>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return jsonEncode(a) == jsonEncode(b);
}

int _sampleHash(List<Map<String, Object?>>? sample) {
  if (sample == null) return null.hashCode;
  return jsonEncode(sample).hashCode;
}
