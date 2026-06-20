// Rendered multi-column label sheet golden (spec 034). Public API only;
// regenerate with `--update-goldens`.
@Tags(['golden'])
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

ReportDefinition _definition() => const ReportDefinition(
      name: 'Labels',
      page: PageFormat(width: 400, height: 300, margins: JetEdgeInsets.all(16)),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'label',
              type: BandType.detail,
              height: 60,
              columnLayout: ColumnLayout(
                  columnCount: 2,
                  columnWidth: 170,
                  columnSpacing: 28,
                  rowSpacing: 12),
              elements: <ReportElement>[
                TextElement(
                  id: 'name',
                  bounds: JetRect(x: 6, y: 6, width: 158, height: 16),
                  text: 'name',
                  style: JetTextStyle(weight: JetFontWeight.bold),
                  expression: r'$F{name}',
                ),
                TextElement(
                  id: 'city',
                  bounds: JetRect(x: 6, y: 26, width: 158, height: 14),
                  text: 'city',
                  expression: r'$F{city}',
                ),
              ],
            )),
          ],
        ),
      ),
    );

RenderedReport _report() => const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 1; i <= 6; i++)
          <String, Object?>{'name': 'Contact $i', 'city': 'City $i'},
      ]),
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 480));
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
  testWidgets('rendered label sheet matches its light golden',
      (WidgetTester tester) async {
    await _pump(tester);
    await expectLater(
      find.byType(JetReportPreview),
      matchesGoldenFile('label_sheet_light.png'),
    );
  });
}
