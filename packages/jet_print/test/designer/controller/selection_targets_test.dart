// Selection can target a single band or the whole report/page, in addition to a
// set of elements. These targets are mutually exclusive and drive the new
// band/page selection chrome. Exercised through the public Selection type.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('a band selection carries its id and holds no elements', () {
    final Selection s = Selection.band('detail');
    expect(s.bandId, 'detail');
    expect(s.isReport, isFalse);
    expect(s.ids, isEmpty);
    expect(s.length, 0);
    expect(s.singleOrNull, isNull);
    expect(s.isEmpty, isFalse,
        reason: 'a selected band is a non-empty selection');
    expect(s.isNotEmpty, isTrue);
  });

  test('a report selection is flagged and holds neither band nor elements', () {
    final Selection s = Selection.report();
    expect(s.isReport, isTrue);
    expect(s.bandId, isNull);
    expect(s.ids, isEmpty);
    expect(s.isEmpty, isFalse);
  });

  test('the empty selection targets nothing', () {
    expect(Selection.empty.isEmpty, isTrue);
    expect(Selection.empty.bandId, isNull);
    expect(Selection.empty.isReport, isFalse);
  });

  test('an element selection targets neither a band nor the report', () {
    final Selection s = Selection.of(<String>['a', 'b']);
    expect(s.bandId, isNull);
    expect(s.isReport, isFalse);
    expect(s.length, 2);
    expect(s.isEmpty, isFalse);
  });

  test('selection targets compare by kind and value', () {
    expect(Selection.band('ph'), equals(Selection.band('ph')));
    expect(Selection.band('ph'), isNot(equals(Selection.band('detail'))));
    expect(Selection.band('ph'), isNot(equals(Selection.report())));
    expect(Selection.report(), equals(Selection.report()));
    expect(Selection.band('ph'), isNot(equals(Selection.of(<String>['x']))));
    expect(Selection.band('ph').hashCode, Selection.band('ph').hashCode);
  });

  // Spec B: a crosstab is the fifth target. The invariant "exactly one of
  // five" is enforced by hand in the factories, ==, and toString, so it is
  // pinned here rather than trusted.
  test('every factory produces exactly one non-empty target', () {
    final List<Selection> all = <Selection>[
      Selection.of(<String>['e1']),
      Selection.band('b1'),
      Selection.group('g1'),
      Selection.scope('s1'),
      Selection.crosstab('ct1'),
      Selection.report(),
    ];
    for (final Selection s in all) {
      final int targets = (s.ids.isNotEmpty ? 1 : 0) +
          (s.bandId != null ? 1 : 0) +
          (s.groupId != null ? 1 : 0) +
          (s.scopeId != null ? 1 : 0) +
          (s.crosstabId != null ? 1 : 0) +
          (s.isReport ? 1 : 0);
      expect(targets, 1, reason: '$s');
      expect(s.isEmpty, isFalse, reason: '$s');
    }
    for (int i = 0; i < all.length; i++) {
      for (int j = i + 1; j < all.length; j++) {
        expect(all[i] == all[j], isFalse, reason: '${all[i]} vs ${all[j]}');
      }
    }
  });

  test('a crosstab selection carries its id and nothing else', () {
    final Selection s = Selection.crosstab('ct1');
    expect(s.crosstabId, 'ct1');
    expect(s.toString(), contains('ct1'));
    expect(Selection.crosstab('ct1'), equals(Selection.crosstab('ct1')));
    expect(
        Selection.crosstab('ct1').hashCode, Selection.crosstab('ct1').hashCode);
    expect(Selection.empty.crosstabId, isNull);
    expect(s.including('e1').crosstabId, isNull);
  });

  test('extending a band selection with an element switches to elements', () {
    final Selection s = Selection.band('detail').including('e1');
    expect(s.bandId, isNull);
    expect(s.isReport, isFalse);
    expect(s.ids, <String>['e1']);
  });
}
