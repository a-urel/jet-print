// DataRow immutable row snapshot (spec 004). No Flutter UI import.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';

DataRow _row() => DataRow(
      fields: const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('note', type: JetFieldType.string),
      ],
      values: <String, Object?>{'qty': 3, 'note': null},
    );

void main() {
  group('DataRow', () {
    test('exposes its declared fields', () {
      expect(_row().fields, const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('note', type: JetFieldType.string),
      ]);
    });

    test('field() returns a declared value, including null', () {
      expect(_row().field('qty'), 3);
      expect(_row().field('note'), isNull);
    });

    test('hasField() distinguishes declared from undeclared', () {
      expect(_row().hasField('qty'), isTrue);
      expect(_row().hasField('missing'), isFalse);
    });

    test('field() throws ArgumentError for an undeclared field', () {
      expect(() => _row().field('missing'), throwsArgumentError);
    });

    test('has value equality and a consistent hash code', () {
      expect(_row(), _row());
      expect(_row().hashCode, _row().hashCode);
    });

    test('rows differing in a value are unequal', () {
      final DataRow other = DataRow(
        fields: const <FieldDef>[
          FieldDef('qty', type: JetFieldType.integer),
          FieldDef('note', type: JetFieldType.string),
        ],
        values: <String, Object?>{'qty': 4, 'note': null},
      );
      expect(_row() == other, isFalse);
    });

    test('rows differing only in a field type are unequal', () {
      final DataRow typed = DataRow(
        fields: const <FieldDef>[
          FieldDef('qty', type: JetFieldType.string), // type differs
          FieldDef('note', type: JetFieldType.string),
        ],
        values: <String, Object?>{'qty': 3, 'note': null},
      );
      expect(_row() == typed, isFalse);
    });

    test('rows with equal values but different field order are unequal', () {
      final DataRow reordered = DataRow(
        fields: const <FieldDef>[
          FieldDef('note', type: JetFieldType.string),
          FieldDef('qty', type: JetFieldType.integer),
        ],
        values: <String, Object?>{'qty': 3, 'note': null},
      );
      expect(_row() == reordered, isFalse);
    });

    test(
        'is immutable — the source map cannot mutate the row after construction',
        () {
      final Map<String, Object?> values = <String, Object?>{
        'qty': 3,
        'note': null
      };
      final DataRow row = DataRow(
        fields: const <FieldDef>[
          FieldDef('qty', type: JetFieldType.integer),
          FieldDef('note', type: JetFieldType.string),
        ],
        values: values,
      );
      values['qty'] = 99; // mutate the caller's map
      expect(row.field('qty'), 3); // row unaffected
    });
  });
}
