// test/rendering/paint/paint_frame_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';

class _Recorder implements ReportPainter {
  final List<String> calls = <String>[];
  @override
  Future<void> prepare(PageFrame frame) async => calls.add('prepare');
  @override
  void beginPage(PageFormat format) => calls.add('beginPage');
  @override
  void drawTextRun(TextRunPrimitive p) => calls.add('text');
  @override
  void drawImage(ImagePrimitive p) => calls.add('image');
  @override
  void drawLine(LinePrimitive p) => calls.add('line');
  @override
  void drawRect(RectPrimitive p) => calls.add('rect');
  @override
  void drawPath(PathPrimitive p) => calls.add('path');
  @override
  void endPage() => calls.add('endPage');
}

void main() {
  test('paintFrame prepares, brackets the page, and dispatches in order',
      () async {
    final PageFrame frame = (FrameBuilder(PageFormat.a4Portrait)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 4, height: 4),
              fill: JetColor.black))
          ..add(const LinePrimitive(
              bounds: JetRect(x: 0, y: 0, width: 4, height: 0),
              start: JetOffset(0, 0),
              end: JetOffset(4, 0),
              color: JetColor.black)))
        .build();
    final _Recorder rec = _Recorder();
    await paintFrame(frame, rec);
    expect(
        rec.calls, <String>['prepare', 'beginPage', 'rect', 'line', 'endPage']);
  });
}
