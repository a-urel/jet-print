/// Resolves the scalar (non-collection) fields a new group on a scope may key
/// on: the fields in scope at [scopeId] per the data [schema], with collection
/// fields excluded. Shared by the Outline "Add group" submenu and the Data
/// Source scalar "＋ group" affordance so both offer identical, schema-correct
/// choices. Empty when no schema is attached or the scope does not resolve.
library;

import '../../../data/binding_scope.dart';
import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../../domain/detail_scope.dart';
import '../../../domain/report_definition.dart';
import '../../controller/band_walker.dart';

List<FieldDef> scalarFieldsForScope(
  JetDataSchema? schema,
  ReportDefinition def,
  String scopeId,
) {
  if (schema == null) return const <FieldDef>[];
  final List<DetailScope> chain = scopePathToScope(def, scopeId);
  if (chain.isEmpty) return const <FieldDef>[];
  return <FieldDef>[
    for (final FieldDef f in fieldsInScopeForChain(schema, chain))
      if (f.type != JetFieldType.collection) f,
  ];
}
