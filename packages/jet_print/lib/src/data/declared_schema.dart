/// Which data sources declare their schema, for the engine's `knownFields`
/// default (#99).
library;

import 'field_def.dart';
import 'in_memory_data_source.dart';
import 'jet_data_source.dart';
import 'json_data_source.dart';
import 'object_data_source.dart';
import 'paged_data_source.dart';

/// The field names [source] declares explicitly, flattened through nested
/// collections, or null when it declares none.
///
/// `JetObjectDataSource` and `JetPagedDataSource` always take an explicit
/// schema; `JetInMemoryDataSource` and `JetJsonDataSource` only when `fields:`
/// is passed. An inferred schema and a custom source yield null, so a binding
/// to an unknown field keeps rendering empty there.
Set<String>? declaredFieldNames(JetDataSource source) {
  final List<FieldDef>? fields = switch (source) {
    final JetInMemoryDataSource s => declaredInMemoryFields(s),
    final JetJsonDataSource s => declaredJsonFields(s),
    final JetObjectDataSource<Object?> s => s.fields,
    final JetPagedDataSource s => s.fields,
    _ => null,
  };
  return fields == null ? null : _names(fields);
}

Set<String> _names(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{f.name, ..._names(f.fields)},
    };
