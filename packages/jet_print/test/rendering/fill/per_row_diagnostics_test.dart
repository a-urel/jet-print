// Per-row data diagnostics carry the row position and are bounded (spec E2,
// R2 missing field + R7 non-row collection entry).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 100, height: 12);

TextElement _el(String id, {String? text, String? expr}) =>
    TextElement(id: id, bounds: _r, text: text ?? '', expression: expr);

ReportDefinition _flat(List<ReportElement> detail) => ReportDefinition(
      name: 'perRow',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 12,
              elements: detail)),
        ]),
      ),
    );

List<Diagnostic> _warnings(FillResult res) => res.diagnostics.entries
    .where((Diagnostic d) => d.severity == DiagnosticSeverity.warning)
    .toList();

void main() {
  test('R2: missing field is row-tagged, once per row, elementId preserved',
      () {
    final FillResult res = ReportFiller().fillDefinition(
      _flat(<ReportElement>[_el('bad', expr: r'$F{nope}')]),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'name': 'a'},
        <String, Object?>{'name': 'b'},
      ]),
    );
    final List<Diagnostic> w = _warnings(res);
    expect(w, hasLength(2), reason: 'one per row, not globally deduped');
    expect(w[0].message, startsWith('Row 1: '));
    expect(w[0].message, contains('nope'));
    expect(w[0].elementId, 'bad');
    expect(w[1].message, startsWith('Row 2: '));
  });

  test('R7: a non-row collection entry is row-tagged', () {
    final FillResult res = ReportFiller().fillDefinition(
      ReportDefinition(
        name: 'r7',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(Band(
                    id: 'line',
                    type: BandType.detail,
                    height: 12,
                    elements: <ReportElement>[_el('v', expr: r'$F{v}')])),
              ],
            )),
          ]),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{
          'lines': <Object?>[
            <String, Object?>{'v': 1},
            'I am not a row', // non-row entry
          ],
        },
      ]),
    );
    final Diagnostic d = _warnings(res)
        .firstWhere((Diagnostic d) => d.message.contains('non-row entry'),
            orElse: () => fail('no non-row-entry diagnostic: '
                '${res.diagnostics.entries}'));
    expect(d.message, startsWith('Row 1: '));
  });
}
