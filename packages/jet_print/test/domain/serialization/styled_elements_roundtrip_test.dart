// T052 closure (spec 021): a report carrying all three styled element kinds —
// text (underline + translucent color), shape (fill/stroke/none states), and
// barcode (custom color) — survives an encode→decode round-trip byte-for-byte
// (quickstart §4.3). This is the automatable half of the format-properties
// acceptance; the visual GUI steps are recorded in acceptance-T052.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _styledDef() => const ReportDefinition(
      name: 'Styled',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 80,
              elements: <ReportElement>[
                TextElement(
                  id: 't1',
                  bounds: JetRect(x: 0, y: 0, width: 120, height: 18),
                  text: 'Hi',
                  style: JetTextStyle(
                    weight: JetFontWeight.bold,
                    underline: true,
                    color: JetColor(0x80123456), // translucent
                    align: JetTextAlign.center,
                  ),
                ),
                ShapeElement(
                  id: 's1',
                  bounds: JetRect(x: 0, y: 20, width: 40, height: 40),
                  kind: ShapeKind.rectangle,
                  style: JetBoxStyle(
                    fill: JetColor(0x3300FF00),
                    stroke: JetColor.black,
                    strokeWidth: 3,
                  ),
                ),
                BarcodeElement(
                  id: 'b1',
                  bounds: JetRect(x: 0, y: 64, width: 60, height: 16),
                  symbology: BarcodeSymbology.qrCode,
                  data: '42',
                  color: JetColor(0xFF1E40AF),
                ),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  test('all three styled element kinds round-trip losslessly (T052)', () {
    final ReportDefinition original = _styledDef();
    final String json = JetReportFormat.encodeDefinitionJson(original);
    final ReportDefinition reopened =
        JetReportFormat.decodeDefinitionJson(json);

    // Byte-stable canonical form is the strongest single assertion.
    expect(
      JetReportFormat.encodeDefinition(reopened),
      equals(JetReportFormat.encodeDefinition(original)),
    );

    // Spot-check the specific style fields the quickstart calls out.
    final List<ReportElement> els =
        reopened.body.root.children.whereType<BandNode>().single.band.elements;
    final TextElement text = els.whereType<TextElement>().single;
    expect(text.style.underline, isTrue);
    expect(text.style.color, const JetColor(0x80123456));
    final ShapeElement shape = els.whereType<ShapeElement>().single;
    expect(shape.style.fill, const JetColor(0x3300FF00));
    expect(shape.style.strokeWidth, 3);
    final BarcodeElement barcode = els.whereType<BarcodeElement>().single;
    expect(barcode.color, const JetColor(0xFF1E40AF));
  });
}
