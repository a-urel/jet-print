import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/report_format.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';
import 'package:jet_print/src/rendering/legacy/report_template_adapter.dart';

import '../support/workspace.dart';

const List<String> _fixtures = <String>[
  'default',
  'invoice',
  'multi_level_grouped',
  'deep_master_detail',
  'empty_data',
  'furniture_reserved',
];

String _json(String name) => File(
        '${findWorkspaceRoot().path}/packages/jet_print/test/fixtures/v1/$name.json')
    .readAsStringSync();

/// A representative populated dataset spanning every field the fixtures bind,
/// with two invoices, two regions/categories (group breaks) and nested
/// lines→notes (deep master/detail). Both pipelines consume identical data.
List<Map<String, Object?>> _populated() => <Map<String, Object?>>[
      <String, Object?>{
        'name': 'Row A', 'invoiceNo': 'INV-1', 'customerName': 'Acme',
        'total': 12.0, 'region': 'West', 'category': 'X', 'amount': 5.0,
        'item': 'Widget', 'orderNo': 'O-1',
        'lines': <Map<String, Object?>>[
          <String, Object?>{
            'description': 'Bolt', 'qty': 2, 'unitPrice': 1.5, 'lineTotal': 3.0,
            'notes': <Map<String, Object?>>[
              <String, Object?>{'note': 'urgent'},
            ],
          },
        ],
      },
      <String, Object?>{
        'name': 'Row B', 'invoiceNo': 'INV-1', 'customerName': 'Acme',
        'total': 9.0, 'region': 'West', 'category': 'X', 'amount': 4.0,
        'item': 'Gear', 'orderNo': 'O-1',
        'lines': <Map<String, Object?>>[],
      },
      <String, Object?>{
        'name': 'Row C', 'invoiceNo': 'INV-2', 'customerName': 'Globex',
        'total': 20.0, 'region': 'East', 'category': 'Y', 'amount': 11.0,
        'item': 'Cog', 'orderNo': 'O-2',
        'lines': <Map<String, Object?>>[
          <String, Object?>{
            'description': 'Nut', 'qty': 5, 'unitPrice': 0.4, 'lineTotal': 2.0,
            'notes': <Map<String, Object?>>[
              <String, Object?>{'note': 'n1'},
              <String, Object?>{'note': 'n2'},
            ],
          },
        ],
      },
    ];

JetDataSource _source(List<Map<String, Object?>> rows) =>
    JetInMemoryDataSource(rows);

List<String> _messages(ReportDiagnostics d) =>
    d.entries.map((Object e) => e.toString()).toList();

void main() {
  group('engine parity (native ReportDefinition pipeline == legacy template '
      'pipeline) — C6', () {
    for (final String name in _fixtures) {
      for (final bool empty in <bool>[false, true]) {
        final String label = '$name (${empty ? 'empty' : 'populated'})';
        test('$label fills + paginates byte-identically', () {
          final String json = _json(name);
          final ReportTemplate template = JetReportFormat.decodeJson(json);
          final ReportDefinition def = convertTemplate(template);
          final List<Map<String, Object?>> rows =
              empty ? <Map<String, Object?>>[] : _populated();

          final FillResult legacyFill =
              ReportFiller().fill(template, _source(rows));
          final FillResult nativeFill =
              ReportFiller().fillDefinition(def, _source(rows));

          // 1) The Fill IR is byte-identical (same band stream + variable snaps).
          expect(nativeFill.report, equals(legacyFill.report),
              reason: '$label: FilledReport');
          expect(_messages(nativeFill.diagnostics),
              _messages(legacyFill.diagnostics),
              reason: '$label: fill diagnostics');

          // 2) Pagination produces byte-identical frames.
          final List<PageFrame> legacyPages =
              ReportLayouter().layout(template, legacyFill.report).pages;
          final List<PageFrame> nativePages = ReportLayouter()
              .layoutDefinition(def, nativeFill.report)
              .pages;
          expect(nativePages.length, legacyPages.length,
              reason: '$label: page count');
          for (int i = 0; i < legacyPages.length; i++) {
            expect(nativePages[i], equals(legacyPages[i]),
                reason: '$label: page $i frame');
          }
        });
      }
    }
  });
}
