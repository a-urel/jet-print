/// Coerces a raw collection value (a list of row-maps) into [DataRow]s.
///
/// The single source of truth for how a nested collection field's raw value
/// becomes rows — shared by the fill engine (a nested band's children) and the
/// chart resolver (a chart's bound series). A non-`List` [raw] yields no rows;
/// a non-`Map` entry is skipped (reported via [onSkippedEntry]).
library;

import 'data_row.dart';
import 'field_def.dart';

/// Projects [raw] onto rows.
///
/// When [declaredChildFields] is non-empty each entry is projected onto exactly
/// those fields (missing keys → null). When [declaredChildFields] is empty the
/// child schema is inferred from all entry keys via [inferFields], which types
/// nested collections recursively — matching the fill engine's behavior exactly.
///
/// Non-`Map` entries are skipped; [onSkippedEntry] is called with a stable key
/// (e.g. `'coll-entry'`) and a human-readable message so the caller can route
/// the report to its diagnostic budget.
List<DataRow> coerceCollectionRows(
  Object? raw, {
  required List<FieldDef> declaredChildFields,
  void Function(String entryKey, String message)? onSkippedEntry,
}) {
  if (raw is! List) return const <DataRow>[];
  final List<Map<String, Object?>> maps = <Map<String, Object?>>[];
  for (final Object? entry in raw) {
    if (entry is Map) {
      maps.add(entry.map((Object? k, Object? v) =>
          MapEntry<String, Object?>(k.toString(), v)));
    } else {
      onSkippedEntry?.call(
          'coll-entry', 'Collection contains a non-row entry; it is skipped');
    }
  }
  final List<FieldDef> fields =
      declaredChildFields.isNotEmpty ? declaredChildFields : inferFields(maps);
  return <DataRow>[
    for (final Map<String, Object?> m in maps)
      DataRow(
        fields: fields,
        values: <String, Object?>{
          for (final FieldDef f in fields) f.name: m[f.name],
        },
      ),
  ];
}
