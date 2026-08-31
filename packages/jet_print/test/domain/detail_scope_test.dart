import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/scope_total.dart';

const Band _detail = Band(id: 'd', type: BandType.detail, height: 10);

String _describe(ScopeNode node) => switch (node) {
      BandNode(band: final Band b) => 'band:${b.id}',
      NestedScope(scope: final DetailScope s) => 'scope:${s.id}',
      CrosstabNode(crosstab: final Crosstab ct) => 'crosstab:${ct.id}',
      UnknownScopeNode(:final String? kind) => 'unknown:${kind ?? '?'}',
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
      expect(scope.copyWith(collectionField: () => 'x').collectionField, 'x');
      expect(scope.copyWith(collectionField: () => 'x').id, 'root');
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

    test(
        'a scope with a footer differs from one without and copyWith '
        'preserves it', () {
      const Band footer = Band(id: 'f', type: BandType.groupFooter, height: 12);
      const DetailScope a =
          DetailScope(id: 's', collectionField: 'lines', footer: footer);
      const DetailScope b = DetailScope(id: 's', collectionField: 'lines');
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
      expect(a.copyWith(id: 's2').footer, footer);
      expect(a.footer, footer);
      expect(b.footer, isNull);
    });

    test(
        'a scope with totals differs from one without; copyWith preserves '
        'them and copyWith(totals:) replaces', () {
      const ScopeTotal t = ScopeTotal('orderTotal', r'SUM($F{lineTotal})');
      const DetailScope a = DetailScope(
          id: 's', collectionField: 'lines', totals: <ScopeTotal>[t]);
      const DetailScope b = DetailScope(id: 's', collectionField: 'lines');
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
      expect(b.totals, isEmpty);
      // copyWith with an unrelated field preserves the existing totals.
      expect(a.copyWith(id: 's2').totals, <ScopeTotal>[t]);
      // copyWith(totals:) replaces them.
      const ScopeTotal u = ScopeTotal('x', r'SUM($F{y})');
      expect(a.copyWith(totals: const <ScopeTotal>[u]).totals, <ScopeTotal>[u]);
    });
  });

  group('UnknownScopeNode equality', () {
    // A fresh map literal each call, so two "separately decoded" nodes never
    // share object identity — this is what two independent decodes of the
    // same JSON document actually produce.
    Map<String, Object?> alienJson() => <String, Object?>{
          'kind': 'sparkline',
          'payload': <String, Object?>{
            'id': 'x1',
            // A list of objects nested inside the object payload: exercises
            // Map-inside-List-inside-Map, not just one level of nesting.
            'tags': <Object?>[
              <String, Object?>{'k': 'v'},
            ],
          },
        };

    test(
        'two nodes decoded from identical JSON with a nested object payload '
        'are value-equal', () {
      final UnknownScopeNode a = UnknownScopeNode(rawJson: alienJson());
      final UnknownScopeNode b = UnknownScopeNode(rawJson: alienJson());
      expect(identical(a.rawJson, b.rawJson), isFalse,
          reason: 'the two nodes must not share the same map instance');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('a node with a differing nested payload value is unequal', () {
      final UnknownScopeNode a = UnknownScopeNode(rawJson: alienJson());
      final Map<String, Object?> differentJson = alienJson();
      (differentJson['payload']! as Map<String, Object?>)['id'] = 'x2';
      final UnknownScopeNode b = UnknownScopeNode(rawJson: differentJson);
      expect(a, isNot(equals(b)));
    });
  });
}
