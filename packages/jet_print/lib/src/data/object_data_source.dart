/// Data source over a typed list of objects (spec 004).
library;

import 'data_set.dart';
import 'field_def.dart';
import 'jet_data_source.dart';
import 'row_cursor_data_set.dart';

/// A [JetDataSource] over a `List<T>` of domain objects.
///
/// Because `T` is opaque, the caller supplies both an explicit typed [fields]
/// schema and a [row] extractor that maps one object to a field-value map.
/// For master/detail, the extractor returns the child rows as a `List` of
/// maps under the collection field's name (declared as a
/// [JetFieldType.collection] `FieldDef` with child fields). The same logical
/// dataset renders identically through every public source (SC-006).
/// Mapping is lazy: [row] runs per object during iteration, not eagerly at
/// construction. [open] ignores its `params`.
class JetObjectDataSource<T> implements JetDataSource {
  /// Creates a source over [objects], described by [fields] and mapped by [row].
  JetObjectDataSource(
    List<T> objects, {
    required List<FieldDef> fields,
    required Map<String, Object?> Function(T object) row,
  })  : _objects = List<T>.unmodifiable(objects),
        _fields = List<FieldDef>.unmodifiable(fields),
        _row = row;

  final List<T> _objects;
  final List<FieldDef> _fields;
  final Map<String, Object?> Function(T object) _row;

  /// The explicit schema, in column order.
  List<FieldDef> get fields => _fields;

  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      RowCursorDataSet(
        fields: _fields,
        rowCount: _objects.length,
        rowAt: (int i) => _row(_objects[i]),
      );
}
