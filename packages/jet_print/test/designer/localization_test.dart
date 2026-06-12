// Localization widget test — English + fallback (US4 / FR-016/017, SC-007).
//
// Asserts the default English chrome and the fallback behavior for an
// unsupported locale. German and Turkish each get their OWN test file
// (localization_de_test.dart / localization_tr_test.dart) on purpose: Flutter's
// Global localizations load some locales' CLDR data through process-global async
// state, and switching between two such non-English locales within a single test
// isolate leaves the later tree unbuilt (a framework quirk — every locale
// renders correctly on its own and in the real app). One isolate per non-English
// locale sidesteps it entirely.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

void main() {
  // C6 (spec 014): ruler mm labels follow the active locale's number grouping,
  // and the ruler toggle tooltip resolves via the existing key.
  testWidgets(
      'ruler labels group thousands in English; toggle tooltip localized',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        size: const Size(2400, 800), locale: const Locale('en'));
    c.setViewScale(0.25); // zoom out so the strip reaches 1,000 mm
    await tester.pumpAndSettle();

    expect(find.text('1,000'), findsWidgets,
        reason: 'English groups thousands with a comma');
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
        tester.element(find.byType(JetReportDesigner)));
    expect(l10n.toggleRulerTooltip, 'Show rulers');
  });

  testWidgets('an unsupported locale falls back to the English ruler tooltip',
      (WidgetTester tester) async {
    await pumpDesigner(tester, locale: const Locale('fr'));
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
        tester.element(find.byType(JetReportDesigner)));
    expect(l10n.toggleRulerTooltip, 'Show rulers');
  });

  testWidgets('English captions render (default locale)', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, locale: const Locale('en'));

    expect(find.text('Untitled report'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget); // top-bar action
    expect(find.text('Data Source'), findsWidgets); // tab + panel header
  });

  testWidgets('an unsupported locale falls back to English (FR-017)', (
    WidgetTester tester,
  ) async {
    // French is not shipped; Flutter resolves it to the first supported locale,
    // which is English — never a blank or a raw key.
    await pumpDesigner(tester, locale: const Locale('fr'));

    expect(find.text('Untitled report'), findsOneWidget);
    expect(find.text('Data Source'), findsWidgets);
    // No raw resource keys leak through.
    expect(find.text('reportTitlePlaceholder'), findsNothing);
    expect(find.text('tabDataSource'), findsNothing);
  });

  testWidgets('the Arrange menu actions are localized in English (SC-008)', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, locale: const Locale('en'));
    await openArrangeMenu(tester, c);

    expect(find.text('Align left'), findsOneWidget);
    expect(find.text('Distribute horizontally'), findsOneWidget);
    expect(find.text('Bring to front'), findsOneWidget);
    expect(find.text('Send to back'), findsOneWidget);
    // No raw resource keys leak through any new affordance.
    expect(find.text('arrangeAlignLeft'), findsNothing);
    expect(find.text('arrangeBringToFront'), findsNothing);
  });

  testWidgets(
      'the Properties inspector is localized in English across every state', (
    WidgetTester tester,
  ) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, locale: const Locale('en'));
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(20, 20));
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    // (1) Element inspector — section labels are upper-cased by SectionLabel.
    expect(find.text('POSITION'), findsOneWidget);
    expect(find.text('SIZE'), findsOneWidget);
    expect(find.text('VALUE'), findsOneWidget); // unified value field (013)
    expect(find.text('FORMAT'), findsOneWidget); // format property (013)
    // No raw resource keys leak through.
    expect(find.text('propertiesPosition'), findsNothing);
    expect(find.text('PROPERTIESPOSITION'), findsNothing);
    expect(find.text('propertiesValue'), findsNothing);

    // (2) Report inspector — page section label + verbatim header/margins rows.
    c.selectReport();
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsWidgets); // inspector header
    expect(find.text('PAGE'), findsOneWidget);
    expect(find.text('Paper'), findsOneWidget); // editable paper-type row (018)

    // (3) Band inspector — the height row label (rendered verbatim).
    c.selectBand(1);
    await tester.pumpAndSettle();
    expect(find.text('Height'), findsOneWidget);

    // (4) Empty state — nothing selected.
    c.clearSelection();
    await tester.pumpAndSettle();
    expect(
      find.text('Select an object to edit its properties.'),
      findsOneWidget,
    );

    // (5) Multi-selection — the count summary.
    c.createElement(DesignerToolType.text,
        bandIndex: 1, at: const JetOffset(80, 60));
    c.selectAll();
    await tester.pumpAndSettle();
    expect(find.text('2 elements selected'), findsOneWidget);
  });

  // 020 / C9.3 — the Shape section label and the eight form names resolve in
  // English (the de/tr variants are checked in their own isolate files).
  testWidgets('the shape gallery strings are localized in English (020)', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, locale: const Locale('en'));
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
        tester.element(find.byType(JetReportDesigner)));

    expect(l10n.propertiesShape, 'Shape');
    expect(l10n.shapeFormLine, 'Line');
    expect(l10n.shapeFormRectangle, 'Rectangle');
    expect(l10n.shapeFormEllipse, 'Ellipse');
    expect(l10n.shapeFormTriangle, 'Triangle');
    expect(l10n.shapeFormDiamond, 'Diamond');
    expect(l10n.shapeFormPentagon, 'Pentagon');
    expect(l10n.shapeFormHexagon, 'Hexagon');
    expect(l10n.shapeFormStar, 'Star');
  });
}
