import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/controller/band_walker.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';

TextElement _txt(String id) => TextElement(
    id: id, bounds: const JetRect(x: 0, y: 0, width: 10, height: 10), text: id);

Band _band(String id, BandType type, {List<ReportElement> els = const <ReportElement>[]}) =>
    Band(id: id, type: type, height: 10, elements: els);

/// furniture(pageHeader,pageFooter) + title + a master group (header/footer) +
/// a nested `lines` scope with a per-row band.
ReportDefinition _def() => ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: _band('ph', BandType.pageHeader),
        pageFooter: _band('pf', BandType.pageFooter),
      ),
      body: ReportBody(
        title: _band('title', BandType.title),
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'root/g0',
              name: 'invoice',
              key: r'$F{inv}',
              header: _band('gh', BandType.groupHeader,
                  els: <ReportElement>[_txt('e1')]),
              footer: _band('gf', BandType.groupFooter),
            ),
          ],
          children: <ScopeNode>[
            BandNode(_band('m', BandType.detail)),
            NestedScope(DetailScope(
              id: 'lines',
              collectionField: 'lines',
              children: <ScopeNode>[
                BandNode(_band('line', BandType.detail,
                    els: <ReportElement>[_txt('e2')])),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  group('band_walker', () {
    test('findBand reaches every slot (furniture, body, group, scope)', () {
      final ReportDefinition d = _def();
      for (final String id in <String>['ph', 'pf', 'title', 'gh', 'gf', 'm', 'line']) {
        expect(findBand(d, id)?.id, id, reason: id);
      }
      expect(findBand(d, 'nope'), isNull);
    });

    test('allBands enumerates every band exactly once', () {
      final Set<String> ids = allBands(_def()).map((Band b) => b.id).toSet();
      expect(ids, <String>{'ph', 'pf', 'title', 'gh', 'gf', 'm', 'line'});
    });

    test('updateBand replaces only the matching band', () {
      final ReportDefinition d = _def();
      final ReportDefinition updated =
          updateBand(d, 'line', (Band b) => b.copyWith(height: 99));
      expect(findBand(updated, 'line')?.height, 99);
      // Everything else is untouched.
      expect(findBand(updated, 'gh'), equals(findBand(d, 'gh')));
      expect(updated.furniture, equals(d.furniture));
    });

    test('mapBands transforms every band', () {
      final ReportDefinition d = _def();
      final ReportDefinition tall = mapBands(d, (Band b) => b.copyWith(height: 5));
      expect(allBands(tall).every((Band b) => b.height == 5), isTrue);
    });

    test('findBandOfElement locates the owning band', () {
      final ReportDefinition d = _def();
      expect(findBandOfElement(d, 'e1')?.id, 'gh');
      expect(findBandOfElement(d, 'e2')?.id, 'line');
      expect(findBandOfElement(d, 'missing'), isNull);
    });

    test('findGroup / updateGroup address a GroupLevel by id', () {
      final ReportDefinition d = _def();
      expect(findGroup(d, 'root/g0')?.name, 'invoice');
      expect(findGroup(d, 'nope'), isNull);
      final ReportDefinition updated = updateGroup(
          d, 'root/g0', (GroupLevel g) => g.copyWith(startNewPage: true));
      expect(findGroup(updated, 'root/g0')?.startNewPage, isTrue);
      // The group's bands survive the update.
      expect(findBand(updated, 'gh')?.id, 'gh');
    });

    test('findScope addresses a DetailScope by id', () {
      final ReportDefinition d = _def();
      expect(findScope(d, 'root')?.collectionField, isNull);
      expect(findScope(d, 'lines')?.collectionField, 'lines');
      expect(findScope(d, 'nope'), isNull);
    });
  });
}
