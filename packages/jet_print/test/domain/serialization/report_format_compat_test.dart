import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';

/// A report serialized by the codec **before** feature 021 (format properties)
/// landed. The string is frozen: it pins the pre-feature wire shape — schema
/// version 1, every existing omission rule (default text style omitted,
/// `fontFamily` only when set, null fill/stroke omitted, barcode color omitted
/// when black) — so any accidental wire change in 021 turns this red (C10,
/// FR-006, SC-004).
const String _preFeatureReportJson =
    '{"schemaVersion":1,"name":"Pre-021 Compatibility Fixture",'
    '"page":{"width":595.28,"height":841.89,'
    '"margins":{"l":28.35,"t":28.35,"r":28.35,"b":28.35}},'
    '"bands":[{"type":"pageHeader","height":120.0,"elements":['
    '{"type":"text","id":"styled-text",'
    '"bounds":{"x":10.0,"y":10.0,"w":200.0,"h":24.0},"text":"INVOICE",'
    '"style":{"fontFamily":"Helvetica","fontSize":20.0,"weight":"semiBold",'
    '"italic":true,"color":"#80FF8800","align":"justify"}},'
    '{"type":"text","id":"plain-text",'
    '"bounds":{"x":10.0,"y":40.0,"w":200.0,"h":16.0},'
    '"text":"Unstyled fallback text"},'
    '{"type":"shape","id":"box",'
    '"bounds":{"x":10.0,"y":60.0,"w":80.0,"h":40.0},"kind":"rectangle",'
    '"style":{"fill":"#3300FF00","stroke":"#FF112233","strokeWidth":2.5}},'
    '{"type":"shape","id":"rule",'
    '"bounds":{"x":10.0,"y":105.0,"w":180.0,"h":0.0},"kind":"line",'
    '"style":{"stroke":"#FF000000","strokeWidth":1.0}},'
    '{"type":"barcode","id":"qr",'
    '"bounds":{"x":120.0,"y":60.0,"w":40.0,"h":40.0},"symbology":"qrCode",'
    '"data":"https://example.com/inv/42","color":"#FF1E40AF"},'
    '{"type":"barcode","id":"code",'
    '"bounds":{"x":170.0,"y":60.0,"w":40.0,"h":40.0},"symbology":"code128",'
    '"data":"42"}]}]}';

void main() {
  group('pre-feature report compatibility (C10 / FR-006 / SC-004)', () {
    test('loads and re-saves byte-identically', () {
      final ReportTemplate decoded =
          JetReportFormat.decodeJson(_preFeatureReportJson);
      expect(JetReportFormat.encodeJson(decoded), _preFeatureReportJson);
    });

    test('loads every element with its pre-feature values intact', () {
      final ReportTemplate decoded =
          JetReportFormat.decodeJson(_preFeatureReportJson);
      final List<ReportElement> elements = decoded.bands.single.elements;

      final TextElement styled = elements[0] as TextElement;
      expect(styled.style.fontFamily, 'Helvetica');
      expect(styled.style.weight, JetFontWeight.semiBold);
      expect(styled.style.color, const JetColor(0x80FF8800));
      expect(styled.style.align, JetTextAlign.justify);

      final TextElement plain = elements[1] as TextElement;
      expect(plain.style, JetTextStyle.fallback);

      final ShapeElement box = elements[2] as ShapeElement;
      expect(box.style.fill, const JetColor(0x3300FF00));
      expect(box.style.stroke, const JetColor(0xFF112233));
      expect(box.style.strokeWidth, 2.5);

      final ShapeElement rule = elements[3] as ShapeElement;
      expect(rule.style.fill, isNull);

      final BarcodeElement qr = elements[4] as BarcodeElement;
      expect(qr.color, const JetColor(0xFF1E40AF));

      final BarcodeElement code = elements[5] as BarcodeElement;
      expect(code.color, JetColor.black);
    });

    test('schema version is still 1 (no migration this feature)', () {
      expect(kReportSchemaVersion, 1);
    });
  });
}
