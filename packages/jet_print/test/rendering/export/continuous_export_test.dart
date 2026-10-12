// Continuous (roll-paper) pages through every output: each PDF page's
// MediaBox, each PNG page's pixels and the print seam all carry the height the
// layout fitted that page to — one ticket per group, each its own length.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jet_print/jet_print.dart';

import 'support/pdf_inspector.dart';

// An 80 mm roll (226.77 pt) with a 50 pt minimum and 5 pt margins.
const PageFormat _roll = PageFormat(
  width: 226.77,
  height: 50,
  margins: JetEdgeInsets.all(5),
  continuous: true,
);

/// Two kitchen tickets: one per station, a 20 pt header and a 20 pt line per
/// item, and a 15 pt page footer that follows each ticket's content.
RenderedReport _tickets() => const JetReportEngine().renderDefinition(
      const ReportDefinition(
        name: 'Kitchen tickets',
        page: _roll,
        furniture: PageFurniture(
          pageFooter: Band(
            id: 'pf',
            type: BandType.pageFooter,
            height: 15,
            elements: <ReportElement>[
              TextElement(
                id: 'thanks',
                bounds: JetRect(x: 0, y: 0, width: 200, height: 12),
                text: 'Afiyet olsun',
              ),
            ],
          ),
        ),
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            groups: <GroupLevel>[
              GroupLevel(
                id: 'g',
                name: 'station',
                key: r'$F{station}',
                startNewPage: true,
                header: Band(
                  id: 'gh',
                  type: BandType.groupHeader,
                  height: 20,
                  elements: <ReportElement>[
                    TextElement(
                      id: 'station',
                      bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                      text: '',
                      expression: r'$F{station}',
                    ),
                  ],
                ),
              ),
            ],
            children: <ScopeNode>[
              BandNode(Band(
                id: 'd',
                type: BandType.detail,
                height: 20,
                elements: <ReportElement>[
                  TextElement(
                    id: 'item',
                    bounds: JetRect(x: 0, y: 0, width: 200, height: 16),
                    text: '',
                    expression: r'$F{item}',
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'station': 'Mutfak', 'item': 'Adana kebap'},
        <String, Object?>{'station': 'Mutfak', 'item': 'Lahmacun'},
        <String, Object?>{'station': 'Mutfak', 'item': 'Mercimek'},
        <String, Object?>{'station': 'Bar', 'item': 'Ayran'},
      ]),
    );

// 5 top + 20 header + n×20 items + 15 footer + 5 bottom.
double _ticketHeight(int items) => 5 + 20 + items * 20 + 15 + 5;

void main() {
  const JetReportExporter exporter = JetReportExporter();

  test('each PDF page is as tall as its own ticket', () async {
    final RenderedReport report = _tickets();
    expect(report.pageCount, 2);
    final PdfInspector pdf = PdfInspector(await exporter.toPdf(report));
    expect(pdf.pageCount, 2);
    expect(pdf.mediaBoxOf(0)[2], closeTo(226.77, 0.01));
    expect(pdf.mediaBoxOf(0)[3], closeTo(_ticketHeight(3), 0.01));
    expect(pdf.mediaBoxOf(1)[2], closeTo(226.77, 0.01));
    expect(pdf.mediaBoxOf(1)[3], closeTo(_ticketHeight(1), 0.01));
    expect(pdf.textOnPage(0), contains('Afiyet olsun'));
    expect(pdf.textOnPage(1), contains('Ayran'));
  });

  test('a PNG page at printer resolution has that ticket\'s height', () async {
    final RenderedReport report = _tickets();
    // 203 dpi, the common thermal printer resolution.
    const double scale = 203 / 72;
    final Uint8List png = await exporter.pageToPng(report, 0, scale: scale);
    final img.Image decoded = img.decodePng(png)!;
    expect(decoded.width, (226.77 * scale).round());
    expect(decoded.height, (_ticketHeight(3) * scale).round());
  });

  test('the print seam is handed page 0\'s fitted size', () async {
    double? height;
    final JetReportPrinter printer = JetReportPrinter(
      presenter: (Uint8List bytes,
          {required String jobName,
          required double pageWidthPt,
          required double pageHeightPt}) async {
        height = pageHeightPt;
        return true;
      },
    );
    await printer.printReport(_tickets());
    expect(height, closeTo(_ticketHeight(3), 0.01));
  });
}
