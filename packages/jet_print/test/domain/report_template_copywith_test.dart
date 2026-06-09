// Unit tests for the additive `ReportBand.copyWith` / `ReportTemplate.copyWith`
// value-copy helpers (Phase 2 / T006 / FR-025 non-destructiveness).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/domain/value_type.dart';

const TextElement _t = TextElement(
  id: 't1',
  bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
  text: 'A',
);

void main() {
  group('ReportBand.copyWith', () {
    const ReportBand band = ReportBand(
      type: BandType.detail,
      height: 24,
      elements: <ReportElement>[_t],
    );

    test('replaces the element list, preserving type/height', () {
      final ReportBand out = band.copyWith(elements: const <ReportElement>[]);
      expect(out.elements, isEmpty);
      expect(out.type, BandType.detail);
      expect(out.height, 24);
    });

    test('preserves the (referentially identical) element list when omitted',
        () {
      final ReportBand out = band.copyWith(height: 40);
      expect(out.height, 40);
      expect(identical(out.elements, band.elements), isTrue);
    });

    test('can change height and group', () {
      final ReportBand out =
          band.copyWith(type: BandType.groupHeader, group: 'g1');
      expect(out.type, BandType.groupHeader);
      expect(out.group, 'g1');
    });
  });

  group('ReportTemplate.copyWith', () {
    const ReportTemplate template = ReportTemplate(
      name: 'Invoice',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[ReportBand(type: BandType.detail, height: 18)],
      parameters: <ReportParameter>[
        ReportParameter(name: 'p', type: JetFieldType.string),
      ],
      variables: <ReportVariable>[
        ReportVariable(name: 'v', expression: '1'),
      ],
      groups: <ReportGroup>[
        ReportGroup(name: 'g', expression: r'$F{k}'),
      ],
    );

    test('replaces bands while preserving parameters/variables/groups', () {
      final ReportTemplate out = template.copyWith(
        bands: const <ReportBand>[ReportBand(type: BandType.title, height: 50)],
      );
      expect(out.bands.single.type, BandType.title);
      // Untouched declarations are referentially preserved (non-destructive).
      expect(identical(out.parameters, template.parameters), isTrue);
      expect(identical(out.variables, template.variables), isTrue);
      expect(identical(out.groups, template.groups), isTrue);
      expect(out.name, 'Invoice');
      expect(out.page, PageFormat.a4Portrait);
    });

    test('can rename without disturbing structure', () {
      final ReportTemplate out = template.copyWith(name: 'Renamed');
      expect(out.name, 'Renamed');
      expect(identical(out.bands, template.bands), isTrue);
    });
  });
}
