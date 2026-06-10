// Diagnostics instead of crashes (011 — contracts C9/C10 / SC-007; FR-013/
// FR-014). The full malformed-input matrix: unknown field, missing parameter,
// expression-evaluation errors (type mismatch, divide-by-zero), empty
// dataset, and URL-only image. Each produces a SPECIFIC diagnostic (with
// elementId where applicable) and a non-crashing, best-effort render: the
// offending element falls back (blank / '!ERR' / placeholder) while the
// surrounding content renders normally.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/value_type.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

const PageFormat _page =
    PageFormat(width: 400, height: 400, margins: JetEdgeInsets.all(10));

TextElement _text(String id, String expression, {double y = 0}) => TextElement(
      id: id,
      bounds: JetRect(x: 0, y: y, width: 360, height: 16),
      text: id,
      expression: expression,
    );

ReportTemplate _template(List<ReportElement> detailElements,
        {List<ReportParameter> parameters = const <ReportParameter>[],
        List<ReportBand> extraBands = const <ReportBand>[]}) =>
    ReportTemplate(
      name: 'diag',
      page: _page,
      parameters: parameters,
      bands: <ReportBand>[
        ReportBand(type: BandType.detail, height: 80, elements: detailElements),
        ...extraBands,
      ],
    );

JetInMemoryDataSource _rows() => JetInMemoryDataSource(<Map<String, Object?>>[
      <String, Object?>{'name': 'alpha', 'qty': 2},
    ]);

Map<String, String> _texts(RenderedReport report) => <String, String>{
      for (final TextRunPrimitive p
          in report.pageAt(0).frame.primitives.whereType<TextRunPrimitive>())
        if (p.elementId != null)
          p.elementId!: p.lines.map((TextLine l) => l.text).join(),
    };

Diagnostic _diagnosticMatching(RenderedReport report, Pattern pattern) =>
    report.diagnostics.entries.firstWhere(
      (Diagnostic d) => d.message.contains(pattern),
      orElse: () => fail('no diagnostic matching "$pattern" in '
          '${report.diagnostics.entries}'),
    );

void main() {
  test(
      'unknown field -> specific warning with elementId + blank fallback, '
      'surrounding content renders', () {
    final RenderedReport report = const JetReportEngine().render(
      _template(<ReportElement>[
        _text('good', r'$F{name}'),
        _text('bad', r'$F{nope}', y: 20),
      ]),
      _rows(),
    );
    final Diagnostic d = _diagnosticMatching(report, 'nope');
    expect(d.severity, DiagnosticSeverity.warning);
    expect(d.elementId, 'bad');
    final Map<String, String> texts = _texts(report);
    expect(texts['good'], 'alpha', reason: 'surrounding content renders');
    expect(texts['bad'], '', reason: 'the offending element falls back blank');
  });

  test(
      'missing parameter -> specific diagnostic naming the parameter + '
      'blank fallback', () {
    final RenderedReport report = const JetReportEngine().render(
      _template(
        <ReportElement>[
          _text('good', r'$F{name}'),
          _text('by', r'$P{printedBy}', y: 20),
        ],
        parameters: const <ReportParameter>[
          ReportParameter(name: 'printedBy', type: JetFieldType.string),
        ],
      ),
      _rows(),
      // No parameters supplied.
    );
    final Diagnostic d = _diagnosticMatching(report, 'printedBy');
    expect(d.severity, DiagnosticSeverity.warning);
    expect(_texts(report)['by'], '');
    expect(_texts(report)['good'], 'alpha');
  });

  test('a declared parameter default fills in without a diagnostic', () {
    final RenderedReport report = const JetReportEngine().render(
      _template(
        <ReportElement>[_text('by', r'$P{printedBy}')],
        parameters: const <ReportParameter>[
          ReportParameter(
              name: 'printedBy',
              type: JetFieldType.string,
              defaultValue: 'system'),
        ],
      ),
      _rows(),
    );
    expect(_texts(report)['by'], 'system');
    expect(report.diagnostics.entries, isEmpty);
  });

  test('expression type mismatch -> error diagnostic + !ERR fallback', () {
    final RenderedReport report = const JetReportEngine().render(
      _template(<ReportElement>[
        _text('good', r'$F{name}'),
        _text('boom', r'$F{name} * 2', y: 20),
      ]),
      _rows(),
    );
    final Diagnostic d = _diagnosticMatching(report, 'Expression error');
    expect(d.severity, DiagnosticSeverity.error);
    expect(d.elementId, 'boom');
    expect(_texts(report)['boom'], '!ERR');
    expect(_texts(report)['good'], 'alpha');
  });

  test('divide-by-zero -> error diagnostic + !ERR fallback', () {
    final RenderedReport report = const JetReportEngine().render(
      _template(<ReportElement>[
        _text('boom', r'$F{qty} / 0'),
      ]),
      _rows(),
    );
    final Diagnostic d = _diagnosticMatching(report, 'zero');
    expect(d.severity, DiagnosticSeverity.error);
    expect(d.elementId, 'boom');
    expect(_texts(report)['boom'], '!ERR');
  });

  test('empty dataset -> specific diagnostic + noData best-effort render', () {
    final RenderedReport report = const JetReportEngine().render(
      ReportTemplate(
        name: 'empty',
        page: _page,
        bands: <ReportBand>[
          ReportBand(
            type: BandType.detail,
            height: 20,
            elements: <ReportElement>[_text('d', r'$F{name}')],
          ),
          ReportBand(
            type: BandType.noData,
            height: 20,
            elements: const <ReportElement>[
              TextElement(
                id: 'nd',
                bounds: JetRect(x: 0, y: 0, width: 360, height: 16),
                text: 'No data available',
              ),
            ],
          ),
        ],
      ),
      JetInMemoryDataSource(const <Map<String, Object?>>[]),
    );
    _diagnosticMatching(report, 'no rows');
    expect(report.pageCount, 1);
    expect(_texts(report)['nd'], 'No data available',
        reason: 'the noData band renders instead of details');
  });

  test(
      'URL-only image -> diagnostic with elementId + placeholder render, '
      'no I/O (FR-012b/FR-015)', () {
    final RenderedReport report = const JetReportEngine().render(
      _template(<ReportElement>[
        const ImageElement(
          id: 'logo',
          bounds: JetRect(x: 0, y: 0, width: 60, height: 40),
          source: UrlImageSource('https://example.com/logo.png'),
        ),
        _text('good', r'$F{name}', y: 50),
      ]),
      _rows(),
    );
    final Diagnostic d = _diagnosticMatching(report, 'logo');
    expect(d.elementId, 'logo');
    // The shared renderer draws a placeholder for the unresolved image: the
    // element still contributes primitives (no crash, no network fetch).
    final Iterable<FramePrimitive> placeholder = report
        .pageAt(0)
        .frame
        .primitives
        .where((FramePrimitive p) => p.elementId == 'logo');
    expect(placeholder, isNotEmpty);
    expect(placeholder.whereType<ImagePrimitive>(), isEmpty,
        reason: 'no bytes were fetched — the library performs no I/O');
    expect(_texts(report)['good'], 'alpha');
  });

  test(
      'the whole matrix at once still renders — 0 unhandled crashes '
      '(SC-007), diagnostics merged fill-then-layout in order (FR-013)', () {
    final RenderedReport report = const JetReportEngine().render(
      _template(
        <ReportElement>[
          _text('unknown', r'$F{nope}'),
          _text('mismatch', r'$F{name} * 2', y: 20),
          const ImageElement(
            id: 'logo',
            bounds: JetRect(x: 0, y: 40, width: 60, height: 40),
            source: UrlImageSource('https://example.com/logo.png'),
          ),
          _text('good', r'$F{name}', y: 90),
        ],
        parameters: const <ReportParameter>[
          ReportParameter(name: 'missing', type: JetFieldType.string),
        ],
        extraBands: <ReportBand>[
          // A chrome expression referencing a field: a LAYOUT-pass warning.
          const ReportBand(
            type: BandType.pageFooter,
            height: 16,
            elements: <ReportElement>[
              TextElement(
                id: 'pf',
                bounds: JetRect(x: 0, y: 0, width: 360, height: 12),
                text: '',
                expression: r'$F{name}',
              ),
            ],
          ),
        ],
      ),
      _rows(),
    );
    expect(_texts(report)['good'], 'alpha');

    final List<String> messages =
        report.diagnostics.entries.map((Diagnostic d) => d.message).toList();
    int indexOf(Pattern p) => messages.indexWhere((String m) => m.contains(p));
    expect(indexOf('missing'), greaterThanOrEqualTo(0));
    expect(indexOf('nope'), greaterThanOrEqualTo(0));
    expect(indexOf('chrome text'), greaterThanOrEqualTo(0));
    // Merged in pass order: parameter (pre-fill) -> fill -> layout (FR-013).
    expect(indexOf('missing'), lessThan(indexOf('nope')));
    expect(indexOf('nope'), lessThan(indexOf('chrome text')));
  });
}
