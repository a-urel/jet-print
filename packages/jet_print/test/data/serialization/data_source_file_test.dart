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

    test('wraps malformed JSON in JetDataSourceFormatException', () {
      expect(
        () => JetDataSourceFile.decodeJson('{bad'),
        throwsA(isA<JetDataSourceFormatException>()),
      );
    });

    test('rejects a too-new version', () {
      expect(
        () => JetDataSourceFile.decode(<String, Object?>{
          'jetDataSource': 999,
          'schema': <String, Object?>{'name': 'X', 'fields': <Object?>[]},
        }),
        throwsA(isA<JetDataSourceFormatException>()),
      );
    });

    test('equality and hashCode are deep for nested-list sample rows', () {
      const JetDataSourceDocument docA = JetDataSourceDocument(
        schema: schema,
        sample: <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'lines': <Map<String, Object?>>[
              <String, Object?>{'sku': 'A', 'qty': 2},
              <String, Object?>{'sku': 'B', 'qty': 3},
            ],
          },
        ],
      );
      // Identical nested structure — must be equal.
      const JetDataSourceDocument docB = JetDataSourceDocument(
        schema: schema,
        sample: <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'lines': <Map<String, Object?>>[
              <String, Object?>{'sku': 'A', 'qty': 2},
              <String, Object?>{'sku': 'B', 'qty': 3},
            ],
          },
        ],
      );
      expect(docA, equals(docB));
      expect(docA.hashCode, docB.hashCode);

      // Different nested content — must NOT be equal.
      const JetDataSourceDocument docC = JetDataSourceDocument(
        schema: schema,
        sample: <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'lines': <Map<String, Object?>>[
              <String, Object?>{'sku': 'X', 'qty': 99},
            ],
          },
        ],
      );
      expect(docA, isNot(equals(docC)));
    });

    test(
        'non-Map child in collection fields throws JetDataSourceFormatException',
        () {
      expect(
        () => JetDataSourceFile.decode(<String, Object?>{
          'jetDataSource': 1,
          'schema': <String, Object?>{
            'name': 'X',
            'fields': <Object?>[
              <String, Object?>{
                'name': 'lines',
                'type': 'collection',
                'fields': <Object?>['not-a-map'],
              },
            ],
          },
        }),
        throwsA(isA<JetDataSourceFormatException>()),
      );
    });
  });
}
