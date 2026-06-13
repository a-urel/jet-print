// test/rendering/text/ui_font_family_test.dart
//
// The engine font-family naming convention shared by the canvas painter
// (which loads variant bytes under these names) and the designer's family
// picker (whose option previews fall back to them).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/text/ui_font_family.dart';

void main() {
  group('uiFontFamily', () {
    test('mangles (family, weight, italic) into a unique engine name', () {
      expect(uiFontFamily('Default', JetFontWeight.normal, false),
          'Default__normal');
      expect(
          uiFontFamily('Default', JetFontWeight.bold, false), 'Default__bold');
      expect(uiFontFamily('Default', JetFontWeight.normal, true),
          'Default__normal_italic');
      expect(uiFontFamily('Roboto', JetFontWeight.bold, true),
          'Roboto__bold_italic');
    });
  });
}
