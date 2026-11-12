// JP0 spike: draws today's chart renderer (left) beside the jet_charts_core
// converter (right), as PNG and PDF. Writes files only when CHART_SPIKE_OUT is
// set to a directory; otherwise it only checks that both paths produce output.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart' as core;
import 'package:jet_print/src/domain/elements/chart_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/chart/chart_frame_converter.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/chart_element_renderer.dart';
import 'package:jet_print/src/rendering/export/pdf_painter.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/paint/page_rasterizer.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

const List<String> _cats = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
const List<double> _vals = <double>[120, 340, 210, 480, 390, 260];

core.Chart _core(core.ChartKind kind) => core.Chart(
      kind: kind,
      title: const core.ChartTitle(text: 'Monthly sales'),
      legend: const core.ChartLegend(),
      series: <core.ChartSeries>[
        core.ChartSeries(
          name: core.ChartData<String>(values: <String>['Revenue']),
          categories: core.ChartData<Object>(values: List<Object>.of(_cats)),
          values: core.ChartData<double>(values: List<double>.of(_vals)),
        ),
      ],
    );

ChartElement _old(ChartType t, JetRect b) => ChartElement(
      id: 'old',
      bounds: b,
      chartType: t,
      collectionField: 'months',
      valueExpression: 'v',
      title: 'Monthly sales',
      showLegend: true,
      points: <ChartPoint>[
        for (int i = 0; i < _cats.length; i++) ChartPoint(_cats[i], _vals[i]),
      ],
    );

void main() {
  final FontRegistry fonts = FontRegistry()..registerDefault();
  final MetricsTextMeasurer measurer = MetricsTextMeasurer(fonts);
  final String? out = Platform.environment['CHART_SPIKE_OUT'];
  const PageFormat page =
      PageFormat(width: 595, height: 760, margins: JetEdgeInsets.all(20));

  final List<(String, ChartType, core.ChartKind)> cases =
      <(String, ChartType, core.ChartKind)>[
    ('column', ChartType.bar, core.ChartKind.column),
    ('line', ChartType.line, core.ChartKind.line),
    ('pie', ChartType.pie, core.ChartKind.pie),
    ('area', ChartType.line, core.ChartKind.area),
    ('donut', ChartType.pie, core.ChartKind.donut),
  ];

  testWidgets('old and new chart paths both draw, side by side',
      (tester) async {
    await tester.runAsync(() async {
      final FrameBuilder fb = FrameBuilder(page);
      final StringBuffer report = StringBuffer();
      double y = 20;
      for (final (String name, ChartType ot, core.ChartKind nk) in cases) {
        final JetRect l = JetRect(x: 20, y: y, width: 270, height: 130);
        final JetRect r = JetRect(x: 305, y: y, width: 270, height: 130);
        final int before = _count(fb);
        const ChartElementRenderer()
            .emit(_old(ot, l), RenderContext(measurer: measurer), l, fb);
        final ChartFrameResult res =
            chartToFrame(_core(nk), bounds: r, measurer: measurer);
        res.primitives.forEach(fb.add);
        report
            .writeln('$name: old ${_count(fb) - before - res.primitives.length}'
                ' prims, new ${res.primitives.length} prims, ${res.gaps}, '
                'hidden labels ${res.layout.hidden.length}');
        expect(res.primitives, isNotEmpty);
        y += 145;
      }
      final PageFrame frame = fb.build();
      final PdfPainter pdf = PdfPainter(fonts);
      await paintFrame(frame, pdf);
      final pdfBytes = await pdf.save();
      final png =
          await const PageRasterizer().rasterize(frame, fonts, scale: 2);
      expect(pdfBytes.length, greaterThan(1000));
      expect(png.length, greaterThan(1000));
      if (out != null) {
        File('$out/chart_compare.png').writeAsBytesSync(png);
        File('$out/chart_compare.pdf').writeAsBytesSync(pdfBytes);
        File('$out/chart_compare.txt').writeAsStringSync(report.toString());
      }
    });
  });
}

int _count(FrameBuilder fb) => fb.build().primitives.length;
