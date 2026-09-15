import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// Resolves the bundled sample against the package rather than the process's
/// working directory. `flutter test` is documented (README, CI, AGENTS.md) to
/// run from the workspace ROOT with the member packages named explicitly, which
/// leaves `Directory.current` at the root — so a bare relative path resolves to
/// the wrong place and the test fails everywhere except inside the app folder.
File _bundledSample() {
  const String relative = 'sample_data/invoice.jetreport.datasource';
  for (final String prefix in <String>['', 'apps/jet_print_playground/']) {
    final File candidate = File('$prefix$relative');
    if (candidate.existsSync()) return candidate;
  }
  fail('Could not locate $relative from ${Directory.current.path}');
}

void main() {
  test('bundled sample invoice.jetreport.datasource decodes', () {
    final String text = _bundledSample().readAsStringSync();
    final JetDataSourceDocument doc = JetDataSourceFile.decodeJson(text);
    expect(doc.schema.name, 'Invoice');
    expect(doc.schema.fields.any((FieldDef f) => f.name == 'lines'), isTrue);
    expect(doc.sample, isNotNull);
  });
}
