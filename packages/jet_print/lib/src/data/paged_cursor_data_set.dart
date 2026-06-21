/// Internal: the cursor backing [JetPagedDataSource] — a forward-only walk over
/// a lazily-paged feed of unknown total length (spec 040).
library;

import 'data_row.dart';
import 'data_set.dart';
import 'field_def.dart';
import 'row_projection.dart';

/// A [DataSet] that pulls rows one page at a time via [fetchPage] and discards
/// each page once iterated, so the full dataset is never held in memory.
///
/// The total is **unknown up front**: iteration ends when a fetched page returns
/// fewer than [pageSize] rows (a short or empty final page). When the total is an
/// exact multiple of [pageSize], the last full page is followed by one empty
/// fetch that ends the feed. [fetchPage] must return at most [pageSize] rows; a
/// full page (`== pageSize`) signals "there may be more", fewer signals "this is
/// the last page". Fetching is synchronous.
///
/// Internal to the data seam — not part of the public API. Row projection is
/// shared with [RowCursorDataSet] via [projectRowOntoFields].
class PagedCursorDataSet implements DataSet {
  /// Creates a cursor over the [fetchPage] feed, projecting onto [fields].
  PagedCursorDataSet({
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

  int _pageIndex = -1; // index of the most recently fetched page
  List<Map<String, Object?>> _page = const <Map<String, Object?>>[];
  int _posInPage = -1; // cursor within _page
  bool _exhausted = false; // a short/empty page was seen → no more pages exist
  bool _closed = false;
  DataRow? _current;

  @override
  List<FieldDef> get fields => _fields;

  @override
  bool moveNext() {
    if (_closed) {
      _current = null;
      return false;
    }
    while (true) {
      // Serve the next row of the current page, if any.
      if (_posInPage + 1 < _page.length) {
        _posInPage++;
        _current = projectRowOntoFields(_fields, _page[_posInPage]);
        return true;
      }
      // Current page is drained — fetch the next, unless the feed has ended.
      if (_exhausted) {
        _current = null;
        return false;
      }
      _pageIndex++;
      final List<Map<String, Object?>> next = _fetchPage(_pageIndex);
      _page = next;
      _posInPage = -1;
      if (next.length < _pageSize) {
        _exhausted = true; // short or empty page → this is the last fetch
      }
      if (next.isEmpty) {
        _current = null;
        return false; // empty page → no row to serve, end of feed
      }
      // Loop to serve the first row of the freshly fetched page.
    }
  }

  @override
  DataRow get current {
    final DataRow? row = _current;
    if (row == null) {
      throw StateError(
        'No current row: call moveNext() and check it returned true first.',
      );
    }
    return row;
  }

  @override
  void close() {
    _closed = true;
    _current = null;
  }
}
