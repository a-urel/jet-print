/// Scope-level field resolution for the Outline "+" menu submenus: the scalar
/// fields a new group may key on ([scalarFieldsForScope]) and the collection
/// fields a new child list may iterate ([collectionFieldsForScope]). Both read
/// the fields resolvable at a scope's level and filter by kind, so the Outline
/// menu offers only schema-correct, bindable choices. Empty when no schema is
/// attached or the scope does not resolve.
library;

import '../../../data/binding_scope.dart';
import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../../domain/detail_scope.dart';
import '../../../domain/report_definition.dart';
import '../../controller/band_walker.dart';

/// All fields resolvable at [scopeId]'s level — the shared core of the two
/// filters below. Empty when no schema is attached or the scope does not
/// resolve.
List<FieldDef> _inScopeFields(
  JetDataSchema? schema,
  ReportDefinition def,
  String scopeId,
) {
  if (schema == null) return const <FieldDef>[];
  final List<DetailScope> chain = scopePathToScope(def, scopeId);
  if (chain.isEmpty) return const <FieldDef>[];
  return fieldsInScopeForChain(schema, chain);
}

/// The scalar (non-collection) fields a new group on [scopeId] may key on.
List<FieldDef> scalarFieldsForScope(
  JetDataSchema? schema,
  ReportDefinition def,
  String scopeId,
) =>
    <FieldDef>[
      for (final FieldDef f in _inScopeFields(schema, def, scopeId))
        if (f.type != JetFieldType.collection) f,
    ];

/// The collection fields visible at [scopeId]'s level — the ones a direct child
/// list of [scopeId] may iterate — excluding any already iterated by an existing
/// child list, so the same collection is never offered (and thus bound) twice
/// and no redundant `List: <field>` node can form.
List<FieldDef> collectionFieldsForScope(
  JetDataSchema? schema,
  ReportDefinition def,
  String scopeId,
) {
  final DetailScope? scope = findScope(def, scopeId);
  final Set<String> alreadyBound = <String>{
    if (scope != null)
      for (final ScopeNode n in scope.children)
        if (n is NestedScope && n.scope.collectionField != null)
          n.scope.collectionField!,
  };
  return <FieldDef>[
    for (final FieldDef f in _inScopeFields(schema, def, scopeId))
      if (f.type == JetFieldType.collection && !alreadyBound.contains(f.name)) f,
  ];
}
