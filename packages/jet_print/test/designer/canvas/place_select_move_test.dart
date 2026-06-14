// US1 interaction widget tests (T036 / contracts §7.6 / acceptance US1.1–US1.5):
// drop-create, click-select + 8 handles, empty-click clear, and drag-move.
//
// Drives the public designer through a supplied controller; finds elements and
// handles by their stable widget keys (the canvas gesture detector owns
// hit-testing, so the per-element regions are non-capturing test hooks).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _toolFinder(DesignerToolType type) =>
    find.byKey(ValueKey<String>('jet_print.designer.tool.${type.name}'));

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

Finder _handleFinder = find.byWidgetPredicate((Widget w) =>
    w.key is ValueKey<String> &&
    (w.key! as ValueKey<String>)
        .value
        .startsWith('jet_print.designer.handle.'));

int _elementCount(JetReportDesignerController c) => _allElements(c).length;

// Every element across the (reified) definition's per-row bands.
Iterable<ReportElement> _allElements(JetReportDesignerController c) =>
    c.definition.body.root.children
        .whereType<BandNode>()
        .expand((BandNode n) => n.band.elements);

void main() {
  testWidgets('clicking a toolbox entry places a selected element of its type',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    expect(_elementCount(controller), 0);

    await tester.tap(_toolFinder(DesignerToolType.text));
    await tester.pumpAndSettle();

    expect(_elementCount(controller), 1);
    final String? id = controller.selection.singleOrNull;
    expect(id, isNotNull);
    // The created element is a text element in a detail band.
    final ReportElement created =
        _allElements(controller).firstWhere((ReportElement e) => e.id == id);
    expect(created, isA<TextElement>());
  });

  testWidgets('each toolbox type is creatable', (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    for (final DesignerToolType type in DesignerToolType.values) {
      await tester.tap(_toolFinder(type));
      await tester.pumpAndSettle();
    }
    expect(_elementCount(controller), DesignerToolType.values.length);
  });

  testWidgets('dragging a toolbox entry onto the canvas creates an element',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);

    final Offset toolCenter =
        tester.getCenter(_toolFinder(DesignerToolType.barcode));
    final Offset canvasCenter = tester.getCenter(find.byKey(kDesignCanvasKey));
    final TestGesture gesture = await tester.startGesture(toolCenter);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveTo(canvasCenter);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_elementCount(controller), 1);
    expect(
      _allElements(controller).single,
      isA<BarcodeElement>(),
    );
  });

  testWidgets('selection shows 8 handles; empty-click clears it',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await tester.tap(_toolFinder(DesignerToolType.shape));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;

    // Created element is auto-selected → 8 resize handles render.
    expect(_handleFinder, findsNWidgets(8));

    // Empty-click in the muted margin just left of the page clears. Anchored to
    // the page edge so it stays in the margin regardless of the ruler inset.
    final Offset pageTopLeft = tester.getTopLeft(find.byKey(kDesignPageKey));
    await tester.tapAt(Offset(pageTopLeft.dx - 8, pageTopLeft.dy + 120));
    await tester.pumpAndSettle();
    expect(controller.selection.isEmpty, isTrue);
    expect(_handleFinder, findsNothing);

    // Clicking the element re-selects it (handles return).
    await tester.tapAt(tester.getCenter(_elementFinder(id)));
    await tester.pumpAndSettle();
    expect(controller.selection.singleOrNull, id);
    expect(_handleFinder, findsNWidgets(8));
  });

  testWidgets('dragging a selected element moves and commits its position',
      (WidgetTester tester) async {
    final JetReportDesignerController controller =
        await pumpDesignerWith(tester);
    await tester.tap(_toolFinder(DesignerToolType.text));
    await tester.pumpAndSettle();
    final String id = controller.selection.singleOrNull!;

    final JetRect before = _allElements(controller)
        .firstWhere((ReportElement e) => e.id == id)
        .bounds;

    // The element region is a non-capturing test hook; the canvas gesture
    // detector owns the drag, so the hit-on-widget warning is expected.
    await tester.drag(_elementFinder(id), const Offset(40, 24),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    final JetRect after = _allElements(controller)
        .firstWhere((ReportElement e) => e.id == id)
        .bounds;

    expect(after.x, greaterThan(before.x), reason: 'moved right');
    expect(after.y, greaterThan(before.y), reason: 'moved down');
    // The move is a single undoable step that restores the original position.
    controller.undo();
    final JetRect undone = _allElements(controller)
        .firstWhere((ReportElement e) => e.id == id)
        .bounds;
    expect(undone.x, before.x);
    expect(undone.y, before.y);
  });
}
