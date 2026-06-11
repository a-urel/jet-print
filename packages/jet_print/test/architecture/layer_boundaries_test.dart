// Architecture (layer-boundary) test (FR-007 / SC-005).
//
// Makes the inward-dependency rule executable rather than aspirational: the
// domain seam is the innermost layer, so no file under lib/src/domain may import
// the rendering or designer seams, nor any Flutter UI/rendering library. A
// violation fails the suite (and CI) deterministically.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

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

  group('layer boundaries — designer ruler helpers (014)', () {
    // The pure measurement seam: RulerScale/RulerTick + the points↔mm and
    // selection-extent metrics. They must stay Flutter-/rendering-free (C7.2,
    // FR-016) and carry NO coupling to selection-drag or guide state, so
    // draggable alignment guides can be layered on later without touching the
    // measurement model. They depend only on dart:math + view/geometry inputs.
    final File rulerScale = File(
        '${root.path}/packages/jet_print/lib/src/designer/canvas/ruler_scale.dart');
    final File rulerMetrics = File(
        '${root.path}/packages/jet_print/lib/src/designer/canvas/ruler_metrics.dart');

    test('the pure ruler helpers exist (no false green)', () {
      expect(rulerScale.existsSync(), isTrue,
          reason: 'Missing ${rulerScale.path}');
      expect(rulerMetrics.existsSync(), isTrue,
          reason: 'Missing ${rulerMetrics.path}');
    });

    test('they import no rendering/Flutter-UI library', () {
      final List<String> violations = <String>[];
      for (final File file in <File>[rulerScale, rulerMetrics]) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (_isFlutterUi(uri) ||
              uri.startsWith('package:flutter/') ||
              uri.contains('rendering')) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason:
              'RulerScale/metrics must stay pure (dart:math + view/geometry '
              'only):\n${violations.join('\n')}');
    });

    test('they carry no coupling to selection-drag or guide state (FR-016)',
        () {
      final List<String> violations = <String>[];
      for (final File file in <File>[rulerScale, rulerMetrics]) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          // The measurement model may read the current Selection + layout, but
          // must not reach drag/snap/guide/command machinery — that coupling is
          // what would block adding draggable guides later.
          if (uri.contains('snapping') ||
              uri.contains('guide') ||
              uri.contains('/commands/') ||
              uri.contains('command')) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'the measurement model must not couple to drag/guide state:\n'
              '${violations.join('\n')}');
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

    test(
        'only paint/canvas_painter.dart and paint/page_rasterizer.dart '
        'import dart:ui / Flutter UI', () {
      final List<String> violations = <String>[];
      for (final File file in renderingFiles()) {
        final String path = file.path.replaceAll(r'\', '/');
        // The two declared dart:ui paint backends: the preview's canvas
        // painter (011) and the PNG rasterizer composing it (012 — PNG
        // encoding is an engine capability). Nothing else.
        final bool isDeclaredUiBackend =
            path.endsWith('/paint/canvas_painter.dart') ||
                path.endsWith('/paint/page_rasterizer.dart');
        // The single sanctioned exception besides the painters (011):
        // RenderOptions carries the host's per-render `Locale` — a pure value
        // type from dart:ui with a const constructor. No other dart:ui symbol
        // may be used there, and no other engine file may import dart:ui.
        final bool isRenderOptions =
            path.endsWith('/engine/render_options.dart');
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (_isFlutterUi(uri) && !isDeclaredUiBackend && !isRenderOptions) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Only CanvasPainter + PageRasterizer (and RenderOptions, '
              'for the Locale value type) may import dart:ui; '
              'frame/text/report_painter/export must stay headless:\n'
              '${violations.join('\n')}');
    });

    test(
        'the engine/ facade seam exists and only depends inward '
        '(fill/layout/frame/expression/data/domain)', () {
      final Directory engineDir =
          Directory('${root.path}/packages/jet_print/lib/src/rendering/engine');
      expect(engineDir.existsSync(), isTrue,
          reason: 'Missing ${engineDir.path}');
      final List<File> engineFiles = engineDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((FileSystemEntity f) => f.path.endsWith('.dart'))
          .toList();
      expect(engineFiles, isNotEmpty);
      final List<String> violations = <String>[];
      for (final File file in engineFiles) {
        final String path = file.path.replaceAll(r'\', '/');
        final bool isRenderOptions = path.endsWith('/render_options.dart');
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          // The facade composes fill + layout and wraps frames; it must not
          // reach the designer seam nor the paint/text/elements siblings, and
          // (except RenderOptions' Locale) stays Flutter-free.
          final bool outward = uri.contains('designer') ||
              uri.contains('../paint/') ||
              uri.contains('../text/') ||
              uri.contains('../elements/') ||
              uri.contains('/rendering/paint/') ||
              uri.contains('/rendering/text/') ||
              uri.contains('/rendering/elements/');
          if (outward || (_isFlutterUi(uri) && !isRenderOptions)) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'rendering/engine may depend only inward '
              '(fill/layout/frame/expression/data/domain):\n'
              '${violations.join('\n')}');
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
          reason:
              'rendering/elements must stay headless (no dart:ui/Flutter):\n'
              '${violations.join('\n')}');
    });

    test(
        'the fill/ seam exists, stays Flutter-free, and imports no sibling '
        'rendering subdir', () {
      final Directory fillDir =
          Directory('${root.path}/packages/jet_print/lib/src/rendering/fill');
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

    test(
        'the export/ seam stays pure Dart (012): PDF generation must be '
        'usable headlessly, with no dart:ui or Flutter import', () {
      final Directory exportDir =
          Directory('${root.path}/packages/jet_print/lib/src/rendering/export');
      expect(exportDir.existsSync(), isTrue,
          reason: 'Missing ${exportDir.path}');
      final List<File> exportFiles = exportDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((FileSystemEntity f) => f.path.endsWith('.dart'))
          .toList();
      expect(exportFiles, isNotEmpty);
      final List<String> violations = <String>[];
      for (final File file in exportFiles) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (_isFlutterUi(uri) || uri.startsWith('package:flutter/')) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'rendering/export must stay headless pure Dart '
              '(package:pdf, package:image, and inward seams only):\n'
              '${violations.join('\n')}');
    });

    test(
        'the print seam (012) is outermost: package:printing lives ONLY in '
        'lib/src/print/, and no library file imports the print seam', () {
      final Directory libDir = Directory('${root.path}/packages/jet_print/lib');
      final Directory printDir =
          Directory('${root.path}/packages/jet_print/lib/src/print');
      expect(printDir.existsSync(), isTrue, reason: 'Missing ${printDir.path}');
      final List<File> libFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((FileSystemEntity f) => f.path.endsWith('.dart'))
          .toList();
      expect(libFiles, isNotEmpty);
      final List<String> violations = <String>[];
      for (final File file in libFiles) {
        final String path = file.path.replaceAll(r'\', '/');
        final bool inPrintSeam = path.contains('/lib/src/print/');
        final bool isEntryPoint = path.endsWith('/lib/jet_print.dart');
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (uri.startsWith('package:printing/') && !inPrintSeam) {
            violations.add('${file.path} -> $uri (printing outside seam)');
          }
          // The print seam is OUTERMOST: only the public entry point may
          // export it; no other library file may import it.
          final bool reachesPrintSeam =
              uri.contains('src/print/') || uri.contains('../print/');
          if (reachesPrintSeam && !inPrintSeam && !isEntryPoint) {
            violations.add('${file.path} -> $uri (print seam imported)');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'printing is confined to lib/src/print/ behind the '
              'presenter abstraction:\n${violations.join('\n')}');
    });

    test(
        'the public entry point exports the 011 render surface '
        '(engine, options, render IR, diagnostics, data-source API)', () {
      final File entry =
          File('${root.path}/packages/jet_print/lib/jet_print.dart');
      final Set<String> exported = _directive
          .allMatches(entry.readAsStringSync())
          .map((Match m) => m.group(1)!)
          .toSet();
      const List<String> required = <String>[
        'src/rendering/engine/jet_report_engine.dart',
        'src/rendering/engine/render_options.dart',
        'src/rendering/engine/rendered_report.dart',
        'src/rendering/export/jet_report_exporter.dart',
        'src/print/jet_report_printer.dart',
        'src/rendering/fill/report_diagnostics.dart',
        'src/data/jet_data_source.dart',
        'src/data/in_memory_data_source.dart',
        'src/data/json_data_source.dart',
        'src/data/object_data_source.dart',
        'src/data/data_set.dart',
        'src/data/data_row.dart',
      ];
      final List<String> missing = <String>[
        for (final String uri in required)
          if (!exported.contains(uri)) uri,
      ];
      expect(missing, isEmpty,
          reason: 'lib/jet_print.dart must export the full 011 surface; '
              'missing:\n${missing.join('\n')}');
    });

    test(
        'the 012 export/print public surface matches contract §1 EXACTLY '
        '(exporter, printer, presenter typedef, exception — nothing more)', () {
      final String entry =
          File('${root.path}/packages/jet_print/lib/jet_print.dart')
              .readAsStringSync();
      Set<String> shownBy(String uri) {
        final RegExp re =
            RegExp("export\\s+'${RegExp.escape(uri)}'\\s+show\\s+([^;]+);");
        final Match? m = re.firstMatch(entry);
        expect(m, isNotNull,
            reason: 'jet_print.dart must export $uri with an explicit '
                '`show` combinator');
        return m!
            .group(1)!
            .split(',')
            .map((String s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toSet();
      }

      expect(shownBy('src/rendering/export/jet_report_exporter.dart'),
          <String>{'JetReportExporter'});
      expect(shownBy('src/print/jet_report_printer.dart'), <String>{
        'JetReportPrinter',
        'PrintDialogPresenter',
        'PrintUnavailableException',
      });
    });

    test(
        'the render path is read-only over templates: schemaVersion stays 1 '
        '(FR-016)', () {
      // No schema change, no migration: the existing format round-trips
      // unchanged. The dedicated round-trip / UnknownElement passthrough
      // tests cover fidelity; this pins the version constant itself.
      const ReportTemplate template =
          ReportTemplate(name: 'fr016', page: PageFormat.a4Portrait);
      expect(JetReportFormat.encode(template)['schemaVersion'], 1);
    });

    test('the layout/ seam exists and stays Flutter-free', () {
      final Directory layoutDir =
          Directory('${root.path}/packages/jet_print/lib/src/rendering/layout');
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
          // layout stays headless. Since 008c it MAY import the expression engine
          // (page-scoped chrome substitution): expression is inward of rendering
          // in the dependency DAG, so the import is legal. The Flutter-UI ban
          // remains.
          if (_isFlutterUi(uri)) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'rendering/layout must stay headless (Flutter-free):\n'
              '${violations.join('\n')}');
    });
  });
}
