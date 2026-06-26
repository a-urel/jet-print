import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  group('JetDataSourceFile', () {
    const JetDataSchema schema = JetDataSchema(
      name: 'Invoice',
      fields: <FieldDef>[
        FieldDef('id', type: JetFieldType.integer),
        FieldDef('customer', type: JetFieldType.string),
        FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
          FieldDef('sku', type: JetFieldType.string),
          FieldDef('qty', type: JetFieldType.integer),
        ]),
      ],
    );

    test('round-trips schema only (no sample)', () {
      const JetDataSourceDocument doc = JetDataSourceDocument(schema: schema);
      final JetDataSourceDocument back =
          JetDataSourceFile.decodeJson(JetDataSourceFile.encodeJson(doc));
      expect(back.schema, schema);
      expect(back.sample, isNull);
    });

    test('round-trips nested collection fidelity + sample rows', () {
      const JetDataSourceDocument doc = JetDataSourceDocument(
        schema: schema,
        sample: <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'customer': 'Acme',
            'lines': <Map<String, Object?>>[
              <String, Object?>{'sku': 'A', 'qty': 2},
            ],
          },
        ],
      );
      final JetDataSourceDocument back =
          JetDataSourceFile.decodeJson(JetDataSourceFile.encodeJson(doc));
      expect(back.schema, schema);
      expect(back.sample, doc.sample);
    });

    test('stamps the version constant', () {
      final Map<String, Object?> json =
          JetDataSourceFile.encode(const JetDataSourceDocument(schema: schema));
      expect(json['jetDataSource'], JetDataSourceFile.version);
    });

    test('rejects a missing/wrong version', () {
      expect(
        () => JetDataSourceFile.decode(<String, Object?>{
          'schema': <String, Object?>{'name': 'X', 'fields': <Object?>[]},
        }),
        throwsA(isA<JetDataSourceFormatException>()),
      );
    });

    test('rejects an unknown field type', () {
      expect(
        () => JetDataSourceFile.decode(<String, Object?>{
          'jetDataSource': 1,
          'schema': <String, Object?>{
            'name': 'X',
            'fields': <Object?>[
              <String, Object?>{'name': 'a', 'type': 'wat'},
            ],
          },
        }),
        throwsA(isA<JetDataSourceFormatException>()),
      );
    });

    test('rejects non-object JSON text', () {
      expect(() => JetDataSourceFile.decodeJson('[]'),
          throwsA(isA<JetDataSourceFormatException>()));
    });
  });
}
