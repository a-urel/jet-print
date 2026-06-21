/// Internal: the shared raw-row → [DataRow] projection used by both built-in
/// cursors (spec 040).
library;

import 'data_row.dart';
import 'field_def.dart';

/// Projects [raw] onto [fields]: every declared field reads its value from
/// [raw] (a missing key yields `null`); keys not in [fields] are dropped. The
/// single source of the built-in cursors' projection rule, so index-driven
/// ([RowCursorDataSet]) and paged ([PagedCursorDataSet]) sources project
/// identically.
DataRow projectRowOntoFields(
  List<FieldDef> fields,
  Map<String, Object?> raw,
) =>
    DataRow(
      fields: fields,
      values: <String, Object?>{
        for (final FieldDef f in fields) f.name: raw[f.name],
      },
    );
