/// Resolving an inline-aggregate operand against a scope's fields (spec 033).
///
/// Given the fields in scope at an aggregate-sink band and a leaf operand name,
/// this pure resolver answers where that operand lives: a non-collection field
/// at this scope (`SameScope`), a uniquely-reachable non-collection leaf in the
/// descendant collection subtree (`DescendPath`, the chain of collection-field
/// names to descend), `NotFound`, or `Ambiguous` (≥2 distinct descend paths).
///
/// Same-scope wins: a non-collection field at this scope short-circuits, even
/// if the name also appears deeper. The descend search never crosses a
/// same-name match into ambiguity — that is the "the engine does not guess"
/// rule (FR-001). Pure Dart, no Flutter; data layer (operates on [FieldDef]).
library;

import 'field_def.dart';

/// Where an aggregate operand resolves relative to a band's scope.
sealed class AggregatePath {
  const AggregatePath();
}

/// The operand is a non-collection field at the band's own scope; the existing
/// same-scope mechanisms (spec 028 / 029) compute it unchanged.
class SameScope extends AggregatePath {
  const SameScope();
}

/// The operand is a unique non-collection leaf reached by descending [path]
/// (collection-field names, outermost-first) from the band's scope.
class DescendPath extends AggregatePath {
  const DescendPath(this.path);

  /// The collection-field names to descend, outermost-first.
  final List<String> path;
}

/// The operand is neither a field at this scope nor a descendant leaf (e.g. a
/// typo, or a published-total name resolved elsewhere).
class NotFound extends AggregatePath {
  const NotFound();
}

/// The operand names a leaf reachable by ≥2 distinct descend [paths]; the engine
/// refuses to guess which collection was meant (validation error / fill fallback).
class Ambiguous extends AggregatePath {
  const Ambiguous(this.paths);

  /// The distinct descend paths that each reach a leaf named `operand`.
  final List<List<String>> paths;
}

/// Resolves [operand] against [scopeFields]. See [AggregatePath].
AggregatePath resolveAggregatePath(List<FieldDef> scopeFields, String operand) {
  for (final FieldDef f in scopeFields) {
    if (f.name == operand && f.type != JetFieldType.collection) {
      return const SameScope();
    }
  }
  final List<List<String>> found = <List<String>>[];
  void descend(List<FieldDef> fields, List<String> trail) {
    for (final FieldDef f in fields) {
      if (f.type != JetFieldType.collection) continue;
      final List<String> next = <String>[...trail, f.name];
      for (final FieldDef child in f.fields) {
        if (child.name == operand && child.type != JetFieldType.collection) {
          found.add(next);
        }
      }
      descend(f.fields, next);
    }
  }

  descend(scopeFields, const <String>[]);
  if (found.isEmpty) return const NotFound();
  if (found.length == 1) return DescendPath(found.single);
  return Ambiguous(found);
}
