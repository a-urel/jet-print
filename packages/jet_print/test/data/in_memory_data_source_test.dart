// JetInMemoryDataSource over List<Map> (spec 004). No Flutter UI import.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/in_memory_data_source.dart';
import 'package:jet_print/src/data/jet_data_source.dart';

void main() {
  group('JetInMemoryDataSource', () {
    test('is a JetDataSource', () {
      expect(JetInMemoryDataSource(const <Map<String, Object?>>[]),
          isA<JetDataSource>());
    });

    test('infers a typed schema as the union of keys in first-seen order', () {
      final JetInMemoryDataSource source =
          JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'qty': 2, 'price': 9.5},
        <String, Object?>{'qty': 3, 'note': 'late'}, // introduces `note`
      ]);
      expect(source.fields, const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('price', type: JetFieldType.double),
        FieldDef('note', type: JetFieldType.string),
      ]);
    });

    test('iterates rows, projecting missing keys to null', () {
      final JetDataSource source = JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'qty': 2, 'price': 9.5},
        <String, Object?>{'qty': 3}, // no price
      ]);
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 2);
      expect(ds.current.field('price'), 9.5);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 3);
      expect(ds.current.field('price'), isNull);
      expect(ds.moveNext(), isFalse);
    });

    test('honours an explicit schema over inference', () {
      final JetInMemoryDataSource source = JetInMemoryDataSource(
        <Map<String, Object?>>[
          <String, Object?>{'qty': 2, 'ignored': true},
        ],
        fields: const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
      );
      expect(source.fields,
          const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)]);
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.hasField('ignored'), isFalse);
    });

    test('open() accepts but ignores params', () {
      final JetDataSource source = JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'qty': 1},
      ]);
      final DataSet ds = source.open(<String, Object?>{'unused': 42});
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 1);
      expect(ds.moveNext(), isFalse); // params had no effect on the rows
    });

    test('open() yields independent cursors', () {
      final JetDataSource source = JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'qty': 1},
        <String, Object?>{'qty': 2},
      ]);
      final DataSet a = source.open();
      final DataSet b = source.open();
      expect(a.moveNext(), isTrue);
      expect(a.current.field('qty'), 1);
      // b is independent and still positioned before its first row.
      expect(b.moveNext(), isTrue);
      expect(b.current.field('qty'), 1);
    });

    test('an empty source infers an empty schema and yields no rows', () {
      final JetInMemoryDataSource source =
          JetInMemoryDataSource(const <Map<String, Object?>>[]);
      expect(source.fields, isEmpty);
      expect(source.open().moveNext(), isFalse);
    });

    test('is immutable — mutating the source list does not affect the source',
        () {
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[
        <String, Object?>{'qty': 1},
      ];
      final JetDataSource source = JetInMemoryDataSource(rows);
      rows.add(<String, Object?>{'qty': 2});
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.moveNext(), isFalse); // still only one row
    });

    test('is immutable — mutating a source row map does not affect the source',
        () {
      final Map<String, Object?> row = <String, Object?>{'qty': 1};
      final JetDataSource source =
          JetInMemoryDataSource(<Map<String, Object?>>[row]);
      row['qty'] = 99; // mutate the caller's row map after construction
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 1); // row snapshot unchanged
    });
  });
}
