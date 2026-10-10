// `jetPrintVersion` is the version a host reads at runtime, and pub.dev
// publishes the `version:` in pubspec.yaml. They are set by hand in two files,
// so a release that bumps one and not the other ships a library that reports
// the wrong version. This pins them together.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/workspace.dart';

void main() {
  test('jetPrintVersion matches the version in pubspec.yaml', () {
    final String pubspec = File(
      '${findWorkspaceRoot().path}/packages/jet_print/pubspec.yaml',
    ).readAsStringSync();
    final Match? declared =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);

    expect(declared, isNotNull, reason: 'pubspec.yaml has no version: line');
    expect(
      jetPrintVersion,
      declared!.group(1),
      reason: 'Bump lib/src/version.dart together with pubspec.yaml.',
    );
  });
}
