import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;

const Band _detail = Band(id: 'd', type: BandType.detail, height: 10);

String _describe(ScopeNode node) => switch (node) {
      BandNode(band: final Band b) => 'band:${b.id}',
      NestedScope(scope: final DetailScope s) => 'scope:${s.id}',
    };

void main() {
  group('DetailScope', () {
    test('root has a null collectionField; defaults are empty', () {
      const DetailScope root = DetailScope(id: 'root');
      expect(root.id, 'root');
      expect(root.collectionField, isNull);
      expect(root.groups, isEmpty);
      expect(root.children, isEmpty);
    });

    test('a nested scope iterates a collection field', () {
      const DetailScope lines =
          DetailScope(id: 'lines', collectionField: 'lines');
      expect(lines.collectionField, 'lines');
    });

    test('children are ordered and heterogeneous (band, scope, band)', () {
      const DetailScope scope = DetailScope(
        id: 'root',
        children: <ScopeNode>[
          BandNode(Band(id: 'meta', type: BandType.detail, height: 8)),
          NestedScope(DetailScope(id: 'lines', collectionField: 'lines')),
          BandNode(Band(id: 'total', type: BandType.detail, height: 8)),
        ],
      );
      expect(scope.children.map(_describe).toList(),
          <String>['band:meta', 'scope:lines', 'band:total']);
    });

    test('ScopeNode pattern-matches exhaustively without a default', () {
      const ScopeNode band = BandNode(_detail);
      const ScopeNode nested = NestedScope(DetailScope(id: 's'));
      expect(_describe(band), 'band:d');
      expect(_describe(nested), 'scope:s');
    });

    test('is value-equal by content (deep over groups and children)', () {
      const DetailScope a = DetailScope(
        id: 'root',
        groups: <GroupLevel>[GroupLevel(id: 'g', name: 'n', key: '1')],
        children: <ScopeNode>[BandNode(_detail)],
      );
      const DetailScope b = DetailScope(
        id: 'root',
        groups: <GroupLevel>[GroupLevel(id: 'g', name: 'n', key: '1')],
        children: <ScopeNode>[BandNode(_detail)],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const DetailScope(id: 'root')));
    });

    test('copyWith replaces only named fields', () {
      const DetailScope scope = DetailScope(id: 'root');
      expect(scope.copyWith(collectionField: 'x').collectionField, 'x');
      expect(scope.copyWith(collectionField: 'x').id, 'root');
      expect(
          scope.copyWith(
              children: const <ScopeNode>[BandNode(_detail)]).children,
          hasLength(1));
    });

    test('BandNode / NestedScope are value-equal by content', () {
      expect(const BandNode(_detail), equals(const BandNode(_detail)));
      expect(const NestedScope(DetailScope(id: 's')),
          equals(const NestedScope(DetailScope(id: 's'))));
      expect(const BandNode(_detail),
          isNot(const NestedScope(DetailScope(id: 's'))));
    });
  });
}
