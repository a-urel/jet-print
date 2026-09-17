import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/controller/band_walker.dart';
import 'package:jet_print/src/designer/controller/commands/scope_commands.dart';
import 'package:jet_print/src/designer/controller/designer_document.dart';
import 'package:jet_print/src/designer/controller/selection.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/domain/scope_total.dart';
import 'package:jet_print/src/domain/watermark.dart';

TextElement _txt(String id) => TextElement(
    id: id, bounds: const JetRect(x: 0, y: 0, width: 10, height: 10), text: id);

Band _band(String id, BandType type,
        {List<ReportElement> els = const <ReportElement>[]}) =>
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
      for (final String id in <String>[
        'ph',
        'pf',
        'title',
        'gh',
        'gf',
        'm',
        'line'
      ]) {
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
      final ReportDefinition tall =
          mapBands(d, (Band b) => b.copyWith(height: 5));
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

  group('band_walker nested DetailScope.footer', () {
    // root → NestedScope(DetailScope(id:'lines', footer: lf w/ element 'ot')).
    ReportDefinition defWithFooter() => ReportDefinition(
          name: 'R',
          page: PageFormat.a4Portrait,
          body: ReportBody(
            root: DetailScope(
              id: 'root',
              children: <ScopeNode>[
                NestedScope(DetailScope(
                  id: 'lines',
                  collectionField: 'lines',
                  totals: const <ScopeTotal>[
                    ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
                  ],
                  footer: const Band(
                    id: 'lf',
                    type: BandType.groupFooter,
                    height: 12,
                    elements: <ReportElement>[
                      TextElement(
                        id: 'ot',
                        bounds: JetRect(x: 0, y: 0, width: 80, height: 12),
                        text: 'ot',
                        expression: r'$F{orderTotal}',
                      ),
                    ],
                  ),
                  children: <ScopeNode>[
                    BandNode(_band('lineRow', BandType.detail)),
                  ],
                )),
              ],
            ),
          ),
        );

    test('allBands includes the nested footer band', () {
      final Set<String> ids =
          allBands(defWithFooter()).map((Band b) => b.id).toSet();
      expect(ids, contains('lf'));
    });

    test('findBand reaches the nested footer band', () {
      expect(findBand(defWithFooter(), 'lf'), isNotNull);
    });

    test('findBandOfElement locates the nested footer element', () {
      expect(findBandOfElement(defWithFooter(), 'ot')?.id, 'lf');
    });

    test('allIds includes the nested footer band + element ids', () {
      final List<String> ids = allIds(defWithFooter()).toList();
      expect(ids, contains('lf'));
      expect(ids, contains('ot'));
    });

    test('scopePathToBand resolves the nested footer band', () {
      final List<DetailScope> path = scopePathToBand(defWithFooter(), 'lf');
      expect(path, isNotEmpty);
      expect(path.last.id, 'lines');
    });

    test('findScopeOfBand owns the nested footer band', () {
      expect(findScopeOfBand(defWithFooter(), 'lf')?.id, 'lines');
    });

    test('mapBands preserves the nested footer band and the scope totals', () {
      // Regression: rebuilding the scope field-by-field used to drop both the
      // nested footer and the published totals — so a
      // single element edit silently destroyed live totals.
      final ReportDefinition mapped =
          mapBands(defWithFooter(), (Band b) => b.copyWith(height: 99));
      // Footer survives AND is transformed.
      expect(findBand(mapped, 'lf')?.height, 99);
      // Totals survive untouched.
      expect(findScope(mapped, 'lines')?.totals.map((ScopeTotal t) => t.name),
          contains('orderTotal'));
    });

    test('updateBand on a sibling preserves the scope footer + totals', () {
      final ReportDefinition updated = updateBand(
          defWithFooter(), 'lineRow', (Band b) => b.copyWith(height: 7));
      expect(findBand(updated, 'lf'), isNotNull);
      expect(findScope(updated, 'lines')?.totals.length, 1);
    });

    test('mapGroups preserves the nested footer band + totals', () {
      final ReportDefinition mapped = mapGroups(
          defWithFooter(), (GroupLevel g) => g.copyWith(startNewPage: true));
      expect(findBand(mapped, 'lf'), isNotNull);
      expect(findScope(mapped, 'lines')?.totals.length, 1);
    });

    test('removeBandFromTree of an unrelated band keeps footer + totals', () {
      // Removing the per-row band must not destroy the scope's footer (spec
      // 029) or its published totals.
      final ReportDefinition removed =
          removeBandFromTree(defWithFooter(), 'lineRow');
      expect(findBand(removed, 'lineRow'), isNull);
      expect(findBand(removed, 'lf'), isNotNull);
      expect(findScope(removed, 'lines')?.totals.length, 1);
    });

    test('removeBandFromTree of the footer band nulls footer, keeps totals',
        () {
      // Deleting the nested footer band itself should clear the scope's footer
      // but leave the published totals intact.
      final ReportDefinition removed =
          removeBandFromTree(defWithFooter(), 'lf');
      expect(findBand(removed, 'lf'), isNull);
      expect(findScope(removed, 'lines')?.footer, isNull);
      expect(findScope(removed, 'lines')?.totals.length, 1);
    });

    test('reorderScopeNode preserves the footer + totals', () {
      // Add a second per-row band so there is something to reorder.
      final ReportDefinition base = defWithFooter();
      final DetailScope lines = findScope(base, 'lines')!;
      final ReportDefinition withTwo = mapScopes(
        base,
        (DetailScope s) => s.id == 'lines'
            ? s.copyWith(children: <ScopeNode>[
                ...lines.children,
                BandNode(_band('lineRow2', BandType.detail)),
              ])
            : s,
      );
      final ReportDefinition reordered =
          reorderScopeNode(withTwo, 'lines', 'lineRow2', -1);
      expect(findBand(reordered, 'lf'), isNotNull);
      expect(findScope(reordered, 'lines')?.footer?.id, 'lf');
      expect(findScope(reordered, 'lines')?.totals.length, 1);
    });
  });

  group('SetScopeCollectionCommand preserves footer + totals', () {
    DesignerDocument docWithFooter() => DesignerDocument(
          definition: ReportDefinition(
            name: 'R',
            page: PageFormat.a4Portrait,
            body: ReportBody(
              root: DetailScope(
                id: 'root',
                children: <ScopeNode>[
                  NestedScope(DetailScope(
                    id: 'lines',
                    collectionField: 'lines',
                    totals: const <ScopeTotal>[
                      ScopeTotal('orderTotal', r'SUM($F{lineTotal})'),
                    ],
                    // Every non-`collectionField` slot is populated, so a
                    // rebuilder that drops any one of them is visible.
                    groups: <GroupLevel>[
                      GroupLevel(
                        id: 'bySku',
                        name: 'SKU',
                        key: r'$F{sku}',
                        header: _band('gh', BandType.groupHeader),
                      ),
                    ],
                    footer: _band('lf', BandType.groupFooter),
                    children: <ScopeNode>[
                      BandNode(_band('lineRow', BandType.detail)),
                    ],
                  )),
                ],
              ),
            ),
          ),
          selection: Selection.empty,
        );

    test('rebinding the collection keeps footer + totals', () {
      final DesignerDocument after = const SetScopeCollectionCommand(
              scopeId: 'lines', collectionField: 'rows')
          .apply(docWithFooter());
      final DetailScope scope = findScope(after.definition, 'lines')!;
      expect(scope.collectionField, 'rows');
      expect(scope.footer?.id, 'lf');
      expect(scope.totals.length, 1);
    });

    test('clearing the collection (null) keeps footer + totals', () {
      final DesignerDocument after = const SetScopeCollectionCommand(
              scopeId: 'lines', collectionField: null)
          .apply(docWithFooter());
      final DetailScope scope = findScope(after.definition, 'lines')!;
      expect(scope.collectionField, isNull);
      expect(scope.footer?.id, 'lf');
      expect(scope.totals.length, 1);
    });

    test('rebinding changes collectionField and NOTHING else', () {
      // The command now rebinds through `copyWith`, so no field CAN be
      // dropped — this is what pins that, and what would catch a return to a
      // field-by-field rebuild (the trap AGENTS.md names). Comparing against
      // the source scope with only `collectionField` swapped checks every slot
      // at once, including any field added to `DetailScope` later.
      final DetailScope before =
          findScope(docWithFooter().definition, 'lines')!;
      final DesignerDocument doc = const SetScopeCollectionCommand(
              scopeId: 'lines', collectionField: 'rows')
          .apply(docWithFooter());
      final DetailScope after = findScope(doc.definition, 'lines')!;

      expect(after, before.copyWith(collectionField: () => 'rows'));
      // Spelled out too, so a failure says WHICH slot was dropped rather than
      // printing two whole scopes.
      expect(after.collectionField, 'rows');
      expect(after.id, before.id);
      expect(after.groups, before.groups);
      expect(after.children, before.children);
      expect(after.footer, before.footer);
      expect(after.totals, before.totals);
    });
  });

  group('field preservation through band transforms', () {
    test('mapBands keeps the page watermark', () {
      final ReportDefinition d = _def().copyWith(
        furniture: _def().furniture.copyWith(
              watermark: () => const Watermark(text: 'DRAFT'),
            ),
      );
      final ReportDefinition after = mapBands(d, (Band b) => b);
      expect(after.furniture.watermark, const Watermark(text: 'DRAFT'));
    });

    test('updateElement keeps the page watermark', () {
      final ReportDefinition d = _def().copyWith(
        furniture: _def().furniture.copyWith(
              watermark: () => const Watermark(text: 'DRAFT'),
            ),
      );
      final ReportDefinition after =
          updateElement(d, 'e2', (ReportElement e) => e.withName('renamed'));
      expect(after.furniture.watermark, const Watermark(text: 'DRAFT'),
          reason: 'an element edit must not clear page furniture fields');
      expect(findBandOfElement(after, 'e2'), isNotNull);
    });
  });

  group('crosstab nodes', () {
    const Crosstab ct = Crosstab(
      id: 'ct1',
      rowGroups: <CrosstabGroup>[
        CrosstabGroup(id: 'g/r', name: 'R', expression: r'$F{region}'),
      ],
      columnGroups: <CrosstabGroup>[
        CrosstabGroup(id: 'g/c', name: 'C', expression: r'$F{quarter}'),
      ],
      measures: <CrosstabMeasure>[
        CrosstabMeasure(
          id: 'm/a',
          name: 'A',
          expression: r'$F{amount}',
          aggregate: JetCalculation.sum,
        ),
      ],
    );
    final ReportDefinition def = ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 12)),
            CrosstabNode(ct),
          ],
        ),
      ),
    );

    test('allIds collects the crosstab id so minting cannot collide', () {
      expect(allIds(def), contains('ct1'));
    });

    test(
        'allIds also collects the crosstab\'s group and measure ids '
        '(seedFrom must not let designer authoring collide with them)', () {
      expect(allIds(def), containsAll(<String>['g/r', 'g/c', 'm/a']));
    });

    test('allBands ignores a crosstab (it owns no bands)', () {
      expect(allBands(def).map((Band b) => b.id), <String>['detail']);
    });

    test('findScope still walks past a crosstab sibling', () {
      expect(findScope(def, 'root')?.id, 'root');
    });

    // Pins the ruling in band_walker.dart's mapBands/mapGroups/mapScopes:
    // their `children`-rebuilding switches must pass a CrosstabNode/
    // UnknownScopeNode through unchanged (`=> n`), not `break` it out of the
    // list — a `break` there would silently delete the node from every
    // report on the next designer edit. If either arm were changed to
    // `break`, these two assertions on `whereType<CrosstabNode>().length`
    // would drop from 1 to 0.
    test('mapBands preserves a crosstab node alongside its BandNode sibling',
        () {
      final ReportDefinition after = mapBands(def, (Band b) => b);
      final DetailScope root = after.body.root;
      expect(root.children.whereType<CrosstabNode>().length, 1);
      expect(root.children.whereType<CrosstabNode>().single.crosstab, ct);
      expect(root.children.whereType<BandNode>().length, 1);
    });

    test('mapScopes preserves a crosstab node alongside its BandNode sibling',
        () {
      // addGroup is a real designer edit operation that routes through
      // mapScopes — reaching the switch under test via a public entry point
      // rather than calling mapScopes directly.
      final ReportDefinition after = addGroup(
        def,
        'root',
        const GroupLevel(id: 'g0', name: 'g', key: r'$F{x}'),
      );
      final DetailScope root = after.body.root;
      expect(root.children.whereType<CrosstabNode>().length, 1);
      expect(root.children.whereType<CrosstabNode>().single.crosstab, ct);
      expect(root.children.whereType<BandNode>().length, 1);
    });

    // A crosstab's position among its siblings is semantic (spec A decision
    // 7): above the first row-producing node it prints once BEFORE the row
    // loop, below it once after. Reorder therefore has to move a crosstab,
    // not only a band.
    test('reorderScopeNode moves a crosstab among its siblings', () {
      final ReportDefinition moved = reorderScopeNode(def, 'root', 'ct1', -1);
      final List<ScopeNode> children = moved.body.root.children;
      expect(children.first, isA<CrosstabNode>());
      expect(children.last, isA<BandNode>());
    });

    test('findCrosstab and findScopeOfCrosstab resolve it and its owner', () {
      expect(findCrosstab(def, 'ct1'), ct);
      expect(findScopeOfCrosstab(def, 'ct1')?.id, 'root');
      expect(findCrosstab(def, 'nope'), isNull);
      expect(findScopeOfCrosstab(def, 'nope'), isNull);
    });

    test('mapCrosstabs rewrites in place, leaving siblings untouched', () {
      final ReportDefinition after =
          mapCrosstabs(def, (Crosstab c) => c.copyWith(name: () => 'Pivot'));
      expect(findCrosstab(after, 'ct1')?.name, 'Pivot');
      expect(after.body.root.children.whereType<BandNode>().single.band.id,
          'detail');
    });

    test('removeCrosstab drops only that node', () {
      final ReportDefinition after = removeCrosstab(def, 'ct1');
      expect(findCrosstab(after, 'ct1'), isNull);
      expect(after.body.root.children, hasLength(1));
      expect(removeCrosstab(def, 'nope'), def);
    });

    test('reorderScopeNode still moves a band, and clamps to a no-op', () {
      expect(reorderScopeNode(def, 'root', 'detail', 1).body.root.children.last,
          isA<BandNode>());
      expect(reorderScopeNode(def, 'root', 'detail', -1), def,
          reason: 'a clamped move must leave the definition value-equal');
      expect(reorderScopeNode(def, 'root', 'nope', 1), def);
    });
  });

  group('unknown scope nodes', () {
    const Map<String, Object?> alienJson = <String, Object?>{
      'kind': 'sparkline',
      'payload': <String, Object?>{'id': 'x1'},
    };
    const UnknownScopeNode alien = UnknownScopeNode(rawJson: alienJson);
    final ReportDefinition def = ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 12)),
            alien,
          ],
        ),
      ),
    );

    // Same ruling as the crosstab-node pair above, pinned for the other
    // pass-through variant. If either arm were changed to `break`, these two
    // assertions on `whereType<UnknownScopeNode>().length` would drop from 1
    // to 0.
    test('mapBands preserves an unknown node alongside its BandNode sibling',
        () {
      final ReportDefinition after = mapBands(def, (Band b) => b);
      final DetailScope root = after.body.root;
      expect(root.children.whereType<UnknownScopeNode>().length, 1);
      expect(root.children.whereType<UnknownScopeNode>().single.rawJson,
          alienJson);
      expect(root.children.whereType<BandNode>().length, 1);
    });

    test('mapScopes preserves an unknown node alongside its BandNode sibling',
        () {
      final ReportDefinition after = addGroup(
        def,
        'root',
        const GroupLevel(id: 'g0', name: 'g', key: r'$F{x}'),
      );
      final DetailScope root = after.body.root;
      expect(root.children.whereType<UnknownScopeNode>().length, 1);
      expect(root.children.whereType<UnknownScopeNode>().single.rawJson,
          alienJson);
      expect(root.children.whereType<BandNode>().length, 1);
    });
  });
}
