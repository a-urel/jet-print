// Architecture (layer-boundary) test (FR-007 / SC-005).
//
// Makes the inward-dependency rule executable rather than aspirational: the
// domain seam is the innermost layer, so no file under lib/src/domain may import
// the rendering or designer seams, nor any Flutter UI/rendering library. A
// violation fails the suite (and CI) deterministically.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

/// Captures the URI of an `import`/`export` directive.
final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Flutter libraries that pull in UI/rendering and therefore must never appear
/// in the pure-Dart domain seam. `package:flutter/foundation.dart` is allowed
/// (it is UI-free).
const Set<String> _forbiddenFlutterUiUris = <String>{
  'package:flutter/material.dart',
  'package:flutter/widgets.dart',
  'package:flutter/rendering.dart',
  'package:flutter/cupertino.dart',
  'package:flutter/painting.dart',
};

bool _reachesOtherSeam(String uri) =>
    uri.contains('rendering') || uri.contains('designer');

bool _isFlutterUi(String uri) =>
    _forbiddenFlutterUiUris.contains(uri) || uri.startsWith('dart:ui');

void main() {
  final Directory root = findWorkspaceRoot();
  final Directory domainDir =
      Directory('${root.path}/packages/jet_print/lib/src/domain');

  List<File> domainFiles() => domainDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((FileSystemEntity f) => f.path.endsWith('.dart'))
      .toList();

  group('layer boundaries — domain seam', () {
    test('the domain seam has source files to check (no false green)', () {
      expect(domainDir.existsSync(), isTrue,
          reason: 'Missing ${domainDir.path}');
      expect(domainFiles(), isNotEmpty,
          reason: 'No .dart files found under ${domainDir.path}');
    });

    test('domain imports no other seam and no Flutter UI library', () {
      final List<String> violations = <String>[];
      for (final File file in domainFiles()) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (_reachesOtherSeam(uri) || _isFlutterUi(uri)) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'The domain seam must depend on nothing inward. Violations:\n'
            '${violations.join('\n')}',
      );
    });
  });
}
