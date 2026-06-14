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

  test('extending a band selection with an element switches to elements', () {
    final Selection s = Selection.band('detail').including('e1');
    expect(s.bandId, isNull);
    expect(s.isReport, isFalse);
    expect(s.ids, <String>['e1']);
  });
}
