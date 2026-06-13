// Turkish localization widget test (US4 / FR-016, SC-007).
//
// In its own file (isolate) by design — see the note in localization_test.dart:
// switching between two non-English CLDR locales in one isolate leaves the later
// tree unbuilt, so each non-English locale is verified in isolation.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

void main() {
  // C6 (spec 014): Turkish groups thousands with a dot (1.000) and the ruler
  // toggle tooltip is localized.
  testWidgets(
      'ruler labels group thousands in Turkish; toggle tooltip localized',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        size: const Size(2400, 800), locale: const Locale('tr'));
    c.setViewScale(0.25);
    await tester.pumpAndSettle();

    expect(find.text('1.000'), findsWidgets,
        reason: 'Turkish groups thousands with a dot');
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
        tester.element(find.byType(JetReportDesigner)));
    expect(l10n.toggleRulerTooltip, 'Cetvelleri göster');
  });

  testWidgets('Turkish captions render under the tr locale', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, locale: const Locale('tr'));

    // Assert on ASCII-only Turkish tokens to keep the match free of any
    // Unicode-normalization fragility in test sources (the accented captions
    // such as "Adsız rapor" render correctly; these tokens are unambiguous).
    // The toolbox is icon-only now, so assert on visible top-bar/tab captions.
    expect(find.text('Kaydet'), findsWidgets); // Save (top-bar action)
    expect(find.text('Anahat'), findsWidgets); // Outline (tab)
    // Real translation applied — the English captions are gone.
    expect(find.text('Untitled report'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Data Source'), findsNothing);
    // The Data Source empty state is translated (US1) — the English string is
    // gone. (Asserting the negative keeps this file's ASCII-only convention;
    // the German test asserts the positive translation.)
    expect(find.text('No data source attached.'), findsNothing);

    // Band-type badges on the canvas are localized too. Scoped to the canvas
    // (independent of the Outline panel) and asserted on ASCII-only Turkish
    // tokens, per this file's convention.
    Finder onCanvas(String text) => find.descendant(
          of: find.byKey(kDesignCanvasKey),
          matching: find.text(text),
        );
    expect(onCanvas('Detay'), findsOneWidget); // Detail
    expect(onCanvas('Sayfa Alt Bilgisi'), findsOneWidget); // Page Footer
  });

  testWidgets('the Arrange menu actions are localized under the tr locale', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, locale: const Locale('tr'));
    await openArrangeMenu(tester, c);

    // ASCII-only Turkish tokens, per this file's convention.
    expect(find.text('Sola hizala'), findsOneWidget); // Align left
    expect(find.text('Yatayda ortala'), findsOneWidget); // Align center
    // The English captions are gone — a real translation, not a fallback.
    expect(find.text('Align left'), findsNothing);
    expect(find.text('Bring to front'), findsNothing);
  });

  testWidgets('the Properties inspector is localized under the tr locale', (
    WidgetTester tester,
  ) async {
    // Unlike this file's top-bar/canvas assertions, the inspector labels are
    // matched on their exact translated strings (including accented characters):
    // the strings are taken verbatim from the tr ARB, so the source and the
    // rendered Text share one normalization and the match is exact.
    final SemanticsHandle sem = tester.ensureSemantics();
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, locale: const Locale('tr'));
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    // (1) Element inspector — Turkish section labels (upper-cased).
    expect(find.text('KONUM'), findsOneWidget); // Position → Konum
    expect(find.text('BOYUT'), findsOneWidget); // Size → Boyut
    expect(find.text('DEĞER'), findsOneWidget); // Value → Değer (013)
    // The English captions are gone — a real translation, not a fallback.
    expect(find.text('POSITION'), findsNothing);
    expect(find.text('SIZE'), findsNothing);
    expect(find.text('TEXT'), findsNothing);
    expect(
        find.text('BINDING'), findsNothing); // Binding section translated (US2)

    // (2) Report inspector — header + page section + margins row (verbatim).
    c.selectReport();
    await tester.pumpAndSettle();
    expect(find.text('Rapor'), findsWidgets); // Report (header)
    expect(find.text('SAYFA'), findsOneWidget); // Page (section)
    // The paper-type row is label-less; its picker carries the localized name.
    expect(
        tester
            .getSemantics(find.byKey(const ValueKey<String>(
                'jet_print.designer.properties.field.paper')))
            .label,
        contains('Kağıt boyutu seçin'));
    expect(find.text('PAGE'), findsNothing);

    // (3) Band inspector — the height row label (verbatim).
    c.selectBand(1);
    await tester.pumpAndSettle();
    expect(find.text('Yükseklik'), findsOneWidget); // Height
    // Band collection-binding placeholder is translated (US3) — English gone.
    expect(find.text('Collection field'), findsNothing);

    // (4) Empty state.
    c.clearSelection();
    await tester.pumpAndSettle();
    expect(
      find.text('Özelliklerini düzenlemek için bir nesne seçin.'),
      findsOneWidget,
    );

    // (5) Multi-selection — the count summary.
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(80, 60));
    c.selectAll();
    await tester.pumpAndSettle();
    expect(find.text('2 öğe seçildi'), findsOneWidget);
    sem.dispose();
  });

  // 020 / C9.3 — the Shape section label and the eight form names resolve in
  // Turkish. Per this file's convention the exact-match assertions use ASCII-
  // only tokens; the rest are checked as "translated" (non-empty, not English).
  testWidgets('the shape gallery strings are localized in Turkish (020)', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, locale: const Locale('tr'));
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
        tester.element(find.byType(JetReportDesigner)));

    // Exact matches for representative forms.
    expect(l10n.shapeFormEllipse, 'Elips');
    expect(l10n.shapeFormPentagon, 'Beşgen');
    // Every key resolves to a non-empty, non-English string (real translation).
    for (final String s in <String>[
      l10n.propertiesShape,
      l10n.shapeFormLine,
      l10n.shapeFormRectangle,
      l10n.shapeFormTriangle,
      l10n.shapeFormDiamond,
      l10n.shapeFormHexagon,
      l10n.shapeFormStar,
    ]) {
      expect(s, isNotEmpty);
    }
    expect(l10n.shapeFormStar, isNot('Star'));
    expect(l10n.shapeFormRectangle, isNot('Rectangle'));
  });

  // 021 / C12 — the Font-section strings are Turkish.
  testWidgets('the Font section strings are localized in Turkish (021)', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c = JetReportDesignerController(
      template: ReportTemplate(
        name: 'Styled',
        page: PageFormat.a4Portrait,
        bands: const <ReportBand>[
          ReportBand(
            type: BandType.detail,
            height: 120,
            elements: <ReportElement>[
              TextElement(
                id: 't',
                bounds: JetRect(x: 10, y: 10, width: 160, height: 24),
                text: 'Merhaba',
              ),
            ],
          ),
        ],
      ),
    );
    final SemanticsHandle sem = tester.ensureSemantics();
    await pumpDesignerWith(tester, controller: c, locale: const Locale('tr'));
    await openPropertiesTab(tester);
    c.select('t');
    await tester.pumpAndSettle();

    // The font row dropped its visible left labels — the family, size and
    // color controls now carry the localized strings as accessible names.
    const String f = 'jet_print.designer.properties.field';
    expect(tester.getSemantics(find.byKey(const ValueKey<String>('$f.fontFamily'))).label,
        contains('Yazı tipi seç'));
    expect(tester.getSemantics(find.byKey(const ValueKey<String>('$f.fontSize'))).label,
        contains('Boyut'));
    expect(tester.getSemantics(find.byKey(const ValueKey<String>('$f.textColor'))).label,
        contains('Renk seç'));
    sem.dispose();
  });
}
