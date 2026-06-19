// Pins the property-section caption's compact gap to its input across panes.
// The section label's bottom padding is meant to be the SOLE spacer between a
// caption (e.g. "POSITION") and the field beneath it; no section may add an
// extra spacer on top. Driven through the public designer (no src/ reach-in),
// measured by rendered geometry, so it guards the dense-inspector look in every
// pane against regression.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

/// The gap between a section caption and the field directly below it: the
/// distance from the caption's bottom to the field's top, in logical pixels.
double _gap(WidgetTester tester, Finder caption, Finder field) =>
    tester.getRect(field).top - tester.getRect(caption).bottom;

JetPrintLocalizations _l10n(WidgetTester tester) => JetPrintLocalizations.of(
      tester.element(find.byType(JetReportDesigner)),
    );

void main() {
  // The compact label→input gap: SectionLabel's bottom padding alone. Every
  // pane must match this — no section adds a spacer on top of it.
  const double kCaptionGap = 4;

  testWidgets('the element pane caption sits in a compact gap above its input',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.createElement(DesignerToolType.text,
        bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    final Finder caption =
        find.text(_l10n(tester).propertiesPosition.toUpperCase());
    final Padding labelPad = tester.widget<Padding>(
      find.ancestor(of: caption, matching: find.byType(Padding)).first,
    );
    expect((labelPad.padding as EdgeInsets).bottom, kCaptionGap,
        reason: 'the shared caption spacer is compact');
  });

  testWidgets('every report-pane caption keeps the same compact gap',
      (WidgetTester tester) async {
    // Select the report → the Report properties pane (Name, Page, Margins).
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    await openPropertiesTab(tester);
    c.selectReport();
    await tester.pumpAndSettle();
    final JetPrintLocalizations l10n = _l10n(tester);

    Finder caption(String text) => find.text(text.toUpperCase());
    Finder field(String key) =>
        find.byKey(ValueKey<String>('jet_print.designer.properties.field.$key'));

    expect(_gap(tester, caption(l10n.propertiesName), field('reportName')),
        moreOrLessEquals(kCaptionGap, epsilon: 0.5),
        reason: 'NAME caption hugs its input (no extra spacer)');
    expect(_gap(tester, caption(l10n.propertiesPage), field('paper')),
        moreOrLessEquals(kCaptionGap, epsilon: 0.5),
        reason: 'PAGE caption hugs its picker');
    expect(
        _gap(tester, caption(l10n.propertiesMargins), field('marginPreset')),
        moreOrLessEquals(kCaptionGap, epsilon: 0.5),
        reason: 'MARGINS caption hugs its picker');
  });
}
