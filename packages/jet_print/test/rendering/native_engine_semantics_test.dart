@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/serialization/report_format.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

import '../support/workspace.dart';

ReportDefinition _fixture(String name) => JetReportFormat.decodeDefinitionJson(
    File('${findWorkspaceRoot().path}/packages/jet_print/test/fixtures/v1/$name.json')
        .readAsStringSync());

FilledReport _fill(ReportDefinition def, List<Map<String, Object?>> rows) =>
    ReportFiller().fillDefinition(def, JetInMemoryDataSource(rows)).report;

void main() {
  group('native engine semantics (C8)', () {
    test(
        'master-level multi-level grouping cascades (outer→inner open, '
        'inner→outer close)', () {
      final FilledReport r =
          _fill(_fixture('multi_level_grouped'), <Map<String, Object?>>[
        <String, Object?>{'region': 'West', 'category': 'X', 'amount': 1.0},
        <String, Object?>{'region': 'West', 'category': 'Y', 'amount': 2.0},
        <String, Object?>{'region': 'East', 'category': 'Z', 'amount': 3.0},
      ]);
      final List<String> groupBands = <String>[
        for (final FilledBand b in r.bands)
          if (b.type == BandType.groupHeader || b.type == BandType.groupFooter)
            '${b.type == BandType.groupHeader ? 'H' : 'F'}:${b.group}',
      ];
      expect(groupBands, <String>[
        'H:region', 'H:category', // open West/X
        'F:category', 'H:category', // X→Y break (region intact)
        'F:category', 'F:region', // close Y, West …
        'H:region', 'H:category', // … open East/Z
        'F:category', 'F:region', // final close inner→outer
      ]);
    });

    test('arbitrary-depth master/detail iterates nested collections', () {
      final FilledReport r =
          _fill(_fixture('deep_master_detail'), <Map<String, Object?>>[
        <String, Object?>{
          'orderNo': 'O1',
          'lines': <Map<String, Object?>>[
            <String, Object?>{
              'description': 'L1',
              'notes': <Map<String, Object?>>[
                <String, Object?>{'note': 'n1'},
                <String, Object?>{'note': 'n2'},
              ],
            },
            <String, Object?>{'description': 'L2', 'notes': <Object?>[]},
          ],
        },
      ]);
      // 1 master "order" band + 2 line bands + 2 note bands = 5 detail bands.
      final int detailBands =
          r.bands.where((FilledBand b) => b.type == BandType.detail).length;
      expect(detailBands, 5);
    });

    test('startNewPage puts each group instance on its own page', () {
      final RenderedReport report = const JetReportEngine().renderDefinition(
        _fixture('invoice'),
        JetInMemoryDataSource(<Map<String, Object?>>[
          <String, Object?>{
            'invoiceNo': 'INV-1',
            'customerName': 'Acme',
            'total': 3.0,
            'lines': <Map<String, Object?>>[
              <String, Object?>{'description': 'a', 'lineTotal': 3.0},
            ],
          },
          <String, Object?>{
            'invoiceNo': 'INV-2',
            'customerName': 'Globex',
            'total': 5.0,
            'lines': <Map<String, Object?>>[
              <String, Object?>{'description': 'b', 'lineTotal': 5.0},
            ],
          },
        ]),
      );
      expect(report.pageCount, 2);
    });

    test('an empty dataset renders the noData band', () {
      final FilledReport r =
          _fill(_fixture('empty_data'), const <Map<String, Object?>>[]);
      expect(r.bands.any((FilledBand b) => b.type == BandType.noData), isTrue);
      expect(r.bands.any((FilledBand b) => b.type == BandType.detail), isFalse);
    });

    test('page furniture substitutes PAGE_NUMBER/PAGE_COUNT per page', () {
      final RenderedReport report = const JetReportEngine().renderDefinition(
        _fixture('default'),
        JetInMemoryDataSource(<Map<String, Object?>>[
          for (int i = 0; i < 60; i++) <String, Object?>{'name': 'r$i'},
        ]),
      );
      expect(report.pageCount, greaterThan(1));
      // The page footer reads "Page N of M", so each page's frame differs.
      expect(report.pageAt(0).frame, isNot(equals(report.pageAt(1).frame)));
    });
  });
}
