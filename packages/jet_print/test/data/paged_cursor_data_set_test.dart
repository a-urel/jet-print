// PagedCursorDataSet: forward cursor over an unknown-total paged feed (spec 040).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_set.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/data/paged_cursor_data_set.dart';

const List<FieldDef> _schema = <FieldDef>[
  FieldDef('n', type: JetFieldType.integer),
];

/// A paged feed of [total] rows ({'n': i}) served [pageSize] at a time. Counts
/// how many times the source asked for a page, to prove laziness.
({DataSet ds, List<int> fetched}) _feed(int total, int pageSize) {
  final List<int> fetched = <int>[];
  final DataSet ds = PagedCursorDataSet(
    fields: _schema,
    pageSize: pageSize,
    fetchPage: (int pageIndex) {
      fetched.add(pageIndex);
      final int start = pageIndex * pageSize;
      if (start >= total) return const <Map<String, Object?>>[];
      final int end = (start + pageSize) > total ? total : start + pageSize;
      return <Map<String, Object?>>[
        for (int i = start; i < end; i++) <String, Object?>{'n': i},
      ];
    },
  );
  return (ds: ds, fetched: fetched);
}

List<int> _drain(DataSet ds) {
  final List<int> out = <int>[];
  while (ds.moveNext()) {
    out.add(ds.current.field('n')! as int);
  }
  return out;
}

void main() {
  group('PagedCursorDataSet', () {
    test('is a DataSet exposing the declared fields', () {
      final feed = _feed(0, 3);
      expect(feed.ds, isA<DataSet>());
      expect(feed.ds.fields, _schema);
    });

    test('walks every row across pages in order (short final page)', () {
      final feed = _feed(7, 3); // pages: [0,1,2][3,4,5][6] → short last page
      expect(_drain(feed.ds), <int>[0, 1, 2, 3, 4, 5, 6]);
      // Stopped at the short page; never fetched a page beyond it.
      expect(feed.fetched, <int>[0, 1, 2]);
    });

    test('exact-multiple total ends on the empty trailing page', () {
      final feed = _feed(6, 3); // pages: [0,1,2][3,4,5][] → empty page ends it
      expect(_drain(feed.ds), <int>[0, 1, 2, 3, 4, 5]);
      expect(feed.fetched, <int>[0, 1, 2]); // page 2 came back empty
    });

    test('an immediately-empty feed yields no rows', () {
      final feed = _feed(0, 3);
      expect(feed.ds.moveNext(), isFalse);
      expect(feed.fetched, <int>[0]);
    });

    test('is lazy — fetches only the first page before the first moveNext', () {
      final feed = _feed(100, 10);
      expect(feed.fetched, isEmpty); // construction fetches nothing
      expect(feed.ds.moveNext(), isTrue);
      expect(feed.fetched, <int>[0]); // exactly one page pulled so far
    });

    test('projects each raw row onto the schema', () {
      final DataSet ds = PagedCursorDataSet(
        fields: _schema,
        pageSize: 2,
        fetchPage: (int p) => p == 0
            ? <Map<String, Object?>>[
                <String, Object?>{'n': 1, 'extra': 'x'}, // extra key dropped
                <String, Object?>{}, // missing key → null
              ]
            : const <Map<String, Object?>>[],
      );
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('n'), 1);
      expect(ds.current.hasField('extra'), isFalse);
      expect(ds.moveNext(), isTrue);
      expect(ds.current.field('n'), isNull);
    });

    test('current throws StateError before the first moveNext', () {
      expect(() => _feed(3, 3).ds.current, throwsStateError);
    });

    test('current throws StateError after exhaustion', () {
      final DataSet ds = _feed(1, 3).ds;
      expect(ds.moveNext(), isTrue);
      expect(ds.moveNext(), isFalse);
      expect(() => ds.current, throwsStateError);
    });

    test('moveNext returns false after close; current then throws', () {
      final DataSet ds = _feed(5, 2).ds;
      expect(ds.moveNext(), isTrue);
      ds.close();
      expect(ds.moveNext(), isFalse);
      expect(() => ds.current, throwsStateError);
    });

    test('close() is idempotent', () {
      final DataSet ds = _feed(5, 2).ds;
      ds.close();
      expect(ds.close, returnsNormally);
    });

    test('pageSize < 1 throws ArgumentError', () {
      expect(
        () => PagedCursorDataSet(
          fields: _schema,
          pageSize: 0,
          fetchPage: (int p) => const <Map<String, Object?>>[],
        ),
        throwsArgumentError,
      );
    });
  });
}
