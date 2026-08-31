// Preserves a scope node whose `kind` is not known to this build.
//
// A part of `detail_scope.dart`: ScopeNode is sealed, so every direct
// subtype — BandNode, NestedScope, CrosstabNode, and this one — must live
// in the same library. Kept as its own file (rather than inlined in
// `detail_scope.dart`) purely for organization; it shares that file's imports
// and has no exports of its own beyond UnknownScopeNode itself, re-exported
// from the barrel alongside the other ScopeNode variants.
//
// (Plain comment, not dartdoc: `//`, not `///` — square-bracket references
// here would not resolve to anything, so names are left unbracketed. The
// user-facing rationale lives in the class dartdoc below instead.)
part of 'detail_scope.dart';

/// A [ScopeNode] standing in for a `kind` this build does not recognize.
///
/// It keeps the node's original JSON verbatim ([rawJson]) so a definition
/// authored by a newer build round-trips **losslessly** (Constitution V) rather
/// than failing the whole file. It renders nothing.
final class UnknownScopeNode extends ScopeNode with ValueEquality {
  /// Wraps [rawJson] for an unrecognized node kind.
  const UnknownScopeNode({required this.rawJson});

  /// The node's original JSON, written back unchanged on save.
  ///
  /// The decoder hands this an unmodifiable top-level map ([Map.unmodifiable]
  /// is shallow), but nested lists/maps within it are the same mutable
  /// objects produced by whatever parsed the document — do not mutate them.
  final Map<String, Object?> rawJson;

  /// The unrecognized `kind` string, or null when the JSON had none.
  String? get kind =>
      rawJson['kind'] is String ? rawJson['kind']! as String : null;

  @override
  List<Object?> get props => <Object?>[_flatten(rawJson)];

  @override
  String toString() => 'UnknownScopeNode(${kind ?? '?'})';
}

/// Flattens an arbitrarily-nested JSON value into a [ValueEquality]-friendly
/// shape: every [Map] and [List] becomes a [List], so [ValueEquality]'s
/// element-wise `List` recursion reaches every leaf instead of falling back to
/// identity comparison on a nested [Map] (which does not override `==`).
///
/// Each flattened container is tagged with a leading [Symbol] marker
/// (`#jsonObject` / `#jsonArray`) identifying which JSON shape it came from.
/// Without this, a JSON object and a JSON array can flatten to the exact same
/// `List` (e.g. `{'a': 1, 'b': 2}` and `['a', 1, 'b', 2]` both become
/// `[a, 1, b, 2]`), making two structurally different documents compare
/// equal. A JSON value decodes only to `null` / `bool` / `num` / `String` /
/// [List] / [Map], so a [Symbol] marker can never collide with payload data.
///
/// A [Map] flattens to `[#jsonObject, key1, flatten(value1), key2,
/// flatten(value2), …]` in [Map.entries] order — this makes equality
/// **key-order-sensitive** for unknown nodes. That is acceptable here because
/// [rawJson] only ever comes from a JSON decode, whose key order is stable for
/// a given document, not from hand-built maps a caller might construct in
/// different orders.
Object? _flatten(Object? v) => switch (v) {
      final Map<Object?, Object?> m => <Object?>[
          #jsonObject,
          for (final MapEntry<Object?, Object?> e in m.entries) ...<Object?>[
            e.key,
            _flatten(e.value),
          ],
        ],
      final List<Object?> l => <Object?>[
          #jsonArray,
          for (final Object? x in l) _flatten(x),
        ],
      _ => v,
    };
