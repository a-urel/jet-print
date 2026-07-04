/// Support for thunk-based `copyWith` parameters on nullable fields.
///
/// A plain `T? field` parameter cannot distinguish "leave unchanged" from
/// "set to null", which forces callers that need to *clear* a slot to rebuild
/// the whole object field-by-field — the recurring source of silently dropped
/// fields (name/visible/footer/totals/watermark). A `T Function()? field`
/// parameter keeps both edits expressible: omit (or pass null) to preserve the
/// current value, pass a thunk to replace it (`field: () => null` clears).
library;

/// The value a thunk-based `copyWith` parameter resolves to: [replacement]'s
/// result when provided, else [current].
T pick<T>(T Function()? replacement, T current) =>
    replacement == null ? current : replacement();
