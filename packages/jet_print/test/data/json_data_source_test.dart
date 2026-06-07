// JetJsonDataSource over a JSON array string (spec 004). No Flutter UI import.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/data/json_data_source.dart';

void main() {
  group('JetJsonDataSource.parse', () {
    test('is a JetDataSource', () {
      expect(JetJsonDataSource.parse('[]'), isA<JetDataSource>());
    });

    test('decodes an array of objects into typed rows', () {
      final JetJsonDataSource source = JetJsonDataSource.parse(
        '[{"qty": 2, "price": 9.5}, {"qty": 3, "price": 4.0}]',
      );
      expect(source.fields, const <FieldDef>[
        FieldDef('qty', type: JetFieldType.integer),
        FieldDef('price', type: JetFieldType.double),
      ]);
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 2);
      expect(ds.current.field('price'), 9.5);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('qty'), 3);
      expect(ds.moveNext(), isFalse);
    });

    test('honours an explicit schema', () {
      final JetJsonDataSource source = JetJsonDataSource.parse(
        '[{"qty": 2, "extra": 1}]',
        fields: const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
      );
      expect(source.fields,
          const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)]);
      final DataSet ds = source.open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.hasField('extra'), isFalse);
    });

    test('throws ArgumentError when the top level is not an array', () {
      expect(() => JetJsonDataSource.parse('{"qty": 1}'), throwsArgumentError);
    });

    test('throws ArgumentError when an element is not an object', () {
      expect(() => JetJsonDataSource.parse('[{"qty": 1}, 5]'),
          throwsArgumentError);
    });

    test('throws a FormatException on malformed JSON', () {
      expect(() => JetJsonDataSource.parse('not json'), throwsFormatException);
    });
  });
}
