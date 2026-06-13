// Encapsulation test (SC-007 / FR-011).
//
// Two invariants, both enforced by scanning *import/export directives only*
// (so the literal strings used as patterns below never match themselves):
//
//   (a) No consumer file — the library's own tests (which stand in for an
//       external consumer) or the playground app — reaches into
//       `package:jet_print/src/...`. The public entry point is the only door.
//   (b) No library file under `lib/` depends on the playground or any host app
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
/// exercise the un-exported `domain`/`data`/`expression`/`rendering` types in
/// isolation (SC-004).
/// They are the package's OWN tests, not external consumers, so the `src` ban
/// (which protects external consumers per SC-007) does not apply to them. The
/// allowlist is intentionally narrow: every other test stays default-deny.
bool _isWhiteBoxSeamTest(File file) {
  final String path = file.path.replaceAll(r'\', '/');
  return path.contains('/test/domain/') ||
      path.contains('/test/data/') ||
      path.contains('/test/expression/') ||
      path.contains('/test/rendering/') ||
      path.contains('/test/print/') ||
      // Designer-internal seams (013): the value-field template compiler and the
      // design-time binding token are unexported `src/` modules; their unit
      // tests are white-box. The wider designer widget tests still use the
      // public API only.
      path.contains('/test/designer/template/') ||
      path.endsWith('/test/designer/binding_token_test.dart') ||
      // Canvas-rulers (014): the pure measurement helpers (RulerScale/RulerTick
      // and the points↔mm + selection-extent metrics) are unexported `src/`
      // modules deliberately isolated from Flutter so the tricky math is
      // unit-testable; their unit tests are white-box (Principle III).
      path.endsWith('/test/designer/canvas/ruler_scale_test.dart') ||
      path.endsWith('/test/designer/canvas/ruler_metrics_test.dart') ||
      // Grid & snap (015): `gridLineOffsets` (and the grid/snap tunables it
      // shares with the snap geometry) is an unexported `src/` helper kept
      // Flutter-free so the adaptive-density math is unit-testable; its unit
      // test is white-box (Principle III).
      path.endsWith('/test/designer/canvas/grid_geometry_test.dart') ||
      // Paper & margin presets (018): the standard-size / margin recognition
      // helpers are unexported `src/` pure functions (the `format_presets.dart`
      // precedent — preset identity is derived for display, never persisted);
      // their unit tests are white-box (Principle III).
      path.endsWith('/test/designer/paper_presets_test.dart') ||
      path.endsWith('/test/designer/margin_presets_test.dart') ||
      // Bundled-font preload (021 follow-up): the designer-mount engine
      // preload is an unexported `src/` helper with an injectable loader so
      // the family/byte wiring is unit-testable without dart:ui; its unit
      // test is white-box (Principle III).
      path.endsWith('/test/designer/font_preload_test.dart');
}

void main() {
  final Directory root = findWorkspaceRoot();
  final Directory libraryLib = Directory('${root.path}/packages/jet_print/lib');
  final Directory libraryTest =
      Directory('${root.path}/packages/jet_print/test');
  final Directory playgroundLib =
      Directory('${root.path}/apps/jet_print_playground/lib');

  group('encapsulation', () {
    test('the source trees to scan actually exist (no false green)', () {
      // Guards against a wrong working directory silently skipping a scan and
      // reporting a vacuous pass.
      for (final Directory dir in <Directory>[
        libraryLib,
        libraryTest,
        playgroundLib,
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
      for (final Directory dir in <Directory>[libraryTest, playgroundLib]) {
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

    test('no library file depends on playground/host app code (FR-011)', () {
      final List<String> violations = <String>[];
      for (final File file in _dartFiles(libraryLib)) {
        for (final String uri in _directiveUris(file)) {
          if (uri.startsWith('package:jet_print_playground')) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'The library MUST NOT import playground/host code:\n'
            '${violations.join('\n')}',
      );
    });
  });
}
