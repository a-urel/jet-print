/// The Fill data pass (spec 007b/007c). Walks a [ReportTemplate] over a
/// [JetDataSource], drives the variable calculator, and emits the resolved band
/// stream — title/groupHeader/detail/groupFooter/summary/noData — as a
/// [FilledReport] + diagnostics. INTERNAL — the public surface is the 011
/// JetReportEngine.
library;

import '../../data/aggregate_path.dart';
import '../../data/data_row.dart';
import '../../data/data_set.dart';
import '../../data/field_def.dart';
import '../../data/jet_data_source.dart';
import '../../domain/band.dart';
import '../../domain/bool_property.dart';
import '../../domain/detail_scope.dart';
import '../../domain/group_level.dart';
import '../../domain/report_definition.dart';
import '../../domain/report_element.dart';
import '../../domain/report_group.dart';
import '../../domain/report_variable.dart';
import '../../domain/scope_total.dart';
import '../../expression/aggregate/aggregate_synthesizer.dart';
import '../../expression/aggregate/descendant_aggregate.dart';
import '../../expression/aggregate/nested_footer.dart';
import '../../expression/aggregate/scope_totals.dart';
import '../../expression/aggregate/variable_accumulator.dart';
import '../../expression/aggregate/variable_calculator.dart';
import '../../expression/eval_context.dart';
import '../../expression/expression.dart';
import '../../expression/function_registry.dart';
import '../../expression/functions/built_in_functions.dart';
import '../../expression/value.dart';
import 'diagnostic_budget.dart';
import 'element_resolver.dart';
import 'fill_eval_context.dart';
import 'filled_report.dart';
import 'report_diagnostics.dart';
import 'visibility.dart';

/// The result of a fill: the resolved [report] and the collected [diagnostics].
class FillResult {
  /// Creates a fill result.
  const FillResult({required this.report, required this.diagnostics});

  /// The resolved band stream.
  final FilledReport report;

  /// The non-fatal issues collected during the pass.
  final ReportDiagnostics diagnostics;
}

/// Runs the flat Fill data pass.
class ReportFiller {
  /// Creates a filler; [functions] defaults to the built-in function registry.
  ReportFiller({JetFunctionRegistry? functions})
      : _functions = functions ?? _defaultFunctions();

  final JetFunctionRegistry _functions;

  static JetFunctionRegistry _defaultFunctions() {
    final JetFunctionRegistry r = JetFunctionRegistry();
    registerBuiltInFunctions(r);
    return r;
  }

  /// Fills [rawDefinition] over [source] natively (spec 024) — the reified
  /// counterpart of [fill]. Produces a [FilledReport] **byte-identical** to
  /// filling the equivalent legacy template: groups are keyed internally by
  /// their display [GroupLevel.name] (so a variable's `resetGroup` *id* is
  /// translated to that name to drive the unchanged name-keyed calculator), and
  /// the band stream is emitted in the same title → groups → detail → footers →
  /// summary order, walking `body.root.children` in authored order.
  FillResult fillDefinition(
    ReportDefinition rawDefinition,
    JetDataSource source, {
    Map<String, Object?> params = const <String, Object?>{},
    Set<String>? knownFields,
    String unresolvedFieldToken = '#ERROR',
  }) {
    // Open the source early so its declared schema is available for the
    // descendant-lift pre-pass (spec 033). The cursor is positioned before
    // the first row, exactly as if opened later.
    final DataSet ds = source.open(params);
    final List<FieldDef> rootFields = ds.fields;

    // Spec 033: lift descendant-operand aggregates (SUM($F{lineTotal}) where
    // lineTotal lives in a nested collection) to $V{__dagg<n>} references
    // BEFORE expandAggregates. Same-scope / not-found operands are left in
    // place and handled by expandAggregates as before.
    final DescendantLift lift =
        liftDescendantAggregates(rawDefinition, rootFields);
    // Expand inline aggregates (spec 028) before any group/variable logic: a
    // stored SUM($F{...}) in a summary/group-footer band becomes a hidden
    // band-scoped variable + $V{} reference, so it computes through the
    // unchanged calculator. Returns the definition unchanged when there are none.
    final ReportDefinition definition = expandAggregates(lift.definition);
    final List<DescendantAggregate> descAggs = lift.aggregates;
    final ReportDiagnostics diagnostics = ReportDiagnostics();
    final DiagnosticBudget budget = DiagnosticBudget(diagnostics);
    final Set<String> warnedFields = <String>{};
    final Set<String> ignoredPageRefs = <String>{};

    // Spec 030 (B2): a nested scope's published `ScopeTotal` is injected as a
    // field on its parent row, so enclosing scopes / group footers / the
    // summary reference it as `$F{name}`. Under a schema-aware render these
    // computed names aren't in the caller's `knownFields`, so widen that set
    // with every published total name; otherwise the unresolved-binding gate
    // (FR-007) would render `#ERROR` for a legitimately-injected field.
    final Set<String>? effectiveKnownFields = knownFields == null
        ? null
        : <String>{
            ...knownFields,
            ..._publishedTotalNames(definition.body.root)
          };

    final ElementResolver resolver = ElementResolver(
      functions: _functions,
      diagnostics: diagnostics,
      warnedFields: warnedFields,
      knownFields: effectiveKnownFields,
      unresolvedFieldToken: unresolvedFieldToken,
      budget: budget,
    );

    EvalContext contextFactory({
      DataRow? row,
      Map<String, Object?> params = const <String, Object?>{},
      Map<String, JetValue> variables = const <String, JetValue>{},
      required JetFunctionRegistry functions,
    }) =>
        FillEvalContext(
          row: row,
          params: params,
          variables: variables,
          functions: functions,
          diagnostics: diagnostics,
          warnedFields: warnedFields,
          pageRefs: ignoredPageRefs,
          budget: budget,
        );

    // Groups are first-class here; the calculator stays name-keyed, so build its
    // ReportGroups from the levels and translate each variable's resetGroup id
    // back to the level's name (FR-003a is a model concern; the IR is unchanged).
    final List<GroupLevel> groups = definition.body.root.groups;
    final Map<String, String> nameOfGroupId = <String, String>{
      for (final GroupLevel g in groups) g.id: g.name,
    };
    final List<ReportGroup> calcGroups = <ReportGroup>[
      for (final GroupLevel g in groups)
        ReportGroup(
          name: g.name,
          expression: g.key,
          keepTogether: g.keepTogether,
          reprintHeaderOnEachPage: g.reprintHeaderOnEachPage,
          startNewPage: g.startNewPage,
        ),
    ];
    final List<ReportVariable> calcVars = <ReportVariable>[
      for (final ReportVariable v in definition.variables)
        _withResetGroupName(v, nameOfGroupId),
    ];

    final VariableCalculator calc = VariableCalculator(
      variables: calcVars,
      groups: calcGroups,
      functions: _functions,
      contextFactory: contextFactory,
    )..start();

    // Spec 033: split lifted aggregates by reset scope and build per-name
    // accumulators. Accumulators fold every master row's descendant leaves;
    // group-scoped ones are reset at a group break (mirroring calc's own reset).
    final List<DescendantAggregate> summaryDescAggs = <DescendantAggregate>[
      for (final DescendantAggregate a in descAggs)
        if (a.resetScope == VariableResetScope.report) a,
    ];
    final List<DescendantAggregate> groupDescAggs = <DescendantAggregate>[
      for (final DescendantAggregate a in descAggs)
        if (a.resetScope == VariableResetScope.group) a,
    ];
    final Map<String, VariableAccumulator> descAcc =
        <String, VariableAccumulator>{
      for (final DescendantAggregate a in descAggs)
        a.name: VariableAccumulator(a.calculation),
    };
    // Parallels `prevValues`: the group-scoped descendant values through the
    // previous row, used when a group footer is emitted at a break.
    Map<String, JetValue> descGroupSnapshot = <String, JetValue>{
      for (final DescendantAggregate a in groupDescAggs)
        a.name: JetValue.from(unresolvedFieldToken),
    };

    void scanPageScoped(String expression, String site) {
      final Set<String> refs = <String>{};
      Expression.parse(expression).evaluate(FillEvalContext(
        functions: _functions,
        diagnostics: diagnostics,
        warnedFields: <String>{},
        pageRefs: refs,
      ));
      if (refs.isNotEmpty) {
        diagnostics.error(
            'Page-scoped variable(s) ${refs.join(', ')} are not allowed in $site');
      }
    }

    for (final ReportVariable v in definition.variables) {
      scanPageScoped(v.expression, 'variable "${v.name}"');
    }
    for (final GroupLevel g in groups) {
      scanPageScoped(g.key, 'group "${g.name}"');
    }

    final List<String> groupOrder = <String>[
      for (final GroupLevel g in groups) g.name,
    ];
    List<String> brokenInOrder(Set<String> broken, {required bool reversed}) {
      final List<String> ordered = <String>[
        for (final String name in groupOrder)
          if (broken.contains(name)) name,
      ];
      return reversed ? ordered.reversed.toList() : ordered;
    }

    final Map<String, Band> headerByName = <String, Band>{
      for (final GroupLevel g in groups)
        if (g.header != null) g.name: g.header!,
    };
    final Map<String, Band> footerByName = <String, Band>{
      for (final GroupLevel g in groups)
        if (g.footer != null) g.name: g.footer!,
    };

    final List<FilledBand> bands = <FilledBand>[];

    void addBand(Band band, DataRow? row, Map<String, JetValue> vars,
        {String? group}) {
      // Band-level visibility gate: skip entirely (collapse) when invisible.
      if (band.visible != const BoolProperty()) {
        final Set<String> pageRefs = <String>{};
        final FillEvalContext ctx = FillEvalContext(
          row: row,
          params: params,
          variables: vars,
          functions: _functions,
          diagnostics: diagnostics,
          warnedFields: warnedFields,
          pageRefs: pageRefs,
          elementId: band.id,
          budget: budget,
        );
        if (!resolveVisibility(band.visible, ctx, diagnostics,
            id: band.id, pageRefs: pageRefs)) {
          return;
        }
      }
      bands.add(FilledBand(
        type: band.type,
        height: band.height,
        elements: <ReportElement>[
          for (final ReportElement e in band.elements)
            if (resolver.isVisible(e,
                row: row, params: params, variables: vars))
              resolver.resolve(e, row: row, params: params, variables: vars),
        ],
        variables: vars,
        fields: row == null
            ? const <String, JetValue>{}
            : <String, JetValue>{
                for (final FieldDef f in row.fields)
                  f.name: JetValue.from(row.field(f.name)),
              },
        group: group,
      ));
    }

    void emitOnce(Band? band, DataRow? row) {
      if (band != null) addBand(band, row, calc.values);
    }

    final Set<String> warnedCollections = <String>{};

    List<DataRow> childRowsOf(DataRow scopeRow, String name) {
      if (!scopeRow.hasField(name)) {
        if (warnedCollections.add(name)) {
          diagnostics.warning(
              'Collection field "$name" is not in the data schema; its band '
              'emits no rows');
        }
        return const <DataRow>[];
      }
      final Object? raw = scopeRow.field(name);
      if (raw == null) return const <DataRow>[];
      if (raw is! List) {
        if (warnedCollections.add(name)) {
          diagnostics.warning(
              'Collection field "$name" did not resolve to a collection of '
              'rows; its band emits no rows');
        }
        return const <DataRow>[];
      }
      final List<Map<String, Object?>> maps = <Map<String, Object?>>[];
      for (final Object? entry in raw) {
        if (entry is Map) {
          maps.add(entry.map((Object? k, Object? v) =>
              MapEntry<String, Object?>(k.toString(), v)));
        } else {
          budget.recordRowIssue(
              'coll-entry:$name',
              'Collection field "$name" contains a non-row entry; it is '
                  'skipped');
        }
      }
      final FieldDef declared = scopeRow.fields.firstWhere(
        (FieldDef f) => f.name == name,
        orElse: () => const FieldDef(''),
      );
      final List<FieldDef> fields =
          declared.fields.isNotEmpty ? declared.fields : inferFields(maps);
      return <DataRow>[
        for (final Map<String, Object?> m in maps)
          DataRow(fields: fields, values: <String, Object?>{
            for (final FieldDef f in fields) f.name: m[f.name],
          }),
      ];
    }

    // Spec 033: fold one master row's descendant leaves into accumulator [a].
    void foldDescInto(DescendantAggregate a, DataRow row) {
      if (a.ambiguous) return; // fallback rendered at emit
      foldDescendantLeaves(
        rows: <DataRow>[row],
        path: a.path,
        acc: descAcc[a.name]!,
        eval: (DataRow leaf) => a.argument.evaluate(contextFactory(
          row: leaf,
          params: params,
          variables: calc.values,
          functions: _functions,
        )),
        childRowsOf: childRowsOf,
      );
    }

    // Returns the current accumulator values for [aggs], substituting the
    // unresolved-field fallback for ambiguous operands.
    Map<String, JetValue> descValues(Iterable<DescendantAggregate> aggs) =>
        <String, JetValue>{
          for (final DescendantAggregate a in aggs)
            a.name: a.ambiguous
                ? JetValue.from(unresolvedFieldToken)
                : descAcc[a.name]!.value,
        };

    // Spec 030 (B2) — the parsed published-total fold specs depend only on the
    // static definition, so prepare them ONCE here (mirroring how `calcVars` /
    // `calcGroups` / `expandAggregates` are hoisted above the row loop) rather
    // than re-parsing each total's expression on every master row. Keyed by the
    // owning nested scope's id — unique by validation invariant I1 — so
    // `augmentForScope` can look each scope's specs up in O(1).
    final Map<String, List<ScopeAgg>> scopeAggsById =
        <String, List<ScopeAgg>>{};
    void collectScopeAggs(DetailScope scope) {
      for (final ScopeNode node in scope.children) {
        if (node is! NestedScope) continue;
        final DetailScope cs = node.scope;
        scopeAggsById[cs.id] = prepareScopeTotals(cs.totals);
        collectScopeAggs(cs);
      }
    }

    collectScopeAggs(definition.body.root);

    // Spec 030 (B2) — a single bottom-up rollup pass per master row, run BEFORE
    // `calc.advance`. For each nested child scope it: derives the child rows,
    // recursively augments each (so a child's own published totals are fields
    // on it), folds each published `ScopeTotal` over the augmented child rows
    // (a fresh accumulator → reset per parent), injects the result as a field
    // on this `row`, and replaces this row's collection value+schema with the
    // augmented child rows so `emitNode`'s unchanged `childRowsOf` yields rows
    // already carrying their published totals. Each published total folds once;
    // the master calculator/layout/render are untouched and just see richer
    // rows. Returns `row` unchanged when there is nothing to inject or replace.
    DataRow augmentForScope(DetailScope scope, DataRow row) {
      final Map<String, JetValue> extras = <String, JetValue>{};
      final Map<String, List<DataRow>> replaced = <String, List<DataRow>>{};
      for (final ScopeNode node in scope.children) {
        if (node is! NestedScope) continue;
        final DetailScope cs = node.scope;
        final String field = cs.collectionField!;
        final List<DataRow> childRows = childRowsOf(row, field);
        final List<DataRow> augChildren = <DataRow>[
          for (final DataRow cr in childRows) augmentForScope(cs, cr),
        ];
        for (final ScopeAgg a in scopeAggsById[cs.id] ?? const <ScopeAgg>[]) {
          final VariableAccumulator acc = VariableAccumulator(a.calculation);
          for (final DataRow acr in augChildren) {
            acc.fold(a.argument.evaluate(contextFactory(
              row: acr,
              params: params,
              variables: const <String, JetValue>{},
              functions: _functions,
            )));
          }
          if (acc.skippedNonNumeric > 0) {
            budget.recordRowIssue(
                'agg:scope:${cs.id}:${a.name}',
                '${acc.skippedNonNumeric} non-numeric value(s) were skipped '
                    'from published total "${a.name}"');
          }
          // A published total can collide either with a real data field on the
          // parent row (FR-010 shadow) or with a sibling scope's total already
          // published into `extras` this invocation — validation enforces
          // name-uniqueness only WITHIN one scope, not across siblings. Warn in
          // both cases; the computed value is still injected (last-wins).
          if (row.hasField(a.name) || extras.containsKey(a.name)) {
            diagnostics.warning(
                'published total "${a.name}" on scope "${cs.id}" collides with '
                'an existing field or a sibling scope\'s published total of the '
                'same name; the computed total is used');
          }
          extras[a.name] = acc.value;
        }
        if (augChildren.isNotEmpty) replaced[field] = augChildren;
      }
      if (extras.isEmpty && replaced.isEmpty) return row;
      return _augmentRow(row, extras, replaced);
    }

    // A per-row band renders at the current scope row; a nested scope iterates
    // its collection and emits its own children per child row — mirroring the
    // legacy `emitDataBand` recursion exactly.
    void emitNode(ScopeNode node, DataRow scopeRow) {
      switch (node) {
        case BandNode(band: final Band b):
          addBand(b, scopeRow, calc.values);
        case NestedScope(scope: final DetailScope s):
          final List<DataRow> childRows =
              childRowsOf(scopeRow, s.collectionField!);
          if (childRows.isEmpty) {
            break; // empty collection → no bands, no footer
          }
          final PreparedFooter? footer =
              s.footer == null ? null : prepareNestedFooter(s.footer!);
          // Classify each footer aggregate operand once: same-scope folds over the
          // immediate child rows (spec 029); a descendant leaf folds over the whole
          // subtree (spec 033); an ambiguous operand renders the fallback (FR-010).
          final List<FieldDef> childFields = childRows.first.fields;
          final List<List<String>?> descPaths =
              <List<String>?>[]; // null → same-scope
          final List<bool> ambiguousAgg = <bool>[];
          if (footer != null) {
            for (final NestedAgg a in footer.aggs) {
              final Set<String> refs = a.argument.references.fields;
              AggregatePath? resolved = refs.length == 1
                  ? resolveAggregatePath(childFields, refs.single)
                  : null;
              descPaths.add(resolved is DescendPath ? resolved.path : null);
              ambiguousAgg.add(resolved is Ambiguous);
            }
          }
          final List<VariableAccumulator>? accs = footer == null
              ? null
              : <VariableAccumulator>[
                  for (final NestedAgg a in footer.aggs)
                    VariableAccumulator(a.calculation),
                ];
          for (final DataRow childRow in childRows) {
            for (final ScopeNode child in s.children) {
              emitNode(child, childRow);
            }
            if (footer != null) {
              for (int k = 0; k < footer.aggs.length; k++) {
                // Same-scope: fold over the immediate child rows, as spec 029.
                if (descPaths[k] == null && !ambiguousAgg[k]) {
                  accs![k].fold(footer.aggs[k].argument.evaluate(contextFactory(
                    row: childRow,
                    params: params,
                    variables: calc.values,
                    functions: _functions,
                  )));
                }
              }
            }
          }
          if (footer != null) {
            // Descendant folds run once over the whole subtree of this scope instance.
            for (int k = 0; k < footer.aggs.length; k++) {
              final List<String>? path = descPaths[k];
              if (path != null) {
                foldDescendantLeaves(
                  rows: childRows,
                  path: path,
                  acc: accs![k],
                  eval: (DataRow leaf) =>
                      footer.aggs[k].argument.evaluate(contextFactory(
                    row: leaf,
                    params: params,
                    variables: calc.values,
                    functions: _functions,
                  )),
                  childRowsOf: childRowsOf,
                );
              }
            }
            final Map<String, JetValue> vars = <String, JetValue>{
              ...calc.values,
              for (int k = 0; k < footer.aggs.length; k++)
                footer.aggs[k].name: ambiguousAgg[k]
                    ? JetValue.from(unresolvedFieldToken)
                    : accs![k].value,
            };
            // Name the nested scope (not the aggregate): footer.aggs[k].name is the synthesized $V{__naggN} name, not a user-facing id — naming the scope is robust and parse-free (spec E2).
            for (int k = 0; k < footer.aggs.length; k++) {
              final int skips = accs![k].skippedNonNumeric;
              if (skips > 0) {
                budget.recordRowIssue(
                    'agg:footer:${s.id}:$k',
                    '$skips non-numeric value(s) were skipped from a footer '
                        'aggregate in scope "${s.id}"');
              }
            }
            addBand(footer.band, scopeRow, vars);
          }
      }
    }

    void emitDetail(DataRow row) {
      for (final ScopeNode node in definition.body.root.children) {
        emitNode(node, row);
      }
    }

    void emitGroupHeaders(List<String> names, DataRow? row) {
      for (final String name in names) {
        final Band? header = headerByName[name];
        if (header != null) addBand(header, row, calc.values, group: name);
      }
    }

    void emitGroupFooters(
        List<String> names, DataRow? footerRow, Map<String, JetValue> vars) {
      for (final String name in names) {
        final Band? footer = footerByName[name];
        if (footer != null) addBand(footer, footerRow, vars, group: name);
      }
    }

    emitOnce(definition.body.title, null);

    // `ds` was opened early (above) to read its schema for the descendant-lift
    // pre-pass. The cursor is still positioned before the first row.
    bool hadRows = false;
    int rowNumber = 0;
    Map<String, JetValue> prevValues = const <String, JetValue>{};
    DataRow? prevRow;
    try {
      while (ds.moveNext()) {
        budget.row = ++rowNumber;
        // Inject this master row's published totals (and augment its nested
        // collection tree) BEFORE the calculator advances, so the Phase A
        // grand total over a published total (e.g. SUM($F{customerTotal}))
        // sums it live through the unchanged calculator.
        final DataRow row = augmentForScope(definition.body.root, ds.current);
        final int calcSkipsBefore = calc.aggregateSkips;
        calc.advance(row, params: params);
        final int calcSkipDelta = calc.aggregateSkips - calcSkipsBefore;
        if (calcSkipDelta > 0) {
          budget.recordRowIssue(
              'agg:calc',
              '$calcSkipDelta non-numeric value(s) were skipped from an '
                  'aggregate');
        }
        final Set<String> broken = calc.brokenGroups;
        if (!hadRows) {
          emitGroupHeaders(groupOrder, row);
        } else if (broken.isNotEmpty) {
          // Spec 033: emit the broken group footer(s) with the completed-group
          // descendant snapshot (parallels prevValues for the master calculator).
          emitGroupFooters(brokenInOrder(broken, reversed: true), prevRow,
              <String, JetValue>{...prevValues, ...descGroupSnapshot});
          // Reset group-scoped descendant accumulators whose group broke, then
          // emit new headers — mirroring VariableCalculator.advance's reset order.
          for (final DescendantAggregate a in groupDescAggs) {
            if (broken.contains(a.resetGroup)) descAcc[a.name]!.reset();
          }
          emitGroupHeaders(brokenInOrder(broken, reversed: false), row);
        }
        emitDetail(row);
        hadRows = true;
        prevValues = calc.values;
        prevRow = row;
        // Fold this master row's descendant leaves into all accumulators, then
        // snapshot the group-scoped values (so the next break reads a completed
        // group, just as prevValues captures the completed master row).
        final int descSkipsBefore = _sumAccSkips(descAcc.values);
        for (final DescendantAggregate a in descAggs) {
          foldDescInto(a, row);
        }
        final int descSkipDelta =
            _sumAccSkips(descAcc.values) - descSkipsBefore;
        if (descSkipDelta > 0) {
          budget.recordRowIssue(
              'agg:desc',
              '$descSkipDelta non-numeric value(s) were skipped from a '
                  'roll-up aggregate');
        }
        descGroupSnapshot = descValues(groupDescAggs);
      }
    } finally {
      ds.close();
    }

    if (!hadRows) {
      diagnostics.info(
          'Data source returned no rows; the noData band renders instead of '
          'details');
      emitOnce(definition.body.noData, null);
    } else {
      // End-of-data: emit final group footers with the last completed-group
      // descendant snapshot, then the summary with the report-scoped totals.
      emitGroupFooters(groupOrder.reversed.toList(), prevRow,
          <String, JetValue>{...prevValues, ...descGroupSnapshot});
      if (definition.body.summary != null) {
        addBand(definition.body.summary!, null,
            <String, JetValue>{...calc.values, ...descValues(summaryDescAggs)});
      }
    }

    budget.finish();
    return FillResult(
      report: FilledReport(
        page: definition.page,
        bands: bands,
        params: <String, JetValue>{
          for (final MapEntry<String, Object?> e in params.entries)
            e.key: JetValue.from(e.value),
        },
      ),
      diagnostics: diagnostics,
    );
  }

  /// The total wrong-type skips across [accs] (spec E2). Monotonic per
  /// accumulator, so a difference of two reads is a non-negative per-row delta.
  static int _sumAccSkips(Iterable<VariableAccumulator> accs) {
    int n = 0;
    for (final VariableAccumulator a in accs) {
      n += a.skippedNonNumeric;
    }
    return n;
  }

  /// A copy of [v] whose group-reset reference, if it is a [GroupLevel] id, is
  /// rewritten to that level's display name (the calculator is name-keyed).
  static ReportVariable _withResetGroupName(
      ReportVariable v, Map<String, String> nameOfGroupId) {
    final String? reset = v.resetGroup;
    if (reset == null || !nameOfGroupId.containsKey(reset)) return v;
    return ReportVariable(
      name: v.name,
      expression: v.expression,
      calculation: v.calculation,
      resetScope: v.resetScope,
      resetGroup: nameOfGroupId[reset],
    );
  }

  /// Every published-total name declared anywhere in [scope]'s nested-scope
  /// tree (spec 030, B2) — the synthetic fields the rollup injects onto parent
  /// rows, so the schema-aware resolver must treat them as known.
  static Set<String> _publishedTotalNames(DetailScope scope) {
    final Set<String> names = <String>{};
    void walk(DetailScope s) {
      for (final ScopeNode node in s.children) {
        if (node is! NestedScope) continue;
        for (final ScopeTotal t in node.scope.totals) {
          names.add(t.name);
        }
        walk(node.scope);
      }
    }

    walk(scope);
    return names;
  }

  /// Rebuilds the immutable [row] (spec 030, B2) with [extras] published-total
  /// fields appended and each [replaced] nested collection swapped for its
  /// augmented child rows. A replaced collection's [FieldDef] is re-typed to the
  /// augmented child schema (which now includes deeper published-total names) so
  /// `childRowsOf`'s re-projection preserves them; a published total's
  /// [JetValue] is stored directly (it round-trips unchanged through
  /// `JetValue.from`). A total that shadows an existing field overwrites its
  /// value (the computed total wins) without duplicating the schema entry.
  static DataRow _augmentRow(DataRow row, Map<String, JetValue> extras,
      Map<String, List<DataRow>> replaced) {
    final List<FieldDef> fields = <FieldDef>[
      for (final FieldDef f in row.fields)
        if (replaced.containsKey(f.name) && replaced[f.name]!.isNotEmpty)
          FieldDef(f.name,
              type: f.type,
              description: f.description,
              fields: replaced[f.name]!.first.fields)
        else
          f,
      for (final String name in extras.keys)
        if (!row.hasField(name)) FieldDef(name, type: JetFieldType.double),
    ];
    final Map<String, Object?> values = <String, Object?>{
      for (final FieldDef f in row.fields) f.name: row.field(f.name),
      for (final MapEntry<String, List<DataRow>> e in replaced.entries)
        e.key: <Map<String, Object?>>[
          for (final DataRow cr in e.value)
            <String, Object?>{
              for (final FieldDef cf in cr.fields) cf.name: cr.field(cf.name),
            },
        ],
      for (final MapEntry<String, JetValue> e in extras.entries) e.key: e.value,
    };
    return DataRow(fields: fields, values: values);
  }
}
