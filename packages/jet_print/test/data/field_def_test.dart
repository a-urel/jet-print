// FieldDef + JetFieldType value type and best-effort column-type inference
// (spec 004). No Flutter UI import — the data seam stays headless.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';

void main() {
  group('FieldDef', () {
    test('defaults to an unknown type', () {
      expect(const FieldDef('name').type, JetFieldType.unknown);
    });

    test('has value equality and a consistent hash code', () {
      expect(const FieldDef('qty', type: JetFieldType.integer),
          const FieldDef('qty', type: JetFieldType.integer));
      expect(const FieldDef('qty', type: JetFieldType.integer).hashCode,
          const FieldDef('qty', type: JetFieldType.integer).hashCode);
      expect(
          const FieldDef('qty', type: JetFieldType.integer) ==
              const FieldDef('qty', type: JetFieldType.double),
          isFalse);
      expect(
          const FieldDef('qty', type: JetFieldType.integer) ==
              const FieldDef('price', type: JetFieldType.integer),
          isFalse);
    });
  });

  group('FieldDef.inferType', () {
    test('infers integer / double / boolean / string / dateTime', () {
      expect(FieldDef.inferType(<Object?>[1, 2, 3]), JetFieldType.integer);
      expect(FieldDef.inferType(<Object?>[1.5, 2.0]), JetFieldType.double);
      expect(FieldDef.inferType(<Object?>[true, false]), JetFieldType.boolean);
      expect(FieldDef.inferType(<Object?>['a', 'b']), JetFieldType.string);
      expect(FieldDef.inferType(<Object?>[DateTime(2026), DateTime(2025)]),
          JetFieldType.dateTime);
    });

    test('skips nulls when inferring', () {
      expect(FieldDef.inferType(<Object?>[null, 1, null, 2]),
          JetFieldType.integer);
    });

    test('widens a mixed int/double column to double', () {
      expect(FieldDef.inferType(<Object?>[1, 2.5]), JetFieldType.double);
      // Symmetric: widening holds regardless of which type appears first.
      expect(FieldDef.inferType(<Object?>[2.5, 1]), JetFieldType.double);
    });

    test('falls back to unknown for empty, all-null, or mixed columns', () {
      expect(FieldDef.inferType(<Object?>[]), JetFieldType.unknown);
      expect(FieldDef.inferType(<Object?>[null, null]), JetFieldType.unknown);
      expect(FieldDef.inferType(<Object?>[1, 'a']), JetFieldType.unknown);
      expect(FieldDef.inferType(<Object?>[Object()]), JetFieldType.unknown);
    });

    test('never infers the collection type (collections are declared)', () {
      // A nested list value is not a scalar column, so inference yields unknown;
      // JetFieldType.collection is set explicitly, never inferred.
      expect(FieldDef.inferType(<Object?>[<Object?>[]]), JetFieldType.unknown);
      expect(
        FieldDef.inferType(<Object?>[
          <Map<String, Object?>>[<String, Object?>{}],
        ]),
        JetFieldType.unknown,
      );
    });
  });

  group('FieldDef (nested collection)', () {
    test('a collection field carries its own child schema', () {
      const FieldDef lines = FieldDef(
        'lines',
        type: JetFieldType.collection,
        fields: <FieldDef>[
          FieldDef('description', type: JetFieldType.string),
          FieldDef('qty', type: JetFieldType.integer),
        ],
      );
      expect(lines.type, JetFieldType.collection);
      expect(lines.fields.map((FieldDef f) => f.name), <String>[
        'description',
        'qty',
      ]);
    });

    test('a scalar field has no child fields by default', () {
      expect(
          const FieldDef('total', type: JetFieldType.double).fields, isEmpty);
    });

    test('an empty collection (no declared children) is valid', () {
      const FieldDef empty = FieldDef('lines', type: JetFieldType.collection);
      expect(empty.type, JetFieldType.collection);
      expect(empty.fields, isEmpty);
    });

    test('value equality is deep over child fields', () {
      const FieldDef a = FieldDef(
        'lines',
        type: JetFieldType.collection,
        fields: <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
      );
      const FieldDef same = FieldDef(
        'lines',
        type: JetFieldType.collection,
        fields: <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
      );
      const FieldDef differentChild = FieldDef(
        'lines',
        type: JetFieldType.collection,
        fields: <FieldDef>[FieldDef('qty', type: JetFieldType.double)],
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a == differentChild, isFalse);
    });

    test('nests to arbitrary depth (collection within a collection)', () {
      const FieldDef invoice = FieldDef(
        'lines',
        type: JetFieldType.collection,
        fields: <FieldDef>[
          FieldDef(
            'subLines',
            type: JetFieldType.collection,
            fields: <FieldDef>[FieldDef('sku', type: JetFieldType.string)],
          ),
        ],
      );
      expect(invoice.fields.single.type, JetFieldType.collection);
      expect(invoice.fields.single.fields.single.name, 'sku');
    });

    test('defaults description to null', () {
      expect(const FieldDef('qty', type: JetFieldType.integer).description,
          isNull);
    });

    test('carries an optional description without affecting name/type', () {
      const f = FieldDef('customerTotal',
          type: JetFieldType.double, description: 'Total spend per customer');
      expect(f.name, 'customerTotal');
      expect(f.type, JetFieldType.double);
      expect(f.description, 'Total spend per customer');
    });

    test('value equality and hashCode distinguish description', () {
      const a =
          FieldDef('amount', type: JetFieldType.double, description: 'Net');
      const same =
          FieldDef('amount', type: JetFieldType.double, description: 'Net');
      const noDesc = FieldDef('amount', type: JetFieldType.double);
      const otherDesc =
          FieldDef('amount', type: JetFieldType.double, description: 'Gross');
      expect(a == same, isTrue);
      expect(a.hashCode, same.hashCode);
      expect(a == noDesc, isFalse);
      expect(a == otherDesc, isFalse);
    });

    test('toString includes description when set, omits it when null', () {
      expect(
          const FieldDef('amount',
                  type: JetFieldType.double, description: 'Net')
              .toString(),
          contains('Net'));
      expect(const FieldDef('amount', type: JetFieldType.double).toString(),
          isNot(contains('null')));
    });
  });
}
