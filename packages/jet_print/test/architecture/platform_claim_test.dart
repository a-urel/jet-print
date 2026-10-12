// Architecture test: the platform claim matches CI.
//
// `pubspec.yaml`'s `platforms:` block is what pub.dev shows a stranger as
// supported. P4's exit criterion (docs/roadmap.md) is all six Flutter
// platforms declared there AND green in CI, because a platform claim CI does
// not exercise is the false signal E1 existed to remove. So each declared
// platform must have a CI leg that runs its build command, and the declaration
// must be the six decisions/0003 promises: dropping one is a decision to
// record, not an edit to slip in.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// The shared build step of the desktop matrix; each desktop row only names
/// its `build_target`, so both must be present for that row to build.
const String _matrixBuild = r'flutter build ${{ matrix.build_target }}';

/// Each platform 1.0 claims, and the text in `.github/workflows/ci.yml` that
/// proves a leg builds it: the build command itself, not merely a runner or a
/// test step on that OS.
const Map<String, List<String>> _ciBuildFor = <String, List<String>>{
  'android': <String>['flutter build apk'],
  'ios': <String>['flutter build ios'],
  'linux': <String>['build_target: linux', _matrixBuild],
  'macos': <String>['build_target: macos', _matrixBuild],
  'web': <String>['flutter build web'],
  'windows': <String>['build_target: windows', _matrixBuild],
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
    expect(_declaredPlatforms(pubspec), _ciBuildFor.keys.toSet(),
        reason: 'decisions/0003 claims all six for 1.0; changing the set is '
            'a decision to record there, not a pubspec edit');
  });

  test('every declared platform has a CI leg that builds it', () {
    for (final String platform in _declaredPlatforms(pubspec)) {
      final List<String>? markers = _ciBuildFor[platform];
      expect(markers, isNotNull, reason: 'no known CI build for $platform');
      for (final String marker in markers!) {
        expect(ci, contains(marker),
            reason: '$platform is declared but ci.yml lacks "$marker", '
                'so no leg builds it');
      }
    }
  });
}
