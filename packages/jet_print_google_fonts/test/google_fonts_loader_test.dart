import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

/// Resolves a package-prefixed asset key to a real file path, robust to the
/// test cwd (repo root under `flutter test packages/...`, or the package dir).
String diskPathFor(String key) {
  if (File(key).existsSync()) return key; // cwd = repo root
  const String prefix = 'packages/jet_print_google_fonts/';
  return key.startsWith(prefix) ? key.substring(prefix.length) : key;
}

/// Serves the catalog's real asset bytes by reading them off disk.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final Uint8List bytes = await File(diskPathFor(key)).readAsBytes();
    return ByteData.view(
        bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  }
}

/// Reads from disk but throws for any key containing [failKeyContains].
class _ThrowingBundle extends CachingAssetBundle {
  _ThrowingBundle({required this.failKeyContains});
  final String failKeyContains;
  @override
  Future<ByteData> load(String key) async {
    if (key.contains(failKeyContains)) {
      throw Exception('missing asset $key');
    }
    final Uint8List bytes = await File(diskPathFor(key)).readAsBytes();
    return ByteData.view(
        bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  }
}

void main() {
  test('loads every catalog family as a validated JetFontFamily', () async {
    final List<JetFontFamily> fonts =
        await loadGoogleFonts(bundle: _DiskBundle());
    expect(fonts.map((JetFontFamily f) => f.name),
        containsAll(<String>['Noto Sans', 'Noto Serif', 'JetBrains Mono']));
    final JetFontFamily sans =
        fonts.firstWhere((JetFontFamily f) => f.name == 'Noto Sans');
    expect(sans.faces, hasLength(4), reason: '4 faces grouped per family');
  });

  test('only: limits which families load', () async {
    final List<JetFontFamily> fonts = await loadGoogleFonts(
        only: <String>['Noto Serif'], bundle: _DiskBundle());
    expect(fonts.map((JetFontFamily f) => f.name), <String>['Noto Serif']);
  });

  test('a family whose bytes fail to load is skipped, not thrown', () async {
    final List<JetFontFamily> fonts = await loadGoogleFonts(
      bundle: _ThrowingBundle(failKeyContains: 'JetBrains Mono'),
    );
    final Iterable<String> names = fonts.map((JetFontFamily f) => f.name);
    expect(names, isNot(contains('JetBrains Mono')));
    expect(names, contains('Noto Sans'), reason: 'others still load');
  });
}
