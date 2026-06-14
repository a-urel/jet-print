import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_validation.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

Band _row(String id) => Band(
      id: id,
      type: BandType.detail,
      height: 10,
      elements: <ReportElement>[
        TextElement(
            id: '$id.v',
            bounds: const JetRect(x: 0, y: 0, width: 50, height: 10),
            text: 'v',
            expression: r'$F{v}'),
      ],
    );

ReportDefinition _def(DetailScope root) =>
    ReportDefinition(name: 'D', page: PageFormat.a4Portrait, body: ReportBody(root: root));

int _detailCount(ReportDefinition def, List<Map<String, Object?>> rows) {
  final FilledReport r =
      ReportFiller().fillDefinition(def, JetInMemoryDataSource(rows)).report;
  return r.bands.where((FilledBand b) => b.type == BandType.detail).length;
}

bool _infoFlagged(ReportDefinition def) => validate(def).any((Diagnostic d) =>
    d.severity == DiagnosticSeverity.info &&
    d.message.toLowerCase().contains('not yet rendered'));

void main() {
  group('deferred capabilities render inert (C9)', () {
    test('per-scope grouping is ignored at render but flagged by validate()', () {
      // A nested scope carrying groups — the engine renders its rows as today
      // (no nested group bands), the groups are simply inert.
      final ReportDefinition def = _def(DetailScope(
        id: 'root',
        children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'root/c0',
            collectionField: 'items',
            groups: const <GroupLevel>[
              GroupLevel(id: 'root/c0/g0', name: 'g', key: r'$F{k}'),
            ],
            children: <ScopeNode>[BandNode(_row('root/c0/c0'))],
          )),
        ],
      ));
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[
        <String, Object?>{
          'items': <Map<String, Object?>>[
            <String, Object?>{'k': 'a', 'v': 1},
            <String, Object?>{'k': 'b', 'v': 2},
          ],
        },
      ];

      // Renders without error; the two item rows emit, the nested groups don't.
      expect(() => const JetReportEngine().renderDefinition(
          def, JetInMemoryDataSource(rows)), returnsNormally);
      final FilledReport r =
          ReportFiller().fillDefinition(def, JetInMemoryDataSource(rows)).report;
      expect(r.bands.where((FilledBand b) => b.type == BandType.detail).length, 2);
      expect(
          r.bands.any((FilledBand b) =>
              b.type == BandType.groupHeader || b.type == BandType.groupFooter),
          isFalse);
      expect(_infoFlagged(def), isTrue);
    });

    test('multiple per-row bands in a scope all emit, without error', () {
      final ReportDefinition def = _def(DetailScope(
        id: 'root',
        children: <ScopeNode>[
          NestedScope(DetailScope(
            id: 'root/c0',
            collectionField: 'items',
            children: <ScopeNode>[BandNode(_row('a')), BandNode(_row('b'))],
          )),
        ],
      ));
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[
        <String, Object?>{
          'items': <Map<String, Object?>>[
            <String, Object?>{'v': 1},
          ],
        },
      ];
      expect(() => const JetReportEngine().renderDefinition(
          def, JetInMemoryDataSource(rows)), returnsNormally);
      expect(_detailCount(def, rows), 2); // both per-row bands emit
      expect(_infoFlagged(def), isTrue);
    });
  });
}
