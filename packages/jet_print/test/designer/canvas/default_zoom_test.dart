// Default-zoom behaviour for the designer canvas: a desktop-class page area
// opens at 100% (actual size); a phone-class one keeps the fit-to-width default.
// Black-box via the public designer; the decision is keyed on the live canvas
// viewport width (which `setSurfaceSize` drives), not MediaQuery.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

void main() {
  testWidgets('a desktop-class viewport opens the canvas at 100%',
      (WidgetTester tester) async {
    // pinFitWidth: false → observe the raw default instead of the harness's
    // fit-width pin.
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, pinFitWidth: false);
    expect(c.viewFitMode, JetViewFitMode.none,
        reason: 'desktop default is 100% (no sticky fit)');
    expect(c.viewScale, 1.0);
  });

  testWidgets('a phone-class viewport keeps the fit-to-width default',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(
      tester,
      size: const Size(420, 800),
      pinFitWidth: false,
    );
    expect(c.viewFitMode, JetViewFitMode.width,
        reason: 'a phone-class page area keeps fit-to-width');
  });
}
