library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/aggregate_path.dart';
import 'package:jet_print/src/data/field_def.dart';

// Customer ▸ Order ▸ Line schema fields (root = customer fields).
const List<FieldDef> _root = <FieldDef>[
  FieldDef('customerName', type: JetFieldType.string),
  FieldDef('orders', type: JetFieldType.collection, fields: <FieldDef>[
    FieldDef('orderNo', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('lineTotal', type: JetFieldType.double),
      FieldDef('qty', type: JetFieldType.integer),
    ]),
  ]),
];

void main() {
  test('a non-collection field at this scope is same-scope', () {
    expect(resolveAggregatePath(_root, 'customerName'), isA<SameScope>());
  });

  test('a leaf two collection levels down is a unique descend path', () {
    final AggregatePath r = resolveAggregatePath(_root, 'lineTotal');
    expect(r, isA<DescendPath>());
    expect((r as DescendPath).path, <String>['orders', 'lines']);
  });

  test('a leaf one collection level down is a unique descend path', () {
    final AggregatePath r = resolveAggregatePath(_root, 'orderNo');
    expect((r as DescendPath).path, <String>['orders']);
  });

  test('an unknown operand is not found', () {
    expect(resolveAggregatePath(_root, 'missing'), isA<NotFound>());
  });

  test('same-scope wins even when the name also appears deeper', () {
    const List<FieldDef> fields = <FieldDef>[
      FieldDef('amount', type: JetFieldType.double),
      FieldDef('rows', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
    ];
    expect(resolveAggregatePath(fields, 'amount'), isA<SameScope>());
  });

  test('two distinct sibling descend paths are ambiguous', () {
    const List<FieldDef> fields = <FieldDef>[
      FieldDef('a', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
      FieldDef('b', type: JetFieldType.collection, fields: <FieldDef>[
        FieldDef('amount', type: JetFieldType.double),
      ]),
    ];
    final AggregatePath r = resolveAggregatePath(fields, 'amount');
    expect(r, isA<Ambiguous>());
    expect((r as Ambiguous).paths, hasLength(2));
  });

  test('a collection field of the operand name is not a leaf (not found)', () {
    expect(resolveAggregatePath(_root, 'orders'), isA<NotFound>());
  });
}
