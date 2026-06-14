// Phase 4 / T025 (spec 024 / C11): selecting a group shows a single Group
// inspector that owns the key + all three pagination flags — and that flag is
// NOT duplicated on the group's header and footer bands (the 023 two-bands
// smell). Consumer-style: public API + the shared widget harness only.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

/// A definition whose master scope owns one group with a header + footer band
/// plus a detail band — the shape that used to surface the page-break flag on
/// BOTH the header and footer band inspectors.
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

Finder _field(String field) =>
    find.byKey(ValueKey<String>('jet_print.designer.properties.field.$field'));

void main() {
  testWidgets(
      'selecting a group shows one Group inspector with key + all three flags',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: _grouped());
    await pumpDesignerWith(tester, controller: controller);
    controller.selectGroup('g1');
    await tester.pumpAndSettle();
    await openPropertiesTab(tester);

    expect(_field('groupKey'), findsOneWidget);
    expect(_field('groupKeepTogether'), findsOneWidget);
    expect(_field('groupReprintHeader'), findsOneWidget);
    expect(_field('groupNewPage'), findsOneWidget);
  });

  testWidgets(
      'the group page-break flag is not shown on the header or footer band',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        JetReportDesignerController(definition: _grouped());
    await pumpDesignerWith(tester, controller: controller);
    await openPropertiesTab(tester);

    // Header band selected → a plain band inspector (height only), no group flag.
    controller.selectBand('gh');
    await tester.pumpAndSettle();
    expect(_field('groupNewPage'), findsNothing,
        reason: 'a group header band must not carry the group flag');
    expect(_field('bandHeight'), findsOneWidget);

    // Footer band selected → still no group flag (the 023 duplication is gone).
    controller.selectBand('gf');
    await tester.pumpAndSettle();
    expect(_field('groupNewPage'), findsNothing,
        reason: 'a group footer band must not carry the group flag either');
  });
}
