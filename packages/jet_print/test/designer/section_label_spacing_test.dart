// Pins the property-section caption's compact gap to its input. The section
// label's bottom padding is the sole spacer between a caption (e.g. "POSITION")
// and the field beneath it, so this guards the dense-inspector look against
// regressions. Driven through the public designer (no src/ reach-in), measured
// by the rendered Padding geometry.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

void main() {
  testWidgets('a section caption sits in a compact gap above its input',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    // A selected element makes the inspector show the POSITION/SIZE sections.
    c.createElement(DesignerToolType.text,
        bandId: firstDetailBandId(c), at: const JetOffset(20, 30));
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    final JetPrintLocalizations l10n = JetPrintLocalizations.of(
      tester.element(find.byType(JetReportDesigner)),
    );
    // The caption is upper-cased by the section-label widget.
    final Finder caption = find.text(l10n.propertiesPosition.toUpperCase());
    expect(caption, findsOneWidget);

    final Padding labelPad = tester.widget<Padding>(
      find.ancestor(of: caption, matching: find.byType(Padding)).first,
    );
    expect((labelPad.padding as EdgeInsets).bottom, 4,
        reason: 'the caption sits close to its input (compact inspector)');
  });
}
