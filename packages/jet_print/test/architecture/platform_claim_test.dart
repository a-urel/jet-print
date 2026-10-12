// Architecture test: the platform claim matches CI.
//
// `pubspec.yaml`'s `platforms:` block is what pub.dev shows a stranger as
// supported. P4's exit criterion (docs/roadmap.md) is all six Flutter
// platforms declared there AND green in CI, because a platform claim CI does
// not exercise is the false signal E1 existed to remove. So each declared
// platform must name a CI leg that builds it, and the declaration must be the
// six decisions/0003 promises: dropping one is a decision to record, not an
// edit to slip in.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// Each platform 1.0 claims, and the text in `.github/workflows/ci.yml` that
/// proves a leg builds it.
const Map<String, String> _ciLegFor = <String, String>{
  'android': 'flutter build apk',
  'ios': 'flutter build ios',
  'linux': 'os: ubuntu-latest',
  'macos': 'os: macos-latest',
  'web': '--platform chrome',
  'windows': 'os: windows-latest',
};

/// The keys of the top-level `platforms:` block, read without a YAML parser
/// (the package does not depend on one): the indented keys that follow it,
/// up to the next unindented line.
Set<String> _declaredPlatforms(String pubspec) {
  final List<String> lines = pubspec.split('\n');
  final int start =
      lines.indexWhere((String l) => l.trimRight() == 'platforms:');
  if (start < 0) return <String>{};
  final Set<String> keys = <String>{};
  for (final String line in lines.skip(start + 1)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) break;
    final Match? key = RegExp(r'^\s+([a-z]+):').firstMatch(line);
    if (key != null) keys.add(key.group(1)!);
  }
  return keys;
}

void main() {
  final Directory root = findWorkspaceRoot();
  final String pubspec =
      File('${root.path}/packages/jet_print/pubspec.yaml').readAsStringSync();
  final String ci =
      File('${root.path}/.github/workflows/ci.yml').readAsStringSync();

  test('the pubspec declares the six platforms 1.0 claims', () {
    expect(_declaredPlatforms(pubspec), _ciLegFor.keys.toSet(),
        reason: 'decisions/0003 claims all six for 1.0; changing the set is '
            'a decision to record there, not a pubspec edit');
  });

  test('every declared platform has a CI leg that builds it', () {
    for (final String platform in _declaredPlatforms(pubspec)) {
      final String? leg = _ciLegFor[platform];
      expect(leg, isNotNull, reason: 'no known CI leg for $platform');
      expect(ci, contains(leg),
          reason: '$platform is declared but ci.yml has no "$leg" leg');
    }
  });
}
