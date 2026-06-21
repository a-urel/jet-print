/// Lazily-paged data source: pulls rows one page at a time (spec 040).
library;

import 'data_set.dart';
import 'field_def.dart';
import 'jet_data_source.dart';
import 'paged_cursor_data_set.dart';

/// A [JetDataSource] that fetches rows one page at a time via [fetchPage] and
/// never holds the whole dataset in memory — the fourth public source alongside
/// `JetInMemoryDataSource`, `JetJsonDataSource`, and `JetObjectDataSource`.
///
/// Use it when the dataset is generated on demand or arrives in batches and you
/// do not want to (or cannot) materialize it as one `List`:
///
/// ```dart
/// JetPagedDataSource(
///   fields: schema.fields,            // explicit — see below
///   pageSize: 250,
///   fetchPage: (int pageIndex) {
///     final int start = pageIndex * 250;
///     if (start >= total) return const <Map<String, Object?>>[];
///     return rowsFor(start, 250);     // up to 250 rows, fewer on the last page
///   },
/// )
/// ```
///
/// **Unknown total.** Iteration ends when [fetchPage] returns fewer than
/// [pageSize] rows (a short or empty final page); the cursor never asks for the
/// total up front. [fetchPage] must return at most [pageSize] rows per call.
///
/// **Explicit schema required.** Unlike the in-memory sources, [fields] cannot be
/// inferred — the source never sees the whole dataset — so you must declare it.
///
/// **Synchronous.** [fetchPage] returns rows directly, matching the engine's
/// synchronous fill pass. For a remote/async backend, pre-fetch each page into
/// memory before returning it. [open] ignores its `params`.
class JetPagedDataSource implements JetDataSource {
  /// Creates a paged source over [fetchPage], described by [fields], with
  /// [pageSize] rows per page. Throws [ArgumentError] if [pageSize] < 1.
  JetPagedDataSource({
    required List<FieldDef> fields,
    required int pageSize,
    required List<Map<String, Object?>> Function(int pageIndex) fetchPage,
  })  : _fields = List<FieldDef>.unmodifiable(fields),
        _pageSize = pageSize,
        _fetchPage = fetchPage {
    if (pageSize < 1) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be >= 1');
    }
  }

  final List<FieldDef> _fields;
  final int _pageSize;
  final List<Map<String, Object?>> Function(int pageIndex) _fetchPage;

  /// The explicit schema, in column order.
  List<FieldDef> get fields => _fields;

  @override
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]) =>
      PagedCursorDataSet(
        fields: _fields,
        pageSize: _pageSize,
        fetchPage: _fetchPage,
      );
}
