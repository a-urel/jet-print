// JetFieldType lives in the domain seam (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/value_type.dart';

void main() {
  test('enumerates the coarse value types', () {
    expect(JetFieldType.values, <JetFieldType>[
      JetFieldType.string,
      JetFieldType.integer,
      JetFieldType.double,
      JetFieldType.boolean,
      JetFieldType.dateTime,
      JetFieldType.collection,
      JetFieldType.unknown,
    ]);
  });

  test('is still reachable through the data seam re-export', () {
    // A separate assertion in the data tests; here just pin the canonical home.
    expect(JetFieldType.integer.name, 'integer');
  });
}
