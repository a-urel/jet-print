// JP1: dash, clip and real arcs in the frame.
//
// Each capability is pinned at four layers: value equality, paintFrame
// dispatch order, the PDF operators the backend writes, and the pixels the
// canvas backend produces.
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/export/pdf_painter.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/page_rasterizer.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';

import '../export/support/pdf_inspector.dart';

const PageFormat _page =
    PageFormat(width: 100, height: 100, margins: JetEdgeInsets.all(0));
const JetColor _red = JetColor(0xFFFF0000);

class _Recorder implements ReportPainter {
  final List<String> calls = <String>[];
  @override
  Future<void> prepare(PageFrame frame) async {}
  @override
  void beginPage(PageFormat format) {}
  @override
  void pushTransform(JetOffset center, double radians) => calls.add('push');
  @override
  void popTransform() => calls.add('pop');
  @override
  void pushClip(JetRect rect) => calls.add('pushClip');
  @override
  void popClip() => calls.add('popClip');
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
  void endPage() {}
  @override
  void dispose() {}
}

Future<String> _pdfContent(List<FramePrimitive> primitives) async {
  final PdfPainter painter = PdfPainter(FontRegistry()..registerDefault());
  await paintFrame(PageFrame(page: _page, primitives: primitives), painter);
  return PdfInspector(await painter.save()).contentOf(0);
}

/// Alpha of the pixel at ([x], [y]) after rasterizing at scale 1.
Future<int> _alphaAt(List<FramePrimitive> primitives, int x, int y) async {
  final Uint8List png = await PageRasterizer().rasterize(
      PageFrame(page: _page, primitives: primitives),
      FontRegistry()..registerDefault());
  final ui.Codec codec = await ui.instantiateImageCodec(png);
  final ui.Image image = (await codec.getNextFrame()).image;
  final ByteData data = (await image.toByteData())!;
  final int a = data.getUint8((y * image.width + x) * 4 + 3);
  image.dispose();
  codec.dispose();
  return a;
}

void main() {
  group('equality', () {
    const JetRect b = JetRect(x: 0, y: 0, width: 10, height: 10);
    test('clip and dashPattern are part of a primitive\'s value', () {
      const RectPrimitive plain = RectPrimitive(bounds: b, fill: _red);
      const RectPrimitive clipped = RectPrimitive(
          bounds: b,
          fill: _red,
          clip: JetRect(x: 0, y: 0, width: 5, height: 5));
      expect(plain, isNot(clipped));
      const LinePrimitive solid = LinePrimitive(
          bounds: b,
          start: JetOffset(0, 0),
          end: JetOffset(10, 0),
          color: _red);
      const LinePrimitive dashed = LinePrimitive(
          bounds: b,
          start: JetOffset(0, 0),
          end: JetOffset(10, 0),
          color: _red,
          dashPattern: <double>[3, 2]);
      expect(solid, isNot(dashed));
    });

    test('halfTurnParts keeps the total sweep, direction and a π cap', () {
      for (final double sweep in <double>[0.5, 3.0, 6.283185307179586, -4.0]) {
        final parts = ArcTo(const JetOffset(0, 0), 1, 1.0, sweep).halfTurnParts;
        expect(
            parts.fold<double>(0, (a, p) => a + p.sweep), closeTo(sweep, 1e-9));
        expect(parts.first.start, 1.0);
        for (final p in parts) {
          expect(p.sweep.abs(), lessThanOrEqualTo(3.14159266));
          expect(p.sweep.sign, sweep.sign);
        }
      }
    });

    test('ArcTo compares by value', () {
      expect(const ArcTo(JetOffset(5, 5), 4, 0, 1),
          const ArcTo(JetOffset(5, 5), 4, 0, 1));
      expect(const ArcTo(JetOffset(5, 5), 4, 0, 1),
          isNot(const ArcTo(JetOffset(5, 5), 4, 0, 2)));
    });
  });

  group('paintFrame', () {
    test(
        'a clipped primitive is bracketed by pushClip/popClip, outside any '
        'rotation', () async {
      const JetRect b = JetRect(x: 0, y: 0, width: 10, height: 10);
      final _Recorder rec = _Recorder();
      await paintFrame(
          PageFrame(page: _page, primitives: const <FramePrimitive>[
            RectPrimitive(
                bounds: b,
                fill: _red,
                rotation: 0.5,
                clip: JetRect(x: 0, y: 0, width: 5, height: 5)),
            RectPrimitive(bounds: b, fill: _red),
          ]),
          rec);
      expect(rec.calls,
          <String>['pushClip', 'push', 'rect', 'pop', 'popClip', 'rect']);
    });
  });

  group('PDF', () {
    test('dashPattern writes a dash operator and resets it after', () async {
      final String c = await _pdfContent(const <FramePrimitive>[
        LinePrimitive(
            bounds: JetRect(x: 0, y: 10, width: 50, height: 0),
            start: JetOffset(0, 10),
            end: JetOffset(50, 10),
            color: _red,
            dashPattern: <double>[4, 2]),
      ]);
      expect(c, contains('[4 2] 0 d'));
      // Scoped: a later solid primitive must not inherit the dashes.
      expect(c.indexOf('Q'), greaterThan(c.indexOf('[4 2] 0 d')));
    });

    test('a path dashPattern is written too', () async {
      final String c = await _pdfContent(const <FramePrimitive>[
        PathPrimitive(
            bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
            commands: <PathCommand>[
              MoveTo(JetOffset(0, 0)),
              LineTo(JetOffset(10, 10)),
            ],
            stroke: _red,
            dashPattern: <double>[3, 1]),
      ]);
      expect(c, contains('[3 1] 0 d'));
    });

    test('clip intersects the clip rect before drawing, scoped by q/Q',
        () async {
      final String c = await _pdfContent(const <FramePrimitive>[
        RectPrimitive(
            bounds: JetRect(x: 0, y: 0, width: 50, height: 50),
            fill: _red,
            clip: JetRect(x: 10, y: 20, width: 30, height: 40)),
      ]);
      // y mapped: 100 - 20 - 40 = 40 is the PDF rect's bottom.
      expect(c, contains('10 40 30 40 re'));
      expect(c, contains('W'));
      expect(c.indexOf('W'), lessThan(c.lastIndexOf('f')));
    });

    test('ArcTo becomes cubic curves', () async {
      final String c = await _pdfContent(const <FramePrimitive>[
        PathPrimitive(
            bounds: JetRect(x: 0, y: 0, width: 20, height: 20),
            commands: <PathCommand>[
              MoveTo(JetOffset(10, 10)),
              ArcTo(JetOffset(10, 10), 10, 0, 3.14159),
              ClosePath(),
            ],
            fill: _red),
      ]);
      expect(RegExp(r'\bc\b').hasMatch(c), isTrue, reason: 'bezier operator');
    });
  });

  group('canvas pixels', () {
    test('clip hides what falls outside the clip rect', () async {
      const List<FramePrimitive> prims = <FramePrimitive>[
        RectPrimitive(
            bounds: JetRect(x: 0, y: 0, width: 100, height: 100),
            fill: _red,
            clip: JetRect(x: 0, y: 0, width: 50, height: 100)),
      ];
      expect(await _alphaAt(prims, 25, 50), 255);
      expect(await _alphaAt(prims, 75, 50), 0);
    });

    test('dashPattern leaves gaps on a stroked line', () async {
      const List<FramePrimitive> prims = <FramePrimitive>[
        LinePrimitive(
            bounds: JetRect(x: 0, y: 50, width: 100, height: 0),
            start: JetOffset(0, 50),
            end: JetOffset(100, 50),
            color: _red,
            strokeWidth: 4,
            dashPattern: <double>[10, 10]),
      ];
      expect(await _alphaAt(prims, 5, 50), 255, reason: 'inside a dash');
      expect(await _alphaAt(prims, 15, 50), 0, reason: 'inside a gap');
      expect(await _alphaAt(prims, 25, 50), 255, reason: 'next dash');
    });

    test('ArcTo fills a half disc', () async {
      // Upper half of a circle centred (50,50) r 40: from angle pi (left)
      // sweeping +pi goes through the TOP in y-down space (clockwise).
      const List<FramePrimitive> prims = <FramePrimitive>[
        PathPrimitive(
            bounds: JetRect(x: 10, y: 10, width: 80, height: 80),
            commands: <PathCommand>[
              MoveTo(JetOffset(10, 50)),
              ArcTo(
                  JetOffset(50, 50), 40, 3.141592653589793, 3.141592653589793),
              ClosePath(),
            ],
            fill: _red),
      ];
      expect(await _alphaAt(prims, 50, 30), 255, reason: 'inside upper half');
      expect(await _alphaAt(prims, 50, 70), 0, reason: 'lower half empty');
      expect(await _alphaAt(prims, 15, 15), 0, reason: 'outside the circle');
    });

    test('a full-turn ArcTo fills a disc (Path.arcTo alone draws nothing)',
        () async {
      const List<FramePrimitive> prims = <FramePrimitive>[
        PathPrimitive(
            bounds: JetRect(x: 10, y: 10, width: 80, height: 80),
            commands: <PathCommand>[
              MoveTo(JetOffset(90, 50)),
              ArcTo(JetOffset(50, 50), 40, 0, 6.283185307179586),
              ClosePath(),
            ],
            fill: _red),
      ];
      expect(await _alphaAt(prims, 50, 50), 255, reason: 'inside the disc');
      expect(await _alphaAt(prims, 15, 15), 0, reason: 'outside the circle');
    });
  });
}
