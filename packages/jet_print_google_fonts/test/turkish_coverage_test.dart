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

void main() {
  test('catalog families render Turkish text and export without error',
      () async {
    final List<JetFontFamily> fonts =
        await loadGoogleFonts(bundle: _DiskBundle());
    const String tr = 'İıŞşĞğÇçÖöÜü';
    final String family = googleFontCatalog.first.name;
    final RenderedReport report = const JetReportEngine().renderDefinition(
      ReportDefinition(
        name: 'TR',
        page: const PageFormat(
            width: 300, height: 120, margins: JetEdgeInsets.all(10)),
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(
                id: 'detail',
                type: BandType.detail,
                height: 40,
                elements: <ReportElement>[
                  TextElement(
                    id: 't',
                    bounds: const JetRect(x: 0, y: 0, width: 260, height: 20),
                    text: tr,
                    style: JetTextStyle(fontFamily: family),
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
      options: RenderOptions(fonts: fonts),
    );
    final Uint8List pdf = await const JetReportExporter().toPdf(report);
    expect(pdf, isNotEmpty);
    expect(report.pageAt(0).frame.primitives, isNotEmpty);
  });
}
