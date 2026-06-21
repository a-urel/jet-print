@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_variable.dart';
import 'package:jet_print/src/domain/serialization/report_format.dart';

import '../../support/workspace.dart';

ReportDefinition _fixture(String name) {
  final Directory root = findWorkspaceRoot();
  final File file =
      File('${root.path}/packages/jet_print/test/fixtures/v1/$name.json');
  return JetReportFormat.decodeDefinitionJson(file.readAsStringSync());
}

Band _bandOf(ScopeNode node) => switch (node) {
      BandNode(band: final Band b) => b,
      NestedScope() => throw StateError('expected a BandNode'),
    };

DetailScope _scopeOf(ScopeNode node) => switch (node) {
      NestedScope(scope: final DetailScope s) => s,
      BandNode() => throw StateError('expected a NestedScope'),
    };

void main() {
  group('v1 → v2 migration (lossless flat-bands → tree)', () {
    test('every fixture migrates and re-stamps schemaVersion 2', () {
      for (final String name in <String>[
        'default',
        'invoice',
        'multi_level_grouped',
        'deep_master_detail',
        'empty_data',
        'furniture_reserved',
      ]) {
        final ReportDefinition def = _fixture(name);
        expect(JetReportFormat.encodeDefinition(def)['schemaVersion'], 2,
            reason: name);
      }
    });

    test('default: page chrome → furniture; master detail → one BandNode', () {
      final ReportDefinition def = _fixture('default');
      expect(def.furniture.pageHeader?.type, BandType.pageHeader);
      expect(def.furniture.pageHeader?.id, 'furniture/pageHeader');
      expect(def.furniture.pageFooter?.type, BandType.pageFooter);
      expect(def.body.root.groups, isEmpty);
      expect(def.body.root.children, hasLength(1));
      expect(_bandOf(def.body.root.children.single).type, BandType.detail);
    });

    test('invoice: group folds its header/footer; detail → nested lines scope',
        () {
      final ReportDefinition def = _fixture('invoice');
      expect(def.body.root.groups, hasLength(1));
      final GroupLevel g = def.body.root.groups.single;
      expect(g.name, 'invoice');
      expect(g.id, 'root/g0');
      expect(g.key, r'$F{invoiceNo}');
      expect(g.keepTogether, isTrue);
      expect(g.startNewPage, isTrue);
      expect(g.header?.type, BandType.groupHeader);
      expect(g.footer?.type, BandType.groupFooter);
      expect(def.furniture.pageHeader, isNotNull);
      expect(def.furniture.pageFooter, isNotNull);

      // The detail band bound to `lines` becomes a nested scope.
      expect(def.body.root.children, hasLength(1));
      final DetailScope lines = _scopeOf(def.body.root.children.single);
      expect(lines.collectionField, 'lines');
      expect(_bandOf(lines.children.first).type, BandType.detail);

      // resetGroup name → group id (FR-003a).
      final ReportVariable v = def.variables.single;
      expect(v.resetGroup, 'root/g0');
    });

    test('multi_level_grouped: groups keep order; resetGroups rewritten to ids',
        () {
      final ReportDefinition def = _fixture('multi_level_grouped');
      expect(def.body.root.groups.map((GroupLevel g) => g.name).toList(),
          <String>['region', 'category']);
      expect(def.body.root.groups.map((GroupLevel g) => g.id).toList(),
          <String>['root/g0', 'root/g1']);
      expect(def.body.title?.type, BandType.title);
      expect(def.body.summary?.type, BandType.summary);
      final Map<String, String?> resets = <String, String?>{
        for (final ReportVariable v in def.variables) v.name: v.resetGroup,
      };
      expect(resets['regionTotal'], 'root/g0');
      expect(resets['categoryTotal'], 'root/g1');
    });

    test('deep_master_detail: children order preserved; deterministic ids', () {
      final ReportDefinition def = _fixture('deep_master_detail');
      // v1 band order was [master order band, lines detail band].
      expect(def.body.root.children, hasLength(2));
      expect(_bandOf(def.body.root.children[0]).id, 'root/c0');
      final DetailScope lines = _scopeOf(def.body.root.children[1]);
      expect(lines.id, 'root/c1');
      expect(lines.collectionField, 'lines');
      // The lines band's own elements + the nested `notes` band.
      expect(lines.children, hasLength(2));
      expect(_bandOf(lines.children[0]).id, 'root/c1/c0');
      final DetailScope notes = _scopeOf(lines.children[1]);
      expect(notes.id, 'root/c1/c1');
      expect(notes.collectionField, 'notes');
      expect(_bandOf(notes.children.single).id, 'root/c1/c1/c0');
    });

    test('empty_data: title + noData preserved', () {
      final ReportDefinition def = _fixture('empty_data');
      expect(def.body.title?.type, BandType.title);
      expect(def.body.noData?.type, BandType.noData);
      expect(def.body.root.children, hasLength(1));
    });

    test('furniture_reserved: reserved slots map to reserved furniture', () {
      final ReportDefinition def = _fixture('furniture_reserved');
      expect(def.furniture.background?.type, BandType.background);
      expect(def.furniture.columnHeader?.type, BandType.columnHeader);
      expect(def.furniture.columnFooter?.type, BandType.columnFooter);
      expect(def.furniture.pageHeader?.type, BandType.pageHeader);
      expect(def.furniture.pageFooter?.type, BandType.pageFooter);
      expect(def.body.title?.type, BandType.title);
      expect(def.body.summary?.type, BandType.summary);
    });
  });
}
