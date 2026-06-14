import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/report_format.dart';
import 'package:jet_print/src/rendering/legacy/report_template_adapter.dart';

import '../../support/workspace.dart';

String _fixtureJson(String name) {
  final Directory root = findWorkspaceRoot();
  return File('${root.path}/packages/jet_print/test/fixtures/v1/$name.json')
      .readAsStringSync();
}

void main() {
  group('convertTemplate (ReportTemplate → ReportDefinition)', () {
    // The 1→2 JSON migration is the tested oracle: the in-memory object
    // converter must produce exactly what migrating the same report's JSON
    // produces (same tree, same ids, same resetGroup rewrites, same elements).
    for (final String name in <String>[
      'default',
      'invoice',
      'multi_level_grouped',
      'deep_master_detail',
      'empty_data',
      'furniture_reserved',
    ]) {
      test('$name converts identically to the JSON migration', () {
        final String json = _fixtureJson(name);
        final ReportTemplate template = JetReportFormat.decodeJson(json);
        expect(
          convertTemplate(template),
          equals(JetReportFormat.decodeDefinitionJson(json)),
        );
      });
    }
  });
}
