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
  testWidgets('the scope add-band affordance appends a detail band (T035)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _seed());
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.addBand');
    expect(_detailIds(c), hasLength(3),
        reason: 'the scope "+" affordance adds a per-row band');
  });

  testWidgets('the group add-header affordance adds a group header (T035)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _seed());
    await pumpDesignerWith(tester, controller: c);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.group.g1.addHeader');
    expect(c.definition.body.root.groups.single.header?.type,
        BandType.groupHeader);
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
}
