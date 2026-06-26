// New-symbologies golden — the cheap-add + free-win 1D codes wired over the
// `barcode` package beyond the original spec-036 set.
//
// A 4 × 3 grid of the twelve newly supported symbologies, each in a 120 × 78 pt
// cell, sharing one detail band. Like the spec-036 symbologies golden it is
// data-free and uses each code's human-readable text (showText) rather than
// separate labels, keeping the Skia glyph cache stable across runs.
// Regenerate intentional changes with `flutter test --update-goldens`.
@Tags(['golden'])
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

const PageFormat _page = PageFormat(
  width: 520,
  height: 282,
  margins: JetEdgeInsets.all(8),
);

const double _cellW = 120;
const double _cellH = 78;
const double _gap = 8;
const int _columns = 4;

/// The twelve newly wired symbologies, each with a value valid for it.
const List<({BarcodeSymbology symbology, String value})> _codes =
    <({BarcodeSymbology symbology, String value})>[
  (symbology: BarcodeSymbology.code93, value: 'CODE-93'),
  (symbology: BarcodeSymbology.codabar, value: '1234567'),
  (symbology: BarcodeSymbology.itf, value: '1234'),
  (symbology: BarcodeSymbology.gs128, value: '(01)00012345678905'),
  (symbology: BarcodeSymbology.upcE, value: '01234565'),
  (symbology: BarcodeSymbology.ean2, value: '12'),
  (symbology: BarcodeSymbology.ean5, value: '12345'),
  (symbology: BarcodeSymbology.postnet, value: '55555'),
  (symbology: BarcodeSymbology.itf16, value: '123456789012345'),
  (symbology: BarcodeSymbology.isbn, value: '9780306406157'),
  (symbology: BarcodeSymbology.telepen, value: 'ABC123'),
  (symbology: BarcodeSymbology.rm4scc, value: 'LE28HE'),
];

ReportDefinition _definition() => ReportDefinition(
      name: 'New Barcode Symbologies',
      page: _page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 274,
              elements: <ReportElement>[
                for (int i = 0; i < _codes.length; i++)
                  BarcodeElement(
                    id: 'bc_${_codes[i].symbology.name}',
                    bounds: JetRect(
                      x: (i % _columns) * (_cellW + _gap),
                      y: (i ~/ _columns) * (_cellH + _gap),
                      width: _cellW,
                      height: _cellH,
                    ),
                    symbology: _codes[i].symbology,
                    data: _codes[i].value,
                    showText: true,
                    quietZone: true,
                  ),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  testWidgets('new barcode symbologies render correctly (golden)',
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
      matchesGoldenFile('barcode_new_symbologies.png'),
    );
  });
}
