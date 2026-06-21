// Long-press is the touch right-click: it opens the canvas context menu on the
// pressed element (onTapDown already selects it on contact, so the menu acts
// on the element under the finger with no extra pre-select wiring).
//
// The test runs with the platform override set to macOS — on mobile (Android/
// iOS) the ShadContextMenuRegion already enables long-press by default; the
// implementation adds an explicit `longPressEnabled: true` so the feature also
// works on desktop (the primary target for the designer).
//
// VM-only: long-press simulation depends on test-binding timers that headless
// Chrome does not advance in the same way.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

const Key _cutKey = ValueKey<String>('jet_print.designer.menu.cut');
const Key _copyKey = ValueKey<String>('jet_print.designer.menu.copy');
const Key _pasteKey = ValueKey<String>('jet_print.designer.menu.paste');
const Key _duplicateKey = ValueKey<String>('jet_print.designer.menu.duplicate');
const Key _deleteKey = ValueKey<String>('jet_print.designer.menu.delete');

Finder _elementFinder(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

ReportDefinition _oneElementFixture() => const ReportDefinition(
      name: 'LongPressTest',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(
              Band(
                id: 'detail',
                type: BandType.detail,
                height: 300,
                elements: <ReportElement>[
                  TextElement(
                    id: 'e1',
                    bounds: JetRect(x: 20, y: 20, width: 80, height: 24),
                    text: 'Hello',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

Future<JetReportDesignerController> _pump(WidgetTester tester) async {
  final JetReportDesignerController c = JetReportDesignerController()
    ..open(_oneElementFixture());
  await pumpDesignerWith(tester, controller: c);
  return c;
}

void main() {
  testWidgets(
      'long-press on an element opens the context menu on macOS (touch right-click)',
      (WidgetTester tester) async {
    // Override the platform to macOS: on mobile ShadContextMenuRegion already
    // enables long-press by default; the explicit `longPressEnabled: true` is
    // what makes it work on desktop (the designer's primary target).
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _pump(tester);

      final Finder element = _elementFinder('e1');
      expect(element, findsOneWidget);

      // Guard: the menu must be closed before the gesture.
      expect(find.byKey(_cutKey), findsNothing,
          reason: 'menu must be closed initially');

      // Use longPressAt with the element's centre (mirrors how context_menu_test
      // uses tapAt + getCenter to drive secondary-tap; the semantics widget itself
      // is obscured by the canvas GestureDetector, but the coordinate still lands
      // on the canvas at the right position).
      await tester.longPressAt(tester.getCenter(element));
      await tester.pumpAndSettle();

      // The menu surfaces Cut/Copy/Paste/Duplicate/Delete items.
      expect(find.byKey(_cutKey), findsOneWidget);
      expect(find.byKey(_copyKey), findsOneWidget);
      expect(find.byKey(_pasteKey), findsOneWidget);
      expect(find.byKey(_duplicateKey), findsOneWidget);
      expect(find.byKey(_deleteKey), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'long-press on a resize handle resizes the element (not the menu)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pump(tester);
    c.select('e1');
    await tester.pumpAndSettle();

    JetRect boundsOfE1() {
      final Band detail =
          (c.definition.body.root.children.first as BandNode).band;
      return detail.elements
          .firstWhere((ReportElement e) => e.id == 'e1')
          .bounds;
    }

    final JetRect before = boundsOfE1();
    const Key bottomRight =
        ValueKey<String>('jet_print.designer.handle.bottomRight');
    expect(find.byKey(bottomRight), findsOneWidget,
        reason: 'the selected element shows resize handles');

    // Press-hold past the long-press timeout, then drag the corner outward. The
    // handle owns the long-press (it is the deepest detector), so the canvas
    // context-menu never opens — the press resizes instead. (Default gesture
    // kind is touch, which is the case the user hit.)
    final Offset handleCenter = tester.getCenter(find.byKey(bottomRight));
    final TestGesture g = await tester.startGesture(handleCenter);
    await tester.pump(const Duration(milliseconds: 600)); // → onLongPressStart
    await g.moveTo(handleCenter + const Offset(40, 30)); // → resize
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(find.byKey(_cutKey), findsNothing,
        reason: 'pressing a handle resizes — it must NOT open the menu');
    expect(boundsOfE1().width, greaterThan(before.width),
        reason: 'dragging the bottom-right handle enlarges the element');
  });
}
