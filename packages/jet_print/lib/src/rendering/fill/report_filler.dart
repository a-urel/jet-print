/// The Fill data pass (spec 007b/007c). Walks a [ReportTemplate] over a
/// [JetDataSource], drives the variable calculator, and emits the resolved band
/// stream — title/groupHeader/detail/groupFooter/summary/noData — as a
/// [FilledReport] + diagnostics. INTERNAL — the public surface is the 011
/// JetReportEngine.
library;

import '../../data/data_row.dart';
import '../../data/data_set.dart';
import '../../data/jet_data_source.dart';
import '../../domain/report_band.dart';
import '../../domain/report_element.dart';
import '../../domain/report_group.dart';
import '../../domain/report_template.dart';
import '../../domain/report_variable.dart';
import '../../expression/aggregate/variable_calculator.dart';
import '../../expression/eval_context.dart';
import '../../expression/expression.dart';
import '../../expression/function_registry.dart';
import '../../expression/functions/built_in_functions.dart';
import '../../expression/value.dart';
import 'element_resolver.dart';
import 'fill_eval_context.dart';
import 'filled_report.dart';
import 'group_band_index.dart';
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

  /// Fills [template] over [source] (with [params]) into a [FillResult].
  FillResult fill(
    ReportTemplate template,
    JetDataSource source, {
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    final ReportDiagnostics diagnostics = ReportDiagnostics();
    final Set<String> warnedFields = <String>{};
    // A write-only sink for the calculator-injected context's page-scoped refs.
    // The driver never READS it: variable/group page-scoped detection is done by
    // the site-aware `scanPageScoped` pre-scan below (which preserves the site
    // tag). This must be a mutable set, not `const <String>{}`, because
    // FillEvalContext.resolveVariable calls `pageRefs.add(...)` and would throw
    // on an unmodifiable set. It exists only to satisfy the required parameter
    // and to share the context's missing-field tracking (diagnostics/warnedFields).
    final Set<String> ignoredPageRefs = <String>{};

    final ElementResolver resolver = ElementResolver(
      functions: _functions,
      diagnostics: diagnostics,
      warnedFields: warnedFields,
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

    // Validate + index group bands FIRST: this throws ReportFormatException
    // (fail-fast) on duplicate group names BEFORE constructing the calculator —
    // whose brokenGroups/reset logic assumes unique names (spec 007c §4/§6).
    final GroupBandIndex groupIndex = GroupBandIndex(template, diagnostics);

    final VariableCalculator calc = VariableCalculator(
      variables: template.variables,
      groups: template.groups,
      functions: _functions,
      contextFactory: contextFactory,
    )..start();

    void scanPageScoped(String expression, String site) {
      final Set<String> refs = <String>{};
      Expression.parse(expression).evaluate(FillEvalContext(
        functions: _functions,
        diagnostics: diagnostics,
        warnedFields: <String>{}, // var/group missing-field is the factory's job
        pageRefs: refs,
      ));
      if (refs.isNotEmpty) {
        diagnostics.error(
            'Page-scoped variable(s) ${refs.join(', ')} are not allowed in $site');
      }
    }

    for (final ReportVariable v in template.variables) {
      scanPageScoped(v.expression, 'variable "${v.name}"');
    }
    for (final ReportGroup g in template.groups) {
      scanPageScoped(g.expression, 'group "${g.name}"');
    }

    // The authored group order (outermost first) is the single source of nesting
    // order. `brokenGroups` is a membership Set, never iterated for order.
    final List<String> groupOrder = <String>[
      for (final ReportGroup g in template.groups) g.name,
    ];
    List<String> brokenInOrder(Set<String> broken, {required bool reversed}) {
      final List<String> ordered = <String>[
        for (final String name in groupOrder)
          if (broken.contains(name)) name,
      ];
      return reversed ? ordered.reversed.toList() : ordered;
    }

    final List<FilledBand> bands = <FilledBand>[];

    void addBand(ReportBand band, DataRow? row, Map<String, JetValue> vars) {
      bands.add(FilledBand(
        type: band.type,
        height: band.height,
        elements: <ReportElement>[
          for (final ReportElement e in band.elements)
            resolver.resolve(e, row: row, params: params, variables: vars),
        ],
        variables: vars,
        group: band.group,
      ));
    }

    void emit(BandType type, DataRow? row) {
      for (final ReportBand band in template.bands) {
        if (band.type != type) continue;
        addBand(band, row, calc.values);
      }
    }

    void emitGroupHeaders(List<String> names, DataRow? row) {
      for (final String name in names) {
        for (final ReportBand band in groupIndex.headersFor(name)) {
          addBand(band, row, calc.values);
        }
      }
    }

    void emitGroupFooters(
        List<String> names, DataRow? footerRow, Map<String, JetValue> vars) {
      for (final String name in names) {
        for (final ReportBand band in groupIndex.footersFor(name)) {
          addBand(band, footerRow, vars);
        }
      }
    }

    emit(BandType.title, null);

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
          // First data row: open every group, outermost->innermost.
          emitGroupHeaders(groupOrder, row);
        } else if (broken.isNotEmpty) {
          // Close the ended groups (inner->outer) with the pre-reset snapshot,
          // then re-open them (outer->inner) with the post-reset snapshot.
          emitGroupFooters(
              brokenInOrder(broken, reversed: true), prevRow, prevValues);
          emitGroupHeaders(brokenInOrder(broken, reversed: false), row);
        }
        emit(BandType.detail, row);
        hadRows = true;
        prevValues = calc.values;
        prevRow = row;
      }
    } finally {
      ds.close();
    }

    if (!hadRows) {
      emit(BandType.noData, null);
    } else {
      // Close every still-open group (inner->outer) with the final snapshot.
      emitGroupFooters(groupOrder.reversed.toList(), prevRow, prevValues);
      emit(BandType.summary, null);
    }

    return FillResult(
      report: FilledReport(page: template.page, bands: bands),
      diagnostics: diagnostics,
    );
  }
}
