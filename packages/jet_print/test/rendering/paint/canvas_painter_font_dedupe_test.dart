@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(CanvasPainter.debugResetEngineFonts);

  // Builds a one-text-run frame for the default family.
  PageFrame textFrame(FontRegistry reg) {
    final MeasuredText m = MetricsTextMeasurer(reg)
        .measure('Hi', const JetTextStyle(fontSize: 10));
    return (FrameBuilder(const PageFormat(
            width: 100, height: 20, margins: JetEdgeInsets.all(0)))
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 0, y: 0, width: 100, height: 14),
              lines: m.lines,
              style: const JetTextStyle(fontSize: 10),
              fontFamily: FontRegistry.defaultFamily)))
        .build();
  }

  test('a font variant is registered into the engine only once per process',
      () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    int loads = 0;
    Future<void> counting(Uint8List bytes, {String? fontFamily}) async =>
        loads++;

    // Two painters sharing the default (process-global) registry — like two
    // successive recordFrame() calls.
    for (var i = 0; i < 2; i++) {
      final ui.PictureRecorder rec = ui.PictureRecorder();
      final CanvasPainter painter =
          CanvasPainter(ui.Canvas(rec), reg, fontLoader: counting);
      await painter.prepare(textFrame(reg));
      rec.endRecording();
    }

    expect(loads, 1,
        reason: 'second painter must reuse the engine registration');
  });

  test(
      'an injected fresh registry registers again (proves the guard is the set)',
      () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    int loads = 0;
    Future<void> counting(Uint8List bytes, {String? fontFamily}) async =>
        loads++;

    for (var i = 0; i < 2; i++) {
      final ui.PictureRecorder rec = ui.PictureRecorder();
      final CanvasPainter painter = CanvasPainter(ui.Canvas(rec), reg,
          fontLoader: counting, registeredFamilies: <String>{});
      await painter.prepare(textFrame(reg));
      rec.endRecording();
    }

    expect(loads, 2, reason: 'isolated registries do not share state');
  });
}
