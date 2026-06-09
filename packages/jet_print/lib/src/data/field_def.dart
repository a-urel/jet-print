/// Typed field metadata for the data layer (spec 004).
///
/// A [FieldDef] names a column and tags it with a best-effort [JetFieldType]
/// (re-exported from the domain seam). The type is additive metadata — a slot
/// the expression engine uses for formatting and coercion — never a hard
/// contract; an indeterminate column is simply [JetFieldType.unknown]. Pure
/// Dart, no Flutter dependency.
library;

import '../domain/value_type.dart';

export '../domain/value_type.dart' show JetFieldType;

/// An immutable description of one field of a [DataSet]'s schema: a [name], a
/// coarse [type], and — for a [JetFieldType.collection] field — its own child
/// [fields] (spec 009). The recursion lets a schema model master/detail to
/// arbitrary depth (e.g. invoice → lines → sub-lines).
class FieldDef {
  /// Creates a field named [name] with the given [type] (default
  /// [JetFieldType.unknown]). Pass [fields] only for a [JetFieldType.collection]
  /// field, to declare its child schema.
  const FieldDef(
    this.name, {
    this.type = JetFieldType.unknown,
    this.fields = const <FieldDef>[],
  });

  /// The field's name, as referenced by `DataRow.field(name)`.
  final String name;

  /// The field's coarse value type (best-effort).
  final JetFieldType type;

  /// The child field schema of a [JetFieldType.collection] field; empty for a
  /// scalar field. Recursive — a child may itself be a collection.
  final List<FieldDef> fields;

  /// Best-effort inference of a column's [JetFieldType] from its [values].
  ///
  /// Nulls are ignored. A column of all `int` is [JetFieldType.integer]; mixing
  /// `int` and `double` widens to [JetFieldType.double]. Any other mixture, an
  /// unsupported runtime type, an empty sequence, or an all-null sequence yields
  /// [JetFieldType.unknown].
  static JetFieldType inferType(Iterable<Object?> values) {
    JetFieldType? result;
    for (final Object? value in values) {
      if (value == null) continue;
      final JetFieldType current = _typeOf(value);
      if (current == JetFieldType.unknown) return JetFieldType.unknown;
      if (result == null) {
        result = current;
      } else if (result != current) {
        final bool intDoubleMix = (result == JetFieldType.integer &&
                current == JetFieldType.double) ||
            (result == JetFieldType.double && current == JetFieldType.integer);
        if (intDoubleMix) {
          result = JetFieldType.double;
        } else {
          return JetFieldType.unknown;
        }
      }
    }
    return result ?? JetFieldType.unknown;
  }

  static JetFieldType _typeOf(Object value) {
    if (value is int) return JetFieldType.integer;
    if (value is double) return JetFieldType.double;
    if (value is bool) return JetFieldType.boolean;
    if (value is DateTime) return JetFieldType.dateTime;
    if (value is String) return JetFieldType.string;
    return JetFieldType.unknown;
  }

  @override
  bool operator ==(Object other) =>
      other is FieldDef &&
      other.name == name &&
      other.type == type &&
      _fieldListEquals(other.fields, fields);

  @override
  int get hashCode => Object.hash(name, type, Object.hashAll(fields));

  @override
  String toString() => fields.isEmpty
      ? 'FieldDef($name, $type)'
      : 'FieldDef($name, $type, fields: $fields)';
}

/// Deep, order-sensitive equality over two [FieldDef] lists. Pure Dart (no
/// Flutter `listEquals`) so the data seam stays headless; the per-element `==`
/// recurses into nested collection schemas.
bool _fieldListEquals(List<FieldDef> a, List<FieldDef> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
