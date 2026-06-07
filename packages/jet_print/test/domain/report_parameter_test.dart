// ReportParameter value type + serialization (spec 005b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_parameter.dart';
import 'package:jet_print/src/domain/value_type.dart';

void main() {
  group('ReportParameter', () {
    test('round-trips a typed parameter with a default', () {
      const ReportParameter p = ReportParameter(
        name: 'minAmount',
        type: JetFieldType.double,
        defaultValue: 10.0,
      );
      expect(ReportParameter.fromJson(p.toJson()), p);
    });

    test('omits the default key when null', () {
      const ReportParameter p =
          ReportParameter(name: 'note', type: JetFieldType.string);
      expect(p.toJson().containsKey('default'), isFalse);
      expect(ReportParameter.fromJson(p.toJson()), p);
    });

    test('encodes a dateTime default as ISO 8601 and decodes it back', () {
      final ReportParameter p = ReportParameter(
        name: 'asOf',
        type: JetFieldType.dateTime,
        defaultValue: DateTime(2026, 6, 7),
      );
      expect(p.toJson()['default'], DateTime(2026, 6, 7).toIso8601String());
      expect(ReportParameter.fromJson(p.toJson()), p);
    });

    test('has value equality and a consistent hash code', () {
      expect(const ReportParameter(name: 'a', type: JetFieldType.integer),
          const ReportParameter(name: 'a', type: JetFieldType.integer));
      expect(
          const ReportParameter(name: 'a', type: JetFieldType.integer).hashCode,
          const ReportParameter(name: 'a', type: JetFieldType.integer)
              .hashCode);
      expect(
          const ReportParameter(name: 'a', type: JetFieldType.integer) ==
              const ReportParameter(name: 'b', type: JetFieldType.integer),
          isFalse);
    });
  });
}
