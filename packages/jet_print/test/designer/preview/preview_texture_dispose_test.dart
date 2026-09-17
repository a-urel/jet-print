// Texture-disposal coverage for the two preview surfaces, end to end.
//
// Both record through `recordPageFrame`, which releases the painter — these
// tests pin that the release actually reaches a real widget, on the surfaces
// that re-record most often (the preview on every page change, the rail on
// every tile). The only observable evidence is
// `CanvasPainter.debugLiveDecodedImages`: the seam builds the painter
// internally and never hands it back.
//
// White-box: the rail is an unexported `src/` designer-internal seam (the
// `page_thumbnail_rail_test` precedent), and the counters are an unexported
// test seam.
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/preview/page_thumbnail_rail.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// 200x100 page, 10pt margins -> 80pt body; 30pt detail bands -> 2 rows/page.
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

/// A tiny but genuinely valid PNG (pure-Dart encode, so it decodes on web too).
Uint8List _validPng() {
  final img.Image image = img.Image(width: 4, height: 2);
  for (int y = 0; y < 2; y++) {
    for (int x = 0; x < 4; x++) {
      image.setPixelRgba(x, y, 32 + 48 * x, 64 + 64 * y, 200, 255);
    }
  }
  return img.encodePng(image);
}

/// A report whose every detail row carries an image, so each recorded page
/// decodes textures and a per-record leak accumulates visibly. When
/// [trailingBytes] is given, a SECOND image follows the valid one in the same
/// band — pass corrupt bytes to make `prepare` throw with one texture already
/// decoded.
RenderedReport _report({int rows = 4, Uint8List? trailingBytes}) =>
    const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'Imaged Report',
        page: _page,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(
                id: 'root/c0',
                type: BandType.detail,
                height: 30,
                elements: <ReportElement>[
                  ImageElement(
                    id: 'img',
                    bounds: const JetRect(x: 0, y: 0, width: 16, height: 16),
                    source: BytesImageSource(_validPng()),
                  ),
                  if (trailingBytes != null)
                    ImageElement(
                      id: 'img2',
                      bounds: const JetRect(x: 20, y: 0, width: 16, height: 16),
                      source: BytesImageSource(trailingBytes),
                    ),
                ],
              )),
            ],
          ),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < rows; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

Widget _shell(Widget child) => ShadApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      themeMode: ThemeMode.light,
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadSlateColorScheme.light(),
      ),
      home: child,
    );

/// Pumps [child], draining real-async work until every in-flight record has
/// finished.
///
/// Two things make this fiddly, and both matter for the assertions to mean
/// anything.
///
/// `ui.instantiateImageCodec` is an engine-mediated async decode that a plain
/// widget test never completes, so without [WidgetTester.runAsync] nothing is
/// ever decoded — and "no textures alive" would then hold vacuously. Every
/// test below therefore also asserts `debugTotalDecodedImages`, the monotonic
/// counter: a live gauge sampled between turns would MISS the throwing path,
/// where a decode and its disposal land in the same turn.
///
/// And ONE `runAsync` turn is not enough: it resolves the codec future, but
/// the continuation that awaited it — the half of `_record` that records the
/// picture and releases the painter — only runs on a later real-async turn,
/// which `pumpAndSettle` (fake clock) will not drive. The VM reaches that in
/// two turns; a browser takes about six. Hence the rounds, sized well past
/// both.
Future<void> _pumpAndDrain(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_shell(child));
  for (int round = 0; round < 16; round++) {
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(CanvasPainter.debugResetDecodedImageCounters);

  testWidgets('JetReportPreview leaves no decoded texture alive',
      (WidgetTester tester) async {
    final RenderedReport report = _report();

    await _pumpAndDrain(
        tester, JetReportPreview(report: report, showThumbnails: false));

    expect(CanvasPainter.debugTotalDecodedImages, greaterThan(0),
        reason: 'the run must actually decode something');
    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });

  testWidgets('PageThumbnailRail leaves no decoded texture alive',
      (WidgetTester tester) async {
    final RenderedReport report = _report();

    await _pumpAndDrain(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: PageThumbnailRail(
          report: report,
          currentIndex: 0,
          onSelect: (int _) {},
        ),
      ),
    );

    expect(CanvasPainter.debugTotalDecodedImages, greaterThan(0),
        reason: 'the run must actually decode something');
    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });

  testWidgets('PageThumbnailRail releases textures when a record throws',
      (WidgetTester tester) async {
    // A VALID image precedes a corrupt one in the same band, so
    // `ui.instantiateImageCodec` throws inside `CanvasPainter.prepare` with a
    // texture already decoded (the rail catches and swallows the throw). Had
    // every image been corrupt, nothing would ever decode and this would pass
    // vacuously.
    final RenderedReport report =
        _report(trailingBytes: Uint8List.fromList(<int>[1, 2, 3, 4]));

    await _pumpAndDrain(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: PageThumbnailRail(
          report: report,
          currentIndex: 0,
          onSelect: (int _) {},
        ),
      ),
    );

    expect(CanvasPainter.debugTotalDecodedImages, greaterThan(0),
        reason: 'the run must actually decode something');
    expect(CanvasPainter.debugLiveDecodedImages, 0);
  });
}
