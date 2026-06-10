/// In-memory data source over a list of row maps (spec 004).
library;

import 'data_set.dart';
import 'field_def.dart';
import 'jet_data_source.dart';
import 'row_cursor_data_set.dart';

/// A [JetDataSource] backed by an in-memory `List<Map<String, Object?>>`.
///
/// The simplest way to feed `JetReportEngine.render` (FR-011). A nested
/// collection (master/detail) is just a `List` of child maps under one key:
///
/// ```dart
/// JetInMemoryDataSource([
///   {
///     'invoiceNo': 'INV-1042',
///     'lines': [                       // nested collection → a detail band
///       {'desc': 'Widget', 'qty': 3},  // with collectionField: 'lines'
///       {'desc': 'Gadget', 'qty': 1},  // repeats once per entry
///     ],
///   },
/// ])
/// ```
///
/// When [fields] is omitted the schema is inferred: the union of all row keys
/// in first-seen order, each typed best-effort via [FieldDef.inferType] over
/// that column's values (a nested collection's child schema is then inferred
/// from its entries at fill time). The rows and schema are copied defensively,
/// so later mutation of the caller's list does not affect the source. [open]
/// ignores its `params`.
class JetInMemoryDataSource implements JetDataSource {
  /// Creates a source over [rows], with an optional explicit [fields] schema.
  JetInMemoryDataSource(
    List<Map<String, Object?>> rows, {
    List<FieldDef>? fields,
  })  : _rows = <Map<String, Object?>>[
          for (final Map<String, Object?> row in rows)
            Map<String, Object?>.unmodifiable(row),
        ],
        _fields = List<FieldDef>.unmodifiable(fields ?? _inferFields(rows));

  final List<Map<String, Object?>> _rows;
  final List<FieldDef> _fields;

  /// The source's schema (explicit or inferred), in column order.
  List<FieldDef> get fields => _fields;

  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      RowCursorDataSet(
        fields: _fields,
        rowCount: _rows.length,
        rowAt: (int i) => _rows[i],
      );

  static List<FieldDef> _inferFields(List<Map<String, Object?>> rows) {
    final List<String> names = <String>[];
    final Set<String> seen = <String>{};
    for (final Map<String, Object?> row in rows) {
      for (final String key in row.keys) {
        if (seen.add(key)) names.add(key);
      }
    }
    return <FieldDef>[
      for (final String name in names)
        FieldDef(
          name,
          type: FieldDef.inferType(
            rows.map((Map<String, Object?> r) => r[name]),
          ),
        ),
    ];
  }
}
