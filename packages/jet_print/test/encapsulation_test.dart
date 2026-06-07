// Encapsulation test (SC-007 / FR-011).
//
// Two invariants, both enforced by scanning *import/export directives only*
// (so the literal strings used as patterns below never match themselves):
//
//   (a) No consumer file — the library's own tests (which stand in for an
//       external consumer) or the tester app — reaches into
//       `package:jet_print/src/...`. The public entry point is the only door.
//   (b) No library file under `lib/` depends on the tester or any host app
//       (FR-011): the product must stand alone.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/workspace.dart';

/// Captures the URI of a Dart `import`/`export` directive (single- or
/// double-quoted). Matching directives — not raw substrings — avoids
/// false positives from string literals that merely mention a path.
final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

List<File> _dartFiles(Directory dir) {
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((FileSystemEntity f) => f.path.endsWith('.dart'))
      .toList();
}

Iterable<String> _directiveUris(File file) => _directive
    .allMatches(file.readAsStringSync())
    .map((Match m) => m.group(1)!);

/// White-box seam tests legitimately import the library's own internals to
/// exercise the un-exported `domain`/`data`/`rendering` types in isolation
/// (SC-004).
/// They are the package's OWN tests, not external consumers, so the `src` ban
/// (which protects external consumers per SC-007) does not apply to them. The
/// allowlist is intentionally narrow: every other test stays default-deny.
bool _isWhiteBoxSeamTest(File file) {
  final String path = file.path.replaceAll(r'\', '/');
  return path.contains('/test/domain/') ||
      path.contains('/test/data/') ||
      path.contains('/test/rendering/');
}

void main() {
  final Directory root = findWorkspaceRoot();
  final Directory libraryLib = Directory('${root.path}/packages/jet_print/lib');
  final Directory libraryTest =
      Directory('${root.path}/packages/jet_print/test');
  final Directory testerLib =
      Directory('${root.path}/apps/jet_print_tester/lib');

  group('encapsulation', () {
    test('the source trees to scan actually exist (no false green)', () {
      // Guards against a wrong working directory silently skipping a scan and
      // reporting a vacuous pass.
      for (final Directory dir in <Directory>[
        libraryLib,
        libraryTest,
        testerLib,
      ]) {
        expect(
          dir.existsSync(),
          isTrue,
          reason: 'Expected ${dir.path} to exist; the encapsulation scan '
              'would otherwise be skipped and give a false pass.',
        );
      }
    });

    test('no consumer file imports package:jet_print/src/...', () {
      final List<String> violations = <String>[];
      for (final Directory dir in <Directory>[libraryTest, testerLib]) {
        for (final File file in _dartFiles(dir)) {
          if (_isWhiteBoxSeamTest(file)) continue;
          for (final String uri in _directiveUris(file)) {
            if (uri.startsWith('package:jet_print/src/')) {
              violations.add('${file.path} -> $uri');
            }
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Consumers must import only package:jet_print/jet_print.dart:\n'
            '${violations.join('\n')}',
      );
    });

    test('no library file depends on tester/host app code (FR-011)', () {
      final List<String> violations = <String>[];
      for (final File file in _dartFiles(libraryLib)) {
        for (final String uri in _directiveUris(file)) {
          if (uri.startsWith('package:jet_print_tester')) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'The library MUST NOT import tester/host code:\n'
            '${violations.join('\n')}',
      );
    });
  });
}
