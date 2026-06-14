/// A data-iteration scope and its ordered, heterogeneous contents.
///
/// Part of the reified report model (spec 024). A [DetailScope] is either the
/// master/root scope (`collectionField == null`) or a nested scope iterating a
/// child collection. Its [children] are an **ordered** list of [ScopeNode]s, so
/// the authored interleaving of per-row bands and sub-scopes (e.g. "meta band →
/// lines scope → total band") is preserved through migration and editing.
library;

import 'package:flutter/foundation.dart' show listEquals;

import 'band.dart';
import 'group_level.dart';

/// One entry in a [DetailScope]'s ordered contents: either a per-row [Band]
/// (wrapped in [BandNode]) or a nested [DetailScope] (wrapped in [NestedScope]).
/// Sealed, so traversal pattern-matches exhaustively with no default arm.
sealed class ScopeNode {
  /// Const base constructor.
  const ScopeNode();
}

/// A per-row band rendered within the owning scope.
final class BandNode extends ScopeNode {
  /// Wraps [band] as a scope child.
  const BandNode(this.band);

  /// The band rendered once per row of the owning scope.
  final Band band;

  @override
  bool operator ==(Object other) => other is BandNode && other.band == band;

  @override
  int get hashCode => band.hashCode;

  @override
  String toString() => 'BandNode(${band.id})';
}

/// A nested collection scope rendered within the owning scope.
final class NestedScope extends ScopeNode {
  /// Wraps [scope] as a scope child.
  const NestedScope(this.scope);

  /// The nested scope iterating a child collection.
  final DetailScope scope;

  @override
  bool operator ==(Object other) =>
      other is NestedScope && other.scope == scope;

  @override
  int get hashCode => scope.hashCode;

  @override
  String toString() => 'NestedScope(${scope.id})';
}

/// An immutable data-iteration scope: the master/root (`collectionField` null)
/// or a nested collection. Owns its [groups] (master-level on `root`) and an
/// ordered list of [children].
class DetailScope {
  /// Creates a scope identified by [id]. A non-null [collectionField] makes it a
  /// nested scope iterating that child collection.
  const DetailScope({
    required this.id,
    this.collectionField,
    this.groups = const <GroupLevel>[],
    this.children = const <ScopeNode>[],
  });

  /// Stable identity.
  final String id;

  /// The nested-collection field this scope iterates, or null for the root.
  final String? collectionField;

  /// Group levels owned by this scope, outermost-first. (Rendered only on `root`
  /// in this feature; per-scope grouping is representable but deferred.)
  final List<GroupLevel> groups;

  /// Ordered, heterogeneous contents — per-row bands and nested scopes,
  /// preserving authored interleaving.
  final List<ScopeNode> children;

  /// Returns a copy with the given fields replaced.
  DetailScope copyWith({
    String? id,
    String? collectionField,
    List<GroupLevel>? groups,
    List<ScopeNode>? children,
  }) =>
      DetailScope(
        id: id ?? this.id,
        collectionField: collectionField ?? this.collectionField,
        groups: groups ?? this.groups,
        children: children ?? this.children,
      );

  @override
  bool operator ==(Object other) =>
      other is DetailScope &&
      other.id == id &&
      other.collectionField == collectionField &&
      listEquals(other.groups, groups) &&
      listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(
      id, collectionField, Object.hashAll(groups), Object.hashAll(children));

  @override
  String toString() => 'DetailScope($id'
      '${collectionField == null ? '' : ', collection: $collectionField'}, '
      '${groups.length} group(s), ${children.length} child(ren))';
}
