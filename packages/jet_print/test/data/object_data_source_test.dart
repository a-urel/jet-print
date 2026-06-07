// JetObjectDataSource<T> over a typed object list (spec 004). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/jet_data_source.dart';
import 'package:jet_print/src/data/object_data_source.dart';

class _Line {
  const _Line(this.sku, this.qty);
  final String sku;
  final int qty;
}

JetObjectDataSource<_Line> _source(List<_Line> lines) =>
    JetObjectDataSource<_Line>(
      lines,
      fields: const <FieldDef>[
        FieldDef('sku', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
      ],
      row: (_Line l) => <String, Object?>{'sku': l.sku, 'qty': l.qty},
    );

void main() {
  group('JetObjectDataSource', () {
    test('is a JetDataSource exposing the explicit schema', () {
      final JetObjectDataSource<_Line> source = _source(const <_Line>[]);
      expect(source, isA<JetDataSource>());
      expect(source.fields, const <FieldDef>[
        FieldDef('sku', type: JetFieldType.string),
        FieldDef('qty', type: JetFieldType.integer),
      ]);
      expect(source.open().moveNext(), isFalse); // empty list → no rows
    });

    test('iterates objects, mapping each via the extractor', () {
      final DataSet ds = _source(const <_Line>[
        _Line('A1', 2),
        _Line('B2', 5),
      ]).open();
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('sku'), 'A1');
      expect(ds.current.field('qty'), 2);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('sku'), 'B2');
      expect(ds.moveNext(), isFalse);
    });

    test('maps lazily — the extractor runs only during iteration', () {
      int calls = 0;
      final JetObjectDataSource<_Line> source = JetObjectDataSource<_Line>(
        const <_Line>[_Line('A1', 2), _Line('B2', 5)],
        fields: const <FieldDef>[FieldDef('qty', type: JetFieldType.integer)],
        row: (_Line l) {
          calls++;
          return <String, Object?>{'qty': l.qty};
        },
      );
      expect(calls, 0); // construction maps nothing
      final DataSet ds = source.open();
      expect(calls, 0); // open maps nothing
      ds.moveNext();
      expect(calls, 1); // first row mapped on demand
    });

    test('open() yields independent cursors', () {
      final JetObjectDataSource<_Line> source =
          _source(const <_Line>[_Line('A1', 2)]);
      final DataSet a = source.open();
      final DataSet b = source.open();
      expect(a.moveNext(), isTrue);
      expect(b.moveNext(), isTrue);
      expect(b.current.field('sku'), 'A1');
    });
  });
}
