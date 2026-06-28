// test/rendering/paint/report_painter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';

class _RecordingPainter implements ReportPainter {
  final List<String> calls = <String>[];
  @override
  Future<void> prepare(PageFrame frame) async {}
  @override
  void beginPage(PageFormat format) => calls.add('begin');
  @override
  void endPage() => calls.add('end');
  @override
  void pushTransform(JetOffset center, double radians) =>
      calls.add('push(${center.dx},${center.dy},$radians)');
  @override
  void popTransform() => calls.add('pop');
  @override
  void drawRect(RectPrimitive p) => calls.add('rect');
  @override
  void drawTextRun(TextRunPrimitive p) => calls.add('text');
  @override
  void drawImage(ImagePrimitive p) => calls.add('image');
  @override
  void drawLine(LinePrimitive p) => calls.add('line');
  @override
  void drawPath(PathPrimitive p) => calls.add('path');
}

void main() {
  const page =
      PageFormat(width: 100, height: 100, margins: JetEdgeInsets.all(0));

  test('rotated primitive is wrapped in push/pop about its center', () async {
    final frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 10, y: 20, width: 40, height: 60),
              fill: JetColor.black,
              rotation: 0.5)))
        .build();
    final p = _RecordingPainter();
    await paintFrame(frame, p);
    // center = (10+20, 20+30) = (30, 50)
    expect(p.calls,
        <String>['begin', 'push(30.0,50.0,0.5)', 'rect', 'pop', 'end']);
  });

  test('unrotated primitive is NOT wrapped', () async {
    final frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 1, height: 1),
              fill: JetColor.black)))
        .build();
    final p = _RecordingPainter();
    await paintFrame(frame, p);
    expect(p.calls, <String>['begin', 'rect', 'end']);
  });
}
