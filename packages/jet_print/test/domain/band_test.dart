import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_element.dart';

TextElement _txt(String id) => TextElement(
      id: id,
      bounds: const JetRect(x: 0, y: 0, width: 10, height: 10),
      text: id,
    );

void main() {
  group('Band', () {
    test('constructs with an id, type, height and elements', () {
      final Band band = Band(
        id: 'b1',
        type: BandType.detail,
        height: 22,
        elements: <ReportElement>[_txt('e1')],
      );
      expect(band.id, 'b1');
      expect(band.type, BandType.detail);
      expect(band.height, 22);
      expect(band.elements, hasLength(1));
    });

    test('defaults elements to empty', () {
      const Band band = Band(id: 'b', type: BandType.title, height: 10);
      expect(band.elements, isEmpty);
    });

    test('is value-equal by content (deep over elements)', () {
      final Band a = Band(
          id: 'b', type: BandType.detail, height: 5,
          elements: <ReportElement>[_txt('e')]);
      final Band b = Band(
          id: 'b', type: BandType.detail, height: 5,
          elements: <ReportElement>[_txt('e')]);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differs when any field differs', () {
      const Band base = Band(id: 'b', type: BandType.detail, height: 5);
      expect(base, isNot(const Band(id: 'x', type: BandType.detail, height: 5)));
      expect(base, isNot(const Band(id: 'b', type: BandType.title, height: 5)));
      expect(base, isNot(const Band(id: 'b', type: BandType.detail, height: 6)));
    });

    test('copyWith replaces only named fields', () {
      const Band band = Band(id: 'b', type: BandType.detail, height: 5);
      expect(band.copyWith(height: 9),
          const Band(id: 'b', type: BandType.detail, height: 9));
      expect(band.copyWith(type: BandType.groupHeader).type,
          BandType.groupHeader);
      expect(band.copyWith().id, 'b');
    });
  });
}
