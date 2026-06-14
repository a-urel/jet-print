// Visible alignment grid — placement & visibility (spec 015, US1 / contract C2).
//
// Drives the public designer and locates the grid by its stable widget key (the
// painter itself is private — keys are the test seam, as for the rulers). Pins:
// the grid paints when `gridEnabled`, is absent when off, sits BACKMOST in the
// page stack (so it never obscures content), survives a ≥2-band layout, and is
// on by default with the top-bar grid button reflecting it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../support/designer_harness.dart';

/// The grid layer's stable key (must match `canvas/design_canvas.dart`).
const Key _kGrid = ValueKey<String>('jet_print.designer.grid');

/// The top-bar grid toggle's key (must match `designer_top_bar.dart`).
const Key _kGridToggle = ValueKey<String>('jet_print.designer.toggle.grid');

/// The page's top-level Stack — the grid must be its FIRST (backmost) child.
Stack _pageStack(WidgetTester tester) => tester.widget<Stack>(
      find
          .descendant(
            of: find.byKey(kDesignPageKey),
            matching: find.byType(Stack),
          )
          .first,
    );

ReportDefinition _twoBands() => const ReportDefinition(
      name: 'F',
      page: PageFormat.a4Portrait,
      // Heights deliberately NOT whole multiples of the 5 mm step, so a
      // per-band origin (lines restart at each band top) is the only way the
      // drawn lines can coincide with that band's snap targets.
      furniture: PageFurniture(
        pageFooter:
            Band(id: 'pageFooter', type: BandType.pageFooter, height: 73),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 137)),
          ],
        ),
      ),
    );

void main() {
  testWidgets('C2.1 paints the grid when gridEnabled is true (default)',
      (WidgetTester tester) async {
    await pumpDesignerWith(tester);
    expect(find.byKey(_kGrid), findsOneWidget);
  });

  testWidgets('C2.2 paints no grid when gridEnabled is false',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    c.setGridEnabled(false);
    await tester.pumpAndSettle();
    expect(find.byKey(_kGrid), findsNothing);
  });

  testWidgets('C2.3 the grid is the backmost child of the page stack',
      (WidgetTester tester) async {
    await pumpDesignerWith(tester);
    // First child paints first → it sits behind band chrome, elements, and the
    // selection overlay (FR-003): content pixels are never obscured.
    expect(_pageStack(tester).children.first.key, _kGrid);
  });

  testWidgets('C2.4 renders across a ≥2-band layout (per-band origin)',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _twoBands());
    await pumpDesignerWith(tester, controller: c);
    // The grid still paints; that each band restarts its lines at its own top
    // (coincident with that band's snap targets) is pinned at the unit level by
    // grid_geometry_test (offsets always start at 0 from the band origin).
    expect(find.byKey(_kGrid), findsOneWidget);
    expect(_pageStack(tester).children.first.key, _kGrid);
  });

  testWidgets('C2.5 grid is on by default and the toggle reflects it',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester);
    expect(c.gridEnabled, isTrue);
    expect(find.byKey(_kGrid), findsOneWidget);
    // Active toggles use the secondary (filled) variant; inactive use ghost.
    expect(tester.widget<ShadIconButton>(find.byKey(_kGridToggle)).variant,
        ShadButtonVariant.secondary);
  });
}
