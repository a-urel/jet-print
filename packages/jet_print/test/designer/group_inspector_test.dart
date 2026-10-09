// Spec 024 / C11, refined by the 2026-06-14 design note
// (group-flags-on-band-inspector): the group's key + its start-new-page flag
// are edited from the band the author sees — the group's HEADER band — not from
// an abstract group node. The footer band shows height only; a headerless group
// falls back to its footer so the section is never unreachable; selecting the
// group row shows a read-only summary with no flag switches.
//
// One flag, not all three: `keepTogether` and `reprintHeaderOnEachPage` are
// implemented and covered by `test/rendering/layout/report_layouter_test.dart`,
// but kept out of the UI (same design note), which is why the cases below assert
// only `startNewPage`.
// Consumer-style: public API + the shared widget harness only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

/// A master scope owning one group with both a header and a footer band, plus a
/// detail band — the common shape.
ReportDefinition _grouped() => const ReportDefinition(
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
            BandNode(Band(id: 'detail', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );

/// A group with ONLY a footer band (no header) — the reachability-fallback case.
ReportDefinition _footerOnly() => const ReportDefinition(
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
              footer: Band(id: 'gf', type: BandType.groupFooter, height: 24),
            ),
          ],
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );

Finder _field(String field) =>
    find.byKey(ValueKey<String>('jet_print.designer.properties.field.$field'));

GroupLevel _g1(JetReportDesignerController c) =>
    c.definition.body.root.groups.single;

void main() {
  testWidgets(
      'the group HEADER band carries the key + Start-on-new-page, plus height',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: _grouped());
    await pumpDesignerWith(tester, controller: controller);
    await openPropertiesTab(tester);

    controller.selectBand('gh');
    await tester.pumpAndSettle();

    expect(_field('bandHeight'), findsOneWidget,
        reason: 'the band keeps its own height field');
    expect(_field('groupKey'), findsOneWidget);
    expect(_field('groupNewPage'), findsOneWidget);
    // keepTogether + reprintHeader are implemented but hidden for now
    // (2026-06-14 design note) — only Start-on-new-page is surfaced.
    expect(_field('groupKeepTogether'), findsNothing);
    expect(_field('groupReprintHeader'), findsNothing);
  });

  testWidgets('toggling a flag on the group header band edits the GroupLevel',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: _grouped());
    await pumpDesignerWith(tester, controller: controller);
    await openPropertiesTab(tester);

    controller.selectBand('gh');
    await tester.pumpAndSettle();
    expect(_g1(controller).startNewPage, isFalse);

    await tester.tap(_field('groupNewPage'));
    await tester.pumpAndSettle();
    expect(_g1(controller).startNewPage, isTrue,
        reason: 'the switch writes through to the one GroupLevel');
    expect(controller.canUndo, isTrue);
  });

  testWidgets(
      'the group FOOTER band shows height only (no flags) when a header exists',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: _grouped());
    await pumpDesignerWith(tester, controller: controller);
    await openPropertiesTab(tester);

    controller.selectBand('gf');
    await tester.pumpAndSettle();

    expect(_field('bandHeight'), findsOneWidget);
    expect(_field('groupNewPage'), findsNothing,
        reason: 'the footer does not carry the flags when the group has a '
            'header');
    expect(_field('groupKey'), findsNothing);
  });

  testWidgets('a headerless group surfaces the section on its FOOTER band',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: _footerOnly());
    await pumpDesignerWith(tester, controller: controller);
    await openPropertiesTab(tester);

    controller.selectBand('gf');
    await tester.pumpAndSettle();

    expect(_field('groupNewPage'), findsOneWidget,
        reason: 'with no header, the footer carries the flags so they stay '
            'reachable');
    expect(_field('groupKey'), findsOneWidget);
  });

  testWidgets('selecting the group ROW shows a summary with no flag switches',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: _grouped());
    await pumpDesignerWith(tester, controller: controller);
    controller.selectGroup('g1');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    expect(_field('groupNewPage'), findsNothing);
    expect(_field('groupKeepTogether'), findsNothing);
    expect(_field('groupReprintHeader'), findsNothing);
    expect(_field('groupKey'), findsNothing,
        reason: 'flag/key editing moved to the group header band');
  });

  // Regression (#35): the group-row hint always named the HEADER band, even for
  // a footer-only group, whose settings live on its footer — sending the author
  // to a band that does not exist. The hint now names the actual carrier.
  group('the group-row hint names the band that carries the settings', () {
    const String headerHint =
        'Edit page & group settings on the group header band.';
    const String footerHint =
        'Edit page & group settings on the group footer band.';

    Future<void> selectGroupRow(
        WidgetTester tester, ReportDefinition def) async {
      final JetReportDesignerController controller =
          JetReportDesignerController(definition: def);
      await pumpDesignerWith(tester, controller: controller);
      await openPropertiesTab(tester);
      controller.selectGroup(controller.definition.body.root.groups.single.id);
      await tester.pumpAndSettle();
    }

    testWidgets('a group with a header points to the header',
        (WidgetTester tester) async {
      await selectGroupRow(tester, _grouped());
      expect(find.text(headerHint), findsOneWidget);
      expect(find.text(footerHint), findsNothing);
    });

    testWidgets('a footer-only group points to the footer',
        (WidgetTester tester) async {
      await selectGroupRow(tester, _footerOnly());
      expect(find.text(footerHint), findsOneWidget);
      expect(find.text(headerHint), findsNothing);
    });

    testWidgets('a group with neither band points nowhere',
        (WidgetTester tester) async {
      final ReportDefinition bare = _footerOnly().copyWith(
        body: _footerOnly().body.copyWith(
              root: _footerOnly().body.root.copyWith(groups: <GroupLevel>[
                _footerOnly()
                    .body
                    .root
                    .groups
                    .single
                    .copyWith(footer: () => null),
              ]),
            ),
      );
      await selectGroupRow(tester, bare);
      expect(find.text(headerHint), findsNothing);
      expect(find.text(footerHint), findsNothing);
    });
  });
}
