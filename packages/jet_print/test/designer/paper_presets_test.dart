// Paper-size preset recognition unit tests (018 / US1 / contracts §C1).
//
// White-box: recognizePaper/applyPaper are pure, un-exported designer helpers
// (the `format_presets.dart` precedent), so their unit test reaches into `src/`
// — recorded in the encapsulation allowlist. Recognition names the live page by
// a standard size in EITHER orientation, tolerating whole-point rounding, and
// reports Custom otherwise — it never rewrites dimensions (display only).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/paper_presets.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';

PageFormat _page(double w, double h) =>
    PageFormat(width: w, height: h, margins: const JetEdgeInsets.all(28.35));

void main() {
  group('recognizePaper', () {
    test('names each standard size in both orientations (C1.5)', () {
      for (final PaperPreset preset in kPaperPresets) {
        final PaperMatch portrait =
            recognizePaper(_page(preset.portraitWidth, preset.portraitHeight));
        final PaperMatch landscape =
            recognizePaper(_page(preset.portraitHeight, preset.portraitWidth));
        expect(portrait.name, preset.name, reason: '${preset.name} portrait');
        expect(landscape.name, preset.name, reason: '${preset.name} landscape');
        expect(portrait.isCustom, isFalse);
        expect(landscape.isCustom, isFalse);
      }
    });

    test('A4 is in the preset set with the exact a4Portrait dimensions', () {
      final PaperMatch m = recognizePaper(PageFormat.a4Portrait);
      expect(m.name, 'A4');
    });

    test('a whole-point-rounded A4 (595 × 842) still names A4 (C1.4)', () {
      expect(recognizePaper(_page(595, 842)).name, 'A4');
    });

    test('a size matching no preset reports Custom, unaltered (C1.3)', () {
      final PageFormat custom = _page(500, 700);
      final PaperMatch m = recognizePaper(custom);
      expect(m.isCustom, isTrue);
      expect(m.name, isNull);
      // Recognition is display-only — it must not mutate the page.
      expect(custom.width, 500);
      expect(custom.height, 700);
    });

    test('a size near but beyond tolerance is Custom, not the neighbour', () {
      // 595.28 × 860 differs from A4 height by ~18pt → Custom.
      expect(recognizePaper(_page(595.28, 860)).isCustom, isTrue);
    });
  });

  group('applyPaper', () {
    test('builds the portrait size and preserves the given margins', () {
      final PaperPreset letter =
          kPaperPresets.firstWhere((PaperPreset p) => p.name == 'Letter');
      const JetEdgeInsets margins =
          JetEdgeInsets(left: 10, top: 20, right: 30, bottom: 40);
      final PageFormat page =
          applyPaper(letter, landscape: false, margins: margins);
      expect(page.width, 612);
      expect(page.height, 792);
      expect(page.margins, margins);
    });

    test('swaps width/height for landscape, preserving margins', () {
      final PaperPreset a4 =
          kPaperPresets.firstWhere((PaperPreset p) => p.name == 'A4');
      const JetEdgeInsets margins = JetEdgeInsets.all(14.17);
      final PageFormat page = applyPaper(a4, landscape: true, margins: margins);
      expect(page.width, closeTo(841.89, 1e-6));
      expect(page.height, closeTo(595.28, 1e-6));
      expect(page.margins, margins);
    });
  });
}
