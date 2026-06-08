// ReportGroup value type + serialization (spec 005b; flags 008b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_group.dart';

void main() {
  group('ReportGroup', () {
    test('round-trips through JSON', () {
      const ReportGroup g =
          ReportGroup(name: 'category', expression: r'$F{category}');
      expect(ReportGroup.fromJson(g.toJson()), g);
    });

    test('has value equality and a consistent hash code', () {
      expect(const ReportGroup(name: 'a', expression: 'x'),
          const ReportGroup(name: 'a', expression: 'x'));
      expect(const ReportGroup(name: 'a', expression: 'x').hashCode,
          const ReportGroup(name: 'a', expression: 'x').hashCode);
      expect(
          const ReportGroup(name: 'a', expression: 'x') ==
              const ReportGroup(name: 'a', expression: 'y'),
          isFalse);
    });

    test('flags default to false and are omitted from JSON', () {
      const ReportGroup g = ReportGroup(name: 'a', expression: 'x');
      expect(g.keepTogether, isFalse);
      expect(g.reprintHeaderOnEachPage, isFalse);
      expect(g.toJson().containsKey('keepTogether'), isFalse);
      expect(g.toJson().containsKey('reprintHeaderOnEachPage'), isFalse);
    });

    test('flags round-trip when true', () {
      const ReportGroup g = ReportGroup(
          name: 'a',
          expression: 'x',
          keepTogether: true,
          reprintHeaderOnEachPage: true);
      final ReportGroup decoded = ReportGroup.fromJson(g.toJson());
      expect(decoded.keepTogether, isTrue);
      expect(decoded.reprintHeaderOnEachPage, isTrue);
      expect(decoded, g);
    });

    test('absent flag keys decode to false (backward compatible)', () {
      final ReportGroup g = ReportGroup.fromJson(
          <String, Object?>{'name': 'a', 'expression': 'x'});
      expect(g.keepTogether, isFalse);
      expect(g.reprintHeaderOnEachPage, isFalse);
    });

    test('flags participate in equality', () {
      expect(
          const ReportGroup(name: 'a', expression: 'x', keepTogether: true) ==
              const ReportGroup(name: 'a', expression: 'x'),
          isFalse);
      expect(
          const ReportGroup(
                  name: 'a', expression: 'x', reprintHeaderOnEachPage: true) ==
              const ReportGroup(name: 'a', expression: 'x'),
          isFalse);
    });
  });
}
