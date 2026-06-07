/// Data source decoded from a JSON array-of-objects string (spec 004).
library;

import 'dart:convert';

import 'data_set.dart';
import 'field_def.dart';
import 'in_memory_data_source.dart';
import 'jet_data_source.dart';

/// A [JetDataSource] built by decoding a JSON array of objects.
///
/// A convenience wrapper over [JetInMemoryDataSource]: each top-level array
/// element becomes a row. The JSON must be an array whose elements are all
/// objects — anything else throws [ArgumentError] (structural input is verified
/// up front rather than failing later during iteration). `int`/`double`
/// distinctions produced by `jsonDecode` flow straight into schema inference.
class JetJsonDataSource implements JetDataSource {
  JetJsonDataSource._(this._delegate);

  /// Parses [json] (a JSON array of objects) into a source.
  ///
  /// Pass an explicit [fields] schema to override inference. Throws
  /// [ArgumentError] if the decoded value is not an array of objects, or a
  /// [FormatException] if [json] is not valid JSON.
  factory JetJsonDataSource.parse(String json, {List<FieldDef>? fields}) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! List) {
      throw ArgumentError.value(
        json,
        'json',
        'Expected a JSON array of objects',
      );
    }
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Object? element in decoded) {
      if (element is! Map) {
        throw ArgumentError.value(
          element,
          'json',
          'Every array element must be a JSON object',
        );
      }
      rows.add(element.map<String, Object?>(
        (Object? key, Object? value) => MapEntry<String, Object?>(
          key.toString(),
          value,
        ),
      ));
    }
    return JetJsonDataSource._(JetInMemoryDataSource(rows, fields: fields));
  }

  final JetInMemoryDataSource _delegate;

  /// The source's schema (explicit or inferred), in column order.
  List<FieldDef> get fields => _delegate.fields;

  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      _delegate.open(params);
}
