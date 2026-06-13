import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

void main() {
  test('GoogleFontEntry exposes name, license, and face asset keys', () {
    const GoogleFontEntry entry = GoogleFontEntry(
      name: 'Noto Sans',
      license: 'OFL-1.1',
      faceAssets: <FontFaceSlot, String>{
        (
          weight: JetFontWeight.normal,
          italic: false
        ): 'packages/jet_print_google_fonts/assets/fonts/Noto Sans/NotoSans-Regular.ttf',
      },
    );
    expect(entry.name, 'Noto Sans');
    expect(entry.license, 'OFL-1.1');
    expect(entry.faceAssets, hasLength(1));
    expect(
      entry.faceAssets[(weight: JetFontWeight.normal, italic: false)],
      contains('NotoSans-Regular.ttf'),
    );
  });
}
