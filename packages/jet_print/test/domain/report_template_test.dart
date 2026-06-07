import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_template.dart';

void main() {
  group('ReportBand', () {
    test('defaults to no elements', () {
      const ReportBand band = ReportBand(type: BandType.pageHeader, height: 40);
      expect(band.type, BandType.pageHeader);
      expect(band.height, 40);
      expect(band.elements, isEmpty);
    });
  });

  group('ReportTemplate', () {
    test('holds a name, page, and ordered bands', () {
      const ReportTemplate template = ReportTemplate(
        name: 'Invoice',
        page: PageFormat.a4Portrait,
        bands: <ReportBand>[
          ReportBand(
            type: BandType.detail,
            height: 18,
            elements: <TextElement>[
              TextElement(
                id: 'line',
                bounds: JetRect(x: 0, y: 0, width: 200, height: 18),
                text: r'$F{description}',
              ),
            ],
          ),
        ],
      );
      expect(template.name, 'Invoice');
      expect(template.page, PageFormat.a4Portrait);
      expect(template.bands.single.elements.single, isA<TextElement>());
    });
  });
}
