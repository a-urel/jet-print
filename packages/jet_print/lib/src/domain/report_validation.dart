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

import '../data/aggregate_path.dart';
import '../data/binding_scope.dart';
import '../data/data_schema.dart';
import '../data/field_def.dart';
import '../expression/aggregate/aggregate_functions.dart';
import '../expression/ast.dart';
import '../expression/expression.dart';
import '../expression/expression_exception.dart';
import 'band.dart';
import 'column_layout.dart';
import 'detail_scope.dart';
import 'diagnostic.dart';
import 'elements/image_element.dart';
import 'elements/image_source.dart';
import 'elements/text_element.dart';
import 'group_level.dart';
import 'report_band.dart' show BandType;
import 'report_definition.dart';
import 'report_element.dart';
import 'scope_total.dart';

/// Validates [def]'s semantic invariants (I1–I8), returning a [Diagnostic] for
/// each violation in document order. Returns an empty list for a valid
/// definition. **Never throws.**
///
/// * I1 unique ids · I2 unique group names per scope · I3 parseable group keys ·
///   I4 record-blind furniture/title/summary/noData (no `$F{}`) ·
///   I5 band `type` consistent with its slot · I6 root/nested `collectionField`
///   rule — reported as **errors/warnings**.
/// * I7 representable-but-not-yet-rendered shapes (per-scope grouping; multiple
///   per-row bands) — reported as **info**.
/// * I8 inline aggregates (`SUM`/`AVG`/… top-level calls) appear only in the
///   summary band, a root group footer, or a nested-scope footer (spec 029, a
///   collection total); anywhere else is an error, because only those bands are
///   expanded by the aggregate synthesizer. A scope `footer` is slot-checked
///   (`groupFooter`) and is forbidden on the root (which has no collection).
///
/// When [schema] is provided, an additional operand check is applied to each
/// aggregate in a sink band: same-scope or unique-descend → no diagnostic;
/// `Ambiguous` → error; `NotFound` → error UNLESS the operand is a
/// published-total name (spec 030 `ScopeTotal`) — those are legitimately not
/// in the schema. When [schema] is null, behavior is unchanged (backward
/// compatible with all existing callers).
List<Diagnostic> validate(ReportDefinition def, {JetDataSchema? schema}) {
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

  // Collect ALL published-total names from the scope tree once (spec 030).
  // These names are legitimately not in the schema — they are injected at fill
  // time — so a NotFound result for them must not produce a diagnostic.
  final Set<String> publishedTotalNames = <String>{};
  if (schema != null) {
    void collectTotals(DetailScope s) {
      for (final ScopeNode node in s.children) {
        if (node is NestedScope) {
          for (final ScopeTotal t in node.scope.totals) {
            publishedTotalNames.add(t.name);
          }
          collectTotals(node.scope);
        }
      }
    }

    collectTotals(def.body.root);
  }

  // Schema-aware I8 operand check for a single sink band.
  // [scopeFields] are the schema fields visible at the band's scope.
  // Runs only when [schema != null].
  void checkOperands(Band? band, List<FieldDef> scopeFields) {
    if (band == null || schema == null) return;
    for (final ReportElement el in band.elements) {
      if (el is! TextElement || el.expression == null) continue;
      AggregateCall? agg;
      try {
        agg = topLevelAggregate(Expression.parse(el.expression!).root);
      } on ExpressionException {
        continue;
      }
      if (agg == null) continue;
      // Extract the single $F{name} field ref from the aggregate's argument.
      final Expr arg = agg.argument;
      if (arg is! FieldRefExpr) continue;
      final String operand = arg.name;
      final AggregatePath path =
          resolveAggregatePath(scopeFields, operand);
      switch (path) {
        case SameScope():
        case DescendPath():
          break; // valid
        case Ambiguous():
          out.add(Diagnostic(
            DiagnosticSeverity.error,
            'element "${el.id}" aggregate operand "\$$operand" is ambiguous — '
            'the same field name appears in multiple descendant collections; '
            'use a published total to make the intent explicit',
            elementId: el.id,
          ));
        case NotFound():
          // Published-total names are injected at fill time — not in the schema.
          if (publishedTotalNames.contains(operand)) break;
          out.add(Diagnostic(
            DiagnosticSeverity.error,
            'element "${el.id}" aggregate operand "\$$operand" was not found '
            'in the schema',
            elementId: el.id,
          ));
      }
    }
  }

  // Inline aggregates are only computed in the summary band and root group
  // footers (the synthesizer expands only those). Flag an aggregate authored in
  // any other band — it would never be computed and silently error at fill.
  void aggregateBand(Band? band, {required bool supported}) {
    if (band == null || supported) return;
    for (final ReportElement el in band.elements) {
      if (el is! TextElement || el.expression == null) continue;
      AggregateCall? agg;
      try {
        agg = topLevelAggregate(Expression.parse(el.expression!).root);
      } on ExpressionException {
        continue;
      }
      if (agg == null) continue;
      out.add(Diagnostic(
        DiagnosticSeverity.error,
        'element "${el.id}" uses an aggregate '
        '(${aggregateNameFor(agg.calculation)!}) in band "${band.id}", which is '
        'not a summary or group footer; aggregates are only computed there',
        elementId: el.id,
      ));
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

  // [chain] is the list of DetailScopes from root down to (but NOT including)
  // the current scope, used to descend schema fields for nested-scope footers.
  void walkScope(DetailScope scope,
      {required bool isRoot, required List<DetailScope> chain}) {
    claim(scope.id);

    // I6 — collectionField rule.
    if (isRoot && scope.collectionField != null) {
      out.add(Diagnostic(DiagnosticSeverity.error,
          'root scope "${scope.id}" must not carry a collectionField'));
    } else if (!isRoot && scope.collectionField == null) {
      out.add(Diagnostic(DiagnosticSeverity.error,
          'nested scope "${scope.id}" is missing its collectionField'));
    }

    // Spec 029 — a nested scope may carry a footer (a collection total). The root
    // scope must not (it has no collection). The footer is slot-checked and is an
    // aggregate sink; no record-blind check — it renders against the parent collection row.
    if (isRoot) {
      if (scope.footer != null) {
        out.add(Diagnostic(DiagnosticSeverity.error,
            'root scope "${scope.id}" must not carry a footer'));
      }
    } else {
      slotBand(scope.footer, BandType.groupFooter);
      aggregateBand(scope.footer, supported: true);
      // Schema-aware operand check for the nested-scope footer.
      // The footer band aggregates fold over the scope's OWN rows, so resolve
      // against the fields descended to this scope (chain includes this scope).
      if (schema != null) {
        final List<FieldDef> scopeFields =
            fieldsInScopeForChain(schema, <DetailScope>[...chain, scope]);
        checkOperands(scope.footer, scopeFields);
      }
    }

    // Spec 030 — a nested scope may publish named roll-up totals onto its parent
    // row. The root has no parent row, so it must not. Each expression must be a
    // top-level aggregate (a published total is by definition a roll-up); names
    // are unique within the scope. (A name shadowing a real data field is a
    // FILL-time diagnostic — the schema is unknown here.)
    if (isRoot && scope.totals.isNotEmpty) {
      out.add(Diagnostic(DiagnosticSeverity.error,
          'root scope "${scope.id}" must not publish totals'));
    }
    if (!isRoot) {
      final Set<String> seenTotals = <String>{};
      for (final ScopeTotal t in scope.totals) {
        if (!seenTotals.add(t.name)) {
          out.add(Diagnostic(
              DiagnosticSeverity.error,
              'duplicate published-total name "${t.name}" in scope '
              '"${scope.id}"'));
        }
        AggregateCall? agg;
        try {
          agg = topLevelAggregate(Expression.parse(t.expression).root);
        } on ExpressionException catch (e) {
          out.add(Diagnostic(DiagnosticSeverity.error,
              'published total "${t.name}" failed to parse: ${e.message}'));
          continue;
        }
        if (agg == null) {
          out.add(Diagnostic(
              DiagnosticSeverity.error,
              'published total "${t.name}" is not a top-level aggregate '
              '(SUM/AVG/COUNT/MIN/MAX)'));
        }
      }
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
      // Only a ROOT group footer is an aggregate sink; headers never are, and
      // nested-scope group footers are not expanded.
      aggregateBand(g.header, supported: false);
      aggregateBand(g.footer, supported: isRoot);
      // Schema-aware operand check for root group footers (master scope fields).
      if (isRoot && schema != null) {
        checkOperands(g.footer, schema.fields);
      }
    }

    // Children: I5 per-row band type, I7 multiple per-row bands, recurse scopes.
    int bandNodes = 0;
    for (final ScopeNode node in scope.children) {
      switch (node) {
        case BandNode(band: final Band b):
          bandNodes++;
          slotBand(b, BandType.detail);
          aggregateBand(b, supported: false);
        case NestedScope(scope: final DetailScope s):
          walkScope(s, isRoot: false, chain: <DetailScope>[...chain, scope]);
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

  // Furniture is never an aggregate sink.
  aggregateBand(def.furniture.pageHeader, supported: false);
  aggregateBand(def.furniture.pageFooter, supported: false);
  aggregateBand(def.furniture.columnHeader, supported: false);
  aggregateBand(def.furniture.columnFooter, supported: false);
  aggregateBand(def.furniture.background, supported: false);

  // Body once-bands (record-blind) + the scope tree.
  slotBand(def.body.title, BandType.title, isRecordBlind: true);
  slotBand(def.body.summary, BandType.summary, isRecordBlind: true);
  slotBand(def.body.noData, BandType.noData, isRecordBlind: true);
  // Only the summary band is an aggregate sink among the once-bands.
  aggregateBand(def.body.title, supported: false);
  aggregateBand(def.body.summary, supported: true);
  aggregateBand(def.body.noData, supported: false);
  // Schema-aware operand check for the summary band (master scope fields).
  if (schema != null) {
    checkOperands(def.body.summary, schema.fields);
  }
  walkScope(def.body.root, isRoot: true, chain: const <DetailScope>[]);

  _validateColumns(def, out);

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
      final Expression expr = Expression.parse(el.expression!);
      // A top-level inline aggregate (e.g. `SUM($F{total})`) folds its operand
      // over the data rows — its inner field refs are aggregate operands, not a
      // record-blind binding, so they don't count here. (Bands that aren't an
      // aggregate sink reject the aggregate itself via the I8 check.)
      if (topLevelAggregate(expr.root) != null) return const <String>{};
      return expr.references.fields;
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

/// Every [Band] in [def], in document order (furniture, body once-bands, then
/// the scope tree). Used to find stray `columnLayout`s (spec 034).
List<Band> _allBands(ReportDefinition def) {
  final List<Band> bands = <Band>[];
  void add(Band? b) {
    if (b != null) bands.add(b);
  }

  add(def.furniture.pageHeader);
  add(def.furniture.pageFooter);
  add(def.furniture.columnHeader);
  add(def.furniture.columnFooter);
  add(def.furniture.background);
  add(def.body.title);
  add(def.body.summary);
  add(def.body.noData);
  void walk(DetailScope s) {
    for (final GroupLevel g in s.groups) {
      add(g.header);
      add(g.footer);
    }
    add(s.footer);
    for (final ScopeNode node in s.children) {
      switch (node) {
        case BandNode(band: final Band b):
          add(b);
        case NestedScope(scope: final DetailScope child):
          walk(child);
      }
    }
  }

  walk(def.body.root);
  return bands;
}

/// Validates the spec-034 label grid: the active band's geometry (FR-007/008)
/// and a fallback warning for any `columnLayout` carried by a band that is not
/// the active label band (FR-009).
void _validateColumns(ReportDefinition def, List<Diagnostic> out) {
  final Band? active =
      def.soleDetailBand?.columnLayout != null ? def.soleDetailBand : null;

  for (final Band b in _allBands(def)) {
    if (b.columnLayout != null && !identical(b, active)) {
      out.add(Diagnostic(
        DiagnosticSeverity.warning,
        'column layout on band "${b.id}" is ignored — it applies only to the '
        'lone detail band of a pure single-detail body',
        elementId: b.id,
      ));
    }
  }

  if (active == null) return;
  final ColumnLayout cl = active.columnLayout!;
  if (cl.columnCount < 1) {
    out.add(Diagnostic(DiagnosticSeverity.error,
        'columnLayout columnCount must be >= 1 (was ${cl.columnCount})',
        elementId: active.id));
  }
  if (cl.columnWidth <= 0 || cl.columnSpacing < 0 || cl.rowSpacing < 0) {
    out.add(Diagnostic(
        DiagnosticSeverity.error,
        'columnLayout dimensions must be non-negative (columnWidth > 0)',
        elementId: active.id));
  }

  final double bodyWidth =
      def.page.width - def.page.margins.left - def.page.margins.right;
  if (cl.columnCount >= 1 && cl.columnWidth > 0) {
    final double gridWidth =
        cl.columnCount * cl.columnWidth + (cl.columnCount - 1) * cl.columnSpacing;
    if (gridWidth > bodyWidth) {
      out.add(Diagnostic(
          DiagnosticSeverity.error,
          'columnLayout grid ($gridWidth pt) is wider than the page body '
          '($bodyWidth pt)',
          elementId: active.id));
    }
  }

  final double headerH = def.furniture.pageHeader?.height ?? 0;
  final double footerH = def.furniture.pageFooter?.height ?? 0;
  final double bodyCapacity = def.page.height -
      def.page.margins.top -
      def.page.margins.bottom -
      headerH -
      footerH;
  if (active.height > bodyCapacity) {
    out.add(Diagnostic(
        DiagnosticSeverity.error,
        'label height (${active.height} pt) is taller than the page body '
        '($bodyCapacity pt); no rows fit',
        elementId: active.id));
  }

  for (final ReportElement el in active.elements) {
    if (el.bounds.x + el.bounds.width > cl.columnWidth) {
      out.add(Diagnostic(
          DiagnosticSeverity.warning,
          'element "${el.id}" overflows cell width (${cl.columnWidth} pt); '
          'it will be clipped',
          elementId: el.id));
    }
  }
}
