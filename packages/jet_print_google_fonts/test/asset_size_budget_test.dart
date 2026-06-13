import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'bundled font assets stay under the size budget (catch un-subsetted commits)',
      () {
    // Robust to test cwd (repo root or package dir).
    Directory dir = Directory('packages/jet_print_google_fonts/assets/fonts');
    if (!dir.existsSync()) dir = Directory('assets/fonts');
    expect(dir.existsSync(), isTrue);
    int total = 0;
    for (final FileSystemEntity f in dir.listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.ttf')) total += f.lengthSync();
    }
    // 12 MB ceiling: comfortably above ~60 subset families × 4 faces, far below
    // an accidental full-font commit. Raise deliberately if the catalog grows.
    expect(total, lessThan(12 * 1024 * 1024),
        reason:
            'assets/fonts is ${total ~/ 1024} KB — did a non-subset font slip in?');
  });
}
