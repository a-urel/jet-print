/// Typed field metadata for the data layer (spec 004).
///
/// A [FieldDef] names a column and tags it with a best-effort [JetFieldType].
/// The type is additive metadata — a slot the expression engine (005) uses for
/// formatting and coercion — never a hard contract; an indeterminate column is
/// simply [JetFieldType.unknown]. Pure Dart, no Flutter dependency.
library;

/// The coarse value type of a data field.
///
/// Deliberately small: enough to drive number/date formatting and coercion
/// without modelling a full type system. [unknown] covers empty, all-null, or
/// genuinely mixed columns.
enum JetFieldType {
  /// Textual values (`String`).
  string,

  /// Whole numbers (`int`).
  integer,

  /// Fractional numbers (`double`), or a column mixing `int` and `double`.
  double,

  /// Boolean values (`bool`).
  boolean,

  /// Timestamps (`DateTime`).
  dateTime,

  /// Indeterminate — empty, all-null, or mixed/unsupported value types.
  unknown,
}

/// An immutable (name, type) pair describing one field of a [DataSet]'s schema.
class FieldDef {
  /// Creates a field named [name] with the given [type] (default
  /// [JetFieldType.unknown]).
  const FieldDef(this.name, {this.type = JetFieldType.unknown});

  /// The field's name, as referenced by `DataRow.field(name)`.
  final String name;

  /// The field's coarse value type (best-effort).
  final JetFieldType type;

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
      other is FieldDef && other.name == name && other.type == type;

  @override
  int get hashCode => Object.hash(name, type);

  @override
  String toString() => 'FieldDef($name, $type)';
}
