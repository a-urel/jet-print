/// The structure of a data source attached to the designer (spec 009).
library;

import 'field_def.dart';

/// An immutable description of a data source's **structure** — a named dataset
/// and its root [fields] — that a host attaches to the designer so authors can
/// see and bind to it. It carries structure, not rows: the designer displays it
/// and resolves bindings against it, but (this iteration) never iterates data.
///
/// A field of type [JetFieldType.collection] carries its own child schema in
/// [FieldDef.fields], so a single schema can model master/detail to arbitrary
/// depth (e.g. an invoice with a nested `lines` collection).
///
/// Pure Dart (no Flutter dependency); value-equality, so two schemas with the
/// same name and (deeply) equal fields are equal.
class JetDataSchema {
  /// Creates a schema for a dataset named [name] with the given root [fields]
  /// and an optional [description].
  const JetDataSchema({
    required this.name,
    required this.fields,
    this.description,
  });

  /// The dataset's display name (shown as the structure tree's root).
  final String name;

  /// The dataset's root fields, in declaration order. A field may be a nested
  /// [JetFieldType.collection] carrying its own child schema.
  final List<FieldDef> fields;

  /// An optional human-friendly description of the data source, shown as a muted
  /// second line under [name] in the designer's Data Source view. Pure display
  /// sugar mirroring [FieldDef.description]: it never affects binding, type,
  /// expression resolution, or rendering. Null when unspecified.
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is JetDataSchema &&
      other.name == name &&
      other.description == description &&
      _fieldListEquals(other.fields, fields);

  @override
  int get hashCode => Object.hash(name, description, Object.hashAll(fields));

  @override
  String toString() => 'JetDataSchema($name, ${fields.length} fields)';
}

/// Deep, order-sensitive equality over two [FieldDef] lists (each element's
/// `==` recurses into nested collection schemas). Kept local so the data seam
/// imports no Flutter `listEquals`.
bool _fieldListEquals(List<FieldDef> a, List<FieldDef> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
