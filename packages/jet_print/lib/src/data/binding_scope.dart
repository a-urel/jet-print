/// Resolving which schema fields a band/element binds against (US3 / FR-016,
/// FR-017, FR-018). Pure logic over a [ReportTemplate] (domain) and a
/// [JetDataSchema] (data) — no Flutter. Lives in the data seam because it spans
/// the report model and the data schema; the data seam may depend on domain.
library;

import '../domain/report_band.dart';
import '../domain/report_template.dart';
import 'data_schema.dart';
import 'field_def.dart';

/// Field references `$F{name}` anywhere in an expression.
final RegExp _fieldRef = RegExp(r'\$F\{([^}]+)\}');

/// The fields **in scope** for the band addressed by [bandPath] (child indices
/// from the top-level band list; `[]` = the master/root scope). Each time the
/// path enters a band with a `collectionField`, the scope descends into that
/// collection's child schema — so an element inside a `lines`-bound band sees
/// the line fields, and a deeper `subLines`-bound band sees the sub-line fields
/// (arbitrary depth). An unresolved collection along the way yields no fields.
List<FieldDef> fieldsInScopeAt(
  JetDataSchema schema,
  ReportTemplate template,
  List<int> bandPath,
) {
  List<FieldDef> scope = schema.fields;
  List<ReportBand> bands = template.bands;
  for (final int idx in bandPath) {
    if (idx < 0 || idx >= bands.length) return const <FieldDef>[];
    final ReportBand band = bands[idx];
    final String? cf = band.collectionField;
    if (cf != null) {
      scope = _collectionChildren(scope, cf);
    }
    bands = band.children;
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

/// The path (child indices from the top-level band list) to the band owning the
/// element with [elementId], or null if no band contains it. Walks nested bands.
List<int>? bandPathOfElement(ReportTemplate template, String elementId) =>
    _searchBands(template.bands, elementId, const <int>[]);

List<int>? _searchBands(
  List<ReportBand> bands,
  String elementId,
  List<int> prefix,
) {
  for (int i = 0; i < bands.length; i++) {
    final List<int> here = <int>[...prefix, i];
    if (bands[i].elements.any((dynamic e) => e.id == elementId)) return here;
    final List<int>? nested = _searchBands(bands[i].children, elementId, here);
    if (nested != null) return nested;
  }
  return null;
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
