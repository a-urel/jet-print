// Margin preset recognition unit tests (018 / US2 / contracts §C2).
//
// White-box: recognizeMargin is a pure, un-exported designer helper (the
// `format_presets.dart` precedent), recorded in the encapsulation allowlist. A
// margin preset is recognized only when all four sides are equal (within
// whole-point rounding) and match a preset value; any unevenness reports Custom.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/margin_presets.dart';
import 'package:jet_print/src/domain/geometry.dart';

void main() {
  group('recognizeMargin', () {
    test('four equal sides at a preset value name that preset (C2.3)', () {
      for (final MarginPreset preset in kMarginPresets) {
        final MarginMatch m = recognizeMargin(JetEdgeInsets.all(preset.value));
        expect(m.kind, preset.kind, reason: '${preset.kind}');
        expect(m.isCustom, isFalse);
      }
    });

    test('whole-point-rounded Normal (all 28) still names Normal', () {
      expect(recognizeMargin(const JetEdgeInsets.all(28)).kind,
          MarginPresetKind.normal);
    });

    test('uneven sides report Custom (C2.3)', () {
      final MarginMatch m = recognizeMargin(const JetEdgeInsets(
          left: 50, top: 28.35, right: 28.35, bottom: 28.35));
      expect(m.isCustom, isTrue);
      expect(m.kind, isNull);
    });

    test('four equal sides at a non-preset value report Custom', () {
      expect(recognizeMargin(const JetEdgeInsets.all(99)).isCustom, isTrue);
    });
  });
}
