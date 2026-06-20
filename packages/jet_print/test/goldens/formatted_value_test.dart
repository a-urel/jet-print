// Formatted-value golden (013 / T032; Constitution IV — WYSIWYG).
//
// A label bound to a numeric / date field with the new `format` property renders
// the formatted value through the SAME engine -> paintFrame -> CanvasPainter
// pipeline the preview uses — proving the format property is WYSIWYG, not a
// parallel path. Public API only; regenerate with `--update-goldens`.
@Tags(['golden'])
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

ReportDefinition _definition() => const ReportDefinition(
      name: 'Formatted',
      page: PageFormat(width: 240, height: 120, margins: JetEdgeInsets.all(16)),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 80,
              elements: <ReportElement>[
                // Raw (no format) for contrast: prints the bare double "1234.5".
                TextElement(
                  id: 'raw',
                  bounds: JetRect(x: 0, y: 0, width: 208, height: 16),
                  text: 'raw',
                  expression: r'$F{amount}',
                ),
                // Number format property → "1,234.50".
                TextElement(
                  id: 'amount',
                  bounds: JetRect(x: 0, y: 22, width: 208, height: 16),
                  text: 'amount',
                  expression: r'$F{amount}',
                  format: '#,##0.00',
                ),
                // Date format property → "2026-06-11".
                TextElement(
                  id: 'when',
                  bounds: JetRect(x: 0, y: 44, width: 208, height: 16),
                  text: 'when',
                  expression: r'$F{when}',
                  format: 'yyyy-MM-dd',
                ),
              ],
            )),
          ],
        ),
      ),
    );

RenderedReport _report() => JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'amount': 1234.5, 'when': DateTime(2026, 6, 11)},
      ]),
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 360));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    themeMode: ThemeMode.light,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadSlateColorScheme.light(),
    ),
    home: JetReportPreview(report: _report()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // Date formatting needs the locale's symbols initialized — the host's job
  // (documented on RenderOptions.locale / FORMAT); the golden does it once.
  setUpAll(() async => initializeDateFormatting());

  testWidgets('the format property renders formatted values in the preview', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await expectLater(
      find.byType(JetReportPreview),
      matchesGoldenFile('formatted_value_light.png'),
    );
  });
}
