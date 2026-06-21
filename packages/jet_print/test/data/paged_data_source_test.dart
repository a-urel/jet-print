// JetPagedDataSource: public lazily-paged source (spec 040). No Flutter UI import.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart'
    show JetDataSource, JetPagedDataSource;
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('n', type: JetFieldType.integer),
];

JetPagedDataSource _source(int total, {int pageSize = 3}) => JetPagedDataSource(
      fields: _schema,
      pageSize: pageSize,
      fetchPage: (int pageIndex) {
        final int start = pageIndex * pageSize;
        if (start >= total) return const <Map<String, Object?>>[];
        final int end = (start + pageSize) > total ? total : start + pageSize;
        return <Map<String, Object?>>[
          for (int i = start; i < end; i++) <String, Object?>{'n': i},
        ];
      },
    );

void main() {
  group('JetPagedDataSource', () {
    test('is a JetDataSource exposing its explicit schema', () {
      final JetPagedDataSource s = _source(0);
      expect(s, isA<JetDataSource>());
      expect(s.fields, _schema);
    });

    test('walks an unknown-total feed to completion', () {
      final DataSet ds = _source(7).open();
      final List<int> out = <int>[];
      while (ds.moveNext()) {
        out.add(ds.current.field('n')! as int);
      }
      expect(out, <int>[0, 1, 2, 3, 4, 5, 6]);
    });

    test('open() yields fresh independent cursors', () {
      final JetDataSource s = _source(5);
      final DataSet a = s.open();
      final DataSet b = s.open();
      expect(a.moveNext(), isTrue);
      expect(a.current.field('n'), 0);
      expect(b.moveNext(), isTrue);
      expect(b.current.field('n'), 0); // b independent, still at the start
    });

    test('open() accepts but ignores params', () {
      final DataSet ds = _source(2).open(<String, Object?>{'unused': 1});
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('n'), 0);
      expect(ds.moveNext(), isTrue);
      expect(ds.moveNext(), isFalse);
    });

    test('pageSize < 1 throws ArgumentError', () {
      expect(
        () => JetPagedDataSource(
          fields: _schema,
          pageSize: 0,
          fetchPage: (int p) => const <Map<String, Object?>>[],
        ),
        throwsArgumentError,
      );
    });
  });
}
