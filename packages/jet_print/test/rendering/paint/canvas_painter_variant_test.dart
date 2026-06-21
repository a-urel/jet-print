@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

import '../../support/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paint loads the SAME variant bytes the measurer measures', () async {
    final Uint8List boldBytes = File('${findWorkspaceRoot().path}'
            '/packages/jet_print/tool/fonts/NotoSans-Bold-subset.ttf')
        .readAsBytesSync();
    final FontRegistry reg = FontRegistry()
      ..registerDefault()
      ..register(FontRegistry.defaultFamily, boldBytes,
          weight: JetFontWeight.bold);
    final int regularLen = reg.bytesFor(FontRegistry.defaultFamily).length;
    final int boldLen = reg
        .bytesFor(FontRegistry.defaultFamily, weight: JetFontWeight.bold)
        .length;
    expect(regularLen, isNot(boldLen));

    final MetricsTextMeasurer measurer = MetricsTextMeasurer(reg);
    final MeasuredText normalM =
        measurer.measure('Hi', const JetTextStyle(fontSize: 10));
    final MeasuredText boldM = measurer.measure(
        'Hi', const JetTextStyle(fontSize: 10, weight: JetFontWeight.bold));

    final List<({String family, int len})> loads =
        <({String family, int len})>[];
    Future<void> recordingLoader(Uint8List bytes, {String? fontFamily}) async {
      loads.add((family: fontFamily!, len: bytes.length));
    }

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final CanvasPainter painter = CanvasPainter(ui.Canvas(recorder), reg,
        fontLoader: recordingLoader, registeredFamilies: <String>{});

    const PageFormat page =
        PageFormat(width: 100, height: 40, margins: JetEdgeInsets.all(0));
    final frame = (FrameBuilder(page)
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 0, y: 0, width: 100, height: 14),
              lines: normalM.lines,
              style: const JetTextStyle(fontSize: 10),
              fontFamily: FontRegistry.defaultFamily))
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 0, y: 14, width: 100, height: 14),
              lines: boldM.lines,
              style:
                  const JetTextStyle(fontSize: 10, weight: JetFontWeight.bold),
              fontFamily: FontRegistry.defaultFamily)))
        .build();
    await painter.prepare(frame);

    expect(loads, hasLength(2));
    expect(loads.map((({String family, int len}) e) => e.family).toSet(),
        hasLength(2));
    expect(loads.map((({String family, int len}) e) => e.len).toSet(),
        <int>{regularLen, boldLen});
  });

  test(
      'drawTextRun renders the measured variant (bold pixels differ from normal)',
      () async {
    final Uint8List boldBytes = File('${findWorkspaceRoot().path}'
            '/packages/jet_print/tool/fonts/NotoSans-Bold-subset.ttf')
        .readAsBytesSync();
    final FontRegistry reg = FontRegistry()
      ..registerDefault()
      ..register(FontRegistry.defaultFamily, boldBytes,
          weight: JetFontWeight.bold);
    final MetricsTextMeasurer measurer = MetricsTextMeasurer(reg);

    Future<Uint8List> render(JetTextStyle style) async {
      final MeasuredText m = measurer.measure('Hi', style);
      final frame = (FrameBuilder(const PageFormat(
              width: 60, height: 24, margins: JetEdgeInsets.all(0)))
            ..add(TextRunPrimitive(
                bounds: const JetRect(x: 2, y: 2, width: 56, height: 20),
                lines: m.lines,
                style: style,
                fontFamily: FontRegistry.defaultFamily)))
          .build();
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final CanvasPainter painter = CanvasPainter(ui.Canvas(recorder), reg);
      await paintFrame(frame, painter);
      final ui.Image img = await recorder.endRecording().toImage(60, 24);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
    }

    final Uint8List normalPx = await render(const JetTextStyle(fontSize: 16));
    final Uint8List boldPx = await render(
        const JetTextStyle(fontSize: 16, weight: JetFontWeight.bold));

    // If drawTextRun ignored the run's variant, bold would render with the
    // regular face and the two images would be byte-identical.
    expect(_bytesEqual(normalPx, boldPx), isFalse);
  });
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
