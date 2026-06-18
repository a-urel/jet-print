// Barcode-symbologies golden (036 / FR-001 / SC-001 / SC-006).
//
// Renders a small one-band report with four representative symbologies:
//   • Code 128 (alphanumeric, showText: true)  — 1D with HRI digits
//   • EAN-13 ('590123412345', auto-fixed)       — 1D retail barcode + digits
//   • QR code (URL, ecc H)                     — 2D module grid
//   • Data Matrix                               — 2D compact grid
//
// All four share one detail band row, each within a 120 × 90 pt cell.
// The golden exercises the shared render pipeline in a stable, data-free way.
// Regenerate intentional changes with `flutter test --update-goldens`.
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

const PageFormat _page = PageFormat(
  width: 520,
  height: 130,
  margins: JetEdgeInsets.all(8),
);

const double _cellW = 120;
const double _cellH = 90;
const double _topY = 4;

ReportDefinition _definition() => ReportDefinition(
      name: 'Barcode Symbologies',
      page: _page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 100,
              elements: <ReportElement>[
                // Code 128 — 1D, alphanumeric, human-readable text visible
                BarcodeElement(
                  id: 'bc_code128',
                  bounds:
                      JetRect(x: 0, y: _topY, width: _cellW, height: _cellH),
                  symbology: BarcodeSymbology.code128,
                  data: 'JET-036',
                  showText: true,
                  quietZone: true,
                ),
                // EAN-13 — 1D retail, auto-fixed from 12-digit input
                BarcodeElement(
                  id: 'bc_ean13',
                  bounds: JetRect(
                      x: _cellW + 8, y: _topY, width: _cellW, height: _cellH),
                  symbology: BarcodeSymbology.ean13,
                  data: '590123412345',
                  showText: true,
                  quietZone: true,
                ),
                // QR code — 2D, high error-correction
                BarcodeElement(
                  id: 'bc_qr',
                  bounds: JetRect(
                      x: (_cellW + 8) * 2,
                      y: _topY,
                      width: _cellH,
                      height: _cellH),
                  symbology: BarcodeSymbology.qrCode,
                  data: 'https://x.example',
                  eccLevel: QrErrorCorrectionLevel.h,
                  quietZone: true,
                ),
                // Data Matrix — compact 2D
                BarcodeElement(
                  id: 'bc_datamatrix',
                  bounds: JetRect(
                      x: (_cellW + 8) * 2 + _cellH + 8,
                      y: _topY,
                      width: _cellH,
                      height: _cellH),
                  symbology: BarcodeSymbology.dataMatrix,
                  data: 'DM-036',
                  quietZone: true,
                ),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  testWidgets('barcode symbologies render correctly (golden)',
      (WidgetTester tester) async {
    await pumpDesignerWith(
      tester,
      controller: JetReportDesignerController(definition: _definition()),
      themeMode: ThemeMode.light,
      rulers: false,
      grid: false,
    );

    await expectLater(
      find.byType(JetReportDesigner),
      matchesGoldenFile('barcode_symbologies.png'),
    );
  });
}
