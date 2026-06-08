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
  final Directory dataDir =
      Directory('${root.path}/packages/jet_print/lib/src/data');
  final Directory expressionDir =
      Directory('${root.path}/packages/jet_print/lib/src/expression');

  List<File> domainFiles() => domainDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((FileSystemEntity f) => f.path.endsWith('.dart'))
      .toList();

  List<File> dataFiles() => dataDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((FileSystemEntity f) => f.path.endsWith('.dart'))
      .toList();

  List<File> expressionFiles() => expressionDir
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

  group('layer boundaries — data seam', () {
    test('the data seam has source files to check (no false green)', () {
      expect(dataDir.existsSync(), isTrue, reason: 'Missing ${dataDir.path}');
      expect(dataFiles(), isNotEmpty,
          reason: 'No .dart files found under ${dataDir.path}');
    });

    test('data imports no outer seam and no Flutter UI library', () {
      final List<String> violations = <String>[];
      for (final File file in dataFiles()) {
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
        reason: 'The data seam may depend only on domain. Violations:\n'
            '${violations.join('\n')}',
      );
    });
  });

  group('layer boundaries — expression seam', () {
    test('the expression seam has source files to check (no false green)', () {
      expect(expressionDir.existsSync(), isTrue,
          reason: 'Missing ${expressionDir.path}');
      expect(expressionFiles(), isNotEmpty,
          reason: 'No .dart files found under ${expressionDir.path}');
    });

    test('expression imports no outer seam and no Flutter UI library', () {
      final List<String> violations = <String>[];
      for (final File file in expressionFiles()) {
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
        reason:
            'The expression seam may depend only on domain/data (and intl). '
            'Violations:\n${violations.join('\n')}',
      );
    });
  });

  group('layer boundaries — rendering seam', () {
    final Directory renderingDir =
        Directory('${root.path}/packages/jet_print/lib/src/rendering');
    List<File> renderingFiles() => renderingDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((FileSystemEntity f) => f.path.endsWith('.dart'))
        .toList();

    test('the rendering seam has source files to check (no false green)', () {
      expect(renderingDir.existsSync(), isTrue);
      expect(renderingFiles(), isNotEmpty);
    });

    test('rendering imports no designer seam', () {
      final List<String> violations = <String>[];
      for (final File file in renderingFiles()) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (uri.contains('designer')) violations.add('${file.path} -> $uri');
        }
      }
      expect(violations, isEmpty,
          reason: 'Rendering must not depend on the designer seam:\n'
              '${violations.join('\n')}');
    });

    test('only paint/canvas_painter.dart imports dart:ui / Flutter UI', () {
      final List<String> violations = <String>[];
      for (final File file in renderingFiles()) {
        final String path = file.path.replaceAll(r'\', '/');
        final bool isCanvasPainter =
            path.endsWith('/paint/canvas_painter.dart');
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (_isFlutterUi(uri) && !isCanvasPainter) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Only CanvasPainter may import dart:ui; frame/text/'
              'report_painter must stay headless:\n${violations.join('\n')}');
    });

    test('the elements/ seam exists and stays Flutter-free', () {
      final Directory elementsDir = Directory(
          '${root.path}/packages/jet_print/lib/src/rendering/elements');
      expect(elementsDir.existsSync(), isTrue,
          reason: 'Missing ${elementsDir.path}');
      final List<File> elementsFiles = elementsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((FileSystemEntity f) => f.path.endsWith('.dart'))
          .toList();
      expect(elementsFiles, isNotEmpty);
      final List<String> violations = <String>[];
      for (final File file in elementsFiles) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (_isFlutterUi(uri)) violations.add('${file.path} -> $uri');
        }
      }
      expect(violations, isEmpty,
          reason: 'rendering/elements must stay headless (no dart:ui/Flutter):\n'
              '${violations.join('\n')}');
    });

    test('the fill/ seam exists, stays Flutter-free, and imports no sibling '
        'rendering subdir', () {
      final Directory fillDir = Directory(
          '${root.path}/packages/jet_print/lib/src/rendering/fill');
      expect(fillDir.existsSync(), isTrue, reason: 'Missing ${fillDir.path}');
      final List<File> fillFiles = fillDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((FileSystemEntity f) => f.path.endsWith('.dart'))
          .toList();
      expect(fillFiles, isNotEmpty);
      final List<String> violations = <String>[];
      for (final File file in fillFiles) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          // A fill file (lib/src/rendering/fill/) reaches a rendering sibling via a
          // RELATIVE import like '../elements/foo.dart' (the codebase enforces
          // prefer_relative_imports, so this — not a package: URI — is the real
          // violation shape). The absolute '/rendering/<sibling>/' forms are kept as
          // defense-in-depth for any package-qualified import. Note: the relative
          // '../elements/' form does NOT match the LEGITIMATE '../../domain/elements/'
          // import (TextElement/ImageElement live in domain/elements/), because that
          // path has no '..' immediately before '/elements/'.
          final bool sibling = uri.contains('../elements/') ||
              uri.contains('../frame/') ||
              uri.contains('../paint/') ||
              uri.contains('../text/') ||
              uri.contains('/rendering/elements/') ||
              uri.contains('/rendering/frame/') ||
              uri.contains('/rendering/paint/') ||
              uri.contains('/rendering/text/');
          if (_isFlutterUi(uri) || sibling) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'rendering/fill must stay headless and depend only on '
              'domain/data/expression:\n${violations.join('\n')}');
    });

    test('the layout/ seam exists, stays Flutter-free, and imports no '
        'expression engine', () {
      final Directory layoutDir = Directory(
          '${root.path}/packages/jet_print/lib/src/rendering/layout');
      expect(layoutDir.existsSync(), isTrue,
          reason: 'Missing ${layoutDir.path}');
      final List<File> layoutFiles = layoutDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((FileSystemEntity f) => f.path.endsWith('.dart'))
          .toList();
      expect(layoutFiles, isNotEmpty);
      final List<String> violations = <String>[];
      for (final File file in layoutFiles) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          // 008a is pure geometry: layout composes domain + sibling rendering
          // subdirs (frame/elements/text/fill) but must NOT reach the expression
          // engine. A relative '../../expression/' or absolute '/expression/' is
          // the violation shape.
          final bool expressionSeam =
              uri.contains('../../expression/') || uri.contains('/expression/');
          if (_isFlutterUi(uri) || expressionSeam) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'rendering/layout must stay headless and free of the '
              'expression engine (008a is pure geometry):\n'
              '${violations.join('\n')}');
    });
  });
}
