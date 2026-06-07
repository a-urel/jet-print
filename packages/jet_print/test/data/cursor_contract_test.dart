// DataSet cursor protocol via the shared RowCursorDataSet (spec 004).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/row_cursor_data_set.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('a', type: JetFieldType.integer),
  FieldDef('b', type: JetFieldType.string),
];

DataSet _cursorOver(List<Map<String, Object?>> rows) => RowCursorDataSet(
      fields: _schema,
      rowCount: rows.length,
      rowAt: (int i) => rows[i],
    );

void main() {
  group('RowCursorDataSet (DataSet contract)', () {
    test('is a DataSet exposing the declared fields', () {
      final DataSet ds = _cursorOver(const <Map<String, Object?>>[]);
      expect(ds, isA<DataSet>());
      expect(ds.fields, _schema);
    });

    test('iterates rows forward, projecting each onto the schema', () {
      final DataSet ds = _cursorOver(<Map<String, Object?>>[
        <String, Object?>{'a': 1, 'b': 'x'},
        <String, Object?>{'a': 2, 'b': 'y'},
      ]);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('a'), 1);
      expect(ds.current.field('b'), 'x');
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('a'), 2);
      expect(ds.moveNext(), isFalse);
    });

    test('projects a missing key to null and drops extra keys', () {
      final DataSet ds = _cursorOver(<Map<String, Object?>>[
        <String, Object?>{'a': 1, 'extra': 'dropped'},
      ]);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('a'), 1);
      expect(ds.current.field('b'), isNull); // missing key → null
      expect(ds.current.hasField('extra'), isFalse); // extra key dropped
    });

    test('current throws StateError before the first moveNext', () {
      final DataSet ds = _cursorOver(const <Map<String, Object?>>[
        <String, Object?>{'a': 1, 'b': 'x'},
      ]);
      expect(() => ds.current, throwsStateError);
    });

    test('current throws StateError after exhaustion', () {
      final DataSet ds = _cursorOver(const <Map<String, Object?>>[
        <String, Object?>{'a': 1, 'b': 'x'},
      ]);
      expect(ds.moveNext(), isTrue);
      expect(ds.moveNext(), isFalse);
      expect(() => ds.current, throwsStateError);
    });

    test('moveNext returns false after close', () {
      final DataSet ds = _cursorOver(const <Map<String, Object?>>[
        <String, Object?>{'a': 1, 'b': 'x'},
      ]);
      ds.close();
      expect(ds.moveNext(), isFalse);
      expect(() => ds.current, throwsStateError);
    });

    test('close() is idempotent — calling it twice does not throw', () {
      final DataSet ds = _cursorOver(const <Map<String, Object?>>[
        <String, Object?>{'a': 1, 'b': 'x'},
      ]);
      ds.close();
      expect(ds.close, returnsNormally);
    });
  });
}
