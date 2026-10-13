// A report is written at the lowest schema version that holds it: 2 for a
// sheet report, so builds up to 1.0 keep opening it unchanged, and 3 only for
// a report on roll paper (PageFormat.continuous), so such a build refuses that
// report with a ReportFormatException instead of opening it as a sheet and
// dropping the roll on save.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _report(PageFormat page) => ReportDefinition(
      name: 'Fiş',
      page: page,
      body: const ReportBody(root: DetailScope(id: 'root')),
    );

final PageFormat _roll =
    PageFormat.a4Portrait.copyWith(width: 226.77, continuous: true);

void main() {
  test('this build reads and writes up to schema version 3', () {
    expect(JetReportFormat.schemaVersion, 3);
  });

  test('a sheet report is still written at version 2, byte-for-byte as before',
      () {
    final Map<String, Object?> json =
        JetReportFormat.encodeDefinition(_report(PageFormat.a4Portrait));
    expect(json['schemaVersion'], 2);
    expect((json['page']! as Map).containsKey('continuous'), isFalse);
  });

  test('a roll-paper report is written at version 3', () {
    final Map<String, Object?> json =
        JetReportFormat.encodeDefinition(_report(_roll));
    expect(json['schemaVersion'], 3);
    expect((json['page']! as Map)['continuous'], isTrue);
  });

  test('both versions decode, and a roll report round-trips', () {
    final ReportDefinition sheet = _report(PageFormat.a4Portrait);
    final ReportDefinition roll = _report(_roll);
    expect(
        JetReportFormat.decodeDefinition(
            JetReportFormat.encodeDefinition(sheet)),
        sheet);
    final Map<String, Object?> rollJson =
        JetReportFormat.encodeDefinition(roll);
    final ReportDefinition back = JetReportFormat.decodeDefinition(rollJson);
    expect(back, roll);
    expect(JetReportFormat.encodeDefinition(back), equals(rollJson));
  });

  test('a document newer than version 3 is still refused', () {
    final Map<String, Object?> json =
        JetReportFormat.encodeDefinition(_report(_roll));
    json['schemaVersion'] = 4;
    expect(() => JetReportFormat.decodeDefinition(json),
        throwsA(isA<ReportFormatException>()));
  });
}
