// At a phone width the designer lays out in the narrow (rail) layout WITHOUT
// falling back to the 600px horizontal-scroll shell.
//
// Task 8 — E5 Phase 3: lower _minShellWidth to 360 so a ~390pt phone authors
// in the real narrow (rail) layout rather than a horizontally-scrolling shell.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/designer_harness.dart';

void main() {
  testWidgets('a 390pt-wide designer does not horizontally scroll the shell',
      (tester) async {
    // Phone width (390 × 844 logical pixels, dpr=1 → same as physical).
    await pumpDesigner(tester, size: const Size(390, 844));

    // The horizontal-scroll fallback only mounts below _minShellWidth; at 390pt
    // it must NOT be present (the narrow rail layout absorbs the width instead).
    expect(
      find.byKey(const ValueKey<String>('jet_print.designer.shellHScroll')),
      findsNothing,
    );
    // The collapsed right-panel rail IS present (narrow layout is active).
    expect(find.byKey(kRightPanelRailKey), findsOneWidget);
  });
}
