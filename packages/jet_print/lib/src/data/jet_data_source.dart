/// The data-source factory contract (spec 004).
library;

import 'data_set.dart';

/// A factory that opens forward-only [DataSet] cursors over a row collection.
///
/// The host's side of the render contract (FR-011): build one of the public
/// implementations — `JetInMemoryDataSource` (rows as maps),
/// `JetJsonDataSource` (a JSON array of objects), or `JetObjectDataSource<T>`
/// (domain objects + extractor) — and hand it to `JetReportEngine.render`.
/// All three yield identical rendered output for the same logical dataset
/// (SC-006).
///
/// **Master/detail**: a row value that is a `List` of maps is a nested
/// collection; declare it as a [JetFieldType.collection] `FieldDef` (with its
/// child fields) and bind a detail band's `collectionField` to it — the band
/// repeats once per child row, to arbitrary nesting depth.
///
/// A source can be opened repeatedly — each [open] yields a fresh, independent
/// cursor positioned before the first row. [params] carries optional runtime
/// parameters (e.g. filters) for sources that support them; the built-in
/// in-memory sources accept but ignore it. This is extension point #3 of the
/// engine: a custom backend implements [open] returning its own [DataSet].
abstract class JetDataSource {
  /// Opens a fresh cursor, optionally parameterised by [params].
  DataSet open([Map<String, Object?> params = const <String, Object?>{}]);
}
