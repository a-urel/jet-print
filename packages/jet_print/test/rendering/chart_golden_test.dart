// Chart element golden (044 — chart support).
//
// Pins the visual output of the three chart types (bar, line, pie) rendered
// from a single master row carrying a nested `months` collection — through both
// the [JetReportPreview] widget path (light theme) and the PNG export path
// (page 1 at 2x). Public API only; regenerate with `--update-goldens`.
@Tags(['golden'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// ---------------------------------------------------------------------------
// Shared definition + data source
// ---------------------------------------------------------------------------

ReportDefinition _definition() => const ReportDefinition(
      name: 'Sales Chart',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'title',
              type: BandType.title,
              height: 30,
              elements: <ReportElement>[
                TextElement(
                  id: 'heading',
                  bounds: JetRect(x: 0, y: 4, width: 500, height: 22),
                  text: 'Monthly Sales',
                  style: JetTextStyle(fontSize: 16, weight: JetFontWeight.bold),
                ),
              ],
            )),
            BandNode(Band(
              id: 'barBand',
              type: BandType.detail,
              height: 160,
              elements: <ReportElement>[
                ChartElement(
                  id: 'barChart',
                  bounds: JetRect(x: 0, y: 0, width: 500, height: 155),
                  chartType: ChartType.bar,
                  collectionField: 'months',
                  valueExpression: r'$F{revenue}',
                  categoryExpression: r'$F{month}',
                  title: 'Revenue (Bar)',
                  showAxes: true,
                  showValueLabels: true,
                ),
              ],
            )),
            BandNode(Band(
              id: 'lineBand',
              type: BandType.detail,
              height: 160,
              elements: <ReportElement>[
                ChartElement(
                  id: 'lineChart',
                  bounds: JetRect(x: 0, y: 0, width: 500, height: 155),
                  chartType: ChartType.line,
                  collectionField: 'months',
                  valueExpression: r'$F{units}',
                  categoryExpression: r'$F{month}',
                  title: 'Units Sold (Line)',
                  showAxes: true,
                ),
              ],
            )),
            BandNode(Band(
              id: 'pieBand',
              type: BandType.detail,
              height: 180,
              elements: <ReportElement>[
                ChartElement(
                  id: 'pieChart',
                  bounds: JetRect(x: 50, y: 0, width: 400, height: 175),
                  chartType: ChartType.pie,
                  collectionField: 'months',
                  valueExpression: r'$F{revenue}',
                  categoryExpression: r'$F{month}',
                  title: 'Revenue Share (Pie)',
                  showAxes: false,
                  showValueLabels: true,
                  showLegend: true,
                ),
              ],
            )),
          ],
        ),
      ),
    );

JetDataSource _dataSource() => JetInMemoryDataSource(
      <Map<String, Object?>>[
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
      ],
      fields: const <FieldDef>[
        FieldDef('months', type: JetFieldType.collection, fields: <FieldDef>[
          FieldDef('month', type: JetFieldType.string),
          FieldDef('revenue', type: JetFieldType.double),
          FieldDef('units', type: JetFieldType.integer),
        ]),
      ],
    );

RenderedReport _report() => const JetReportEngine().renderDefinition(
      _definition(),
      _dataSource(),
    );

// ---------------------------------------------------------------------------
// Preview golden helper
// ---------------------------------------------------------------------------

Future<void> _pump(WidgetTester tester, ThemeMode mode) async {
  await tester.binding.setSurfaceSize(const Size(600, 840));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    themeMode: mode,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadSlateColorScheme.light(),
    ),
    darkTheme: ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadSlateColorScheme.dark(),
    ),
    home: JetReportPreview(report: _report()),
  ));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// PNG decode helper
// ---------------------------------------------------------------------------

Future<ui.Image> _decodeUi(Uint8List png) async {
  final ui.Codec codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chart preview light golden', (WidgetTester tester) async {
    await _pump(tester, ThemeMode.light);
    await expectLater(
      find.byType(JetReportPreview),
      matchesGoldenFile('../goldens/chart_preview_light.png'),
    );
  });

  test('chart page 1 raster (PNG) export golden', () async {
    final RenderedReport report = _report();
    const JetReportExporter exporter = JetReportExporter();
    final Uint8List png = await exporter.pageToPng(report, 0, scale: 2);
    final ui.Image image = await _decodeUi(png);
    await expectLater(
      image,
      matchesGoldenFile('../goldens/chart_pdf_page1_2x.png'),
    );
  }, tags: 'golden');
}
