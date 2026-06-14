// Cross-path host-font parity (022 — contract C9, the headline; T009).
//
// The engine builds ONE registry and RenderedReport carries it, so canvas,
// preview, PNG, and PDF all paint the identical measured frame — host fonts
// render the same everywhere by construction (Principle IV / SC-002). This
// test pins the two observable ends of that guarantee:
//   * the PDF text geometry matches the carried frame's measured baselines
//     (the same frame the canvas/preview/PNG paths consume), and
//   * the host font actually flows into measurement+paint — a host-font page
//     differs from the default-only render of the same design, while the
//     default-only render stays deterministic/unchanged (SC-005).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/engine/jet_report_engine.dart';
import 'package:jet_print/src/rendering/engine/render_options.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/jet_font.dart';

import '../support/test_fonts.dart';
import 'export/support/pdf_inspector.dart';

const PageFormat _page =
    PageFormat(width: 300, height: 200, margins: JetEdgeInsets.all(10));

final RegExp _tdRe = RegExp(r'([\d.+-]+)\s+([\d.+-]+)\s+Td\b');

ReportDefinition _definition() => const ReportDefinition(
      name: 'Parity',
      page: _page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 40,
              elements: <ReportElement>[
                TextElement(
                  id: 't',
                  bounds: JetRect(x: 0, y: 0, width: 260, height: 20),
                  text: 'Brand parity',
                  style: JetTextStyle(fontFamily: 'Acme Brand', fontSize: 14),
                ),
              ],
            )),
          ],
        ),
      ),
    );

JetDataSource _source() =>
    JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]);

List<JetFontFamily> _brand() => <JetFontFamily>[
      JetFontFamily(
        name: 'Acme Brand',
        faces: <JetFontFace>[JetFontFace(bytes: validRegularFontBytes())],
      ),
    ];

RenderedReport _render({List<JetFontFamily> fonts = const <JetFontFamily>[]}) =>
    const JetReportEngine().renderDefinition(_definition(), _source(),
        options: RenderOptions(fonts: fonts));

void main() {
  test('PDF text geometry matches the carried frame the other paths paint',
      () async {
    final RenderedReport report = _render(fonts: _brand());
    // The single shared frame canvas/preview/PNG/PDF all consume.
    final TextRunPrimitive run =
        report.pageAt(0).frame.primitives.whereType<TextRunPrimitive>().single;
    expect(run.fontFamily, 'Acme Brand',
        reason: 'measurement resolved the host family');

    final Uint8List pdf = await const JetReportExporter().toPdf(report);
    final String content = PdfInspector(pdf).contentOf(0);
    final Match td = _tdRe.firstMatch(content)!;
    expect(double.parse(td.group(1)!), closeTo(run.bounds.x, 0.001));
    expect(
      double.parse(td.group(2)!),
      closeTo(_page.height - (run.bounds.y + run.lines.single.baseline), 0.001),
      reason: 'the PDF baseline equals the carried frame measured baseline',
    );
  });

  test('a host-font page differs from the default-only render of the design',
      () async {
    final Uint8List host =
        await const JetReportExporter().pageToPng(_render(fonts: _brand()), 0);
    final Uint8List fallback =
        await const JetReportExporter().pageToPng(_render(), 0);
    expect(host, isNot(orderedEquals(fallback)),
        reason: 'the host font flows through measurement+paint into the PNG');
  });

  test('the default-only render is deterministic / unchanged (SC-005)',
      () async {
    final Uint8List a = await const JetReportExporter().pageToPng(_render(), 0);
    final Uint8List b = await const JetReportExporter().pageToPng(_render(), 0);
    expect(a, orderedEquals(b));
  });
}
