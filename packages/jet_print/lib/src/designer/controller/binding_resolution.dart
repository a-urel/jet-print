/// Author-time field resolution accounting for spec-030 published totals and the
/// spec-029 nested-footer parent/child duality. Composes the band-walk (designer)
/// with the pure schema/total seam (data): the names/fields the Properties panel
/// may show or accept for a band, without false-flagging a published total.
///
/// Designer-layer (depends on [band_walker.dart]); the data seam itself never
/// depends on the designer.
library;

import '../../data/binding_scope.dart';
import '../../data/data_schema.dart';
import '../../data/field_def.dart';
import '../../domain/detail_scope.dart';
import '../../domain/report_definition.dart';
import 'band_walker.dart';

/// The names resolvable in band [bandId]: the schema fields in its data scope
/// plus the published totals injected onto its render row. A nested-scope footer
/// (renders at its PARENT row but aggregates over its OWN collection) sees the
/// union of what a band at its own scope sees and what a band at its parent scope
/// sees; every other band sees only its own scope.
Set<String> resolvableNamesForBand(
    ReportDefinition def, JetDataSchema schema, String bandId) {
  final _Roles roles = _rolesForBand(def, bandId);
  final Set<String> out = <String>{..._namesAtChain(def, schema, roles.own)};
  if (roles.parent != null) {
    out.addAll(_namesAtChain(def, schema, roles.parent!));
  }
  return out;
}

/// The value-field picker choices for [bandId]: in-scope NON-collection schema
/// fields, plus a synthetic `FieldDef(name, JetFieldType.double)` per published
/// total on the render row (deduped against schema names). For a nested-scope
/// footer this spans both its own scope and its parent scope (see
/// [resolvableNamesForBand]).
List<FieldDef> resolvableFieldChoices(
    ReportDefinition def, JetDataSchema schema, String bandId) {
  final _Roles roles = _rolesForBand(def, bandId);
  final List<FieldDef> out = <FieldDef>[];
  final Set<String> seen = <String>{};
  void addChain(List<DetailScope> chain) {
    for (final FieldDef f in fieldsInScopeForChain(schema, chain)) {
      if (f.type == JetFieldType.collection) continue;
      if (seen.add(f.name)) out.add(f);
    }
    for (final String name in publishedTotalsForScope(_scopeOf(def, chain))) {
      if (seen.add(name)) {
        out.add(FieldDef(name, type: JetFieldType.double));
      }
    }
  }

  addChain(roles.own);
  if (roles.parent != null) addChain(roles.parent!);
  return out;
}

/// The names — schema fields + published totals — visible at a single scope
/// [chain] (the chain's last scope, or the root for an empty chain).
Set<String> _namesAtChain(
        ReportDefinition def, JetDataSchema schema, List<DetailScope> chain) =>
    <String>{
      for (final FieldDef f in fieldsInScopeForChain(schema, chain)) f.name,
      ...publishedTotalsForScope(_scopeOf(def, chain)),
    };

/// The scope a [chain] resolves against: its last entry, or the root scope when
/// the chain is empty (furniture / body once-bands resolve against the root).
DetailScope _scopeOf(ReportDefinition def, List<DetailScope> chain) =>
    chain.isEmpty ? def.body.root : chain.last;

/// The scope chain(s) a band resolves against: always its [own] chain, plus a
/// [parent] chain when the band is its scope's footer (spec-029 duality).
class _Roles {
  const _Roles(this.own, this.parent);
  final List<DetailScope> own;
  final List<DetailScope>? parent;
}

_Roles _rolesForBand(ReportDefinition def, String bandId) {
  final List<DetailScope> chain = scopePathToBand(def, bandId);
  final DetailScope? owner = findScopeOfBand(def, bandId);
  final bool isNestedFooter = owner != null && owner.footer?.id == bandId;
  if (isNestedFooter && chain.isNotEmpty) {
    return _Roles(chain, chain.sublist(0, chain.length - 1));
  }
  return _Roles(chain, null);
}
