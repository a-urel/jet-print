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
///
/// Synthesized variables are named `__agg<n>`; a user-declared variable with
/// that name would be shadowed, so the `__agg` prefix is reserved.
library;

import '../../data/aggregate_path.dart';
import '../../data/field_def.dart';
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
    // Leave a malformed value untouched (parity: unparseable expressions are
    // never rewritten). A parseable expression guarantees balanced parens for
    // the scanner below.
    try {
      Expression.parse(expr);
    } on ExpressionException {
      return null;
    }
    bool found = false;
    final String rewritten =
        _expandInlineAggregates(expr, (JetCalculation calc, String inner) {
      found = true;
      final String key = '${scope.name}\x00${resetGroup ?? ''}\x00'
          '${calc.name}\x00$inner';
      return nameByKey.putIfAbsent(key, () {
        final String n = '__agg${nameByKey.length}';
        synth.add(ReportVariable(
          name: n,
          expression: inner,
          calculation: calc,
          resetScope: scope,
          resetGroup: resetGroup,
        ));
        return n;
      });
    });
    // null (not the unchanged string) preserves the band's structural identity
    // when nothing was lifted.
    return found ? rewritten : null;
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

  // This list is discarded when synth.isEmpty (the early `return def` fires
  // first), so building it here does not defeat the no-op identity guarantee.
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

/// Rewrites every inline aggregate call found anywhere in [expr] to a `$V{name}`
/// reference, obtaining each name from [register] (which also synthesizes the
/// backing variable). Quoted string literals are copied verbatim so an aggregate
/// name inside a string is never matched; non-aggregate identifiers and all
/// other syntax pass through unchanged. Because only the aggregate call itself is
/// replaced, an aggregate inside a larger expression (`SUM($F{t}) + 500`) or
/// nested in a scalar call (`ROUND(SUM($F{x}), 2)`) lifts the aggregate while
/// keeping the surrounding arithmetic/call intact (spec 032 amendment #2).
///
/// When [register] returns `null` for a call, that call is left in place
/// verbatim (allows callers to selectively skip aggregates they don't own).
String _expandInlineAggregates(
  String expr,
  String? Function(JetCalculation calc, String inner) register,
) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < expr.length) {
    final String c = expr[i];
    if (c == '"' || c == "'") {
      i = _copyStringLiteral(expr, i, out);
    } else if (_isIdentStart(c)) {
      final int identEnd = _identEnd(expr, i);
      final String ident = expr.substring(i, identEnd);
      final JetCalculation? calc = aggregateCalculationFor(ident);
      if (calc != null && identEnd < expr.length && expr[identEnd] == '(') {
        final int close = _matchParen(expr, identEnd);
        final String inner = expr.substring(identEnd + 1, close);
        // Confirm a single-argument aggregate (arity enforced by
        // topLevelAggregate) before lifting; otherwise pass it through.
        if (_isSingleArgAggregate(ident, inner)) {
          final String? name = register(calc, inner);
          if (name != null) {
            out.write('\$V{$name}');
            i = close + 1;
            continue;
          }
          // name == null → leave this aggregate call exactly as written.
          out.write(expr.substring(i, close + 1));
          i = close + 1;
          continue;
        }
      }
      out.write(ident);
      i = identEnd;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

bool _isSingleArgAggregate(String name, String inner) {
  try {
    return topLevelAggregate(Expression.parse('$name($inner)').root) != null;
  } on ExpressionException {
    return false;
  }
}

/// Copies the string literal starting at the quote [open] into [out] (honoring
/// `\`-escapes) and returns the index just past the closing quote.
int _copyStringLiteral(String s, int open, StringBuffer out) {
  final String q = s[open];
  out.write(q);
  int i = open + 1;
  while (i < s.length && s[i] != q) {
    if (s[i] == r'\' && i + 1 < s.length) {
      out.write(s[i]);
      i++;
    }
    out.write(s[i]);
    i++;
  }
  if (i < s.length) {
    out.write(s[i]); // closing quote
    i++;
  }
  return i;
}

/// Index of the `)` matching the `(` at [open], skipping nested parens and
/// quoted strings. The expression is validated as parseable upstream, so a match
/// is guaranteed.
int _matchParen(String s, int open) {
  int depth = 0;
  int i = open;
  while (i < s.length) {
    final String c = s[i];
    if (c == '"' || c == "'") {
      final String q = c;
      i++;
      while (i < s.length && s[i] != q) {
        if (s[i] == r'\') i++;
        i++;
      }
      if (i < s.length) i++;
    } else if (c == '(') {
      depth++;
      i++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
      i++;
    } else {
      i++;
    }
  }
  return s.length - 1; // unreachable for a parseable expression
}

int _identEnd(String s, int start) {
  int i = start;
  while (i < s.length && _isIdentPart(s[i])) {
    i++;
  }
  return i;
}

bool _isIdentStart(String c) {
  final int u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || c == '_';
}

bool _isIdentPart(String c) {
  final int u = c.codeUnitAt(0);
  return _isIdentStart(c) || (u >= 0x30 && u <= 0x39);
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

/// Lifts descendant aggregates out of a group's footer, preserving the group's
/// identity when nothing changed (mirrors [_rewriteGroup]'s identity pattern).
GroupLevel _liftGroup(
  GroupLevel g,
  Band? Function(Band?, VariableResetScope, String?) rewriteBand,
) {
  final Band? footer = rewriteBand(g.footer, VariableResetScope.group, g.name);
  return identical(footer, g.footer) ? g : g.copyWith(footer: footer);
}

/// One descendant inline aggregate lifted out of a summary band or root group
/// footer: its synth variable [name] (`__dagg<n>`) the element now references,
/// the [calculation], the parsed operand [argument] evaluated per descendant
/// leaf, the collection-field [path] to descend (empty when [ambiguous]), the
/// reset [resetScope]/[resetGroup], and whether the operand was [ambiguous]
/// (the filler then renders the unresolved fallback rather than folding).
class DescendantAggregate {
  /// Creates a descendant-aggregate spec.
  const DescendantAggregate({
    required this.name,
    required this.calculation,
    required this.argument,
    required this.path,
    required this.resetScope,
    required this.resetGroup,
    required this.ambiguous,
  });

  /// The synth variable name (`__dagg<n>`) the rewritten element references.
  final String name;

  /// The fold strategy (SUM / AVG / COUNT / MIN / MAX).
  final JetCalculation calculation;

  /// The operand expression evaluated per descendant leaf row before folding.
  final Expression argument;

  /// The collection-field names to descend from the band's scope, outermost
  /// first; empty when [ambiguous].
  final List<String> path;

  /// `report` for the summary band, `group` for a root group footer.
  final VariableResetScope resetScope;

  /// The owning root group's name for a group footer, else null.
  final String? resetGroup;

  /// True when the operand resolved to ≥2 descend paths; the filler renders the
  /// unresolved fallback for this aggregate (FR-010), never a guessed total.
  final bool ambiguous;
}

/// The result of lifting descendant aggregates: the [definition] with their
/// elements rewritten to `$V{__dagg<n>}`, and the [aggregates] the filler folds.
class DescendantLift {
  /// Creates a descendant-lift result.
  const DescendantLift(this.definition, this.aggregates);

  /// The definition with descendant-aggregate elements rewritten.
  final ReportDefinition definition;

  /// The descendant aggregates to compute in the filler.
  final List<DescendantAggregate> aggregates;
}

/// Lifts every descendant-operand inline aggregate in [def]'s summary band and
/// root group footers (resolved against the master-scope [rootFields]) to a
/// `$V{__dagg<n>}` reference, returning the rewritten definition and the fold
/// specs. Same-scope / not-found operands are left in place for
/// [expandAggregates] and published-total resolution; ambiguous operands are
/// lifted but flagged (the filler renders the fallback). Pure.
DescendantLift liftDescendantAggregates(
    ReportDefinition def, List<FieldDef> rootFields) {
  final List<DescendantAggregate> specs = <DescendantAggregate>[];

  String? Function(JetCalculation, String) registrar(
      VariableResetScope scope, String? group) {
    return (JetCalculation calc, String inner) {
      // Operand = the single $F{} reference, when there is exactly one.
      final Expression parsed;
      try {
        parsed = Expression.parse(inner);
      } on ExpressionException {
        return null;
      }
      final Set<String> refs = parsed.references.fields;
      if (refs.length != 1) return null;
      final AggregatePath resolved =
          resolveAggregatePath(rootFields, refs.single);
      if (resolved is DescendPath) {
        final String name = '__dagg${specs.length}';
        specs.add(DescendantAggregate(
          name: name,
          calculation: calc,
          argument: parsed,
          path: resolved.path,
          resetScope: scope,
          resetGroup: group,
          ambiguous: false,
        ));
        return name;
      }
      if (resolved is Ambiguous) {
        final String name = '__dagg${specs.length}';
        specs.add(DescendantAggregate(
          name: name,
          calculation: calc,
          argument: parsed,
          path: const <String>[],
          resetScope: scope,
          resetGroup: group,
          ambiguous: true,
        ));
        return name;
      }
      return null; // SameScope / NotFound → leave in place.
    };
  }

  Band? rewriteBand(
      Band? band, VariableResetScope scope, String? group) {
    if (band == null) return null;
    bool changed = false;
    final List<ReportElement> els = <ReportElement>[];
    for (final ReportElement e in band.elements) {
      if (e is TextElement && e.expression != null) {
        final String expr = e.expression!;
        try {
          Expression.parse(expr);
        } on ExpressionException {
          els.add(e);
          continue;
        }
        final String next =
            _expandInlineAggregates(expr, registrar(scope, group));
        if (next != expr) {
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
      _liftGroup(g, rewriteBand),
  ];

  if (specs.isEmpty) return DescendantLift(def, const <DescendantAggregate>[]);
  return DescendantLift(
    def.copyWith(
      body: def.body.copyWith(
        summary: summary,
        root: def.body.root.copyWith(groups: groups),
      ),
    ),
    specs,
  );
}
