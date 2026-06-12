// Data-filled invoice golden (011 — contracts C2/C6 / SC-003; Constitution IV).
//
// Closes the golden the 009 plan deferred to "the render slice": the invoice
// with REAL VALUES (master fields + iterated line items + total), paginated,
// shown in JetReportPreview — light and dark — through the shared
// paintFrame -> CanvasPainter pipeline. The preview sheet is white in light mode
// and a slight gray (slate-200) in dark mode so it does not glare; the dark
// print content stays legible on it (the exported artifact is always white).
// Public API only; regenerate with `--update-goldens`.
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

ReportTemplate _template() => const ReportTemplate(
      name: 'Invoice',
      page: PageFormat(width: 400, height: 300, margins: JetEdgeInsets.all(16)),
      bands: <ReportBand>[
        ReportBand(
          type: BandType.title,
          height: 28,
          elements: <ReportElement>[
            TextElement(
              id: 'title',
              bounds: JetRect(x: 0, y: 0, width: 160, height: 24),
              text: 'INVOICE',
              style: JetTextStyle(fontSize: 18, weight: JetFontWeight.bold),
            ),
          ],
        ),
        // Master fields live in a master-scope DETAIL band: title/summary
        // have no row context by design (007b §5).
        ReportBand(
          type: BandType.detail,
          height: 36,
          elements: <ReportElement>[
            TextElement(
              id: 'invoiceNo',
              bounds: JetRect(x: 220, y: 2, width: 148, height: 14),
              text: 'invoiceNo',
              style: JetTextStyle(align: JetTextAlign.right),
              expression: r'$F{invoiceNo}',
            ),
            TextElement(
              id: 'customer',
              bounds: JetRect(x: 0, y: 2, width: 220, height: 14),
              text: 'customer',
              expression: r'$F{customerName}',
            ),
          ],
        ),
        ReportBand(
          type: BandType.detail,
          height: 18,
          collectionField: 'lines',
          elements: <ReportElement>[
            TextElement(
              id: 'desc',
              bounds: JetRect(x: 0, y: 1, width: 180, height: 14),
              text: 'desc',
              expression: r'$F{description}',
            ),
            TextElement(
              id: 'qty',
              bounds: JetRect(x: 190, y: 1, width: 40, height: 14),
              text: 'qty',
              style: JetTextStyle(align: JetTextAlign.right),
              expression: r'$F{qty}',
            ),
            TextElement(
              id: 'lineTotal',
              bounds: JetRect(x: 240, y: 1, width: 128, height: 14),
              text: 'lineTotal',
              style: JetTextStyle(align: JetTextAlign.right),
              expression: r'FORMAT($F{qty} * $F{unitPrice}, "#,##0.00")',
            ),
          ],
        ),
        ReportBand(
          type: BandType.detail,
          height: 30,
          elements: <ReportElement>[
            TextElement(
              id: 'totalLabel',
              bounds: JetRect(x: 190, y: 8, width: 40, height: 14),
              text: 'Total',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
            ),
            TextElement(
              id: 'total',
              bounds: JetRect(x: 240, y: 8, width: 128, height: 14),
              text: 'total',
              style: JetTextStyle(
                  align: JetTextAlign.right, weight: JetFontWeight.bold),
              expression: r'FORMAT($F{total}, "#,##0.00")',
            ),
          ],
        ),
        ReportBand(
          type: BandType.pageFooter,
          height: 16,
          elements: <ReportElement>[
            TextElement(
              id: 'pf',
              bounds: JetRect(x: 0, y: 1, width: 368, height: 12),
              text: '',
              style: JetTextStyle(fontSize: 9, align: JetTextAlign.center),
              expression:
                  r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ],
    );

/// Twelve lines on a 300pt page -> the invoice paginates onto two pages.
RenderedReport _report() => const JetReportEngine().render(
      _template(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'invoiceNo': 'INV-1042',
          'customerName': 'Acme GmbH',
          'total': 318.0,
          'lines': <Map<String, Object?>>[
            for (int i = 1; i <= 12; i++)
              <String, Object?>{
                'description': 'Line item $i',
                'qty': i,
                'unitPrice': 4.0,
              },
          ],
        },
      ]),
    );

Future<void> _pump(
  WidgetTester tester,
  ThemeMode mode, {
  int initialPage = 0,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 560));
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
    home: JetReportPreview(report: _report(), initialPage: initialPage),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rendered invoice page 1 matches its light golden', (
    WidgetTester tester,
  ) async {
    await _pump(tester, ThemeMode.light);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    await expectLater(
      find.byType(JetReportPreview),
      matchesGoldenFile('rendered_invoice_light.png'),
    );
  });

  testWidgets('rendered invoice page 1 matches its dark golden', (
    WidgetTester tester,
  ) async {
    await _pump(tester, ThemeMode.dark);
    await expectLater(
      find.byType(JetReportPreview),
      matchesGoldenFile('rendered_invoice_dark.png'),
    );
  });

  testWidgets('rendered invoice page 2 matches its light golden (pagination)',
      (WidgetTester tester) async {
    await _pump(tester, ThemeMode.light, initialPage: 1);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await expectLater(
      find.byType(JetReportPreview),
      matchesGoldenFile('rendered_invoice_page2_light.png'),
    );
  });
}
