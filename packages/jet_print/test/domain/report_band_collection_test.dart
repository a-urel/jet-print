// ReportBand collection-binding + nested children (US3 / FR-015, FR-015a).
// Pure domain — no Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';

void main() {
  group('ReportBand master/detail', () {
    test('defaults to master scope (no collectionField) with no children', () {
      const ReportBand b = ReportBand(type: BandType.detail, height: 20);
      expect(b.collectionField, isNull);
      expect(b.children, isEmpty);
    });

    test('copyWith sets collectionField + children, preserving other fields',
        () {
      const ReportBand child = ReportBand(
        type: BandType.detail,
        height: 10,
        collectionField: 'subLines',
      );
      const ReportBand b = ReportBand(
        type: BandType.detail,
        height: 20,
        elements: <ReportElement>[
          TextElement(
            id: 't',
            bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
            text: 'x',
          ),
        ],
      );

      final ReportBand updated =
          b.copyWith(collectionField: 'lines', children: <ReportBand>[child]);
      expect(updated.collectionField, 'lines');
      expect(updated.children.single.collectionField, 'subLines');
      // Untouched fields are preserved referentially (FR-025).
      expect(updated.elements, same(b.elements));
      expect(updated.type, BandType.detail);
      expect(updated.height, 20);
    });
  });
}
