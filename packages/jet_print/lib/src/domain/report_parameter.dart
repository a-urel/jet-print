/// A declared report parameter — a named external input (spec 005b).
library;

import 'value_type.dart';

/// An immutable parameter declaration: a [name], a coarse [type], and an
/// optional [defaultValue].
///
/// Parameters are supplied at fill time (resolved by `$P{}` references); this
/// declaration lets a template advertise its inputs with types and defaults.
/// The default serializes inline; a [JetFieldType.dateTime] default is written
/// as an ISO-8601 string.
class ReportParameter {
  /// Creates a parameter declaration.
  const ReportParameter({
    required this.name,
    required this.type,
    this.defaultValue,
  });

  /// Reads a [ReportParameter] from its [toJson] map.
  factory ReportParameter.fromJson(Map<String, Object?> json) {
    final JetFieldType type =
        JetFieldType.values.byName(json['type']! as String);
    return ReportParameter(
      name: json['name']! as String,
      type: type,
      defaultValue: json.containsKey('default')
          ? _decodeDefault(json['default'], type)
          : null,
    );
  }

  /// The parameter name, as referenced by `$P{name}`.
  final String name;

  /// The parameter's coarse value type.
  final JetFieldType type;

  /// The default value used when the caller supplies none (may be `null`).
  final Object? defaultValue;

  /// Serializes to a JSON-safe map (default omitted when null).
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'type': type.name,
        if (defaultValue != null)
          'default': _encodeDefault(defaultValue!, type),
      };

  static Object? _encodeDefault(Object value, JetFieldType type) =>
      type == JetFieldType.dateTime && value is DateTime
          ? value.toIso8601String()
          : value;

  static Object? _decodeDefault(Object? raw, JetFieldType type) =>
      type == JetFieldType.dateTime && raw is String
          ? DateTime.parse(raw)
          : raw;

  @override
  bool operator ==(Object other) =>
      other is ReportParameter &&
      other.name == name &&
      other.type == type &&
      other.defaultValue == defaultValue;

  @override
  int get hashCode => Object.hash(name, type, defaultValue);

  @override
  String toString() => 'ReportParameter($name, $type, default: $defaultValue)';
}
