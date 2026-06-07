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
  });
}
