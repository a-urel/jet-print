import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    // Robust to test cwd (repo root or package dir).
    String path = key;
    if (!File(path).existsSync()) {
      const String prefix = 'packages/jet_print_google_fonts/';
      path = key.startsWith(prefix) ? key.substring(prefix.length) : key;
    }
    final Uint8List bytes = await File(path).readAsBytes();
    return ByteData.view(
        bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  }
}

ReportTemplate _template(String family) => ReportTemplate(
      name: 'Parity',
      page: const PageFormat(
          width: 300, height: 120, margins: JetEdgeInsets.all(10)),
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 40,
          elements: <ReportElement>[
            TextElement(
              id: 't',
              bounds: const JetRect(x: 0, y: 0, width: 260, height: 20),
              text: 'Catalog font sample',
              style: JetTextStyle(fontFamily: family),
            ),
          ],
        ),
      ],
    );

RenderedReport _render(String family, List<JetFontFamily> fonts) =>
    const JetReportEngine().render(
      _template(family),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
      options: RenderOptions(fonts: fonts),
    );

void main() {
  test('a catalog family exports a PDF that differs from the default render',
      () async {
    final List<JetFontFamily> fonts =
        await loadGoogleFonts(bundle: _DiskBundle());
    // Pick a family whose bytes differ from the engine default (the default is
    // the bundled Noto Sans, so 'Noto Sans' would render identically). A
    // monospace family is unmistakably distinct.
    final String family = googleFontCatalog
        .map((GoogleFontEntry e) => e.name)
        .firstWhere((String n) => n == 'JetBrains Mono',
            orElse: () => googleFontCatalog.last.name);
    final Uint8List withFont =
        await const JetReportExporter().toPdf(_render(family, fonts));
    final Uint8List fallback = await const JetReportExporter()
        .toPdf(_render(family, const <JetFontFamily>[]));
    expect(withFont, isNot(orderedEquals(fallback)),
        reason: 'the catalog font flows through measurement + embedding');
  });
}
