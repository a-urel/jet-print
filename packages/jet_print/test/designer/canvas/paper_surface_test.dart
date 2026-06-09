// The design surface represents a sheet of printed paper, so it MUST stay white
// in every theme — the report content is emitted with print colors (e.g. dark
// text) that only read correctly on white, so a theme-tinted (dark) page would
// look wrong and hide content. Drives the public designer only.
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

  testWidgets('the page stays white in dark mode', (WidgetTester tester) async {
    await pumpDesigner(tester, themeMode: ThemeMode.dark);
    expect(_pageColor(tester), const Color(0xFFFFFFFF));
  });
}
