// T016 / FR-007: RenderOptions.knownFields makes an unresolved binding render
// the (host-localizable) unresolvedFieldToken end-to-end through the engine;
// omitting knownFields renders empty (no regression, SC-005).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ReportTemplate _template() => ReportTemplate(
      name: 'unresolved',
      page: _page,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 20,
          elements: <ReportElement>[
            const TextElement(
              id: 'who',
              bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
              text: 'who',
              expression: r'$F{missing}',
            ),
          ],
        ),
      ],
    );

final JetInMemoryDataSource _source = JetInMemoryDataSource(
  <Map<String, Object?>>[
    <String, Object?>{'name': 'Ada'},
  ],
);

List<String> _runs(RenderedReport report) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          p.lines.map((TextLine l) => l.text).join(),
    ];

void main() {
  test('schema-aware render shows the token for an unknown field', () {
    final RenderedReport report = const JetReportEngine().render(
      _template(),
      _source,
      options: const RenderOptions(knownFields: <String>{'name'}),
    );
    expect(_runs(report), contains('#ERROR'));
  });

  test('a host-localized token is used verbatim', () {
    final RenderedReport report = const JetReportEngine().render(
      _template(),
      _source,
      options: const RenderOptions(
        knownFields: <String>{'name'},
        unresolvedFieldToken: '#HATA',
      ),
    );
    expect(_runs(report), contains('#HATA'));
  });

  test('without knownFields the binding renders empty (no regression)', () {
    final RenderedReport report =
        const JetReportEngine().render(_template(), _source);
    expect(_runs(report), isNot(contains('#ERROR')));
  });
}
