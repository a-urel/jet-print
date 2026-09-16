// Architecture test: the record-then-release sequence has ONE home.
//
// `CanvasPainter` decodes images into GPU textures that must be released after
// the frame is recorded. That obligation was open-coded at four call sites and
// honoured at one, because `dispose()` sat on the concrete class while three
// sites held the `ReportPainter` abstraction (or kept no reference at all) and
// so could not call it.
//
// The sequence now lives in `record_page_frame.dart`. This test keeps it there:
// a fifth consumer that builds its own `CanvasPainter` re-opens the same leak,
// and a source scan is the right shape here because the property is "nobody
// else writes this code", not a runtime behaviour. Modelled on
// `barcode_dependency_isolation_test.dart`.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// Matches a `CanvasPainter` **construction** in either spelling — `CanvasPainter(`
/// and the `CanvasPainter.new` tear-off (which the seam itself uses, and which a
/// plain `contains('CanvasPainter(')` scan would miss) — tolerating whitespace
/// before the paren. Dartdoc references such as `[CanvasPainter]` or
/// `[CanvasPainter.prepare]` deliberately do not match, so files may still name
/// the class in prose.
final RegExp _construction = RegExp(r'CanvasPainter\s*(?:\(|\.new)');

void main() {
  test('only record_page_frame.dart constructs a CanvasPainter', () {
    final Directory root = findWorkspaceRoot();
    final List<String> offenders = <String>[];
    for (final FileSystemEntity f in Directory(
      '${root.path}/packages/jet_print/lib',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      // The seam itself, and the class's own declaration file.
      if (f.path.endsWith('record_page_frame.dart')) continue;
      if (f.path.endsWith('canvas_painter.dart')) continue;
      if (_construction.hasMatch(f.readAsStringSync())) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'CanvasPainter built outside the record seam — each such site '
            'must release the decoded textures itself and historically did '
            'not: $offenders');
  });
}
