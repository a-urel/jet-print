import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/serialization/report_format.dart';

ReportDefinition _defWithDetailBand(Band detailBand) => ReportDefinition(
      name: 'Test',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[BandNode(detailBand)],
        ),
      ),
    );

void main() {
  test('band visible round-trips; default omitted', () {
    const nonDefaultVisible = BoolProperty(expression: r'$F{show}');
    final band = Band(
      id: 'root/c0',
      type: BandType.detail,
      height: 20,
      visible: nonDefaultVisible,
    );
    final def = _defWithDetailBand(band);

    final json = JetReportFormat.encodeDefinition(def);
    final back = JetReportFormat.decodeDefinition(json);

    final decodedBand = (back.body.root.children.first as BandNode).band;
    expect(decodedBand.visible, nonDefaultVisible);
  });

  test('default visible band omits the visible key in JSON', () {
    final band = Band(
      id: 'root/c0',
      type: BandType.detail,
      height: 20,
    );
    final def = _defWithDetailBand(band);

    final json = JetReportFormat.encodeDefinition(def);

    // Navigate the encoded JSON to the detail band map
    final bodyJson = json['body']! as Map<String, Object?>;
    final rootJson = bodyJson['root']! as Map<String, Object?>;
    final children = rootJson['children']! as List<Object?>;
    final bandJson = (children.first! as Map).cast<String, Object?>();
    expect(bandJson.containsKey('visible'), isFalse);
  });
}
