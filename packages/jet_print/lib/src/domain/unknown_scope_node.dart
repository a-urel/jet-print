// Preserves a scope node whose `kind` is not known to this build.
//
// A part of `detail_scope.dart`: [ScopeNode] is sealed, so every direct
// subtype — [BandNode], [NestedScope], [CrosstabNode], and this one — must live
// in the same library. Kept as its own file (rather than inlined in
// `detail_scope.dart`) purely for organization; it shares that file's imports
// and has no exports of its own beyond [UnknownScopeNode] itself, re-exported
// from the barrel alongside the other [ScopeNode] variants.
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
  final Map<String, Object?> rawJson;

  /// The unrecognized `kind` string, or null when the JSON had none.
  String? get kind =>
      rawJson['kind'] is String ? rawJson['kind']! as String : null;

  @override
  List<Object?> get props => <Object?>[
        <Object?>[
          for (final MapEntry<String, Object?> e
              in rawJson.entries) ...<Object?>[e.key, e.value],
        ],
      ];

  @override
  String toString() => 'UnknownScopeNode(${kind ?? '?'})';
}
