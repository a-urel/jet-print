/// Author-time validation of a [ReportDefinition]'s semantic invariants
/// (spec 024; research §2).
///
/// Structural invariants are unrepresentable by construction (the typed tree);
/// the **semantic** ones are returned here as non-throwing [Diagnostic]s so the
/// designer can surface them at author time and hold transient invalid states
/// (e.g. a duplicate name mid-rename) without exceptions. Pure domain layer:
/// imports only the domain tree, the expression engine, and the (domain)
/// [Diagnostic] type — never rendering/designer/Flutter UI.
library;

import '../expression/expression.dart';
import '../expression/expression_exception.dart';
import 'band.dart';
import 'detail_scope.dart';
import 'diagnostic.dart';
import 'elements/image_element.dart';
import 'elements/image_source.dart';
import 'elements/text_element.dart';
import 'group_level.dart';
import 'report_band.dart' show BandType;
import 'report_definition.dart';
import 'report_element.dart';

/// Validates [def]'s semantic invariants (I1–I7), returning a [Diagnostic] for
/// each violation in document order. Returns an empty list for a valid
/// definition. **Never throws.**
///
/// * I1 unique ids · I2 unique group names per scope · I3 parseable group keys ·
///   I4 record-blind furniture/title/summary/noData (no `$F{}`) ·
///   I5 band `type` consistent with its slot · I6 root/nested `collectionField`
///   rule — reported as **errors/warnings**.
/// * I7 representable-but-not-yet-rendered shapes (per-scope grouping; multiple
///   per-row bands) — reported as **info**.
List<Diagnostic> validate(ReportDefinition def) {
  final List<Diagnostic> out = <Diagnostic>[];
  final Map<String, int> idCounts = <String, int>{};

  void claim(String id) => idCounts[id] = (idCounts[id] ?? 0) + 1;

  void recordBlind(Band band) {
    for (final ReportElement el in band.elements) {
      final Set<String> fields = _recordFieldRefs(el);
      if (fields.isNotEmpty) {
        out.add(Diagnostic(
          DiagnosticSeverity.warning,
          'record-blind band "${band.id}" element "${el.id}" references '
          'field(s) ${(fields.toList()..sort()).join(', ')}, which have no '
          'data row',
          elementId: el.id,
        ));
      }
    }
  }

  void slotBand(Band? band, BandType expected, {bool isRecordBlind = false}) {
    if (band == null) return;
    claim(band.id);
    if (band.type != expected) {
      out.add(Diagnostic(
        DiagnosticSeverity.error,
        'band "${band.id}" in the ${expected.name} slot has type '
        '${band.type.name} (expected ${expected.name})',
        elementId: band.id,
      ));
    }
    if (isRecordBlind) recordBlind(band);
  }

  void walkScope(DetailScope scope, {required bool isRoot}) {
    claim(scope.id);

    // I6 — collectionField rule.
    if (isRoot && scope.collectionField != null) {
      out.add(Diagnostic(DiagnosticSeverity.error,
          'root scope "${scope.id}" must not carry a collectionField'));
    } else if (!isRoot && scope.collectionField == null) {
      out.add(Diagnostic(DiagnosticSeverity.error,
          'nested scope "${scope.id}" is missing its collectionField'));
    }

    // I7 — per-scope grouping is representable but not yet rendered.
    if (!isRoot && scope.groups.isNotEmpty) {
      out.add(Diagnostic(DiagnosticSeverity.info,
          'per-scope grouping on scope "${scope.id}" is not yet rendered'));
    }

    // I2 — group names unique within this scope; I3 — keys parse.
    final Set<String> seenNames = <String>{};
    for (final GroupLevel g in scope.groups) {
      claim(g.id);
      if (!seenNames.add(g.name)) {
        out.add(Diagnostic(DiagnosticSeverity.error,
            'duplicate group name "${g.name}" in scope "${scope.id}"'));
      }
      try {
        Expression.parse(g.key);
      } on ExpressionException catch (e) {
        out.add(Diagnostic(DiagnosticSeverity.error,
            'group "${g.id}" key failed to parse: ${e.message}'));
      }
      slotBand(g.header, BandType.groupHeader);
      slotBand(g.footer, BandType.groupFooter);
    }

    // Children: I5 per-row band type, I7 multiple per-row bands, recurse scopes.
    int bandNodes = 0;
    for (final ScopeNode node in scope.children) {
      switch (node) {
        case BandNode(band: final Band b):
          bandNodes++;
          slotBand(b, BandType.detail);
        case NestedScope(scope: final DetailScope s):
          walkScope(s, isRoot: false);
      }
    }
    if (bandNodes > 1) {
      out.add(Diagnostic(
          DiagnosticSeverity.info,
          'scope "${scope.id}" has $bandNodes per-row bands; multiple per-row '
          'bands are not yet rendered'));
    }
  }

  // Furniture (all record-blind).
  slotBand(def.furniture.pageHeader, BandType.pageHeader, isRecordBlind: true);
  slotBand(def.furniture.pageFooter, BandType.pageFooter, isRecordBlind: true);
  slotBand(def.furniture.columnHeader, BandType.columnHeader,
      isRecordBlind: true);
  slotBand(def.furniture.columnFooter, BandType.columnFooter,
      isRecordBlind: true);
  slotBand(def.furniture.background, BandType.background, isRecordBlind: true);

  // Body once-bands (record-blind) + the scope tree.
  slotBand(def.body.title, BandType.title, isRecordBlind: true);
  slotBand(def.body.summary, BandType.summary, isRecordBlind: true);
  slotBand(def.body.noData, BandType.noData, isRecordBlind: true);
  walkScope(def.body.root, isRoot: true);

  // I1 — duplicate ids (reported once per offending id, in first-seen order).
  for (final MapEntry<String, int> e in idCounts.entries) {
    if (e.value > 1) {
      out.add(Diagnostic(DiagnosticSeverity.error,
          'duplicate id "${e.key}" (${e.value} uses)'));
    }
  }

  return out;
}

/// The data fields an element binds to (record-dependent). A malformed
/// expression yields no field reference here (its parse failure surfaces via a
/// group key or render diagnostic, not as a phantom binding).
Set<String> _recordFieldRefs(ReportElement el) {
  if (el is TextElement && el.expression != null) {
    try {
      return Expression.parse(el.expression!).references.fields;
    } on ExpressionException {
      return const <String>{};
    }
  }
  if (el is ImageElement) {
    final JetImageSource source = el.source;
    if (source is FieldImageSource) return <String>{source.field};
  }
  return const <String>{};
}
