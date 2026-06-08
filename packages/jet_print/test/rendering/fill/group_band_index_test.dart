// GroupBandIndex: validate + index group bands (007c).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_group.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/rendering/fill/group_band_index.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';

ReportTemplate tpl({
  List<ReportGroup> groups = const <ReportGroup>[],
  List<ReportBand> bands = const <ReportBand>[],
}) =>
    ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: groups,
      bands: bands,
    );

ReportGroup g(String name) => ReportGroup(name: name, expression: r'$F{x}');
ReportBand gh(String group) =>
    ReportBand(type: BandType.groupHeader, height: 10, group: group);
ReportBand gf(String group) =>
    ReportBand(type: BandType.groupFooter, height: 10, group: group);

void main() {
  test('indexes header/footer bands by group name', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final GroupBandIndex idx = GroupBandIndex(
      tpl(groups: <ReportGroup>[g('region')],
          bands: <ReportBand>[gh('region'), gf('region')]),
      d,
    );
    expect(idx.headersFor('region').length, 1);
    expect(idx.footersFor('region').length, 1);
    expect(d.entries, isEmpty);
  });

  test('preserves authored order for multiple bands of one group', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final ReportBand h1 = gh('region');
    final ReportBand h2 = gh('region');
    final GroupBandIndex idx = GroupBandIndex(
      tpl(groups: <ReportGroup>[g('region')], bands: <ReportBand>[h1, h2]),
      d,
    );
    expect(idx.headersFor('region'), <ReportBand>[h1, h2]);
  });

  test('a group band with a null group records an error and is excluded', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final GroupBandIndex idx = GroupBandIndex(
      tpl(groups: <ReportGroup>[g('region')], bands: const <ReportBand>[
        ReportBand(type: BandType.groupHeader, height: 10),
      ]),
      d,
    );
    expect(idx.headersFor('region'), isEmpty);
    expect(d.entries.single.severity, DiagnosticSeverity.error);
  });

  test('an unknown group name records an error and is excluded', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final GroupBandIndex idx = GroupBandIndex(
      tpl(groups: <ReportGroup>[g('region')], bands: <ReportBand>[gh('regn')]),
      d,
    );
    expect(idx.headersFor('regn'), isEmpty);
    expect(idx.headersFor('region'), isEmpty);
    expect(d.entries.single.message, contains('unknown group "regn"'));
  });

  test('duplicate group names throw ReportFormatException (fail-fast)', () {
    final ReportDiagnostics d = ReportDiagnostics();
    expect(
      () => GroupBandIndex(
        tpl(groups: <ReportGroup>[g('region'), g('region')]),
        d,
      ),
      throwsA(isA<ReportFormatException>()),
    );
  });

  test('returned band lists are unmodifiable (frozen snapshot)', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final GroupBandIndex idx = GroupBandIndex(
      tpl(groups: <ReportGroup>[g('region')], bands: <ReportBand>[gh('region')]),
      d,
    );
    expect(() => idx.headersFor('region').add(gh('region')),
        throwsUnsupportedError);
  });

  test('a group on a non-group band is ignored (not indexed, no diagnostic)', () {
    final ReportDiagnostics d = ReportDiagnostics();
    final GroupBandIndex idx = GroupBandIndex(
      tpl(groups: <ReportGroup>[g('region')], bands: const <ReportBand>[
        ReportBand(type: BandType.detail, height: 10, group: 'region'),
      ]),
      d,
    );
    expect(idx.headersFor('region'), isEmpty);
    expect(idx.footersFor('region'), isEmpty);
    expect(d.entries, isEmpty);
  });
}
