// Shared pump for the preview localization tests (011 — C11 / FR-017).
//
// German and Turkish each get their OWN test file (the designer localization
// precedent): switching between two non-English locales within a single test
// isolate can leave the later tree unbuilt — a framework quirk unrelated to
// the library; every locale renders correctly on its own and in the real app.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A two-page rendered report built through the public API only.
RenderedReport previewLocalizationReport() =>
    const JetReportEngine().renderDefinition(
      const ReportDefinition(
        name: 'l10n',
        page:
            PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10)),
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(
                id: 'root/c0',
                type: BandType.detail,
                height: 30,
                elements: <ReportElement>[
                  TextElement(
                    id: 'name',
                    bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
                    text: 'name',
                    expression: r'$F{name}',
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < 4; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

/// Pumps a [JetReportPreview] under [locale], wiring only the library's own
/// synchronous localization delegate (the designer harness precedent).
/// [withActions] wires no-op export/print callbacks so the 012 toolbar
/// actions render and their localized names can be asserted.
Future<void> pumpLocalizedPreview(
  WidgetTester tester,
  Locale locale, {
  bool withActions = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: JetReportPreview(
      report: previewLocalizationReport(),
      onExportPdf: withActions ? () {} : null,
      onPrint: withActions ? () {} : null,
    ),
  ));
  await tester.pumpAndSettle();
}
