import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/canvas/zoom_math.dart';
import 'package:jet_print/src/designer/controller/view_fit_mode.dart';
import 'package:jet_print/src/domain/geometry.dart';

void main() {
  const double padding = 32;

  group('fitWidthScale', () {
    test('scales the page width into the usable viewport width', () {
      // usable = 200 - 2*0 ... use padding 0 for an exact ratio
      final double s =
          fitWidthScale(const JetSize(100, 999), const Size(232, 500), padding);
      // usable width = 232 - 64 = 168; 168 / 100 = 1.68
      expect(s, closeTo(1.68, 1e-9));
    });

    test('clamps up to kMinZoom for an enormous page', () {
      final double s = fitWidthScale(
          const JetSize(100000, 100), const Size(500, 500), padding);
      expect(s, 0.25);
    });

    test('clamps down to kMaxZoom for a tiny page', () {
      final double s =
          fitWidthScale(const JetSize(1, 1), const Size(500, 500), padding);
      expect(s, 4.0);
    });

    test('returns 1.0 when the usable width is non-positive', () {
      expect(
          fitWidthScale(const JetSize(100, 100), const Size(10, 500), padding),
          1.0);
    });
  });

  group('fitPageScale', () {
    test('uses the smaller of the width and height ratios (height-bound)', () {
      // usable W = 264-64 = 200 -> 200/100 = 2.0; usable H = 164-64 = 100 ->
      // 100/100 = 1.0; min = 1.0
      final double s =
          fitPageScale(const JetSize(100, 100), const Size(264, 164), padding);
      expect(s, closeTo(1.0, 1e-9));
    });

    test('uses the smaller of the width and height ratios (width-bound)', () {
      // usable W = 164-64 = 100 -> 1.0; usable H = 264-64 = 200 -> 2.0; min 1.0
      final double s =
          fitPageScale(const JetSize(100, 100), const Size(164, 264), padding);
      expect(s, closeTo(1.0, 1e-9));
    });

    test('returns 1.0 when a usable dimension is non-positive', () {
      expect(
          fitPageScale(const JetSize(100, 100), const Size(10, 500), padding),
          1.0);
      expect(
          fitPageScale(const JetSize(100, 100), const Size(500, 10), padding),
          1.0);
    });

    test('clamps to the allowed zoom range', () {
      expect(fitPageScale(const JetSize(1, 1), const Size(500, 500), padding),
          4.0);
      expect(
          fitPageScale(
              const JetSize(100000, 100000), const Size(500, 500), padding),
          0.25);
    });
  });

  group('defaultFitForScreenWidth', () {
    test('a phone-class width fits to width', () {
      expect(defaultFitForScreenWidth(320), JetViewFitMode.width);
      expect(defaultFitForScreenWidth(599), JetViewFitMode.width);
    });

    test('a desktop-class width opens at 100% (no fit)', () {
      expect(defaultFitForScreenWidth(600), JetViewFitMode.none);
      expect(defaultFitForScreenWidth(1440), JetViewFitMode.none);
    });

    test('the breakpoint is the shared 600px threshold', () {
      expect(kDefaultZoomDesktopMinWidth, 600);
    });
  });
}
