// Pins structural claims the wiki makes, so a change to the code that
// falsifies one fails here and names the doc page to update — and, for the
// primitive count, so a change to the PAGE that falsifies it fails here too.
//
// That second direction was missing, and its absence had the shape this repo
// keeps finding. The count below used to be a literal `5` compared against the
// source, with docs/04-the-frame.md's own "five" never read: a third copy of
// the claim, agreeing with the other two only for as long as nobody edited the
// page. Adding a primitive failed this test, which is the direction that
// breaks in practice; editing the page to say "six" did not. A test holding
// its own copy of the thing it is about is the pattern `shape_element_test`
// had, and it passed for the same reason until the copy went stale.
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

  /// The real number of `FramePrimitive` subclasses, read from the sealed
  /// library that is provably the whole search space (see the header).
  int subclassCount() {
    final String src = File(
      '${root.path}/packages/jet_print/lib/src/rendering/frame/primitive.dart',
    ).readAsStringSync();
    return RegExp(r'class\s+\w+\s+extends\s+FramePrimitive')
        .allMatches(src)
        .length;
  }

  test('the FramePrimitive scan finds subclasses at all (no false green)', () {
    // Deliberately NOT `expect(count, 5)`. That literal was the last
    // hand-copy of a claim that already exists in two places — the sealed
    // library and docs/04-the-frame.md — and it made the test, not the page,
    // the thing an author updated after adding a primitive. With it gone,
    // neither side is authoritative: the page and the source must agree, and
    // a deliberate move to six means touching both and nothing else.
    //
    // What remains here is the floor. If the regex ever stops matching, the
    // comparison below would be reading zero subclasses, and this says so in
    // its own voice rather than letting that surface as a confusing
    // page-disagrees-with-source failure.
    expect(subclassCount(), greaterThan(0),
        reason: 'No `class X extends FramePrimitive` found in '
            'rendering/frame/primitive.dart. The declaration style changed and '
            'this scan no longer matches it — fix the pattern; do not weaken '
            'the comparison that depends on it.');
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

  test('docs/04-the-frame.md states the primitive count the source has', () {
    // The page states the count FIVE times, in four shapes: a heading ("The
    // five primitives"), a sentence ("Five subclasses extend it"), a lead-in
    // ("spelled with those five:"), and twice as a callback ("the same five
    // primitives", "each of the five primitives"). A correct update has to
    // reach all five, so a scan finding only one would pass a half-done edit.
    //
    // It is NOT a blanket sweep for number-words: the same page legitimately
    // says "three fields" and "one stroked segment", and a token that is not a
    // number is ignored rather than failing, because "the primitives" is
    // ordinary prose.
    //
    // The determiner is what separates a COUNT from a QUANTITY, and the page
    // contains both. "the/those/same/all five primitives" states the size of
    // the roster. "two primitives that genuinely differ compare equal" (in the
    // Trap section) means a PAIR, and matching it would make this test fail on
    // correct prose. A count-claim carries a determiner or opens a sentence;
    // a quantity does not.
    const Map<String, int> words = <String, int>{
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
    };
    final String page =
        File('${root.path}/docs/04-the-frame.md').readAsStringSync();
    final List<RegExp> claims = <RegExp>[
      RegExp(r'\b(?:the|those|same|all)\s+(\w+)\s+primitives\b',
          caseSensitive: false),
      RegExp(r'^(\w+)\s+subclasses\b', caseSensitive: false, multiLine: true),
      RegExp(r'\bthose\s+(\w+)\s*:', caseSensitive: false),
    ];
    final List<int> stated = <int>[
      for (final RegExp claim in claims)
        for (final RegExpMatch m in claim.allMatches(page))
          if (words[m.group(1)!.toLowerCase()] != null)
            words[m.group(1)!.toLowerCase()]!,
    ];

    expect(stated.length, greaterThanOrEqualTo(4),
        reason: 'Found only ${stated.length} stated primitive counts in '
            'docs/04-the-frame.md; the page makes the claim five times and '
            'this test is worthless if a rewording drops the scan to zero. '
            'If the page genuinely states it fewer times now, lower this '
            'number deliberately — do not delete the check.');
    expect(stated.toSet(), <int>{subclassCount()},
        reason: 'docs/04-the-frame.md states a primitive count that the '
            'source does not have, or states two different counts because an '
            'edit reached some of the five places and not the others. The '
            'page and the code must agree: $stated vs ${subclassCount()} '
            'actual subclasses.');
  });
}
