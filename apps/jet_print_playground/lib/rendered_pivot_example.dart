/// Renders the pivot sample through the public engine — the consumer side of
/// the crosstab demo, all through `package:jet_print/jet_print.dart` only.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'pivot_sample.dart';

/// The pivot sample rows as an in-memory data source typed by [pivotSchema].
JetDataSource pivotDataSource() =>
    JetInMemoryDataSource(pivotData(), fields: pivotSchema.fields);

/// Renders [pivotDefinition] over [pivotDataSource] through the native
/// [JetReportEngine.renderDefinition] path — the same single call the designer
/// tab's preview uses. [definition] defaults to the bundled sample so the
/// designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderPivotDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? pivotDefinition(),
      source ?? pivotDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(pivotSchema.fields),
        fonts: fonts,
      ),
    );

/// Every field name the schema declares, top-level and nested (so
/// collection-scoped bindings would be recognized too).
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };
