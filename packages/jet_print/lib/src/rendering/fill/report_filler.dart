/// The Fill data pass (spec 007b). Walks a [ReportTemplate] over a
/// [JetDataSource], drives the variable calculator, and emits the resolved
/// title/detail/summary/noData band stream as a [FilledReport] + diagnostics.
/// INTERNAL — the public surface is the 011 JetReportEngine.
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
    // The calculator-injected context records page-scoped refs here, but the
    // driver does NOT read this sink — variable/group page-scoped detection is
    // done site-aware below (`scanPageScoped`). It only satisfies the context's
    // required parameter; the context's missing-field tracking is what matters.
    final Set<String> ignoredPageRefs = <String>{};

    final ElementResolver resolver = ElementResolver(
      functions: _functions,
      diagnostics: diagnostics,
      warnedFields: warnedFields,
    );

    // Inject a tracking context for the calculator's variable/group evaluation,
    // sharing the diagnostics + the missing-field dedup set.
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

    final VariableCalculator calc = VariableCalculator(
      variables: template.variables,
      groups: template.groups,
      functions: _functions,
      contextFactory: contextFactory,
    )..start();

    // Site-aware page-scoped pre-scan (§5): the driver owns the loop, so it
    // supplies the *site* (the variable/group name). Runs after the calculator
    // is built — a malformed variable/group expression has already failed fast,
    // so Expression.parse here is safe. No row is needed (page-scoped detection
    // is via resolveVariable).
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

    final List<FilledBand> bands = <FilledBand>[];

    void emit(BandType type, DataRow? row) {
      for (final ReportBand band in template.bands) {
        if (band.type != type) continue;
        bands.add(FilledBand(
          type: band.type,
          height: band.height,
          elements: <ReportElement>[
            for (final ReportElement e in band.elements)
              resolver.resolve(e,
                  row: row, params: params, variables: calc.values),
          ],
          variables: calc.values,
        ));
      }
    }

    emit(BandType.title, null);

    final DataSet ds = source.open(params);
    bool hadRows = false;
    try {
      while (ds.moveNext()) {
        final DataRow row = ds.current;
        calc.advance(row, params: params);
        hadRows = true;
        emit(BandType.detail, row);
      }
    } finally {
      ds.close();
    }

    if (!hadRows) {
      emit(BandType.noData, null);
    } else {
      emit(BandType.summary, null);
    }

    return FillResult(
      report: FilledReport(page: template.page, bands: bands),
      diagnostics: diagnostics,
    );
  }
}
