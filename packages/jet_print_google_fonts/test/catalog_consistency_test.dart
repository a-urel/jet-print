import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

/// Resolves a package-prefixed asset key to a real path, robust to test cwd.
String _toPath(String assetKey) {
  if (File(assetKey).existsSync()) return assetKey; // cwd = repo root
  const String prefix = 'packages/jet_print_google_fonts/';
  return assetKey.startsWith(prefix)
      ? assetKey.substring(prefix.length)
      : assetKey;
}

void main() {
  test('every catalog entry has a regular face, real assets, and a license',
      () {
    expect(googleFontCatalog, isNotEmpty);
    for (final GoogleFontEntry entry in googleFontCatalog) {
      expect(
        entry.faceAssets
            .containsKey((weight: JetFontWeight.normal, italic: false)),
        isTrue,
        reason: '${entry.name} must declare a regular face',
      );
      for (final String key in entry.faceAssets.values) {
        expect(File(_toPath(key)).existsSync(), isTrue,
            reason: 'missing asset for ${entry.name}: $key');
      }
      expect(
          File(_toPath(
                  'packages/jet_print_google_fonts/assets/licenses/${entry.name}.txt'))
              .existsSync(),
          isTrue,
          reason: '${entry.name} must bundle a license file');
      expect(
          <String>['OFL-1.1', 'Apache-2.0', 'UFL-1.0'], contains(entry.license),
          reason: '${entry.name} license must be embeddable');
    }
  });

  test('family names are unique', () {
    final List<String> names =
        googleFontCatalog.map((GoogleFontEntry e) => e.name).toList();
    expect(names.toSet().length, names.length);
  });
}
