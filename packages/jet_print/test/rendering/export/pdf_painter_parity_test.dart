// PdfPainter <-> CanvasPainter parity (012 — contract B2; research §6; T005).
//
// Pins the per-primitive semantics of the PDF backend against the canvas
// backend's documented behavior, on hand-built frames:
//   * each pre-measured TextLine lands at its exact baseline
//     y' = pageHeight - (bounds.y + line.baseline) with CanvasPainter's
//     left/center/right alignment math (line.baseline is measured FROM THE
//     BLOCK TOP — see TextLine docs/MetricsTextMeasurer);
//   * images use the shared computeImageFit src/dst rects;
//   * rect/path emit fill FIRST, then stroke (CanvasPainter order);
//   * the top-left -> bottom-left y-mapping happens per draw call — there is
//     no global y-flip CTM (which would mirror glyphs).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/shape_element_renderer.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';
import 'package:jet_print/src/rendering/export/pdf_painter.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/image_fit.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/jet_font.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';
import 'package:jet_print/src/rendering/text/underline_metrics.dart';

import '../../support/test_fonts.dart';
import 'support/export_fixtures.dart';
import 'support/pdf_inspector.dart';

/// 200 x 100 pt sheet: pageHeight = 100 keeps the y-mapping arithmetic legible.
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(0));
const double _pageHeight = 100;

final RegExp _tdRe = RegExp(r'([\d.+-]+)\s+([\d.+-]+)\s+Td\b');
final RegExp _lineRe =
    RegExp(r'([\d.+-]+)\s+([\d.+-]+)\s+m\s+([\d.+-]+)\s+([\d.+-]+)\s+l\s+S\b');

/// Paints [primitives] on the small page and returns (inspector, content).
Future<(PdfInspector, String)> _paint(List<FramePrimitive> primitives,
    {FontRegistry? fonts}) async {
  final PdfPainter painter =
      PdfPainter(fonts ?? (FontRegistry()..registerDefault()));
  await paintFrame(PageFrame(page: _page, primitives: primitives), painter);
  final Uint8List bytes = await painter.save();
  final PdfInspector pdf = PdfInspector(bytes);
  return (pdf, pdf.contentOf(0));
}

void main() {
  final FontRegistry fonts = FontRegistry()..registerDefault();
  final MetricsTextMeasurer measurer = MetricsTextMeasurer(fonts);

  group('text — baseline and alignment parity', () {
    const JetTextStyle style = JetTextStyle(fontSize: 12);
    final MeasuredText measured = measurer.measure('Hi', style);
    const JetRect bounds = JetRect(x: 10, y: 20, width: 120, height: 40);

    TextRunPrimitive run(JetTextAlign align) => TextRunPrimitive(
          bounds: bounds,
          lines: measured.lines,
          style: JetTextStyle(fontSize: 12, align: align),
          fontFamily: measured.fontFamily,
        );

    test('a TextLine is placed at its exact pre-measured baseline', () async {
      final (_, String content) = await _paint(<FramePrimitive>[
        run(JetTextAlign.left),
      ], fonts: fonts);
      final Match td = _tdRe.firstMatch(content)!;
      expect(double.parse(td.group(1)!), closeTo(bounds.x, 0.001));
      expect(
          double.parse(td.group(2)!),
          closeTo(
              _pageHeight - (bounds.y + measured.lines.single.baseline), 0.001),
          reason: 'PDF baseline y = pageHeight - (bounds.y + line.baseline); '
              'line.baseline already includes line.top (block-top origin)');
    });

    test('center and right alignment use CanvasPainter\'s extra-space math',
        () async {
      final double extra = bounds.width - measured.lines.single.width;
      for (final (JetTextAlign align, double expectedX)
          in <(JetTextAlign, double)>[
        (JetTextAlign.center, bounds.x + extra / 2),
        (JetTextAlign.right, bounds.x + extra),
      ]) {
        final (_, String content) =
            await _paint(<FramePrimitive>[run(align)], fonts: fonts);
        final Match td = _tdRe.firstMatch(content)!;
        expect(double.parse(td.group(1)!), closeTo(expectedX, 0.001),
            reason: '$align: x = bounds.x + extra * (0|1/2|1)');
      }
    });

    test('every wrapped line lands on its own baseline (no re-wrapping)',
        () async {
      final MeasuredText wrapped = measurer
          .measure('alpha beta gamma delta epsilon zeta', style, maxWidth: 60);
      expect(wrapped.lines.length, greaterThan(1), reason: 'fixture sanity');
      final (_, String content) = await _paint(<FramePrimitive>[
        TextRunPrimitive(
          bounds: bounds,
          lines: wrapped.lines,
          style: style,
          fontFamily: wrapped.fontFamily,
        ),
      ], fonts: fonts);
      final List<Match> tds = _tdRe.allMatches(content).toList();
      expect(tds.length, wrapped.lines.length,
          reason: 'one text object per pre-measured line — the painter must '
              'never merge or re-wrap lines');
      for (int i = 0; i < wrapped.lines.length; i++) {
        expect(
            double.parse(tds[i].group(2)!),
            closeTo(
                _pageHeight - (bounds.y + wrapped.lines[i].baseline), 0.001),
            reason: 'line $i baseline');
      }
    });

    test('empty lines are skipped, exactly like CanvasPainter', () async {
      final MeasuredText twoSegments = measurer.measure('top\n\nbottom', style);
      final (_, String content) = await _paint(<FramePrimitive>[
        TextRunPrimitive(
          bounds: bounds,
          lines: twoSegments.lines,
          style: style,
          fontFamily: twoSegments.fontFamily,
        ),
      ], fonts: fonts);
      final int nonEmpty =
          twoSegments.lines.where((TextLine l) => l.text.isNotEmpty).length;
      expect(_tdRe.allMatches(content).length, nonEmpty,
          reason: 'blank lines draw nothing (but still occupy vertical space '
              'via the following lines\' baselines)');
    });
  });

  group('text — underline parity (021 / US1 / C11)', () {
    test(
        'an underlined run strokes one line segment per text line at the '
        'shared underlineFor geometry', () async {
      const JetTextStyle style = JetTextStyle(fontSize: 12, underline: true);
      final MeasuredText measured = measurer.measure('Hi', style);
      const JetRect bounds = JetRect(x: 10, y: 20, width: 120, height: 40);
      final (_, String content) = await _paint(<FramePrimitive>[
        TextRunPrimitive(
          bounds: bounds,
          lines: measured.lines,
          style: style,
          fontFamily: measured.fontFamily,
        ),
      ], fonts: fonts);

      final ({double offset, double thickness}) m = underlineFor(12);
      final TextLine line = measured.lines.single;
      final double y = _pageHeight - (bounds.y + line.baseline + m.offset);

      final Match seg = _lineRe.firstMatch(content)!;
      expect(double.parse(seg.group(1)!), closeTo(bounds.x, 0.001),
          reason: 'segment starts at the aligned dx');
      expect(double.parse(seg.group(2)!), closeTo(y, 0.001),
          reason: 'segment sits underlineFor().offset below the baseline');
      expect(double.parse(seg.group(3)!), closeTo(bounds.x + line.width, 0.001),
          reason: 'segment spans the measured line width');
      expect(double.parse(seg.group(4)!), closeTo(y, 0.001),
          reason: 'the segment is horizontal');
      final Match width = RegExp(r'([\d.]+)\s+w\b').firstMatch(content)!;
      expect(double.parse(width.group(1)!), closeTo(m.thickness, 0.001),
          reason: 'stroke width = underlineFor().thickness');
    });

    test('a non-underlined run strokes no line segment', () async {
      const JetTextStyle style = JetTextStyle(fontSize: 12);
      final MeasuredText measured = measurer.measure('Hi', style);
      final (_, String content) = await _paint(<FramePrimitive>[
        TextRunPrimitive(
          bounds: const JetRect(x: 10, y: 20, width: 120, height: 40),
          lines: measured.lines,
          style: style,
          fontFamily: measured.fontFamily,
        ),
      ], fonts: fonts);
      expect(_lineRe.hasMatch(content), isFalse);
    });

    test('an underlined centered run places the segment at the aligned dx',
        () async {
      const JetTextStyle style = JetTextStyle(
          fontSize: 12, underline: true, align: JetTextAlign.center);
      final MeasuredText measured = measurer.measure('Hi', style);
      const JetRect bounds = JetRect(x: 10, y: 20, width: 120, height: 40);
      final (_, String content) = await _paint(<FramePrimitive>[
        TextRunPrimitive(
          bounds: bounds,
          lines: measured.lines,
          style: style,
          fontFamily: measured.fontFamily,
        ),
      ], fonts: fonts);
      final double extra = bounds.width - measured.lines.single.width;
      final Match seg = _lineRe.firstMatch(content)!;
      expect(double.parse(seg.group(1)!), closeTo(bounds.x + extra / 2, 0.001),
          reason: 'the underline rides the same alignment math as the glyphs');
    });
  });

  group('images — shared computeImageFit geometry', () {
    test('contain: full source mapped into the centered dst rect', () async {
      const JetRect bounds = JetRect(x: 10, y: 10, width: 60, height: 40);
      final (PdfInspector pdf, _) = await _paint(<FramePrimitive>[
        ImagePrimitive(bounds: bounds, bytes: tinyPngBytes()),
      ]);
      final ImageFit fit =
          computeImageFit(JetBoxFit.contain, bounds, 4, 2); // 4x2 source
      final PdfImageDraw draw = pdf.imageDrawsOn(0).single;
      expect(draw.width, closeTo(fit.dst.width, 0.001));
      expect(draw.height, closeTo(fit.dst.height, 0.001));
      expect(draw.x, closeTo(fit.dst.x, 0.001));
      expect(
          draw.y, closeTo(_pageHeight - (fit.dst.y + fit.dst.height), 0.001));
    });

    test('cover: the cropped src maps onto bounds via a clip + scaled draw',
        () async {
      const JetRect bounds = JetRect(x: 10, y: 10, width: 60, height: 40);
      final (PdfInspector pdf, _) = await _paint(<FramePrimitive>[
        ImagePrimitive(
            bounds: bounds, bytes: tinyPngBytes(), fit: JetBoxFit.cover),
      ]);
      final ImageFit fit = computeImageFit(JetBoxFit.cover, bounds, 4, 2);
      // The painter clips to dst and draws the FULL image scaled so the src
      // window lands exactly on dst (drawImageRect semantics).
      final double scaleX = fit.dst.width / fit.src.width;
      final double scaleY = fit.dst.height / fit.src.height;
      final PdfImageDraw draw = pdf.imageDrawsOn(0).single;
      expect(draw.width, closeTo(4 * scaleX, 0.001));
      expect(draw.height, closeTo(2 * scaleY, 0.001));
      expect(draw.x, closeTo(fit.dst.x - fit.src.x * scaleX, 0.001));
      final double fullTop = fit.dst.y - fit.src.y * scaleY;
      expect(draw.y, closeTo(_pageHeight - (fullTop + 2 * scaleY), 0.001));
      final PdfClipRect clip = pdf.clipRectsOn(0).single;
      expect(clip.x, closeTo(fit.dst.x, 0.001));
      expect(
          clip.y, closeTo(_pageHeight - (fit.dst.y + fit.dst.height), 0.001));
      expect(clip.width, closeTo(fit.dst.width, 0.001));
      expect(clip.height, closeTo(fit.dst.height, 0.001));
    });
  });

  group('shapes — operator and ordering parity', () {
    test('rect with fill and stroke emits fill FIRST, then stroke', () async {
      final (_, String content) = await _paint(<FramePrimitive>[
        const RectPrimitive(
          bounds: JetRect(x: 10, y: 20, width: 50, height: 30),
          fill: JetColor(0xFFFF0000),
          stroke: JetColor(0xFF0000FF),
          strokeWidth: 2,
        ),
      ]);
      // y' = 100 - (20 + 30) = 50.
      expect(content, contains('10 50 50 30 re'));
      final int fillIdx = content.indexOf(RegExp(r're\s+f\b'));
      final int strokeIdx = content.indexOf(RegExp(r're\s+S\b'));
      expect(fillIdx, isNot(-1), reason: 'missing rect fill');
      expect(strokeIdx, isNot(-1), reason: 'missing rect stroke');
      expect(fillIdx, lessThan(strokeIdx),
          reason: 'CanvasPainter paints fill first, then the stroke on top');
      expect(content, contains('2 w'), reason: 'stroke width');
    });

    test('line maps both endpoints per draw call', () async {
      final (_, String content) = await _paint(<FramePrimitive>[
        const LinePrimitive(
          bounds: JetRect(x: 0, y: 0, width: 50, height: 80),
          start: JetOffset(0, 0),
          end: JetOffset(50, 80),
          color: JetColor.black,
        ),
      ]);
      final Match m = _lineRe.firstMatch(content)!;
      expect(double.parse(m.group(1)!), closeTo(0, 0.001));
      expect(double.parse(m.group(2)!), closeTo(100, 0.001),
          reason: 'start y = pageHeight - 0');
      expect(double.parse(m.group(3)!), closeTo(50, 0.001));
      expect(double.parse(m.group(4)!), closeTo(20, 0.001),
          reason: 'end y = pageHeight - 80');
    });

    test('path replays commands (mapped) and fills before stroking', () async {
      final (_, String content) = await _paint(<FramePrimitive>[
        const PathPrimitive(
          bounds: JetRect(x: 0, y: 0, width: 60, height: 40),
          commands: <PathCommand>[
            MoveTo(JetOffset(10, 10)),
            LineTo(JetOffset(60, 10)),
            LineTo(JetOffset(60, 40)),
            ClosePath(),
          ],
          fill: JetColor(0xFFFF0000),
          stroke: JetColor(0xFF0000FF),
        ),
      ]);
      // MoveTo(10,10) -> `10 90 m`; LineTo(60,40) -> `60 60 l`.
      expect(content, contains('10 90 m'));
      expect(content, contains('60 60 l'));
      expect(content, contains('h'), reason: 'ClosePath -> h');
      final int fillIdx = content.indexOf(RegExp(r'\bf\b'));
      final int strokeIdx = content.indexOf(RegExp(r'\bS\b'));
      expect(fillIdx, lessThan(strokeIdx), reason: 'fill first, stroke on top');
    });

    test('a non-opaque color installs an alpha graphic state (gs)', () async {
      final (_, String content) = await _paint(<FramePrimitive>[
        const RectPrimitive(
          bounds: JetRect(x: 10, y: 20, width: 50, height: 30),
          fill: JetColor(0x80FF0000),
        ),
      ]);
      expect(content, contains(' gs'),
          reason: 'CanvasPainter renders 0x80 alpha translucent; the PDF '
              'backend must match via an ExtGState, not drop the alpha');
    });
  });

  group('shapes — stroke width 0 (021 / C7)', () {
    test('a shape with strokeWidth 0 emits no stroke operators', () async {
      // Through the REAL renderer: the seam emits stroke: null at width 0, so
      // the PDF backend writes a fill pass only.
      final FrameBuilder builder = FrameBuilder(_page);
      const ShapeElementRenderer renderer = ShapeElementRenderer();
      const JetRect bounds = JetRect(x: 10, y: 10, width: 60, height: 40);
      renderer.emit(
        const ShapeElement(
          id: 's',
          bounds: bounds,
          kind: ShapeKind.rectangle,
          style: JetBoxStyle(
            fill: JetColor(0xFFFF0000),
            stroke: JetColor(0xFF0000FF),
            strokeWidth: 0,
          ),
        ),
        RenderContext(measurer: measurer),
        bounds,
        builder,
      );
      final PdfPainter painter = PdfPainter(fonts);
      await paintFrame(builder.build(), painter);
      final PdfInspector pdf = PdfInspector(await painter.save());
      final String content = pdf.contentOf(0);

      expect(content, contains(RegExp(r're\s+f\b')),
          reason: 'fill still paints');
      expect(content, isNot(contains(RegExp(r'\bS\b'))),
          reason: 'no stroke operator at width 0');
    });
  });

  group('document mechanics', () {
    test('no global y-flip CTM is installed (it would mirror glyphs)',
        () async {
      final MeasuredText measured =
          measurer.measure('x', const JetTextStyle(fontSize: 12));
      final (_, String content) = await _paint(<FramePrimitive>[
        TextRunPrimitive(
          bounds: const JetRect(x: 0, y: 0, width: 50, height: 20),
          lines: measured.lines,
          style: const JetTextStyle(fontSize: 12),
          fontFamily: measured.fontFamily,
        ),
      ], fonts: fonts);
      expect(content, isNot(contains('1 0 0 -1')),
          reason: 'the mapping is per draw call (research §6), never a '
              'negative-y CTM');
    });

    test('painting two frames produces two pages in paint order', () async {
      final MeasuredText one = measurer.measure('one', const JetTextStyle());
      final MeasuredText two = measurer.measure('two', const JetTextStyle());
      TextRunPrimitive run(MeasuredText m) => TextRunPrimitive(
            bounds: const JetRect(x: 0, y: 0, width: 100, height: 20),
            lines: m.lines,
            style: const JetTextStyle(),
            fontFamily: m.fontFamily,
          );
      final PdfPainter painter = PdfPainter(fonts);
      await paintFrame(
          PageFrame(page: _page, primitives: <FramePrimitive>[run(one)]),
          painter);
      await paintFrame(
          PageFrame(page: _page, primitives: <FramePrimitive>[run(two)]),
          painter);
      final PdfInspector pdf = PdfInspector(await painter.save());
      expect(pdf.pageCount, 2);
      expect(pdf.textOnPage(0), contains('one'));
      expect(pdf.textOnPage(1), contains('two'));
    });
  });

  // --- Export reads the carried registry (022 — contracts C8 & C12) --------
  group('export — carried host registry (C8/C12)', () {
    // Two text elements, BOTH in the host family, so a correct byte-keyed
    // embed produces exactly one font program for the family.
    ReportDefinition hostDefinition() => const ReportDefinition(
          name: 'Host',
          page: PageFormat(
              width: 300, height: 200, margins: JetEdgeInsets.all(10)),
          body: ReportBody(
            root: DetailScope(
              id: 'root',
              children: <ScopeNode>[
                BandNode(Band(
                  id: 'root/c0',
                  type: BandType.detail,
                  height: 60,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'a',
                      bounds: JetRect(x: 0, y: 0, width: 240, height: 20),
                      text: 'Acme heading',
                      style: JetTextStyle(fontFamily: 'Acme Brand'),
                    ),
                    TextElement(
                      id: 'b',
                      bounds: JetRect(x: 0, y: 24, width: 240, height: 20),
                      text: 'Acme body',
                      style: JetTextStyle(fontFamily: 'Acme Brand'),
                    ),
                  ],
                )),
              ],
            ),
          ),
        );

    JetDataSource source() => JetInMemoryDataSource(
        const <Map<String, Object?>>[<String, Object?>{}]);

    RenderedReport renderHost(
            {List<JetFontFamily> fonts = const <JetFontFamily>[]}) =>
        const JetReportEngine().renderDefinition(hostDefinition(), source(),
            options: RenderOptions(fonts: fonts));

    List<JetFontFamily> brand() => <JetFontFamily>[
          JetFontFamily(
            name: 'Acme Brand',
            faces: <JetFontFace>[JetFontFace(bytes: validRegularFontBytes())],
          ),
        ];

    test(
        'a host-family report exports text that uses the host face (not the '
        'default) and stays real/selectable', () async {
      final Uint8List hostBytes =
          await const JetReportExporter().toPdf(renderHost(fonts: brand()));
      final Uint8List defaultBytes =
          await const JetReportExporter().toPdf(renderHost());

      final PdfInspector host = PdfInspector(hostBytes);
      expect(host.allText, containsAll(<String>['Acme heading', 'Acme body']),
          reason: 'PDF text stays real/selectable (FR-004)');
      expect(host.hasTextObjectsOn(0), isTrue);
      // The host font flows to export: the embedded program differs from the
      // default-only export of the same template/data.
      expect(hostBytes, isNot(orderedEquals(defaultBytes)),
          reason: 'export read report.fonts, not a default-only registry');
    });

    test('a host face used twice embeds exactly one font program (C12)',
        () async {
      final PdfInspector pdf = PdfInspector(
          await const JetReportExporter().toPdf(renderHost(fonts: brand())));
      expect(pdf.embeddedFontProgramCount, 1,
          reason: 'byte-keyed cache embeds the host face once per document');
    });

    test('a default-only report is unchanged (deterministic, SC-005)',
        () async {
      final Uint8List a = await const JetReportExporter().toPdf(renderHost());
      final Uint8List b = await const JetReportExporter().toPdf(renderHost());
      expect(a, orderedEquals(b));
    });
  });
}
