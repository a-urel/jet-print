// JetReportEngine facade (011 — contracts C1/C3): fill resolves tokens to
// values, parameters thread through, pagination repeats chrome with a correct
// page count, and rendering is deterministic.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/value_type.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

// 200x100 page, 10pt margins -> 80pt printable height. With 20pt page
// header + footer, body capacity is 40pt.
const PageFormat _smallPage =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

TextElement _text(String id, String expression, {double y = 0}) => TextElement(
      id: id,
      bounds: JetRect(x: 0, y: y, width: 180, height: 16),
      text: id,
      expression: expression,
    );

/// All rendered text across [frame], element id -> joined run text.
Map<String, String> _texts(PageFrame frame) => <String, String>{
      for (final TextRunPrimitive p
          in frame.primitives.whereType<TextRunPrimitive>())
        if (p.elementId != null)
          p.elementId!: p.lines.map((TextLine l) => l.text).join(),
    };

/// Every rendered text run on every page of [report].
List<String> _allRuns(RenderedReport report) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          p.lines.map((TextLine l) => l.text).join(),
    ];

void main() {
  group('C1 — fill resolves tokens to values', () {
    final ReportTemplate template = ReportTemplate(
      name: 'flat',
      page: _smallPage,
      parameters: const <ReportParameter>[
        ReportParameter(name: 'printedBy', type: JetFieldType.string),
      ],
      bands: <ReportBand>[
        ReportBand(
          type: BandType.title,
          height: 20,
          elements: <ReportElement>[_text('by', r'$P{printedBy}')],
        ),
        ReportBand(
          type: BandType.detail,
          height: 20,
          elements: <ReportElement>[_text('name', r'$F{name}')],
        ),
      ],
    );
    final JetInMemoryDataSource source =
        JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'name': 'alpha'},
      <String, Object?>{'name': 'beta'},
      <String, Object?>{'name': 'gamma'},
    ]);

    test('every bound element shows its evaluated value — zero tokens', () {
      final RenderedReport report = const JetReportEngine().render(
        template,
        source,
        options:
            const RenderOptions(parameters: <String, Object?>{'printedBy': 'A. Urel'}),
      );
      final List<String> runs = _allRuns(report);
      expect(runs, containsAll(<String>['alpha', 'beta', 'gamma']));
      for (final String run in runs) {
        expect(run, isNot(contains(r'$F{')));
        expect(run, isNot(contains(r'$P{')));
        expect(run, isNot(contains(r'$V{')));
      }
    });

    test('a parameter-bound element shows the supplied value', () {
      final RenderedReport report = const JetReportEngine().render(
        template,
        source,
        options: const RenderOptions(
            parameters: <String, Object?>{'printedBy': 'A. Urel'}),
      );
      expect(_allRuns(report), contains('A. Urel'));
    });
  });

  group('C3 — pagination with repeated chrome', () {
    final ReportTemplate template = ReportTemplate(
      name: 'paged',
      page: _smallPage,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.pageHeader,
          height: 20,
          elements: <ReportElement>[_text('hd', r'"HEADER"')],
        ),
        ReportBand(
          type: BandType.detail,
          height: 30,
          elements: <ReportElement>[_text('name', r'$F{name}')],
        ),
        ReportBand(
          type: BandType.pageFooter,
          height: 20,
          elements: <ReportElement>[
            _text('pf', r'"Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}'),
          ],
        ),
      ],
    );
    // Body capacity 40pt and 30pt bands -> exactly one row per page.
    final JetInMemoryDataSource source =
        JetInMemoryDataSource(<Map<String, Object?>>[
      for (int i = 0; i < 5; i++) <String, Object?>{'name': 'row $i'},
    ]);

    test('content splits at band boundaries with a correct page count', () {
      final RenderedReport report =
          const JetReportEngine().render(template, source);
      expect(report.pageCount, 5);
      for (int i = 0; i < 5; i++) {
        expect(_texts(report.pageAt(i).frame)['name'], 'row $i');
      }
    });

    test('page header/footer repeat on every page; PAGE_X/COUNT resolve', () {
      final RenderedReport report =
          const JetReportEngine().render(template, source);
      for (int i = 0; i < report.pageCount; i++) {
        final Map<String, String> texts = _texts(report.pageAt(i).frame);
        expect(texts['hd'], 'HEADER');
        expect(texts['pf'], 'Page ${i + 1} of 5');
      }
    });
  });

  group('determinism (FR-010 / SC-004)', () {
    test('identical inputs render byte-identical pages', () {
      final ReportTemplate template = ReportTemplate(
        name: 'det',
        page: _smallPage,
        bands: <ReportBand>[
          ReportBand(
            type: BandType.detail,
            height: 20,
            elements: <ReportElement>[
              _text('v', r'FORMAT($F{amount}, "#,##0.00")'),
            ],
          ),
        ],
      );
      JetInMemoryDataSource source() =>
          JetInMemoryDataSource(<Map<String, Object?>>[
            for (int i = 0; i < 5; i++) <String, Object?>{'amount': i * 11.3},
          ]);
      const RenderOptions options = RenderOptions(locale: Locale('de'));
      final RenderedReport a =
          const JetReportEngine().render(template, source(), options: options);
      final RenderedReport b =
          const JetReportEngine().render(template, source(), options: options);
      expect(a.pageCount, b.pageCount);
      for (int i = 0; i < a.pageCount; i++) {
        expect(a.pageAt(i).frame, b.pageAt(i).frame,
            reason: 'page $i must be byte-identical across renders');
      }
    });
  });
}
