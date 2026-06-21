@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/report_format.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';

import '../support/workspace.dart';

TextElement _txt(String id, String text, {String? expression}) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 2, width: 300, height: 16),
      text: text,
      expression: expression,
    );

/// The `default` fixture authored directly as a [ReportDefinition], matching the
/// ids/elements the 1→2 migration assigns (path-based id scheme).
ReportDefinition _authoredDefault() => ReportDefinition(
      name: 'Default',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: Band(
            id: 'furniture/pageHeader',
            type: BandType.pageHeader,
            height: 20,
            elements: <ReportElement>[_txt('hdr', 'Report')]),
        pageFooter: Band(
            id: 'furniture/pageFooter',
            type: BandType.pageFooter,
            height: 20,
            elements: <ReportElement>[
              _txt('pg', 'Page',
                  expression:
                      r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}')
            ]),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
                id: 'root/c0',
                type: BandType.detail,
                height: 22,
                elements: <ReportElement>[
                  _txt('name', 'name', expression: r'$F{name}')
                ])),
          ],
        ),
      ),
    );

List<PageFrame> _frames(ReportDefinition def) {
  final RenderedReport report = const JetReportEngine().renderDefinition(
    def,
    JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'name': 'Alice'},
      <String, Object?>{'name': 'Bob'},
    ]),
  );
  return <PageFrame>[
    for (int i = 0; i < report.pageCount; i++) report.pageAt(i).frame,
  ];
}

void main() {
  test('a migrated v1 report equals the same report authored directly (C7)',
      () {
    final String json = File(
            '${findWorkspaceRoot().path}/packages/jet_print/test/fixtures/v1/default.json')
        .readAsStringSync();
    final ReportDefinition migrated =
        JetReportFormat.decodeDefinitionJson(json);
    final ReportDefinition authored = _authoredDefault();

    // The migrated tree equals the hand-authored tree (ids, types, elements).
    expect(migrated, equals(authored));

    // And they render to byte-identical frames.
    final List<PageFrame> migratedFrames = _frames(migrated);
    final List<PageFrame> authoredFrames = _frames(authored);
    expect(migratedFrames.length, authoredFrames.length);
    for (int i = 0; i < migratedFrames.length; i++) {
      expect(migratedFrames[i], equals(authoredFrames[i]));
    }
  });
}
