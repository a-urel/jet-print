// ReportBand.group (007c): optional group link; codec round-trips it, omits null.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';

ElementCodecRegistry _registry() => ElementCodecRegistry();

void main() {
  test('group defaults to null and is omitted from a band\'s JSON', () {
    const ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[ReportBand(type: BandType.detail, height: 10)],
    );
    final Map<String, Object?> json = encodeTemplate(tpl, _registry());
    final Map<Object?, Object?> band0 = (json['bands']! as List).first as Map;
    expect(band0.containsKey('group'), isFalse);
  });

  test('group round-trips when set', () {
    const ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}')
      ],
      bands: <ReportBand>[
        ReportBand(type: BandType.groupHeader, height: 10, group: 'region'),
      ],
    );
    final ElementCodecRegistry reg = _registry();
    final ReportTemplate decoded =
        decodeTemplate(encodeTemplate(tpl, reg), reg);
    expect(decoded.bands.single.group, 'region');
  });
}
