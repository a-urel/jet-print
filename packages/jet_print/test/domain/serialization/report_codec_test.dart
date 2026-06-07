import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/migration.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('text', const TextElementCodec());

const ReportTemplate _sample = ReportTemplate(
  name: 'Invoice',
  page: PageFormat.a4Portrait,
  bands: <ReportBand>[
    ReportBand(
      type: BandType.pageHeader,
      height: 60,
      elements: <TextElement>[
        TextElement(
          id: 'title',
          bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
          text: 'INVOICE',
        ),
      ],
    ),
    ReportBand(type: BandType.detail, height: 18),
  ],
);

class _RenameTitleToName extends SchemaMigration {
  @override
  int get fromVersion => 0;

  @override
  Map<String, Object?> upgrade(Map<String, Object?> json) =>
      Map<String, Object?>.of(json)
        ..['name'] = json['title']
        ..remove('title');
}

void main() {
  group('encodeTemplate / decodeTemplate', () {
    test('stamps the current schema version', () {
      expect(encodeTemplate(_sample, _registry())['schemaVersion'],
          kReportSchemaVersion);
    });

    test('round-trips a template through a real JSON string', () {
      final ElementCodecRegistry registry = _registry();
      final String wire = jsonEncode(encodeTemplate(_sample, registry));
      final ReportTemplate decoded = decodeTemplate(
        (jsonDecode(wire) as Map).cast<String, Object?>(),
        registry,
      );
      // Stable: re-encoding the decoded template reproduces the same JSON.
      expect(encodeTemplate(decoded, registry),
          equals(encodeTemplate(_sample, registry)));
      expect(decoded.bands.first.elements.first, isA<TextElement>());
      expect(
          (decoded.bands.first.elements.first as TextElement).text, 'INVOICE');
    });

    test('throws when schemaVersion is missing', () {
      expect(
        () => decodeTemplate(<String, Object?>{'name': 'x'}, _registry()),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('throws when schemaVersion is newer than this build', () {
      expect(
        () => decodeTemplate(
          <String, Object?>{'schemaVersion': kReportSchemaVersion + 1},
          _registry(),
        ),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('migrates an older file forward before parsing', () {
      // A version-0 document used `title` instead of `name`.
      final Map<String, Object?> v0 = <String, Object?>{
        'schemaVersion': 0,
        'title': 'Legacy',
        'page': PageFormat.a4Portrait.toJson(),
        'bands': <Object?>[],
      };
      final ReportTemplate decoded = decodeTemplate(
        v0,
        _registry(),
        migrations: <SchemaMigration>[_RenameTitleToName()],
      );
      expect(decoded.name, 'Legacy');
    });
  });
}
