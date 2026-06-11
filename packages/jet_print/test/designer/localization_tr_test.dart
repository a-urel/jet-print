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
    expect(find.text('Kenar boşlukları'), findsOneWidget); // Margins (row)
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
  });
}
