// Pins two structural claims the wiki makes, so a change to the code that
// falsifies either fails here and names the doc page to update.
//
// Neither claim is protected by anything else. `FramePrimitive` is `sealed`,
// so the compiler already forces every switch over it to be exhaustive — a
// sixth subclass breaks those switches loudly. What nothing catches is
// docs/04-the-frame.md still saying "five" after that sixth subclass lands.
// This file protects the sentence, not the code.
//
// The first scan is provably complete, not a heuristic: `FramePrimitive` is
// declared `sealed` in `rendering/frame/primitive.dart`, and that file has no
// `part` directive. A sealed type's subtypes must live in the same library,
// and with no parts that library is exactly this one file — so reading it is
// the whole search space, not a sample of it. The second scan is a directory
// listing (non-recursive), which is exactly what "at lib/'s root" means, so
// it also cannot miss a sibling file.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

void main() {
  final Directory root = findWorkspaceRoot();

  test('FramePrimitive has exactly five subclasses (docs/04-the-frame.md)', () {
    final String src = File(
      '${root.path}/packages/jet_print/lib/src/rendering/frame/primitive.dart',
    ).readAsStringSync();
    // Matches any class name, not just ones ending in "Primitive" — a
    // subclass named e.g. BarcodeBlock must count too, or this scan could
    // report 5 while the documented claim is already false.
    final int count = RegExp(r'class\s+\w+\s+extends\s+FramePrimitive')
        .allMatches(src)
        .length;
    expect(
      count,
      5,
      reason: 'docs/04-the-frame.md names five primitives as the whole '
          'alphabet a page is written in. Update that page with the new '
          'primitive before changing this number.',
    );
  });

  test(
      'lib/ root holds exactly one library file, jet_print.dart '
      '(docs/01-smallest-report.md, docs/10-designer-seams.md)', () {
    final List<File> rootLibs = Directory('${root.path}/packages/jet_print/lib')
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();
    expect(
      rootLibs.length,
      1,
      reason: 'The single public entry point is the claim docs/01 and '
          'docs/10 both rest on. A second root library breaks it.',
    );
    expect(
      rootLibs.single.path.split(Platform.pathSeparator).last,
      'jet_print.dart',
      reason: 'docs/10-designer-seams.md names the one root library file as '
          'jet_print.dart specifically, not just "exactly one file".',
    );
  });

  test(
      'every other Dart file under lib/ lives in lib/src/ '
      '(docs/10-designer-seams.md)', () {
    final Directory libDir = Directory('${root.path}/packages/jet_print/lib');
    final List<String> offenders = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .map((File f) => f.path.substring(libDir.path.length + 1))
        .where((String relative) =>
            relative != 'jet_print.dart' &&
            !relative.startsWith('src${Platform.pathSeparator}'))
        .toList();
    expect(
      offenders,
      isEmpty,
      reason: 'docs/10-designer-seams.md claims every Dart file under lib/ '
          'other than jet_print.dart lives in lib/src/. Found outside '
          'src/: $offenders',
    );
  });
}
