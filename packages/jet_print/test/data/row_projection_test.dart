// projectRowOntoFields projects a raw map onto a declared schema (spec 040).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/row_projection.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('a', type: JetFieldType.integer),
  FieldDef('b', type: JetFieldType.string),
];

void main() {
  group('projectRowOntoFields', () {
    test('reads each declared field; missing key → null; extra key dropped',
        () {
      final row = projectRowOntoFields(_schema, <String, Object?>{
        'a': 1,
        'extra': 'dropped',
      });
      expect(row.fields, _schema);
      expect(row.field('a'), 1);
      expect(row.field('b'), isNull);
      expect(row.hasField('extra'), isFalse);
    });
  });
}
