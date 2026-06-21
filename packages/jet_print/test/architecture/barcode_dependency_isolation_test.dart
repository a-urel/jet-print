// Architecture test: barcode package isolation (FR-011 / SC-009).
//
// Asserts that `package:barcode/` is used ONLY through the single adapter seam
// (`package_barcode_encoder.dart`) and never leaks into other rendering files
// or the domain layer.  A violation fails the suite (and CI) deterministically.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/workspace.dart';

void main() {
  test('only package_barcode_encoder.dart imports package:barcode', () {
    final Directory root = findWorkspaceRoot();
    final offenders = <String>[];
    for (final f in Directory(
      '${root.path}/packages/jet_print/lib',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('package_barcode_encoder.dart')) continue;
      if (f.readAsStringSync().contains("package:barcode/")) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: 'barcode pkg leaked: $offenders');
  });

  test('domain does not import the encoder seam or barcode pkg', () {
    final Directory root = findWorkspaceRoot();
    final offenders = <String>[];
    for (final f in Directory(
      '${root.path}/packages/jet_print/lib/src/domain',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      if (s.contains('rendering/elements/barcode') ||
          s.contains('package:barcode/')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: 'domain leaked: $offenders');
  });
}
