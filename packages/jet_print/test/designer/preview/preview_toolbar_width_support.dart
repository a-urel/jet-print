// Shared pump for the wide-toolbar-branch-across-locales tests (044 toolbar-
// width fix, round 2). German and Turkish each get their OWN test file (the
// preview_localization_de_test.dart / _tr_test.dart precedent — see
// preview_localization_support.dart): switching between two non-English
// locales within a single test isolate can leave the later tree unbuilt — a
// framework quirk unrelated to the library; every locale renders correctly on
// its own and in the real app.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ReportDefinition _definition() => const ReportDefinition(
      name: 'Quarterly Report',
      page: _page,
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
    );

/// A three-page report (6 rows, 2 per page) rendered via the public engine.
RenderedReport toolbarWidthReport() => const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < 6; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

/// Pumps a [JetReportPreview] under [locale] at a window [windowWidth] pixels
/// wide, with both artifact actions wired (the widest realistic action row —
/// export/print plus the 044 thumbnail toggle + its divider), and asserts the
/// toolbar does not overflow. Content width (what `UnifiedTopBar` actually
/// compares against its `scrollWidth`/`compactWidth` thresholds) is
/// `windowWidth` minus the bar's 16px horizontal padding.
Future<void> expectNoToolbarOverflow(
  WidgetTester tester, {
  required Locale locale,
  required double windowWidth,
}) async {
  await tester.binding.setSurfaceSize(Size(windowWidth, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: JetReportPreview(
      report: toolbarWidthReport(),
      onExportPdf: () {},
      onPrint: () {},
    ),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull,
      reason: 'locale ${locale.languageCode} at window ${windowWidth}px '
          '(content ${windowWidth - 16}px) should not overflow the toolbar');
}
