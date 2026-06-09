// JetDataSchema — the host-supplied data-source structure attached to the
// designer (spec 009). No Flutter UI import — the data seam stays headless.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_schema.dart';
import 'package:jet_print/src/data/field_def.dart';

void main() {
  group('JetDataSchema', () {
    const JetDataSchema invoice = JetDataSchema(
      name: 'Invoice',
      fields: <FieldDef>[
        FieldDef('invoiceNo', type: JetFieldType.string),
        FieldDef('total', type: JetFieldType.double),
        FieldDef(
          'lines',
          type: JetFieldType.collection,
          fields: <FieldDef>[
            FieldDef('description', type: JetFieldType.string),
            FieldDef('qty', type: JetFieldType.integer),
          ],
        ),
      ],
    );

    test('holds a dataset name and a root field list', () {
      expect(invoice.name, 'Invoice');
      expect(invoice.fields.map((FieldDef f) => f.name), <String>[
        'invoiceNo',
        'total',
        'lines',
      ]);
    });

    test('exposes the nested collection field with its child schema', () {
      final FieldDef lines =
          invoice.fields.firstWhere((FieldDef f) => f.name == 'lines');
      expect(lines.type, JetFieldType.collection);
      expect(lines.fields.map((FieldDef f) => f.name), <String>[
        'description',
        'qty',
      ]);
    });

    test('has value equality including nested fields', () {
      const JetDataSchema same = JetDataSchema(
        name: 'Invoice',
        fields: <FieldDef>[
          FieldDef('invoiceNo', type: JetFieldType.string),
          FieldDef('total', type: JetFieldType.double),
          FieldDef(
            'lines',
            type: JetFieldType.collection,
            fields: <FieldDef>[
              FieldDef('description', type: JetFieldType.string),
              FieldDef('qty', type: JetFieldType.integer),
            ],
          ),
        ],
      );
      const JetDataSchema differentChild = JetDataSchema(
        name: 'Invoice',
        fields: <FieldDef>[
          FieldDef('invoiceNo', type: JetFieldType.string),
          FieldDef('total', type: JetFieldType.double),
          FieldDef(
            'lines',
            type: JetFieldType.collection,
            fields: <FieldDef>[
              FieldDef('description', type: JetFieldType.string),
              FieldDef('qty', type: JetFieldType.double), // changed
            ],
          ),
        ],
      );
      expect(invoice, same);
      expect(invoice.hashCode, same.hashCode);
      expect(invoice == differentChild, isFalse);
      expect(
        invoice == const JetDataSchema(name: 'Other', fields: <FieldDef>[]),
        isFalse,
      );
    });

    test('supports a collection-within-a-collection tree', () {
      const JetDataSchema deep = JetDataSchema(
        name: 'Invoice',
        fields: <FieldDef>[
          FieldDef(
            'lines',
            type: JetFieldType.collection,
            fields: <FieldDef>[
              FieldDef(
                'subLines',
                type: JetFieldType.collection,
                fields: <FieldDef>[FieldDef('sku', type: JetFieldType.string)],
              ),
            ],
          ),
        ],
      );
      expect(deep.fields.single.fields.single.type, JetFieldType.collection);
      expect(deep.fields.single.fields.single.fields.single.name, 'sku');
    });
  });
}
