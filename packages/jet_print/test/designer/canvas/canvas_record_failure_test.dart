// The design canvas recovers from a frame recording that throws.
//
// Regression: `_maybeRebuild` set its in-flight flag, then awaited the record
// with no error path. A record that threw — a corrupt embedded image fails to
// decode inside `CanvasPainter.prepare` — left the flag set forever, so every
// later edit was skipped and the canvas froze on its last picture.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/canvas/frame_custom_painter.dart';

import '../support/designer_harness.dart';

ReportDefinition _withCorruptImage() => ReportDefinition(
      name: 'Corrupt image',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 120,
              elements: <ReportElement>[
                // Garbage bytes: decoding throws while the frame is recorded.
                ImageElement(
                  id: 'bad',
                  bounds: const JetRect(x: 10, y: 10, width: 40, height: 40),
                  source:
                      BytesImageSource(Uint8List.fromList(<int>[1, 2, 3, 4])),
                ),
                const ShapeElement(
                  id: 'box',
                  bounds: JetRect(x: 80, y: 10, width: 40, height: 40),
                  kind: ShapeKind.rectangle,
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// The revision of the picture the canvas is currently painting.
int _paintedRevision(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((CustomPaint p) => p.painter)
    .whereType<FrameCustomPainter>()
    .single
    .revision;

void main() {
  testWidgets('a failed record does not stop later edits from redrawing',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        controller:
            JetReportDesignerController(definition: _withCorruptImage()));
    await tester.pumpAndSettle();

    // Removing the image leaves a frame that records fine; the canvas must
    // pick it up rather than staying wedged on the failed one.
    c.select('bad');
    c.delete();
    await tester.pumpAndSettle();

    expect(_paintedRevision(tester), c.frameVersion);
  });
}
