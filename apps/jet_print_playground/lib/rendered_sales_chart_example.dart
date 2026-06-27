/// Real data for the sales-chart sample, plus the one-call render through the
/// public engine — the consumer side of the three-chart demo (bar, line, pie),
/// all through `package:jet_print/jet_print.dart` only.
///
/// One master row with a `months` nested collection (6 months of revenue +
/// units data). The declared `fields:` is passed to the data source so the
/// nested `List<Map>` column is typed as a collection and the chart engine's
/// collection-field lookup resolves correctly.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'sales_chart_sample.dart';

/// The six months of sample data — the source of truth shared by the data
/// source and the golden tests so the rendered output and any expected values
/// can never drift.
const List<Map<String, Object?>> kSampleSalesMonths = <Map<String, Object?>>[
  <String, Object?>{
    'months': <Map<String, Object?>>[
      <String, Object?>{'month': 'Jan', 'revenue': 1200.0, 'units': 45},
      <String, Object?>{'month': 'Feb', 'revenue': 1800.0, 'units': 62},
      <String, Object?>{'month': 'Mar', 'revenue': 1500.0, 'units': 54},
      <String, Object?>{'month': 'Apr', 'revenue': 2100.0, 'units': 78},
      <String, Object?>{'month': 'May', 'revenue': 1900.0, 'units': 68},
      <String, Object?>{'month': 'Jun', 'revenue': 2400.0, 'units': 88},
    ],
  },
];

/// The sample months as an in-memory data source typed by [salesChartSchema].
/// The declared `fields:` is required so the nested `List<Map>` column is
/// recognized as a collection (else the chart engine sees an untyped map and
/// the collection-field lookup returns nothing).
JetDataSource salesChartDataSource() =>
    JetInMemoryDataSource(kSampleSalesMonths, fields: salesChartSchema.fields);

/// Renders [salesChartDefinition] over [salesChartDataSource] through the
/// native [JetReportEngine.renderDefinition] path — the same single call the
/// designer tab's preview uses. [definition] defaults to the bundled sample so
/// the designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderSalesChartDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? salesChartDefinition(),
      source ?? salesChartDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(salesChartSchema.fields),
        fonts: fonts,
      ),
    );

/// Every field name the schema declares, top-level and nested (so
/// collection-scoped bindings like `$F{revenue}` are recognized too).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };
