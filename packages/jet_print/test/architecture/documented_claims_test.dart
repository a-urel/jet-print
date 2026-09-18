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

/// Number words the docs spell out for small counts.
const Map<String, int> _numberWords = <String, int>{
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
          if (_numberWords[m.group(1)!.toLowerCase()] != null)
            _numberWords[m.group(1)!.toLowerCase()]!,
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

  /// Every count [pattern] states across [files], as integers.
  ///
  /// [pattern]'s first group is the number token. A token that is not a number
  /// word is SKIPPED rather than failing: "the ARB file" and "no ARB change"
  /// are ordinary prose, and a guard that fired on them would be failing the
  /// person who wrote clearly.
  List<int> statedCounts(List<String> files, RegExp pattern) => <int>[
        for (final String relative in files)
          for (final RegExpMatch m in pattern
              .allMatches(File('${root.path}/$relative').readAsStringSync()))
            if (_numberWords[m.group(1)!.toLowerCase()] != null)
              _numberWords[m.group(1)!.toLowerCase()]!,
      ];

  test('the ARB-file count the docs state matches the l10n directory', () {
    // AGENTS.md and two recipes all say "three ARB files". The recipe one is
    // the reason this is worth a test: it is PROCEDURAL — it tells an author
    // which files to edit. Every other figure guarded here is descriptive, so
    // a stale one misinforms; a stale count HERE walks someone past a locale
    // and ships it untranslated, which nothing else catches. German strings
    // are the widest in this UI, so a missed locale is not cosmetic.
    const List<String> sites = <String>[
      'AGENTS.md',
      'docs/recipes/add-localized-string.md',
      'docs/recipes/add-element-type.md',
    ];
    final int actual =
        Directory('${root.path}/packages/jet_print/lib/src/designer/l10n')
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.endsWith('.arb'))
            .length;
    final List<int> stated =
        statedCounts(sites, RegExp(r'(\w+)\s+ARB\b', caseSensitive: false));

    expect(stated.length, greaterThanOrEqualTo(3),
        reason: 'Found only ${stated.length} stated ARB counts across '
            '${sites.join(", ")}; there are four. A rewording that drops the '
            'scan to zero would make this pass vacuously — lower this '
            'deliberately if the docs genuinely say it fewer times.');
    expect(stated.toSet(), <int>{actual},
        reason: 'The docs state an ARB-file count the l10n directory does not '
            'have ($stated vs $actual). Adding a locale means adding its .arb '
            'AND updating every place that tells an author how many to edit.');
  });

  test('the generated-localization count matches what gen-l10n writes', () {
    // Same sentence in the recipe as the ARB count ("the three ARB files, the
    // four generated Dart files"), so it is guarded here rather than left as
    // the unguarded half of a pair. l10n.yaml's output-localization-file is
    // jet_print_localizations.dart, so gen-l10n writes that plus one per
    // locale; the other files in that directory are hand-written helpers.
    final int actual =
        Directory('${root.path}/packages/jet_print/lib/src/designer/l10n')
            .listSync()
            .whereType<File>()
            .where((File f) =>
                f.path.replaceAll(r'\', '/').split('/').last.startsWith(
                      'jet_print_localizations',
                    ) &&
                f.path.endsWith('.dart'))
            .length;
    final List<int> stated = statedCounts(
      <String>['docs/recipes/add-localized-string.md'],
      RegExp(r'(\w+)\s+generated Dart files', caseSensitive: false),
    );

    expect(stated, isNotEmpty,
        reason: 'The generated-file count vanished from '
            'docs/recipes/add-localized-string.md; this check now proves '
            'nothing.');
    expect(stated.toSet(), <int>{actual},
        reason: 'The recipe states a generated-file count gen-l10n does not '
            'produce ($stated vs $actual).');
  });

  test('the split-file count the docs state matches the designer part-ofs', () {
    // "Four god-files are split with `part` + `extension`" is stated in
    // AGENTS.md and echoed in three wiki pages, twice as "the four split
    // files" — five sites that rot together.
    //
    // Scoped to lib/src/designer DELIBERATELY. Across all of lib/src there are
    // FIVE part-of families, because domain/detail_scope.dart has one too, and
    // a whole-src scan would make this guard assert the wrong number against
    // correct prose. The claim is about the designer's god-files.
    const List<String> sites = <String>[
      'AGENTS.md',
      'docs/07-designer-loop.md',
      'docs/09-the-panels.md',
      'docs/10-designer-seams.md',
    ];
    final Set<String> families = <String>{
      for (final File f
          in Directory('${root.path}/packages/jet_print/lib/src/designer')
              .listSync(recursive: true)
              .whereType<File>()
              .where((File f) => f.path.endsWith('.dart')))
        ...RegExp("part of '([^']*)'")
            .allMatches(f.readAsStringSync())
            .map((RegExpMatch m) => m.group(1)!.split('/').last),
    };
    final List<int> stated = statedCounts(
      sites,
      RegExp(r'(\w+)\s+(?:god-files?|split files)', caseSensitive: false),
    );

    expect(stated.length, greaterThanOrEqualTo(4),
        reason: 'Found only ${stated.length} stated split-file counts across '
            '${sites.join(", ")}; there are five.');
    expect(stated.toSet(), <int>{families.length},
        reason: 'The docs state a split-file count the designer does not have '
            '($stated vs ${families.length}: ${families.toList()..sort()}). '
            'Splitting a fifth god-file, or rejoining one, means updating '
            'every page that counts them.');
  });

  test('the derived "other N" in docs/10 tracks the split-file count', () {
    // docs/10-designer-seams.md: "Among the four split files only the
    // controller reaches a consumer this way; the other three extend ...".
    // That second number is DERIVED — count minus the controller — so it rots
    // one sentence away from a figure the test above already holds. Guarding
    // the head of the sentence and not its tail is the mirrored-pair failure
    // this repo keeps finding.
    final int families = <String>{
      for (final File f
          in Directory('${root.path}/packages/jet_print/lib/src/designer')
              .listSync(recursive: true)
              .whereType<File>()
              .where((File f) => f.path.endsWith('.dart')))
        ...RegExp("part of '([^']*)'")
            .allMatches(f.readAsStringSync())
            .map((RegExpMatch m) => m.group(1)!.split('/').last),
    }.length;
    final List<String> lines =
        File('${root.path}/docs/10-designer-seams.md').readAsLinesSync();
    final Iterable<String> sentence = lines.where(
        (String l) => l.contains('split files') && l.contains('the other '));
    expect(sentence, isNotEmpty,
        reason: 'The "Among the four split files ... the other three" sentence '
            'is gone from docs/10-designer-seams.md, so this check is inert. '
            'Delete it deliberately, or repoint it.');
    for (final String line in sentence) {
      final RegExpMatch? m =
          RegExp(r'the other (\w+)', caseSensitive: false).firstMatch(line);
      expect(_numberWords[m!.group(1)!.toLowerCase()], families - 1,
          reason: 'docs/10 says "the other ${m.group(1)}" of '
              '$families split files, which should be ${families - 1}.');
    }
  });

  /// A doc read as ONE whitespace-normalized string.
  ///
  /// Markdown wraps at the column, not at the claim: docs/03 ends a line on
  /// "The three `GroupLevel`" and opens the next with "pagination flags". A
  /// line-oriented scan has a hole exactly as wide as the wrap, and would
  /// silently match nothing here — passing while asserting on an empty set.
  /// Flattening first is what closes that; every scan below uses it.
  String flat(String relative) => File('${root.path}/$relative')
      .readAsStringSync()
      .replaceAll(RegExp(r'\s+'), ' ');

  /// Every count [pattern] states in the flattened [relative] docs.
  List<int> flatCounts(List<String> files, RegExp pattern) => <int>[
        for (final String relative in files)
          for (final RegExpMatch m in pattern.allMatches(flat(relative)))
            if (_numberWords[m.group(1)!.toLowerCase()] != null)
              _numberWords[m.group(1)!.toLowerCase()]!,
      ];

  test('docs/04 states the number of fields FramePrimitive actually carries',
      () {
    // Scoped to the BASE class body, not the file: the subclasses declare
    // their own finals (TextRunPrimitive alone has lines/style/fontFamily),
    // and counting those would assert a number against correct prose. The
    // claim is about "the fields every drawn thing has", which is the sealed
    // base's own.
    final String src = File(
      '${root.path}/packages/jet_print/lib/src/rendering/frame/primitive.dart',
    ).readAsStringSync();
    final int open = src.indexOf('sealed class FramePrimitive');
    expect(open, isNot(-1),
        reason: 'FramePrimitive is no longer declared `sealed class` — the '
            'scan below no longer finds the base, so fix the pattern rather '
            'than the assertion.');
    final String body = src.substring(open, src.indexOf('\n}', open));
    final int actual =
        RegExp(r'\n\s+final\s+[\w<>?]+\s+\w+;').allMatches(body).length;

    final List<int> stated = flatCounts(
      <String>['docs/04-the-frame.md'],
      RegExp(r'(\w+) fields every drawn thing has', caseSensitive: false),
    );
    expect(stated, isNotEmpty,
        reason: 'The "fields every drawn thing has" claim is gone from '
            'docs/04-the-frame.md; this check is now inert.');
    expect(stated.toSet(), <int>{actual},
        reason: 'docs/04 states a base-field count FramePrimitive does not '
            'carry ($stated vs $actual).');
  });

  test('the GroupLevel pagination-flag count docs state matches the model', () {
    // The flags ARE the bool fields: GroupLevel's other finals are id, name,
    // key, header and footer. If a non-pagination bool is ever added this
    // fails on correct prose — which is the right moment to re-read the
    // sentence anyway, and the message says so rather than leaving the next
    // author to guess why.
    final int actual = RegExp(r'\n\s+final bool\s+\w+;')
        .allMatches(File(
                '${root.path}/packages/jet_print/lib/src/domain/group_level.dart')
            .readAsStringSync())
        .length;
    final List<int> stated = flatCounts(
      <String>['docs/03-pagination.md', 'docs/README.md'],
      RegExp(r'(\w+) `GroupLevel` pagination flags', caseSensitive: false),
    );

    expect(stated.length, greaterThanOrEqualTo(2),
        reason: 'Found only ${stated.length} stated GroupLevel flag counts; '
            'docs/03 and docs/README each state one. Note docs/03 WRAPS '
            'mid-claim, so a line-oriented scan finds nothing — if this '
            'number fell, check that before lowering it.');
    expect(stated.toSet(), <int>{actual},
        reason: 'The docs state a GroupLevel pagination-flag count the model '
            'does not have ($stated vs $actual bool fields). If a bool was '
            'added that is NOT a pagination flag, this equivalence no longer '
            'holds and the test needs narrowing, not the docs.');
  });

  test('docs/testing.md states the CI shape ci.yml actually has', () {
    final List<String> ci =
        File('${root.path}/.github/workflows/ci.yml').readAsLinesSync();
    final int jobsAt = ci.indexWhere((String l) => l == 'jobs:');
    expect(jobsAt, isNot(-1), reason: 'ci.yml has no top-level `jobs:` key.');
    final int osEntries =
        ci.where((String l) => RegExp(r'^\s+- os:').hasMatch(l)).length;
    // Top-level job keys live below `jobs:`; the `on:` triggers above it look
    // identical at this indent, which is why the scan starts after `jobs:`.
    final int jobKeys = ci
        .skip(jobsAt + 1)
        .where((String l) => RegExp(r'^  [a-z][a-z0-9_-]*:$').hasMatch(l))
        .length;
    final int standalone = jobKeys - 1; // all but the matrix job
    final int legs = osEntries + standalone;

    expect(
      flatCounts(<String>['docs/testing.md'], RegExp(r'ci\.yml`?, (\w+) legs')),
      <int>[legs],
      reason: 'docs/testing.md states a leg count ci.yml does not produce '
          '(expected $legs = $osEntries OS entries + $standalone standalone '
          'jobs).',
    );
    expect(
      flatCounts(
          <String>['docs/testing.md'], RegExp(r'(\w+) OS entries of one')),
      <int>[osEntries],
      reason: 'docs/testing.md states an OS-entry count the ci.yml matrix does '
          'not have.',
    );
    expect(
      flatCounts(
          <String>['docs/testing.md'], RegExp(r'(\w+) jobs of their own')),
      <int>[standalone],
      reason: 'docs/testing.md states a standalone-job count ci.yml does not '
          'have.',
    );

    // The page also TABULATES the legs, one row each. A count updated in the
    // prose but not in the table is the half-done edit this file exists for.
    final List<String> lines =
        File('${root.path}/docs/testing.md').readAsLinesSync();
    final int header = lines.indexWhere((String l) => l.startsWith('| Leg |'));
    expect(header, isNot(-1),
        reason: 'The CI leg table is gone from '
            'docs/testing.md; this check is now inert.');
    final int rows = lines
        .skip(header + 2) // header + the |---|---| separator
        .takeWhile((String l) => l.startsWith('|'))
        .length;
    expect(rows, legs,
        reason: 'The CI leg table lists $rows legs but ci.yml runs $legs.');
  });
}
