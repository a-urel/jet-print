// ReportGroup value type + serialization (spec 005b). No Flutter UI.
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
  });
}
