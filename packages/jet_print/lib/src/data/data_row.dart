/// Immutable snapshot of one data-source row (spec 004).
library;

import 'field_def.dart';

/// An immutable view of a single row: a declared schema plus the row's values.
///
/// Construction defensively copies both the [fields] and the [values] map into
/// unmodifiable collections, so a [DataRow] never changes after it is created —
/// even if the caller later mutates the map it passed in. This makes rows safe
/// to stash (e.g. comparing the previous and current row to detect a group
/// break in the Fill stage).
class DataRow {
  /// Creates a row over [fields] whose declared values are [values].
  ///
  /// [values] must contain an entry for every declared field name (the value
  /// may be `null`); the built-in cursor guarantees this by projecting each raw
  /// row onto the schema.
  DataRow({
    required List<FieldDef> fields,
    required Map<String, Object?> values,
  })  : _fields = List<FieldDef>.unmodifiable(fields),
        _values = Map<String, Object?>.unmodifiable(values);

  final List<FieldDef> _fields;
  final Map<String, Object?> _values;

  /// The row's declared schema, in order.
  List<FieldDef> get fields => _fields;

  /// The value of the declared field [name] (which may be `null`).
  ///
  /// Throws [ArgumentError] if [name] is not a declared field — an undeclared
  /// name is a programming error, distinct from a declared-but-null value.
  Object? field(String name) {
    if (!_values.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown field');
    }
    return _values[name];
  }

  /// Whether [name] is a declared field of this row.
  bool hasField(String name) => _values.containsKey(name);

  @override
  bool operator ==(Object other) =>
      other is DataRow &&
      _fieldsEqual(_fields, other._fields) &&
      _valuesEqual(_values, other._values);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(_fields),
        Object.hashAll(<Object?>[
          for (final MapEntry<String, Object?> e
              in _values.entries) ...<Object?>[
            e.key,
            e.value,
          ],
        ]),
      );

  @override
  String toString() => 'DataRow($_values)';
}

bool _fieldsEqual(List<FieldDef> a, List<FieldDef> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _valuesEqual(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final MapEntry<String, Object?> e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}
