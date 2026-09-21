// The analyser rules exist twice, and both copies say the same thing.
//
// The strict configuration this repository is built under lives in the
// repository-root `analysis_options.yaml`. The published archive contains only
// `packages/jet_print/`, so that file is not in it: pana, and anyone who
// unpacks the package, analyse this code under the analyzer's defaults instead
// — a different rule set from the one CI has ever run, over source (the
// generated localizations) that the root config excludes and nothing has
// linted. `packages/jet_print/analysis_options.yaml` closes that by restating
// the settings inside the package.
//
// Two files saying one thing is the shape this repository keeps finding rots.
// They agree on the day the second one is written and drift the first time
// someone tightens the root and forgets the copy — and the drift is invisible,
// because the root config is the only one CI reads. The published package
// would quietly go back to being analysed under rules nobody ran.
//
// So this guard holds the two to each other: same lint base, same language
// settings, same error promotions, same extra rules, same excludes. The one
// licensed difference is the generated-localization path, which the root
// writes from the workspace root and the package must write relative to
// itself — checked here as a difference in spelling only, against files that
// actually exist, so a corrected path cannot quietly stop matching anything.
//
// Tightening the gate is therefore: edit the root, edit the package copy, and
// let this test say whether the second edit was missed. It reads both files as
// text and never invokes the analyzer, so it says nothing about whether either
// config passes — only that they agree.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// One significant line of a YAML file: its indentation and its text.
typedef _Line = ({int indent, String text});

/// The substring that identifies the generated-localization exclude in either
/// config. It is matched rather than compared, because the two files spell the
/// path differently on purpose.
const String _generatedLocalizations = 'jet_print_localizations';

/// The lines of [file] that carry settings: blank lines and comments dropped,
/// each paired with its indentation.
List<_Line> _significant(File file) {
  final List<_Line> lines = <_Line>[];
  for (final String raw in file.readAsLinesSync()) {
    final String line = raw.replaceAll('\r', '');
    final int comment = line.indexOf(' #');
    final String body = comment == -1 ? line : line.substring(0, comment);
    final String text = body.trim();
    if (text.isEmpty || text.startsWith('#')) continue;
    lines.add((indent: line.length - line.trimLeft().length, text: text));
  }
  return lines;
}

/// The entries directly under [path] in [file] — `['analyzer', 'errors']`
/// yields the promotion lines, `['linter', 'rules']` the extra rules.
///
/// Descends by indentation rather than parsing YAML: the package depends on no
/// YAML library, and these two files are hand-written, flat and short. Returns
/// an empty list when the path is absent; the vacuity guard below is what
/// stops that emptiness from passing as agreement.
List<String> _block(File file, List<String> path) {
  List<_Line> scope = _significant(file);
  for (final String key in path) {
    final int head = scope.indexWhere((_Line l) => l.text == '$key:');
    if (head == -1) return const <String>[];
    final int indent = scope[head].indent;
    final List<_Line> inner = <_Line>[];
    for (final _Line line in scope.skip(head + 1)) {
      if (line.indent <= indent) break;
      inner.add(line);
    }
    scope = inner;
  }
  if (scope.isEmpty) return const <String>[];
  final int top = scope
      .map((_Line l) => l.indent)
      .reduce((int a, int b) => a < b ? a : b);
  return scope
      .where((_Line l) => l.indent == top)
      .map((_Line l) => l.text)
      .toList();
}

/// A list entry with its `- ` and any surrounding quotes removed, so
/// `- "build/**"` and `- build/**` compare equal.
String _entry(String line) {
  String text = line.startsWith('- ') ? line.substring(2).trim() : line;
  final bool quoted = text.length >= 2 &&
      ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith("'") && text.endsWith("'")));
  return quoted ? text.substring(1, text.length - 1) : text;
}

/// The top-level `include:` line of [file], or the empty string if it has none.
String _include(File file) => _significant(file)
    .firstWhere(
      (_Line l) => l.indent == 0 && l.text.startsWith('include:'),
      orElse: () => (indent: 0, text: ''),
    )
    .text;

List<String> _sorted(Iterable<String> values) => values.toList()..sort();

/// Every `analyzer: exclude:` entry of [file], unquoted.
List<String> _excludes(File file) =>
    _block(file, <String>['analyzer', 'exclude']).map(_entry).toList();

/// The excludes of [file] other than the generated-localization one.
List<String> _plainExcludes(File file) => _sorted(
    _excludes(file).where((String e) => !e.contains(_generatedLocalizations)));

/// The generated-localization excludes of [file] — expected to be exactly one.
List<String> _localizationExcludes(File file) => _excludes(file)
    .where((String e) => e.contains(_generatedLocalizations))
    .toList();

void main() {
  final Directory root = findWorkspaceRoot();
  final File rootOptions = File('${root.path}/analysis_options.yaml');
  final File packageOptions =
      File('${root.path}/packages/jet_print/analysis_options.yaml');

  test('the package carries its own analysis_options.yaml', () {
    expect(packageOptions.existsSync(), isTrue,
        reason: 'packages/jet_print/analysis_options.yaml is gone. The root '
            'config is not in the published archive, so without this file the '
            'package is analysed under the analyzer defaults wherever it is '
            'unpacked — including by pana. Restore it from the root config; '
            'the tests below say what has to match.');
    expect(rootOptions.existsSync(), isTrue,
        reason: 'No analysis_options.yaml at the workspace root. Every '
            'comparison below reads it, so a missing root config would make '
            'them all pass while checking nothing.');
  });

  test('both configs were parsed (guards vacuous comparisons)', () {
    expect(_include(rootOptions), isNotEmpty,
        reason: 'No top-level `include:` parsed from the root config.');
    expect(_block(rootOptions, <String>['analyzer', 'language']), isNotEmpty,
        reason: 'No `analyzer: language:` block parsed from the root config. '
            'If the file was restructured, fix the reader here — do not delete '
            'this test: an empty block compares equal to an empty block.');
    expect(_block(rootOptions, <String>['analyzer', 'errors']), isNotEmpty,
        reason: 'No `analyzer: errors:` block parsed from the root config.');
    expect(_block(rootOptions, <String>['linter', 'rules']), isNotEmpty,
        reason: 'No `linter: rules:` block parsed from the root config.');
    expect(_excludes(rootOptions), isNotEmpty,
        reason: 'No `analyzer: exclude:` block parsed from the root config.');
  });

  test('the package config includes the same lint base as the root', () {
    expect(_include(packageOptions), equals(_include(rootOptions)),
        reason: 'The two configs `include:` different lint sets. A consumer '
            'analysing the unpacked package gets whatever the package file '
            'names and nothing else, so it has to name the same base the root '
            'does. Note the include only resolves standing alone because '
            'flutter_lints is a dev dependency of packages/jet_print itself; '
            'if that is removed from its pubspec, this file breaks for every '
            'consumer.');
  });

  test('the package config restates the root language settings', () {
    expect(
      _sorted(_block(packageOptions, <String>['analyzer', 'language'])),
      equals(_sorted(_block(rootOptions, <String>['analyzer', 'language']))),
      reason: 'The `analyzer: language:` blocks differ. strict-casts, '
          'strict-inference and strict-raw-types change what the analyzer '
          'accepts, so a package copy that omits one is a weaker gate than the '
          'one CI runs — and the published package is exactly where that gap '
          'stops being visible.',
    );
  });

  test('the package config restates the root error promotions', () {
    expect(
      _sorted(_block(packageOptions, <String>['analyzer', 'errors'])),
      equals(_sorted(_block(rootOptions, <String>['analyzer', 'errors']))),
      reason: 'The `analyzer: errors:` blocks differ. These promotions are the '
          'zero-warning gate (FR-009 / SC-003); a severity set in one file and '
          'not the other means the same code is an error here and a warning in '
          'the archive, or the reverse.',
    );
  });

  test('the package config restates the root linter rules', () {
    List<String> rules(File file) =>
        _sorted(_block(file, <String>['linter', 'rules']).map(_entry));

    expect(
      rules(packageOptions),
      equals(rules(rootOptions)),
      reason: 'The `linter: rules:` blocks differ. These are the rules the '
          'repository adds on top of flutter_lints; a rule added at the root '
          'and not here is a rule the published package is never checked '
          'against.',
    );
  });

  test('the excludes agree apart from the generated-localization path', () {
    expect(
      _plainExcludes(packageOptions),
      equals(_plainExcludes(rootOptions)),
      reason: 'The `analyzer: exclude:` lists differ by more than the '
          'generated-localization path. Every other entry is carried over '
          'verbatim so the two files can be compared line for line; add the '
          'entry to both, or drop it from both.',
    );
  });

  test('the root still excludes the generated localizations', () {
    expect(_localizationExcludes(rootOptions), hasLength(1),
        reason: 'The root config no longer has exactly one exclude naming '
            '`$_generatedLocalizations`. If the generated output stopped being '
            'excluded, the package copy should follow — and this guard needs '
            'rewriting rather than deleting.');
  });

  test('the package exclude is package-relative and matches real files', () {
    final List<String> found = _localizationExcludes(packageOptions);
    expect(found, hasLength(1),
        reason: 'The package config must have exactly one exclude naming '
            '`$_generatedLocalizations`. Without it, roughly 127 KB of '
            'committed gen-l10n output that CI has never linted enters the '
            'analysis of the published package.');

    final String pattern = found.single;
    expect(pattern.startsWith('**'), isFalse,
        reason: 'The package exclude is "$pattern". The root spells this path '
            'from the workspace root; inside the archive there is no workspace '
            'root, and exclude globs resolve against the directory holding the '
            'options file. Write it relative to the package, e.g. '
            'lib/src/designer/l10n/$_generatedLocalizations*.dart.');

    final int star = pattern.indexOf('*');
    expect(star, isNot(-1),
        reason: 'The package exclude "$pattern" has no glob, so it names one '
            'file and misses the per-locale output beside it.');
    final String prefix = pattern.substring(0, star);
    final int slash = prefix.lastIndexOf('/');
    expect(slash, isNot(-1),
        reason: 'The package exclude "$pattern" has no directory part, so the '
            'check below cannot tell whether it matches anything.');

    final String directory = prefix.substring(0, slash);
    final Directory dir =
        Directory('${root.path}/packages/jet_print/$directory');
    expect(dir.existsSync(), isTrue,
        reason: 'The package exclude points at $directory, which does not '
            'exist under packages/jet_print. gen-l10n writes to the '
            '`output-dir` in l10n.yaml; if that moved, move this path too '
            '— an exclude that matches nothing silently stops excluding.');

    final String stem = prefix.substring(slash + 1);
    final List<String> matched = dir
        .listSync()
        .whereType<File>()
        .map((File f) => f.path.replaceAll(r'\', '/').split('/').last)
        .where((String name) => name.startsWith(stem) && name.endsWith('.dart'))
        .toList();
    expect(matched, isNotEmpty,
        reason: 'The package exclude "$pattern" matches no file in '
            '${dir.path}. It was correct when written and is not now; the '
            'generated output moved or was renamed, and the exclusion is doing '
            'nothing.');
  });
}
