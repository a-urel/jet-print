// `tool/release_notes.dart` writes the body of the GitHub Release that
// `.github/workflows/release.yml` creates for a pushed `jet_print-v*` tag. The
// 1.1.0 pin compares its output with `release_notes_1.1.0.md`, which is the
// body of the 1.1.0 release as it was published by hand, so the generated
// notes keep the house format the earlier releases set.
//
// VM only: the browser test runner serves just `test/`, so it cannot load the
// script from `tool/`; the conditional import below keeps the Chrome bundle
// compiling.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/release_notes_web.dart'
    if (dart.library.io) '../support/release_notes_io.dart';
import '../support/workspace.dart';

const List<String> _tags = <String>[
  'jet_print-v0.1.0',
  'jet_print-v0.1.1',
  'jet_print-v0.2.0',
  'jet_print-v1.0.0',
  'jet_print-v1.1.0',
];

String _pubspec(String version) => 'name: jet_print\nversion: $version\n';

const String _changelog = '''
# Changelog

## 2.0.0

Intro.

## 1.1.1

A patch.

### Fixed

- A fix.

## 1.0.1

Another patch.
''';

void main() {
  final String root = findWorkspaceRoot().path;
  final String changelog = File(
    '$root/packages/jet_print/CHANGELOG.md',
  ).readAsStringSync();

  test('the 1.1.0 notes match the release published by hand', () {
    final ReleaseNotes notes = buildReleaseNotes(
      tag: 'jet_print-v1.1.0',
      changelog: changelog,
      pubspec: _pubspec('1.1.0'),
      tags: _tags,
    );
    final String published = File(
      '$root/packages/jet_print/test/tool/release_notes_1.1.0.md',
    ).readAsStringSync();

    expect(notes.title, 'jet_print 1.1.0');
    expect(notes.body, published);
    expect(notes.latest, isTrue);
    expect(notes.previousTag, 'jet_print-v1.0.0');
  });

  test('the version in pubspec.yaml has a CHANGELOG section', () {
    // What the release job checks when the tag is pushed, run on every change,
    // so a version bump without its CHANGELOG section fails before the tag.
    final String pubspec = File(
      '$root/packages/jet_print/pubspec.yaml',
    ).readAsStringSync();
    final String version = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;

    expect(changelogSection(changelog, version), isNotNull);
  });

  group('unwrapMarkdown', () {
    test('joins the hard-wrapped lines of a paragraph', () {
      expect(unwrapMarkdown('One\ntwo\nthree.\n\nFour\nfive.'),
          'One two three.\n\nFour five.');
    });

    test('joins a list item and its indented continuation', () {
      expect(unwrapMarkdown('- **Item.** One\n  two\n- Next'),
          '- **Item.** One two\n- Next');
    });

    test('keeps a nested list item on its own line, indent intact', () {
      expect(unwrapMarkdown('- Top\n  line\n  - Nested\n    line'),
          '- Top line\n  - Nested line');
    });

    test('does not read a wrapped "0006. " as a new numbered item', () {
      expect(unwrapMarkdown('decision\n0006. One more.'),
          'decision 0006. One more.');
    });

    test('splits a numbered list into its items', () {
      expect(unwrapMarkdown('1. One\n   more\n2. Two'), '1. One more\n2. Two');
    });

    test('leaves a fenced code block verbatim', () {
      const String fenced = 'Run\nthis:\n\n```sh\nflutter pub get\n'
          'flutter test\n```\n\nThen\ndone.';
      expect(
          unwrapMarkdown(fenced),
          'Run this:\n\n```sh\nflutter pub get\nflutter test\n```\n\n'
          'Then done.');
    });

    test('joins inside a block quote and keeps its markers', () {
      expect(unwrapMarkdown('> **Note.** One\n> two.\n>\n> - A\n>   b'),
          '> **Note.** One two.\n>\n> - A b');
    });

    test('keeps a hard line break', () {
      expect(unwrapMarkdown('One  \ntwo\nthree'), 'One\ntwo three');
    });
  });

  group('buildReleaseNotes', () {
    ReleaseNotes build(String version, List<String> tags) => buildReleaseNotes(
          tag: 'jet_print-v$version',
          changelog: _changelog,
          pubspec: _pubspec(version),
          tags: tags,
        );

    test('promotes the section headings and links the comparison', () {
      final ReleaseNotes notes = build('1.1.1', <String>[
        ..._tags,
        'jet_print-v1.1.1',
      ]);

      expect(
        notes.body,
        'A patch.\n'
        '\n'
        '```sh\n'
        'flutter pub upgrade jet_print\n'
        '```\n'
        '\n'
        '[pub.dev](https://pub.dev/packages/jet_print/versions/1.1.1) · '
        '[Changelog](https://github.com/a-urel/jet-print/blob/'
        'jet_print-v1.1.1/packages/jet_print/CHANGELOG.md)\n'
        '\n'
        '## Fixed\n'
        '\n'
        '- A fix.\n'
        '\n'
        '**Full changelog:** [`1.1.0...1.1.1`](https://github.com/a-urel/'
        'jet-print/compare/jet_print-v1.1.0...jet_print-v1.1.1)\n',
      );
    });

    test('adds the new caret range when a release changes it', () {
      expect(build('2.0.0', _tags).body,
          contains('flutter pub add jet_print:^2.0.0'));
      expect(build('1.1.1', _tags).body,
          contains('flutter pub upgrade jet_print'));
      expect(installCommand('0.2.0', previous: '0.1.1'),
          'flutter pub add jet_print:^0.2.0');
      expect(installCommand('0.1.1', previous: '0.1.0'),
          'flutter pub upgrade jet_print');
      expect(installCommand('0.1.0', previous: null),
          'flutter pub add jet_print:^0.1.0');
    });

    test('is Latest only for the highest version', () {
      final ReleaseNotes backport = build('1.0.1', <String>[
        ..._tags,
        'jet_print-v1.0.1',
      ]);

      expect(backport.latest, isFalse);
      expect(backport.previousTag, 'jet_print-v1.0.0');
      expect(build('2.0.0', _tags).latest, isTrue);
    });

    test('omits the comparison for the first release', () {
      final ReleaseNotes first = build('1.1.1', const <String>[]);

      expect(first.previousTag, isNull);
      expect(first.body, isNot(contains('Full changelog')));
    });

    test('keeps a heading inside the intro\'s fenced code in the intro', () {
      const String fenced = '## 1.1.1\n'
          '\n'
          'Run:\n'
          '\n'
          '```sh\n'
          '### Example\n'
          'flutter pub get\n'
          '```\n'
          '\n'
          '### Fixed\n'
          '\n'
          '- A fix.\n';
      final String body = buildReleaseNotes(
        tag: 'jet_print-v1.1.1',
        changelog: fenced,
        pubspec: _pubspec('1.1.1'),
        tags: _tags,
      ).body;

      expect(
        body,
        startsWith(
          'Run:\n\n```sh\n### Example\nflutter pub get\n```\n\n```sh\n'
          'flutter pub upgrade jet_print\n```\n',
        ),
      );
      expect(body, contains('\n## Fixed\n'));
    });

    test('fails when the CHANGELOG has no section for the version', () {
      expect(
        () => build('1.2.0', _tags),
        throwsA(isA<ReleaseNotesException>().having(
          (ReleaseNotesException e) => e.message,
          'message',
          contains('## 1.2.0'),
        )),
      );
    });

    test('fails when the pubspec version differs from the tag', () {
      expect(
        () => buildReleaseNotes(
          tag: 'jet_print-v1.1.1',
          changelog: _changelog,
          pubspec: _pubspec('1.1.0'),
          tags: _tags,
        ),
        throwsA(isA<ReleaseNotesException>()),
      );
    });

    test('fails on a tag that does not name a version', () {
      expect(
        () => buildReleaseNotes(
          tag: 'v1.1.1',
          changelog: _changelog,
          pubspec: _pubspec('1.1.1'),
          tags: _tags,
        ),
        throwsA(isA<ReleaseNotesException>()),
      );
    });
  });

  group('changelogSection', () {
    test('skips a version heading inside fenced code', () {
      const String changelog = '## 1.2.0\n'
          '\n'
          '```md\n'
          '## 1.1.1\n'
          'An example.\n'
          '```\n'
          '\n'
          '## 1.1.1\n'
          '\n'
          'The real entry.\n';

      expect(changelogSection(changelog, '1.1.1'), 'The real entry.');
      expect(
        changelogSection(changelog, '1.2.0'),
        '```md\n## 1.1.1\nAn example.\n```',
      );
    });

    test('finds no section for a version that is only in fenced code', () {
      const String changelog = '## 1.2.0\n\n```md\n## 1.1.1\n```\n';

      expect(changelogSection(changelog, '1.1.1'), isNull);
    });
  });
}
