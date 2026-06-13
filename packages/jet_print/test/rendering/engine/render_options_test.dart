// RenderOptions.fonts default (022 — contract C7; T007).
//
// The host-fonts field defaults to an empty const list, so every pre-feature
// `render(template, source)` call behaves exactly as before (SC-005).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/text/jet_font.dart';

void main() {
  test('RenderOptions().fonts defaults to const []', () {
    const RenderOptions options = RenderOptions();
    expect(options.fonts, isEmpty);
    expect(options.fonts, same(const <JetFontFamily>[]));
  });

  test('the other defaults are unchanged alongside the new field', () {
    const RenderOptions options = RenderOptions();
    expect(options.parameters, isEmpty);
    expect(options.locale.languageCode, 'en');
    expect(options.knownFields, isNull);
    expect(options.unresolvedFieldToken, '#ERROR');
  });
}
