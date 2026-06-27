// test/data/collection_rows_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/collection_rows.dart';
import 'package:jet_print/src/data/field_def.dart';

void main() {
  test('coerces a list of maps into rows', () {
    final rows = coerceCollectionRows(
      <Object?>[
        <String, Object?>{'label': 'Jan', 'revenue': 10},
        <String, Object?>{'label': 'Feb', 'revenue': 20},
      ],
      declaredChildFields: const <FieldDef>[],
    );
    expect(rows, hasLength(2));
    expect(rows.first.field('label'), 'Jan');
    expect(rows[1].field('revenue'), 20);
  });

  test('null and non-list raw → empty', () {
    expect(coerceCollectionRows(null, declaredChildFields: const []), isEmpty);
    expect(coerceCollectionRows(42, declaredChildFields: const []), isEmpty);
  });

  test('non-map entries are skipped and reported', () {
    final skipped = <String>[];
    final rows = coerceCollectionRows(
      <Object?>[
        <String, Object?>{'label': 'ok', 'revenue': 1},
        'oops'
      ],
      declaredChildFields: const <FieldDef>[],
      onSkippedEntry: (k, m) => skipped.add(m),
    );
    expect(rows, hasLength(1));
    expect(skipped, hasLength(1));
  });
}
