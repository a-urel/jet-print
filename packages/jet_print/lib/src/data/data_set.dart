/// The forward-only row cursor contract (spec 004).
library;

import 'data_row.dart';
import 'field_def.dart';

/// A synchronous, forward-only cursor over a data source's rows.
///
/// Usage:
/// ```dart
/// final DataSet ds = source.open(params);
/// try {
///   while (ds.moveNext()) {
///     final DataRow row = ds.current;
///     // ... read row.field('name')
///   }
/// } finally {
///   ds.close();
/// }
/// ```
///
/// [current] is valid only immediately after a [moveNext] that returned `true`.
/// Reading it in any other state — before the first such call, after [moveNext]
/// returns `false`, or after [close] — throws [StateError].
abstract class DataSet {
  /// The cursor's schema, in column order. Stable for the cursor's lifetime.
  List<FieldDef> get fields;

  /// Advances to the next row, returning `true` if one is now available.
  bool moveNext();

  /// The current row snapshot. Throws [StateError] if no row is current.
  DataRow get current;

  /// Releases any resources held by the cursor. Idempotent; in-memory cursors
  /// treat it as a no-op that also disables further iteration.
  void close();
}
