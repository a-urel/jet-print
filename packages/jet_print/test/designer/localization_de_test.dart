// German localization widget test (US4 / FR-016, SC-007).
//
// In its own file (isolate) by design — see the note in localization_test.dart:
// switching between two non-English CLDR locales in one isolate leaves the later
// tree unbuilt, so each non-English locale is verified in isolation.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

void main() {
  // C6 (spec 014): German groups thousands with a dot (1.000) and the ruler
  // toggle tooltip is localized.
  testWidgets(
      'ruler labels group thousands in German; toggle tooltip localized',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        size: const Size(2400, 800), locale: const Locale('de'));
    c.setViewScale(0.25);
    await tester.pumpAndSettle();

    expect(find.text('1.000'), findsWidgets,
        reason: 'German groups thousands with a dot');
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
        tester.element(find.byType(JetReportDesigner)));
    expect(l10n.toggleRulerTooltip, 'Lineale anzeigen');
  });

  testWidgets('German captions render under the de locale', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, locale: const Locale('de'));

    expect(find.text('Unbenannter Bericht'), findsOneWidget);
    expect(find.text('Vorschau'), findsOneWidget); // Preview (top-bar action)
    expect(find.text('Datenquelle'), findsWidgets); // tab + panel header
    // Data Source panel empty state (no schema attached) is localized (US1).
    expect(find.text('Keine Datenquelle verbunden.'), findsOneWidget);
    // Real translation applied — the English captions are gone, not merely
    // falling back everywhere.
    expect(find.text('Untitled report'), findsNothing);
    expect(find.text('Data Source'), findsNothing);
    expect(find.text('No data source attached.'), findsNothing);

    // Band-type badges on the canvas are localized too (scoped to the canvas so
    // the match is independent of the Outline panel's band names).
    Finder onCanvas(String text) => find.descendant(
          of: find.byKey(kDesignCanvasKey),
          matching: find.text(text),
        );
    expect(onCanvas('Seitenkopf'), findsOneWidget); // Page Header
    expect(onCanvas('Seitenfuß'), findsOneWidget); // Page Footer

    // German has the longest chrome captions; the layout must accommodate them
    // (wrap/ellipsize) without clipping adjacent controls — no overflow recorded
    // (longer-text edge case / T037).
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Arrange menu actions are localized under the de locale', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, locale: const Locale('de'));
    await openArrangeMenu(tester, c);

    expect(find.text('Linksbündig ausrichten'), findsOneWidget); // Align left
    expect(find.text('Vertikal verteilen'), findsOneWidget); // Distribute vert.
    expect(find.text('In den Vordergrund'), findsOneWidget); // Bring to front
    // The English captions are gone — a real translation, not a fallback.
    expect(find.text('Align left'), findsNothing);
    expect(find.text('Bring to front'), findsNothing);
  });

  testWidgets('the Properties inspector is localized under the de locale', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, locale: const Locale('de'));
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    // (1) Element inspector — German section label (upper-cased: ß is preserved).
    expect(find.text('GRÖßE'), findsOneWidget); // Size → Größe
    expect(find.text('SIZE'), findsNothing); // real translation, not a fallback
    expect(find.text('WERT'), findsOneWidget); // Value → Wert (013)
    expect(find.text('VALUE'), findsNothing);

    // (2) Report inspector — header + page section + margins row (verbatim).
    c.selectReport();
    await tester.pumpAndSettle();
    expect(find.text('Bericht'), findsWidgets); // Report (header)
    expect(find.text('SEITE'), findsOneWidget); // Page (section)
    expect(find.text('Papier'), findsOneWidget); // Paper row (018)
    expect(find.text('PAGE'), findsNothing);
    expect(find.text('Report'), findsNothing);

    // (3) Band inspector — the height row label (verbatim).
    c.selectBand(1);
    await tester.pumpAndSettle();
    expect(find.text('Höhe'), findsOneWidget); // Height
    expect(find.text('Height'), findsNothing);
    // Band master/detail collection-binding placeholder (US3).
    expect(find.text('Sammlungsfeld'), findsOneWidget); // Collection field
    expect(find.text('Collection field'), findsNothing);

    // (4) Empty state.
    c.clearSelection();
    await tester.pumpAndSettle();
    expect(
      find.text('Wählen Sie ein Objekt, um seine Eigenschaften zu bearbeiten.'),
      findsOneWidget,
    );

    // (5) Multi-selection — the count summary.
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(80, 60));
    c.selectAll();
    await tester.pumpAndSettle();
    expect(find.text('2 Elemente ausgewählt'), findsOneWidget);
  });

  // 020 / C9.3 — the Shape section label and the eight form names are German.
  testWidgets('the shape gallery strings are localized in German (020)', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, locale: const Locale('de'));
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
        tester.element(find.byType(JetReportDesigner)));

    expect(l10n.propertiesShape, 'Form');
    expect(l10n.shapeFormLine, 'Linie');
    expect(l10n.shapeFormRectangle, 'Rechteck');
    expect(l10n.shapeFormEllipse, 'Ellipse');
    expect(l10n.shapeFormTriangle, 'Dreieck');
    expect(l10n.shapeFormDiamond, 'Raute');
    expect(l10n.shapeFormPentagon, 'Fünfeck');
    expect(l10n.shapeFormHexagon, 'Sechseck');
    expect(l10n.shapeFormStar, 'Stern');
  });
}
