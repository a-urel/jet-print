/// The public render facade (spec 011): one call from a reified
/// [ReportDefinition] plus host data to a lazily-paginated, locale-aware
/// [RenderedReport]. A thin orchestrator over the existing `ReportFiller` and
/// `ReportLayouter` — it owns **no** rendering logic of its own.
library;

import 'package:intl/intl.dart';

import '../../data/jet_data_source.dart';
import '../../domain/report_definition.dart';
import '../../domain/report_parameter.dart';
import '../fill/report_diagnostics.dart';
import '../fill/report_filler.dart';
import '../layout/report_layouter.dart';
import '../text/font_registry.dart';
import '../text/metrics_text_measurer.dart';
import 'render_options.dart';
import 'rendered_report.dart';

/// Fills a reified report definition with real data and paginates it for
/// preview (and, in a later slice, export).
///
/// ```dart
/// final RenderedReport report = const JetReportEngine().renderDefinition(
///   definition,                    // a reified ReportDefinition
///   JetInMemoryDataSource(rows),   // the host's records
///   options: const RenderOptions(
///     parameters: {'printedBy': 'A. Urel'},
///     locale: Locale('de'),
///   ),
/// );
/// ```
///
/// The engine is stateless and `const`; each [renderDefinition] composes the
/// fill pass (expression evaluation, master/detail iteration,
/// variables/aggregates) with the lazy layout pass (pagination, repeated page
/// chrome, `PAGE_NUMBER`/`PAGE_COUNT`), threading the per-render parameters and
/// locale through both.
///
/// Guarantees:
///
/// * **Never throws on malformed data** (FR-013/FR-014): unknown fields,
///   missing parameters, unresolvable images, and empty datasets best-effort
///   render and surface on [RenderedReport.diagnostics].
/// * **Deterministic** (FR-010): identical (definition, data, parameters,
///   locale) produce byte-identical pages — no clock, no randomness, no
///   ambient-locale reads.
/// * **Lazy first page** (FR-021): the returned report resolves its exact
///   page count up front, but builds each page's frame only when requested.
/// * **Read-only over definitions** (FR-016): rendering never mutates or
///   re-serializes the definition.
class JetReportEngine {
  /// Creates the stateless render engine.
  const JetReportEngine();

  /// Fills [definition] with [source]'s records (and [options]), paginates, and
  /// returns a lazily-paginated [RenderedReport] — the native render path over
  /// the reified model (spec 024).
  RenderedReport renderDefinition(
    ReportDefinition definition,
    JetDataSource source, {
    RenderOptions options = const RenderOptions(),
  }) {
    final String localeTag =
        Intl.canonicalizedLocale(options.locale.toLanguageTag());
    // One registry per render: the bundled defaults, then host families
    // (last-registration-wins). It drives layout MEASUREMENT and is carried on
    // the returned report so preview/export/print paint from the identical
    // bytes — never a second default-only build (Principle IV / 022 C7/C8).
    final FontRegistry fonts = FontRegistry()
      ..registerDefault()
      ..registerHostFonts(options.fonts);
    final ReportDiagnostics paramDiagnostics = ReportDiagnostics();
    final Map<String, Object?> params =
        _effectiveParameters(definition, options, paramDiagnostics);
    final FillResult fill = _withLocale(
      localeTag,
      () => ReportFiller().fillDefinition(
        definition,
        source,
        params: params,
        knownFields: options.knownFields,
        unresolvedFieldToken: options.unresolvedFieldToken,
      ),
    );
    final LazyLayout lazy = _withLocale(
      localeTag,
      () => ReportLayouter(measurer: MetricsTextMeasurer(fonts))
          .layoutLazyDefinition(definition, fill.report,
              onElementPrint: options.onElementPrint),
    );
    return RenderedReport(
      title: definition.name,
      pageCount: lazy.pageCount,
      fonts: fonts,
      // Lazy builds run later, outside render()'s scope — re-enter the render
      // locale per build so formatting in page chrome stays deterministic.
      buildFrame: (int index) =>
          _withLocale(localeTag, () => lazy.buildPage(index)),
      diagnosticsSources: <ReportDiagnostics>[
        paramDiagnostics,
        fill.diagnostics,
        lazy.diagnostics,
      ],
    );
  }

  /// Runs [body] with [localeTag] as the current Intl locale (FR-012a), typed
  /// (`Intl.withLocale` is declared `dynamic`).
  static T _withLocale<T>(String localeTag, T Function() body) =>
      Intl.withLocale<T>(localeTag, body) as T;

  /// The parameter values the render actually uses: the host-supplied map,
  /// backfilled with declared defaults. A parameter the definition declares
  /// with neither a supplied value nor a default gets a diagnostic and
  /// resolves as empty (FR-012 / FR-013 / SC-007).
  static Map<String, Object?> _effectiveParameters(
    ReportDefinition definition,
    RenderOptions options,
    ReportDiagnostics diagnostics,
  ) {
    final Map<String, Object?> effective = <String, Object?>{
      ...options.parameters,
    };
    for (final ReportParameter parameter in definition.parameters) {
      if (effective.containsKey(parameter.name)) continue;
      if (parameter.defaultValue != null) {
        effective[parameter.name] = parameter.defaultValue;
      } else {
        diagnostics.warning(
            'Parameter "${parameter.name}" was not supplied and declares no '
            'default; it renders as empty');
      }
    }
    return effective;
  }
}
