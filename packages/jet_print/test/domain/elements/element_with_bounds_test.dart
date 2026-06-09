// Unit tests for the additive move/resize primitive `ReportElement.withBounds`
// and `TextElement.copyWith` (Phase 2 / T006 / FR-025).
//
// White-box seam test: it exercises the un-exported domain types directly
// (allowed under test/domain/ by encapsulation_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/unknown_element.dart';

const JetRect _a = JetRect(x: 1, y: 2, width: 3, height: 4);
const JetRect _b = JetRect(x: 10, y: 20, width: 30, height: 40);

void main() {
  group('ReportElement.withBounds returns a same-type copy with new bounds', () {
    test('TextElement preserves text/style/expression', () {
      const TextElement original = TextElement(
        id: 't1',
        bounds: _a,
        text: 'Hello',
        style: JetTextStyle(fontSize: 18, weight: JetFontWeight.bold),
        expression: r'$F{name}',
      );
      final ReportElement moved = original.withBounds(_b);
      expect(moved, isA<TextElement>());
      final TextElement t = moved as TextElement;
      expect(t.bounds, _b);
      expect(t.id, 't1');
      expect(t.text, 'Hello');
      expect(t.style, original.style);
      expect(t.expression, r'$F{name}');
      // Non-destructive: the original is untouched.
      expect(original.bounds, _a);
    });

    test('ShapeElement preserves kind/style/flipDiagonal', () {
      const ShapeElement original = ShapeElement(
        id: 's1',
        bounds: _a,
        kind: ShapeKind.line,
        style: JetBoxStyle(stroke: JetColor(0xFF112233), strokeWidth: 2),
        flipDiagonal: true,
      );
      final ReportElement moved = original.withBounds(_b);
      expect(moved, isA<ShapeElement>());
      final ShapeElement s = moved as ShapeElement;
      expect(s.bounds, _b);
      expect(s.kind, ShapeKind.line);
      expect(s.style, original.style);
      expect(s.flipDiagonal, isTrue);
    });

    test('ImageElement preserves source/fit', () {
      final ImageElement original = ImageElement(
        id: 'i1',
        bounds: _a,
        source: const UrlImageSource('https://example.com/x.png'),
        fit: JetBoxFit.cover,
      );
      final ReportElement moved = original.withBounds(_b);
      expect(moved, isA<ImageElement>());
      final ImageElement i = moved as ImageElement;
      expect(i.bounds, _b);
      expect(i.source, original.source);
      expect(i.fit, JetBoxFit.cover);
    });

    test('BarcodeElement preserves symbology/data/color', () {
      const BarcodeElement original = BarcodeElement(
        id: 'b1',
        bounds: _a,
        symbology: BarcodeSymbology.code128,
        data: '12345',
        color: JetColor(0xFFABCDEF),
      );
      final ReportElement moved = original.withBounds(_b);
      expect(moved, isA<BarcodeElement>());
      final BarcodeElement bc = moved as BarcodeElement;
      expect(bc.bounds, _b);
      expect(bc.symbology, BarcodeSymbology.code128);
      expect(bc.data, '12345');
      expect(bc.color, const JetColor(0xFFABCDEF));
    });

    test('UnknownElement is a passthrough — rawJson preserved byte-for-byte', () {
      final UnknownElement original = UnknownElement(
        typeKey: 'customGauge',
        rawJson: <String, Object?>{
          'type': 'customGauge',
          'id': 'g1',
          'bounds': <String, Object?>{'x': 1.0, 'y': 2.0, 'w': 3.0, 'h': 4.0},
          'min': 0,
          'max': 100,
        },
      );
      final ReportElement result = original.withBounds(_b);
      expect(result, isA<UnknownElement>());
      // The raw JSON is never rewritten (lossless, Constitution V).
      expect((result as UnknownElement).rawJson, original.rawJson);
    });
  });

  group('TextElement.copyWith', () {
    const TextElement base = TextElement(
      id: 't1',
      bounds: _a,
      text: 'Hello',
      expression: 'expr',
    );

    test('replaces only the named fields, preserving the rest', () {
      final TextElement renamed = base.copyWith(text: 'World');
      expect(renamed.text, 'World');
      expect(renamed.bounds, _a);
      expect(renamed.id, 't1');
      expect(renamed.expression, 'expr');
    });

    test('a copyWith with no arguments equals the original by value', () {
      expect(base.copyWith(), base);
    });

    test('can replace style and bounds together', () {
      const JetTextStyle style = JetTextStyle(fontSize: 24);
      final TextElement out = base.copyWith(style: style, bounds: _b);
      expect(out.style, style);
      expect(out.bounds, _b);
      expect(out.text, 'Hello');
    });
  });
}
