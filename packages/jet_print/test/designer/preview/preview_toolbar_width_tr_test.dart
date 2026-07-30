// Toolbar wide-branch width — Turkish (044 toolbar-width fix, round 2). One
// isolate per non-English locale (see preview_toolbar_width_support.dart).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preview_toolbar_width_support.dart';

void main() {
  testWidgets(
      'Turkish: content width 920px does not overflow the toolbar '
      '(not a proven danger zone — no overflow was found scanning down to '
      '834px content width — kept for symmetry with the German pin)',
      (WidgetTester tester) async {
    await expectNoToolbarOverflow(
      tester,
      locale: const Locale('tr'),
      windowWidth: 936,
    );
  });

  testWidgets(
      'Turkish: the wide (non-scrolling) toolbar branch fits at and above '
      'the shipped 960px threshold', (WidgetTester tester) async {
    // 976 -> content 960, exactly at the threshold; 981 -> content 965, just
    // above it; 1016 -> content 1000, comfortably above.
    for (final double windowWidth in <double>[976, 981, 1016]) {
      await expectNoToolbarOverflow(
        tester,
        locale: const Locale('tr'),
        windowWidth: windowWidth,
      );
    }
  });
}
