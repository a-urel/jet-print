/// Resolving which schema fields a band/element binds against (US3 / FR-016,
/// FR-017, FR-018). Pure logic over a scope **chain** through the report model
/// (domain) and a [JetDataSchema] (data) — no Flutter, no designer.
///
/// Reification (spec 024): a band's data scope is the chain of [DetailScope]s
/// enclosing it (each with an optional `collectionField`). The designer computes
/// that chain (and the band owning an element) via the tree-walk helpers; these
/// helpers do the schema-side resolution, so the data seam depends only on the
/// domain — never on the designer.
library;

import '../domain/detail_scope.dart';
import 'data_schema.dart';
import 'field_def.dart';

/// Field references `$F{name}` anywhere in an expression.
final RegExp _fieldRef = RegExp(r'\$F\{([^}]+)\}');

/// The fields **in scope** after descending [schema] through the
/// `collectionField` of each scope in [chain], outermost-first. The master/root
/// scope's null `collectionField` descends nothing, so an element in the root
/// scope sees the top-level fields; each nested scope descends one collection
/// level (arbitrary depth). An empty [chain] yields the root fields; an
/// unresolvable collection along the way yields no fields.
List<FieldDef> fieldsInScopeForChain(
  JetDataSchema schema,
  List<DetailScope> chain,
) {
  List<FieldDef> scope = schema.fields;
  for (final DetailScope s in chain) {
    final String? cf = s.collectionField;
    if (cf != null) {
      scope = _collectionChildren(scope, cf);
    }
  }
  return scope;
}

/// The child schema of the [name] collection field within [fields], or empty if
/// there is no such collection field (an unresolvable scope).
List<FieldDef> _collectionChildren(List<FieldDef> fields, String name) {
  for (final FieldDef f in fields) {
    if (f.name == name && f.type == JetFieldType.collection) return f.fields;
  }
  return const <FieldDef>[];
}

/// The `$F{...}` field names referenced in [expression].
Set<String> fieldRefsIn(String expression) =>
    _fieldRef.allMatches(expression).map((Match m) => m.group(1)!).toSet();

/// Whether every `$F{}` field reference in [expression] resolves to a field in
/// [scopeFields]. An expression with no field references (a `$P{}`/`$V{}` or a
/// literal) always resolves.
bool expressionResolves(List<FieldDef> scopeFields, String expression) {
  final Set<String> names = scopeFields.map((FieldDef f) => f.name).toSet();
  for (final String ref in fieldRefsIn(expression)) {
    if (!names.contains(ref)) return false;
  }
  return true;
}

/// Whether the single field [name] (e.g. an image binding) is in [scopeFields].
bool fieldResolves(List<FieldDef> scopeFields, String name) =>
    scopeFields.any((FieldDef f) => f.name == name);
