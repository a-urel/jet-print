// Master/detail serialization round-trip (US3 / FR-019; Constitution V).
// The new band fields are additive-optional: schemaVersion stays 1, no migration.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/built_in_element_codecs.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';

ElementCodecRegistry _registry() {
  final ElementCodecRegistry registry = ElementCodecRegistry();
  registerBuiltInElementCodecs(registry);
  return registry;
}

const ReportTemplate _masterDetail = ReportTemplate(
  name: 'invoice',
  page: PageFormat.a4Portrait,
  bands: <ReportBand>[
    ReportBand(
      type: BandType.detail,
      height: 100,
      collectionField: 'lines',
      elements: <ReportElement>[
        TextElement(
          id: 'lineDesc',
          bounds: JetRect(x: 0, y: 0, width: 120, height: 16),
          text: 'desc',
          expression: r'$F{description}',
        ),
      ],
      children: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 40,
          collectionField: 'subLines',
          elements: <ReportElement>[
            TextElement(
              id: 'subSku',
              bounds: JetRect(x: 0, y: 0, width: 80, height: 14),
              text: 'sku',
              expression: r'$F{sku}',
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  test('round-trips collectionField + nested children; schemaVersion stays 1',
      () {
    final ElementCodecRegistry registry = _registry();
    final Map<String, Object?> encoded =
        encodeTemplate(_masterDetail, registry);
    expect(encoded['schemaVersion'], 1);

    final String wire = jsonEncode(encoded);
    final ReportTemplate decoded = decodeTemplate(
      (jsonDecode(wire) as Map).cast<String, Object?>(),
      registry,
    );

    // Stable re-encode.
    expect(encodeTemplate(decoded, registry),
        equals(encodeTemplate(_masterDetail, registry)));

    final ReportBand band = decoded.bands.single;
    expect(band.collectionField, 'lines');
    expect(band.children.single.collectionField, 'subLines');
    expect(band.children.single.children, isEmpty);
  });

  test('a band with no collection binding omits the optional keys', () {
    final ElementCodecRegistry registry = _registry();
    const ReportTemplate plain = ReportTemplate(
      name: 'r',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[ReportBand(type: BandType.detail, height: 20)],
    );
    final Map<String, Object?> band =
        (encodeTemplate(plain, registry)['bands']! as List).single
            as Map<String, Object?>;
    expect(band.containsKey('collectionField'), isFalse);
    expect(band.containsKey('children'), isFalse);
  });
}
