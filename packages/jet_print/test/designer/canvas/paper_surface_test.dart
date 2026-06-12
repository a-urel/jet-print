// The design surface represents a sheet of printed paper. In light mode it is
// pure white; in dark mode it is a slight gray (slate-200) so the sheet does not
// glare against the dark canvas while dark print content stays legible. (The
// actual exported/printed artifact is always white — that is the render
// pipeline, not this design-time chrome.)
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/designer_harness.dart';

Color _pageColor(WidgetTester tester) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find.byKey(kDesignPageKey),
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('the page is white in light mode', (WidgetTester tester) async {
    await pumpDesigner(tester);
    expect(_pageColor(tester), const Color(0xFFFFFFFF));
  });

  testWidgets('the page is a slight gray (slate-200) in dark mode', (
    WidgetTester tester,
  ) async {
    await pumpDesigner(tester, themeMode: ThemeMode.dark);
    expect(_pageColor(tester), const Color(0xFFE2E8F0));
  });
}
