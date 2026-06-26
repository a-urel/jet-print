// test/rendering/fill/fill_visibility_test.dart
// Visibility wiring: invisible elements are omitted from FilledBand.elements;
// invisible bands are absent from the band stream (collapse).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';

const JetRect _r = JetRect(x: 0, y: 0, width: 100, height: 10);

TextElement _t(String id, {String text = '.', BoolProperty? visible}) =>
    TextElement(
      id: id,
      bounds: _r,
      text: text,
      visible: visible ?? const BoolProperty(),
    );

Band _detailBand(List<ReportElement> elements,
        {BoolProperty? visible, String id = 'detail'}) =>
    Band(
      id: id,
      type: BandType.detail,
      height: 10,
      elements: elements,
      visible: visible ?? const BoolProperty(),
    );

ReportDefinition _def({
  Band? titleBand,
  Band? detailBand,
  Band? summaryBand,
}) =>
    ReportDefinition(
      name: 'test',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: titleBand,
        summary: summaryBand,
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            if (detailBand != null) BandNode(detailBand),
          ],
        ),
      ),
    );

void main() {
  test('invisible element (static false) is omitted from FilledBand.elements',
      () {
    final FillResult res = ReportFiller().fillDefinition(
      _def(
        detailBand: _detailBand(<ReportElement>[
          _t('visible-el', text: 'Show'),
          _t('hidden-el',
              text: 'Hide', visible: const BoolProperty(value: false)),
        ]),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'x': 1},
      ]),
    );
    expect(res.report.bands, hasLength(1));
    final FilledBand detail = res.report.bands.single;
    expect(detail.elements, hasLength(1));
    expect((detail.elements.single as TextElement).id, 'visible-el');
  });

  test(
      'invisible band (static false) is absent from the band stream (collapse)',
      () {
    final FillResult res = ReportFiller().fillDefinition(
      _def(
        titleBand: Band(
          id: 'title',
          type: BandType.title,
          height: 10,
          elements: <ReportElement>[_t('t')],
          visible: const BoolProperty(value: false),
        ),
        detailBand: _detailBand(<ReportElement>[_t('d', text: 'Detail')]),
        summaryBand: Band(
          id: 'summary',
          type: BandType.summary,
          height: 10,
          elements: <ReportElement>[_t('s')],
          visible: const BoolProperty(value: false),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'x': 1},
      ]),
    );
    // Title and summary are invisible → only the detail band is emitted.
    final List<BandType> types =
        res.report.bands.map((FilledBand b) => b.type).toList();
    expect(types, <BandType>[BandType.detail]);
  });

  test('per-row visible expression hides element on non-matching rows', () {
    // visible when $F{flag} == true — only the first row has flag == true.
    final FillResult res = ReportFiller().fillDefinition(
      _def(
        detailBand: _detailBand(<ReportElement>[
          _t('always', text: 'A'),
          _t('conditional',
              text: 'C',
              visible: const BoolProperty(expression: r'$F{flag} == true')),
        ]),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'flag': true},
        <String, Object?>{'flag': false},
      ]),
    );
    // Two detail bands (one per row).
    expect(res.report.bands, hasLength(2));

    // Row 0: flag == true → both elements present.
    final FilledBand row0 = res.report.bands[0];
    final List<String> ids0 =
        row0.elements.map((ReportElement e) => e.id).toList();
    expect(ids0, containsAll(<String>['always', 'conditional']));

    // Row 1: flag == false → only 'always' present.
    final FilledBand row1 = res.report.bands[1];
    final List<String> ids1 =
        row1.elements.map((ReportElement e) => e.id).toList();
    expect(ids1, contains('always'));
    expect(ids1, isNot(contains('conditional')));
  });

  test('all-visible report is unchanged (regression)', () {
    // Same structure as report_filler_test flat-data golden, but measured by
    // element count so golden bytes are not coupled here.
    final FillResult res = ReportFiller().fillDefinition(
      _def(
        titleBand: Band(
          id: 'title',
          type: BandType.title,
          height: 10,
          elements: <ReportElement>[_t('h', text: 'Report')],
        ),
        detailBand: _detailBand(
            <ReportElement>[_t('d1', text: 'A'), _t('d2', text: 'B')]),
        summaryBand: Band(
          id: 'summary',
          type: BandType.summary,
          height: 10,
          elements: <ReportElement>[_t('s', text: 'End')],
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'x': 1},
        <String, Object?>{'x': 2},
      ]),
    );
    // title + 2 × detail + summary = 4 bands; each detail band has 2 elements.
    expect(res.report.bands, hasLength(4));
    expect(res.report.bands[0].type, BandType.title);
    expect(res.report.bands[0].elements, hasLength(1));
    expect(res.report.bands[1].type, BandType.detail);
    expect(res.report.bands[1].elements, hasLength(2));
    expect(res.report.bands[2].type, BandType.detail);
    expect(res.report.bands[2].elements, hasLength(2));
    expect(res.report.bands[3].type, BandType.summary);
    expect(res.report.bands[3].elements, hasLength(1));
    expect(res.diagnostics.entries, isEmpty);
  });
}
