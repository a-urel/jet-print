/// Inline-aggregate expansion (spec 028, Phase A): a pure transform that turns
/// inline aggregate calls (`SUM($F{customerTotal})`) authored in a value field
/// into hidden, band-scoped [ReportVariable]s plus `$V{}` references, so the fill
/// pass computes them through the unchanged variable/accumulator pipeline.
///
/// Scope is inferred from the band: the **summary** band → report scope; a root
/// **group footer** → that group. Only these two render-complete master-scope
/// bands are expanded; nested-collection aggregation is Phase B. Aggregates in
/// any other band are left in place and flagged by validation, not expanded.
///
/// Nested-field guard (Phase A): an aggregate over a field that lives in a
/// nested collection (not the master row) is still expanded here, but the
/// synthesized variable's `$F{...}` resolves to nothing on a master row, so the
/// fill pass emits an unresolved-field diagnostic and the value falls back —
/// never a silently-wrong number.
library;

import '../../domain/band.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/group_level.dart';
import '../../domain/report_definition.dart';
import '../../domain/report_element.dart';
import '../../domain/report_variable.dart';
import '../expression.dart';
import '../expression_exception.dart';
import 'aggregate_functions.dart';

/// Returns [def] with every inline aggregate in a summary band or root group
/// footer expanded to a synthesized variable + `$V{}` reference. Returns [def]
/// unchanged (identical value) when there are none.
ReportDefinition expandAggregates(ReportDefinition def) {
  final List<ReportVariable> synth = <ReportVariable>[];
  final Map<String, String> nameByKey = <String, String>{};

  String? rewriteExpression(
      String? expr, VariableResetScope scope, String? resetGroup) {
    if (expr == null) return null;
    final AggregateCall? agg;
    try {
      agg = topLevelAggregate(Expression.parse(expr).root);
    } on ExpressionException {
      return null;
    }
    if (agg == null) return null;
    final String inner =
        expr.substring(expr.indexOf('(') + 1, expr.lastIndexOf(')'));
    final String key =
        '${scope.name}|${resetGroup ?? ''}|${agg.calculation.name}|$inner';
    final String name = nameByKey.putIfAbsent(key, () {
      final String n = '__agg${nameByKey.length}';
      synth.add(ReportVariable(
        name: n,
        expression: inner,
        calculation: agg!.calculation,
        resetScope: scope,
        resetGroup: resetGroup,
      ));
      return n;
    });
    return '\$V{$name}';
  }

  Band? rewriteBand(Band? band, VariableResetScope scope, String? resetGroup) {
    if (band == null) return null;
    bool changed = false;
    final List<ReportElement> els = <ReportElement>[];
    for (final ReportElement e in band.elements) {
      if (e is TextElement) {
        final String? next = rewriteExpression(e.expression, scope, resetGroup);
        if (next != null) {
          changed = true;
          els.add(TextElement(
            id: e.id,
            bounds: e.bounds,
            text: e.text,
            style: e.style,
            expression: next,
            format: e.format,
          ));
          continue;
        }
      }
      els.add(e);
    }
    return changed ? band.copyWith(elements: els) : band;
  }

  final Band? summary =
      rewriteBand(def.body.summary, VariableResetScope.report, null);

  final List<GroupLevel> groups = <GroupLevel>[
    for (final GroupLevel g in def.body.root.groups)
      _rewriteGroup(g, rewriteBand),
  ];

  if (synth.isEmpty) return def;

  return def.copyWith(
    variables: <ReportVariable>[...def.variables, ...synth],
    body: def.body.copyWith(
      summary: summary,
      root: def.body.root.copyWith(groups: groups),
    ),
  );
}

/// Rewrites a group's footer (group scope, `resetGroup == g.name`), preserving
/// the group's identity when nothing changed.
GroupLevel _rewriteGroup(
  GroupLevel g,
  Band? Function(Band?, VariableResetScope, String?) rewriteBand,
) {
  final Band? footer = rewriteBand(g.footer, VariableResetScope.group, g.name);
  return identical(footer, g.footer) ? g : g.copyWith(footer: footer);
}
