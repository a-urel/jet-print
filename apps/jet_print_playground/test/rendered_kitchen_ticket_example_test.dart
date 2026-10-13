// Renders the kitchen-ticket sample through the public engine: one ticket per
// station, each cut to its own length, each carrying the order header and only
// its own station's items, with a note line only under the items that have
// one.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/engine/rendered_report.dart'
    show frameOf;
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/rendered_kitchen_ticket_example.dart';

/// Every text run on page [i], each run's lines joined.
List<String> _texts(RenderedReport r, int i) => <String>[
      for (final TextRunPrimitive p
          in frameOf(r.pageAt(i)).primitives.whereType<TextRunPrimitive>())
        p.lines.map((TextLine l) => l.text).join(' '),
    ];

void main() {
  final RenderedReport report = renderKitchenTicketDefinition();

  test('renders with no diagnostics at all', () {
    // Pages are built lazily, and building one can add diagnostics (a page
    // header or footer expression is evaluated then), so build them all first.
    for (int i = 0; i < report.pageCount; i++) {
      report.pageAt(i);
    }
    // Not even a warning: a binding to a field the source does not declare
    // renders a token and warns.
    expect(report.diagnostics.entries, isEmpty);
  });

  test('prints one ticket per station, in order', () {
    expect(report.pageCount, 3);
    expect(_texts(report, 0), contains('MUTFAK'));
    expect(_texts(report, 1), contains('BAR'));
    expect(_texts(report, 2), contains('TATLI'));
  });

  test('every ticket carries the order header', () {
    for (int i = 0; i < report.pageCount; i++) {
      final List<String> texts = _texts(report, i);
      expect(texts, contains('Masa B4 · Ayşe'), reason: 'page $i');
      expect(texts, contains('Sipariş #1042 · 19:42'), reason: 'page $i');
    }
  });

  test('a ticket lists only its own station\'s items', () {
    final List<String> kitchen = _texts(report, 0);
    expect(kitchen, contains('2 × Adana kebap'));
    expect(kitchen, contains('1 × Mercimek çorbası'));
    expect(kitchen, isNot(contains('2 × Ayran')));
    expect(_texts(report, 1), contains('2 × Ayran'));
    expect(_texts(report, 1), isNot(contains('2 × Adana kebap')));
  });

  test('a note line prints only under an item that has a note', () {
    final List<String> kitchen = _texts(report, 0);
    expect(kitchen, contains('Not: acısız'));
    expect(kitchen.where((String t) => t.startsWith('Not: ')), hasLength(1),
        reason: 'two of the three kitchen items have no note');
    expect(
        _texts(report, 2).where((String t) => t.startsWith('Not: ')), isEmpty);
  });

  test('each ticket is as long as its content, not a fixed sheet', () {
    final double kitchen = frameOf(report.pageAt(0)).page.height;
    final double dessert = frameOf(report.pageAt(2)).page.height;
    expect(kitchen, greaterThan(dessert),
        reason: 'three items and a note outgrow one item');
    for (int i = 0; i < report.pageCount; i++) {
      expect(frameOf(report.pageAt(i)).page.width, closeTo(226.77, 0.01));
    }
  });
}
