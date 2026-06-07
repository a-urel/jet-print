/// The runtime value model of the expression engine (spec 005a).
///
/// [JetValue] is a sealed type with one variant per supported value kind, plus
/// a [JetError] variant. Errors are values: a failed operation yields a
/// [JetError] that propagates through the evaluator, so evaluation never throws
/// (render-don't-crash). Numbers are always `double` (the all-double model).
library;

/// A runtime expression value.
sealed class JetValue {
  const JetValue();

  /// Lifts a raw Dart value (e.g. a `DataRow` field) into a [JetValue].
  ///
  /// `null`→[JetNull]; `bool`→[JetBool]; `int`/`double`→[JetNumber] (ints widen
  /// to `double`); `String`→[JetString]; `DateTime`→[JetDate]; an existing
  /// [JetValue] is returned unchanged. Any other runtime type yields a
  /// [JetError] (the strict model surfaces unsupported data rather than
  /// guessing).
  factory JetValue.from(Object? raw) {
    if (raw is JetValue) return raw;
    if (raw == null) return const JetNull();
    if (raw is bool) return JetBool(raw);
    if (raw is num) return JetNumber(raw.toDouble());
    if (raw is String) return JetString(raw);
    if (raw is DateTime) return JetDate(raw);
    return JetError('Unsupported value type: ${raw.runtimeType}');
  }
}

/// The absence of a value.
final class JetNull extends JetValue {
  /// Creates the null value.
  const JetNull();

  @override
  bool operator ==(Object other) => other is JetNull;

  @override
  int get hashCode => (JetNull).hashCode;

  @override
  String toString() => 'JetNull()';
}

/// A boolean value.
final class JetBool extends JetValue {
  /// Creates a boolean value.
  const JetBool(this.value);

  /// The wrapped boolean.
  final bool value;

  @override
  bool operator ==(Object other) => other is JetBool && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'JetBool($value)';
}

/// A numeric value. Always `double` (the all-double model).
final class JetNumber extends JetValue {
  /// Creates a numeric value.
  const JetNumber(this.value);

  /// The wrapped number.
  final double value;

  @override
  bool operator ==(Object other) => other is JetNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'JetNumber($value)';
}

/// A string value.
final class JetString extends JetValue {
  /// Creates a string value.
  const JetString(this.value);

  /// The wrapped string.
  final String value;

  @override
  bool operator ==(Object other) => other is JetString && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'JetString($value)';
}

/// A timestamp value.
final class JetDate extends JetValue {
  /// Creates a timestamp value.
  const JetDate(this.value);

  /// The wrapped timestamp.
  final DateTime value;

  @override
  bool operator ==(Object other) => other is JetDate && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'JetDate($value)';
}

/// A failed evaluation, carrying a human-readable [message].
///
/// A value, not an exception: it propagates through the evaluator and is
/// rendered as `!ERR` (plus a diagnostic) by the render stage.
final class JetError extends JetValue {
  /// Creates an error value with the given [message].
  const JetError(this.message);

  /// Why evaluation failed.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is JetError && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'JetError($message)';
}

/// Renders a [JetValue] to display text (used by `CONCAT` and direct display).
///
/// [JetNull]→`''`; [JetBool]→`'true'`/`'false'`; [JetNumber]→`double.toString()`
/// (so `5.0` prints `5.0` — use `FORMAT` for presentation); [JetString]→its
/// text; [JetDate]→ISO 8601; [JetError]→`'!ERR'`.
String jetStringify(JetValue value) => switch (value) {
      JetNull() => '',
      JetBool(value: final bool v) => v.toString(),
      JetNumber(value: final double v) => v.toString(),
      JetString(value: final String v) => v,
      JetDate(value: final DateTime v) => v.toIso8601String(),
      JetError() => '!ERR',
    };
