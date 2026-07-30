// White-box unit test for the shared preview paper-sheet colour: the main page
// surface and every thumbnail must agree, in both brightnesses.
@TestOn('vm')
library;

import 'dart:ui' show Brightness, Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/preview/preview_sheet.dart';

void main() {
  test('light mode sheets are pure white', () {
    expect(previewSheetColor(Brightness.light), const Color(0xFFFFFFFF));
  });

  test('dark mode sheets are slate-200, not white', () {
    expect(previewSheetColor(Brightness.dark), const Color(0xFFE2E8F0));
  });
}
