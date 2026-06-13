// MeasuredText.fontFamily reports the resolved base family (007a / 006 amendment).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  test('measure reports the default family when the style names none', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final MetricsTextMeasurer m = MetricsTextMeasurer(reg);
    expect(m.measure('A', JetTextStyle.fallback).fontFamily, 'Default');
  });

  test('measure reports a registered custom family', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    reg.register(
        'Custom', reg.bytesFor(null)); // reuse default bytes under a new name
    final MetricsTextMeasurer m = MetricsTextMeasurer(reg);
    expect(
      m.measure('A', const JetTextStyle(fontFamily: 'Custom')).fontFamily,
      'Custom',
    );
  });

  test('an unregistered family falls back to the default family', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final MetricsTextMeasurer m = MetricsTextMeasurer(reg);
    expect(
      m.measure('A', const JetTextStyle(fontFamily: 'Nope')).fontFamily,
      'Default',
    );
  });
}
