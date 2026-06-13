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
      expect(uiFontFamily('JetSans', JetFontWeight.normal, false),
          'JetSans__normal');
      expect(
          uiFontFamily('JetSans', JetFontWeight.bold, false), 'JetSans__bold');
      expect(uiFontFamily('JetSans', JetFontWeight.normal, true),
          'JetSans__normal_italic');
      expect(uiFontFamily('JetSerif', JetFontWeight.bold, true),
          'JetSerif__bold_italic');
    });
  });
}
