// Pure label-grid cue geometry (spec 035 / Task 4). Tests the data the canvas
// overlay draws — no widget pump. Uses src/ imports (internal canvas helper),
// like the other canvas-geometry tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/canvas/design_time_layout.dart';
import 'package:jet_print/src/designer/canvas/label_grid_geometry.dart';

import '../support/designer_harness.dart';

ReportDefinition _withLayout(ColumnLayout cl) => ReportDefinition(
      name: 'labels',
      page: const PageFormat(
        width: 600,
        height: 800,
        margins: JetEdgeInsets(left: 50, top: 50, right: 50, bottom: 50),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail', type: BandType.detail, height: 80, columnLayout: cl)),
          ],
        ),
      ),
    );

void main() {
  test('two columns that exactly fill the body: one ghost, no clipping', () {
    // content width = 600 - 50 - 50 = 500; two 250-wide columns, no spacing.
    final ReportDefinition def = _withLayout(const ColumnLayout(
        columnCount: 2, columnWidth: 250, columnSpacing: 0, rowSpacing: 0));
    final LabelGridCue? cue = labelGridCue(def, DesignTimeLayout.of(def));

    expect(cue, isNotNull);
    expect(cue!.cell.x, 50);
    expect(cue.cell.width, 250);
    expect(cue.ghosts.length, 1);
    expect(cue.ghosts.single.x, 300); // 50 + 250
    expect(cue.ghosts.single.width, 250);
  });

  test('a column count that overflows the body clips the last ghost', () {
    // content width 500; three 200-wide columns would span 600 > 500.
    final ReportDefinition def = _withLayout(const ColumnLayout(
        columnCount: 3, columnWidth: 200, columnSpacing: 0, rowSpacing: 0));
    final LabelGridCue? cue = labelGridCue(def, DesignTimeLayout.of(def));

    expect(cue, isNotNull);
    // Ghosts start at x=250 (w=200, fits to 450) and x=450 (clipped to 100).
    expect(cue!.ghosts.map((JetRect g) => g.x), <double>[250, 450]);
    expect(cue.ghosts.last.width, 100); // 500-content-right (550) - 450
  });

  test('null when the body is not a pure single-detail body', () {
    final ReportDefinition def = ReportDefinition(
      name: 'r',
      page: const PageFormat(
          width: 600,
          height: 800,
          margins: JetEdgeInsets(left: 50, top: 50, right: 50, bottom: 50)),
      body: ReportBody(
        title: const Band(id: 'title', type: BandType.title, height: 30),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(const Band(
                id: 'detail',
                type: BandType.detail,
                height: 80,
                columnLayout: ColumnLayout(
                    columnCount: 2, columnWidth: 250, columnSpacing: 0, rowSpacing: 0))),
          ],
        ),
      ),
    );
    expect(labelGridCue(def, DesignTimeLayout.of(def)), isNull);
  });

  test('null when the sole detail band has no column layout', () {
    final ReportDefinition def = ReportDefinition(
      name: 'r',
      page: const PageFormat(
          width: 600,
          height: 800,
          margins: JetEdgeInsets(left: 50, top: 50, right: 50, bottom: 50)),
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );
    expect(labelGridCue(def, DesignTimeLayout.of(def)), isNull);
  });

  testWidgets('the canvas renders with an active label band (no exception)',
      (WidgetTester tester) async {
    final ReportDefinition def = _withLayout(const ColumnLayout(
        columnCount: 2, columnWidth: 250, columnSpacing: 0, rowSpacing: 0));
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: def));
    c.selectBand('detail');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
