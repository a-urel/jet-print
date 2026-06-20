// PNG page export (012 — contract B4/B3; FR-006/007, SC-006; T015/T020).
//
// One page as in-memory PNG bytes through the UNCHANGED preview paint path
// (paintFrame -> CanvasPainter), rasterized at a host-chosen scale: pixel
// dimensions are exactly round(page x scale), pages export in order by host
// iteration, run-to-run bytes are identical in-process, and invalid requests
// throw the structured errors the render IR already uses. The golden pin
// goes through the standard golden comparator (decoded pixels — the engine
// PNG encoder is not cross-machine byte-stable, research §4).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart';
import 'package:jet_print/src/rendering/export/jet_report_exporter.dart';

import 'support/export_fixtures.dart';

Future<ui.Image> _decodeUi(Uint8List png) async {
  final ui.Codec codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const JetReportExporter exporter = JetReportExporter();

  group('B4/SC-006 — pixel dimensions are exactly round(page x scale)', () {
    test('1x / 2x / 3x of the 400x300 invoice page', () async {
      final RenderedReport report = invoiceReport();
      for (final double scale in <double>[1, 2, 3]) {
        final Uint8List png = await exporter.pageToPng(report, 0, scale: scale);
        final img.Image? decoded = img.decodePng(png);
        expect(decoded, isNotNull, reason: 'scale $scale: not a valid PNG');
        expect(decoded!.width, (400 * scale).round(), reason: 'scale $scale');
        expect(decoded.height, (300 * scale).round(), reason: 'scale $scale');
      }
    });

    test('fractional scale rounds: 200x100 at 2.5x -> 500x250', () async {
      final Uint8List png =
          await exporter.pageToPng(textOnlyReport(customPage), 0, scale: 2.5);
      final img.Image decoded = img.decodePng(png)!;
      expect(decoded.width, 500);
      expect(decoded.height, 250);
    });

    test('non-integer page size rounds: A4 at 1x -> 595x842', () async {
      final Uint8List png =
          await exporter.pageToPng(textOnlyReport(PageFormat.a4Portrait), 0);
      final img.Image decoded = img.decodePng(png)!;
      expect(decoded.width, 595, reason: 'round(595.28)');
      expect(decoded.height, 842, reason: 'round(841.89)');
    });
  });

  group('B4 — all pages, in page order, by host iteration', () {
    test('every page of the invoice exports; distinct pages differ', () async {
      final RenderedReport report = invoiceReport();
      final List<Uint8List> pages = <Uint8List>[
        for (int i = 0; i < report.pageCount; i++)
          await exporter.pageToPng(report, i),
      ];
      expect(pages, hasLength(2));
      expect(pages[0], isNot(equals(pages[1])),
          reason: 'page 1 and page 2 show different content');
    });
  });

  group('B3 — run-to-run determinism (in-process)', () {
    test('exporting the same page twice yields identical bytes', () async {
      final RenderedReport report = invoiceReport();
      final Uint8List first = await exporter.pageToPng(report, 0, scale: 2);
      final Uint8List second = await exporter.pageToPng(report, 0, scale: 2);
      expect(second, first);
    });
  });

  group('B4 — invalid requests throw structured errors', () {
    test('pageIndex out of [0, pageCount) throws RangeError', () async {
      final RenderedReport report = invoiceReport();
      await expectLater(
          exporter.pageToPng(report, -1), throwsA(isA<RangeError>()));
      await expectLater(exporter.pageToPng(report, report.pageCount),
          throwsA(isA<RangeError>()),
          reason: 'the same vocabulary RenderedReport.pageAt uses');
    });

    test('scale <= 0 throws ArgumentError', () async {
      final RenderedReport report = invoiceReport();
      await expectLater(exporter.pageToPng(report, 0, scale: 0),
          throwsA(isA<ArgumentError>()));
      await expectLater(exporter.pageToPng(report, 0, scale: -1.5),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('golden pin (T020) — decoded-pixel comparison', () {
    test('invoice page 1 at 2x matches its golden', () async {
      final Uint8List png =
          await exporter.pageToPng(invoiceReport(), 0, scale: 2);
      final ui.Image image = await _decodeUi(png);
      await expectLater(
          image, matchesGoldenFile('../../goldens/invoice_page1_2x.png'));
    }, tags: 'golden');
  });
}
