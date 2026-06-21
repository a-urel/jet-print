/// Internal: the shared index-driven cursor backing the built-in data sources.
library;

import 'data_row.dart';
import 'data_set.dart';
import 'field_def.dart';
import 'row_projection.dart';

/// A [DataSet] that walks `0..rowCount-1`, pulling each raw row via [rowAt] and
/// projecting it onto a fixed [fields] schema.
///
/// Internal to the data seam — not part of the public API. All three built-in
/// sources (in-memory, JSON, object-list) delegate to this one cursor so the
/// forward-only semantics, schema projection, and `current`/`close` rules live
/// in exactly one place. Projection rule: each declared field reads its value
/// from the raw row (a missing key yields `null`); keys not in the schema are
/// dropped.
class RowCursorDataSet implements DataSet {
  /// Creates a cursor over [rowCount] rows, reading each via [rowAt].
  ///
  /// [rowAt] is called only with indices in `0..rowCount-1`; passing a
  /// [rowCount] larger than [rowAt]'s domain is a caller error (it would feed
  /// [rowAt] an out-of-range index).
  RowCursorDataSet({
    required List<FieldDef> fields,
    required int rowCount,
    required Map<String, Object?> Function(int index) rowAt,
  })  : _fields = List<FieldDef>.unmodifiable(fields),
        _rowCount = rowCount,
        _rowAt = rowAt;

  final List<FieldDef> _fields;
  final int _rowCount;
  final Map<String, Object?> Function(int index) _rowAt;

  int _index = -1;
  DataRow? _current;
  bool _closed = false;

  @override
  List<FieldDef> get fields => _fields;

  @override
  bool moveNext() {
    if (_closed || _index + 1 >= _rowCount) {
      _current = null;
      return false;
    }
    _index++;
    _current = projectRowOntoFields(_fields, _rowAt(_index));
    return true;
  }

  @override
  DataRow get current {
    final DataRow? row = _current;
    if (row == null) {
      throw StateError(
        'No current row: call moveNext() and check it returned true first.',
      );
    }
    return row;
  }

  @override
  void close() {
    _closed = true;
    _current = null;
  }
}
