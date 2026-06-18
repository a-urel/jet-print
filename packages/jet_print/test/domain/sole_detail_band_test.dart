import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';

const Band _detail = Band(id: 'd', type: BandType.detail, height: 80);

ReportDefinition _def(ReportBody body) =>
    ReportDefinition(name: 'x', page: PageFormat.a4Portrait, body: body);

void main() {
  test('pure single-detail body exposes its sole detail band', () {
    final ReportDefinition def = _def(const ReportBody(
        root:
            DetailScope(id: 'root', children: <ScopeNode>[BandNode(_detail)])));
    expect(def.isPureSingleDetailBody, isTrue);
    expect(def.soleDetailBand, _detail);
  });

  test('a title once-band disqualifies the body', () {
    final ReportDefinition def = _def(const ReportBody(
        title: Band(id: 't', type: BandType.title, height: 10),
        root:
            DetailScope(id: 'root', children: <ScopeNode>[BandNode(_detail)])));
    expect(def.isPureSingleDetailBody, isFalse);
    expect(def.soleDetailBand, isNull);
  });

  test('groups, a footer, a nested scope, or multiple bands disqualify it', () {
    final ReportDefinition grouped = _def(const ReportBody(
        root: DetailScope(
            id: 'root',
            groups: <GroupLevel>[GroupLevel(id: 'g', name: 'g', key: r'$F{k}')],
            children: <ScopeNode>[BandNode(_detail)])));
    expect(grouped.soleDetailBand, isNull);

    final ReportDefinition nested = _def(const ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
      BandNode(_detail),
      NestedScope(DetailScope(id: 'n', collectionField: 'lines')),
    ])));
    expect(nested.soleDetailBand, isNull);
  });
}
