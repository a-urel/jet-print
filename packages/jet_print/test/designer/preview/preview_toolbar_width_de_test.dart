// Toolbar wide-branch width — German (044 toolbar-width fix, round 2). One
// isolate per non-English locale (see preview_toolbar_width_support.dart).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'preview_toolbar_width_support.dart';

void main() {
  testWidgets(
      'German: content width 920px (the proven-unsafe round-1 threshold) '
      'does not overflow the toolbar', (WidgetTester tester) async {
    // Content 920px (window 936px) is the EXACT width that overflowed by 9px
    // when scrollWidth/compactWidth were 920 (this fix's round-1 value):
    // German's longer WorkspaceModeSwitch segment labels and its
    // always-visible "Seite X von Y" page indicator both need more room than
    // English, with a measured breakeven of 929px content width — content
    // 920px sits 9px inside that danger zone. This pins the regression a
    // reviewer found in round 1: if scrollWidth/compactWidth is ever reverted
    // to 920 (or anything below 929) without re-measuring German, this exact
    // test starts failing again with the same 9px overflow. It currently
    // passes only because 920 < the shipped 960 threshold, which keeps this
    // width in the scrolling branch (structurally overflow-proof) instead of
    // the wide one.
    await expectNoToolbarOverflow(
      tester,
      locale: const Locale('de'),
      windowWidth: 936,
    );
  });

  testWidgets(
      'German: the wide (non-scrolling) toolbar branch fits at and above '
      'the shipped 960px threshold', (WidgetTester tester) async {
    // 976 -> content 960, exactly at the threshold (the boundary the wide
    // branch is entered on); 981 -> content 965, just above it; 1016 ->
    // content 1000, comfortably above. German is the binding locale (929px
    // measured breakeven), so this is the tightest of the three per-locale
    // wide-branch checks.
    for (final double windowWidth in <double>[976, 981, 1016]) {
      await expectNoToolbarOverflow(
        tester,
        locale: const Locale('de'),
        windowWidth: windowWidth,
      );
    }
  });
}
