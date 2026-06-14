// Phase 5 / T035 (spec 024 / US3): the Outline panel's band-lifecycle
// affordances — add a per-row band / a group header, remove, reorder (up/down),
// and retype — drive the controller's undoable lifecycle ops. Consumer-style:
// public API + the shared widget harness only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

ReportDefinition _seed() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: Band(id: 'ph', type: BandType.pageHeader, height: 24),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(id: 'g1', name: 'g', key: r'$F{k}'),
          ],
          children: <ScopeNode>[
            BandNode(Band(id: 'd1', type: BandType.detail, height: 80)),
            BandNode(Band(id: 'd2', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );

List<String> _detailIds(JetReportDesignerController c) => <String>[
      for (final ScopeNode n in c.definition.body.root.children)
        if (n is BandNode) n.band.id,
    ];

/// Opens the right panel's **Outline** tab in any locale.
Future<void> _openOutline(WidgetTester tester) async {
  final JetPrintLocalizations l10n = JetPrintLocalizations.of(
    tester.element(find.byType(JetReportDesigner)),
  );
  final Finder tab = find.text(l10n.tabOutline);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the scope add menu appends a detail band (T035)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _seed());
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    // The scope "+" is now a menu: open it, then pick "add detail band".
    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add.detail');
    expect(_detailIds(c), hasLength(3),
        reason: 'the scope "+" menu adds a per-row band');
  });

  testWidgets('the scope add menu adds a group header (T035)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _seed());
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    // Group-band adding moved from the (removed) group node to the scope menu.
    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _tapKey(
        tester, 'jet_print.designer.outline.scope.root.add.groupHeader.g1');
    expect(c.definition.body.root.groups.single.header?.type,
        BandType.groupHeader);
  });

  testWidgets('the outline shows group bands directly, with no group node',
      (WidgetTester tester) async {
    // A group with both bands plus a detail band: the group surfaces through its
    // header/footer bands (Jasper-style), not a separate selectable node.
    final JetReportDesignerController c = JetReportDesignerController(
      definition: const ReportDefinition(
        name: 'r',
        page: PageFormat.a4Portrait,
        body: ReportBody(
          root: DetailScope(
            id: 'root',
            groups: <GroupLevel>[
              GroupLevel(
                id: 'g1',
                name: 'category',
                key: r'$F{category}',
                header: Band(id: 'gh', type: BandType.groupHeader, height: 24),
                footer: Band(id: 'gf', type: BandType.groupFooter, height: 24),
              ),
            ],
            children: <ScopeNode>[
              BandNode(Band(id: 'd1', type: BandType.detail, height: 80)),
            ],
          ),
        ),
      ),
    );
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    expect(
        find.byKey(
            const ValueKey<String>('jet_print.designer.outline.group.g1')),
        findsNothing,
        reason: 'groups are no longer shown as a separate node');
    expect(
        find.byKey(
            const ValueKey<String>('jet_print.designer.outline.band.gh')),
        findsOneWidget,
        reason: 'the group header band sits directly under the scope');
    expect(
        find.byKey(
            const ValueKey<String>('jet_print.designer.outline.band.gf')),
        findsOneWidget);
  });

  testWidgets('the band remove affordance deletes the band (T035)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _seed());
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.band.d1.remove');
    expect(_detailIds(c), <String>['d2']);
  });

  testWidgets('the band move-up affordance reorders within the scope (T035)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _seed());
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.band.d2.up');
    expect(_detailIds(c), <String>['d2', 'd1'],
        reason: 'order changes, ids preserved');
  });

  testWidgets(
      'the band retype menu relocates the band to the chosen slot (T035)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _seed());
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    // Open the retype menu on d1, then choose the (empty) title slot.
    await _tapKey(tester, 'jet_print.designer.outline.band.d1.retype');
    await _tapKey(tester, 'jet_print.designer.outline.band.d1.retype.title');
    expect(c.definition.body.title?.id, 'd1',
        reason: 'd1 moved to the title slot, keeping its id');
    expect(c.definition.body.title?.type, BandType.title);
    expect(_detailIds(c), <String>['d2']);
  });

  testWidgets('the retype menu hides the reserved (not-laid-out) band types',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _seed());
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    // Open the retype menu on d1 (all singleton slots but pageHeader are free).
    await _tapKey(tester, 'jet_print.designer.outline.band.d1.retype');

    Finder option(String type) => find.byKey(
        ValueKey<String>('jet_print.designer.outline.band.d1.retype.$type'));

    // A real, laid-out target is still offered...
    expect(option('title'), findsOneWidget,
        reason: 'sanity: the menu is open and offers laid-out slots');
    // ...but the reserved types (columnHeader/columnFooter/background) are not.
    expect(option('columnHeader'), findsNothing);
    expect(option('columnFooter'), findsNothing);
    expect(option('background'), findsNothing);
  });
}
