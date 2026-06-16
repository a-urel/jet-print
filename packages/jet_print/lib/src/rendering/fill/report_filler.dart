/// The Fill data pass (spec 007b/007c). Walks a [ReportTemplate] over a
/// [JetDataSource], drives the variable calculator, and emits the resolved band
/// stream — title/groupHeader/detail/groupFooter/summary/noData — as a
/// [FilledReport] + diagnostics. INTERNAL — the public surface is the 011
/// JetReportEngine.
library;

import '../../data/data_row.dart';
import '../../data/data_set.dart';
import '../../data/field_def.dart';
import '../../data/jet_data_source.dart';
import '../../domain/band.dart';
import '../../domain/detail_scope.dart';
import '../../domain/group_level.dart';
import '../../domain/report_definition.dart';
import '../../domain/report_element.dart';
import '../../domain/report_group.dart';
import '../../domain/report_variable.dart';
import '../../expression/aggregate/aggregate_synthesizer.dart';
import '../../expression/aggregate/nested_footer.dart';
import '../../expression/aggregate/variable_accumulator.dart';
import '../../expression/aggregate/variable_calculator.dart';
import '../../expression/eval_context.dart';
import '../../expression/expression.dart';
import '../../expression/function_registry.dart';
import '../../expression/functions/built_in_functions.dart';
import '../../expression/value.dart';
import 'element_resolver.dart';
import 'fill_eval_context.dart';
import 'filled_report.dart';
import 'report_diagnostics.dart';

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
    // Expand inline aggregates (spec 028) before any group/variable logic: a
    // stored SUM($F{...}) in a summary/group-footer band becomes a hidden
    // band-scoped variable + $V{} reference, so it computes through the
    // unchanged calculator. Returns the definition unchanged when there are none.
    final ReportDefinition definition = expandAggregates(rawDefinition);
    final ReportDiagnostics diagnostics = ReportDiagnostics();
    final Set<String> warnedFields = <String>{};
    final Set<String> ignoredPageRefs = <String>{};

    final ElementResolver resolver = ElementResolver(
      functions: _functions,
      diagnostics: diagnostics,
      warnedFields: warnedFields,
      knownFields: knownFields,
      unresolvedFieldToken: unresolvedFieldToken,
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
      bands.add(FilledBand(
        type: band.type,
        height: band.height,
        elements: <ReportElement>[
          for (final ReportElement e in band.elements)
            resolver.resolve(e, row: row, params: params, variables: vars),
        ],
        variables: vars,
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
        } else if (warnedCollections.add('$name#entry')) {
          diagnostics.warning(
              'Collection field "$name" contains a non-row entry; it is '
              'skipped');
        }
      }
      final FieldDef declared = scopeRow.fields.firstWhere(
        (FieldDef f) => f.name == name,
        orElse: () => const FieldDef(''),
      );
      final List<FieldDef> fields = declared.fields.isNotEmpty
          ? declared.fields
          : _inferChildFields(maps);
      return <DataRow>[
        for (final Map<String, Object?> m in maps)
          DataRow(fields: fields, values: <String, Object?>{
            for (final FieldDef f in fields) f.name: m[f.name],
          }),
      ];
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
          // Fresh accumulators each invocation → the footer total resets per
          // parent.
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
                accs![k].fold(footer.aggs[k].argument.evaluate(contextFactory(
                  row: childRow,
                  params: params,
                  variables: calc.values,
                  functions: _functions,
                )));
              }
            }
          }
          if (footer != null) {
            final Map<String, JetValue> vars = <String, JetValue>{
              ...calc.values,
              for (int k = 0; k < footer.aggs.length; k++)
                footer.aggs[k].name: accs![k].value,
            };
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

    final DataSet ds = source.open(params);
    bool hadRows = false;
    Map<String, JetValue> prevValues = const <String, JetValue>{};
    DataRow? prevRow;
    try {
      while (ds.moveNext()) {
        final DataRow row = ds.current;
        calc.advance(row, params: params);
        final Set<String> broken = calc.brokenGroups;
        if (!hadRows) {
          emitGroupHeaders(groupOrder, row);
        } else if (broken.isNotEmpty) {
          emitGroupFooters(
              brokenInOrder(broken, reversed: true), prevRow, prevValues);
          emitGroupHeaders(brokenInOrder(broken, reversed: false), row);
        }
        emitDetail(row);
        hadRows = true;
        prevValues = calc.values;
        prevRow = row;
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
      emitGroupFooters(groupOrder.reversed.toList(), prevRow, prevValues);
      emitOnce(definition.body.summary, null);
    }

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

  /// Best-effort child schema for a collection whose [FieldDef] declares no
  /// child fields (e.g. the schema was inferred): the union of all entry keys
  /// in first-seen order, each typed via [FieldDef.inferType] over that
  /// column's values — mirroring `JetInMemoryDataSource`'s inference so the
  /// three public sources stay output-identical (SC-006). A nested list value
  /// infers [JetFieldType.unknown], but its raw value is preserved on the
  /// child row, so deeper collection bands still iterate it.
  static List<FieldDef> _inferChildFields(List<Map<String, Object?>> rows) {
    final List<String> names = <String>[];
    final Set<String> seen = <String>{};
    for (final Map<String, Object?> row in rows) {
      for (final String key in row.keys) {
        if (seen.add(key)) names.add(key);
      }
    }
    return <FieldDef>[
      for (final String name in names)
        FieldDef(
          name,
          type: FieldDef.inferType(
            rows.map((Map<String, Object?> r) => r[name]),
          ),
        ),
    ];
  }
}
