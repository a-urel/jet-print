/// The data-source factory contract (spec 004).
library;

import 'data_set.dart';

/// A factory that opens forward-only [DataSet] cursors over a row collection.
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
