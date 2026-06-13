// test/designer/font_preload_test.dart
//
// The designer-mount preload that makes every registered family's picker
// preview render in its own typeface before the canvas has ever painted it.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/font_preload.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';

void main() {
  group('preloadUiFontFamilies', () {
    test('loads every family\'s regular face under its engine name', () async {
      final FontRegistry reg = FontRegistry()..registerDefault();
      final List<(Uint8List, String?)> loads = <(Uint8List, String?)>[];
      await preloadUiFontFamilies(
        reg,
        fontLoader: (Uint8List bytes, {String? fontFamily}) async =>
            loads.add((bytes, fontFamily)),
      );

      expect(loads.map(((Uint8List, String?) l) => l.$2),
          <String>['Default__normal']);
      for (final (Uint8List bytes, String? name) in loads) {
        final String family = name!.substring(0, name.indexOf('__'));
        expect(identical(bytes, reg.bytesFor(family)), isTrue,
            reason: 'engine receives the registry\'s exact $family bytes');
      }
    });
  });
}
