// Touch authoring at phone width: the acceptance criteria in
// docs/touch-authoring.md, each driven end to end with a finger.
//
// Decision 0003 promises the designer on iOS and Android and requires select,
// move, resize and align to be verified at a phone-sized viewport with
// `PointerDeviceKind.touch`, asserting against the definition the controller
// produces. Every test here pumps the designer at 390 × 844 and drives it with
// touch pointers only (the flutter_test default kind); the criterion each one
// pins is named in its description as T1…T9, matching the page.
//
// VM-only: the long-press criteria depend on test-binding timers that headless
// Chrome does not advance in the same way (as in long_press_menu_test.dart).
@TestOn('vm')
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

/// A phone in portrait (an iPhone 14/15 class viewport, in logical pixels).
const Size _phone = Size(390, 844);

const Key _multiSelectKey =
    ValueKey<String>('jet_print.designer.canvas.multiSelect');
const Key _menuCutKey = ValueKey<String>('jet_print.designer.menu.cut');
const Key _menuPasteKey = ValueKey<String>('jet_print.designer.menu.paste');
const Key _alignLeftKey =
    ValueKey<String>('jet_print.designer.arrange.alignLeft');
const Key _bottomRightKey =
    ValueKey<String>('jet_print.designer.handle.bottomRight');
const Key _topLeftKey = ValueKey<String>('jet_print.designer.handle.topLeft');
const Key _bandHandleKey = ValueKey<String>('jet_print.designer.bandHandle');

Finder _element(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

/// Two text elements, far enough apart that a finger on one is not on the other
/// at phone zoom, and offset horizontally so align-left has work to do.
const List<ReportElement> _twoElements = <ReportElement>[
  TextElement(
    id: 'a',
    bounds: JetRect(x: 40, y: 40, width: 200, height: 60),
    text: 'A',
  ),
  TextElement(
    id: 'b',
    bounds: JetRect(x: 180, y: 220, width: 200, height: 60),
    text: 'B',
  ),
];

ReportDefinition _fixture({
  double bandHeight = 600,
  List<ReportElement> elements = _twoElements,
}) =>
    ReportDefinition(
      name: 'PhoneTouch',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(
              Band(
                id: 'detail',
                type: BandType.detail,
                height: bandHeight,
                elements: elements,
              ),
            ),
          ],
        ),
      ),
    );

Future<JetReportDesignerController> _pumpPhone(WidgetTester tester,
    [ReportDefinition? definition]) async {
  final JetReportDesignerController c = JetReportDesignerController()
    ..open(definition ?? _fixture());
  await pumpDesignerWith(tester, controller: c, size: _phone);
  return c;
}

Band _band(JetReportDesignerController c) =>
    (c.definition.body.root.children.single as BandNode).band;

JetRect _bounds(JetReportDesignerController c, String id) =>
    (c.definition.body.root.children.single as BandNode)
        .band
        .elements
        .firstWhere((ReportElement e) => e.id == id)
        .bounds;

/// Drags a finger from [from] by [by] in small steps, the way a real finger
/// arrives: the first step clears the touch slop, the rest follow it.
Future<void> _fingerDrag(WidgetTester tester, Offset from, Offset by) async {
  final TestGesture g =
      await tester.startGesture(from, kind: PointerDeviceKind.touch);
  const int steps = 8;
  for (int i = 1; i <= steps; i++) {
    await g.moveTo(from + by * (i / steps));
    await tester.pump();
  }
  await g.up();
  await tester.pumpAndSettle();
}

/// Taps with a finger, then lets the double-tap window lapse so the next tap
/// is a fresh one rather than the second half of a double-tap.
Future<void> _fingerTap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at, kind: PointerDeviceKind.touch);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('T1 select: a finger tap on an element selects it alone',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);

    await _fingerTap(tester, tester.getCenter(_element('a')));
    expect(c.selection.ids, <String>['a']);

    await _fingerTap(tester, tester.getCenter(_element('b')));
    expect(c.selection.ids, <String>['b'],
        reason: 'a plain tap replaces the selection, it does not extend it');
  });

  testWidgets('T1 select: a finger tap on empty band space selects the band',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));

    final Offset page = tester.getTopLeft(find.byKey(kDesignPageKey));
    final double s = c.viewScale;
    // Inside the detail band (page margin is 36pt by default), clear of both
    // elements.
    await _fingerTap(tester, page + Offset(500 * s, 150 * s));

    expect(c.selection.ids, isEmpty);
    expect(c.selection.bandId, 'detail');
  });

  testWidgets('T2 move: a finger drag on an element moves it, one undo step',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    final JetRect before = _bounds(c, 'a');
    final double s = c.viewScale;
    printOnFailure('phone fit-width scale: $s');

    // Unselected first: the drag selects and moves in one gesture. Distances
    // are screen pixels, well past the touch slop, and expected back in points.
    await _fingerDrag(
        tester, tester.getCenter(_element('a')), const Offset(40, 20));
    final JetRect moved = _bounds(c, 'a');
    expect(moved.x, closeTo(before.x + 40 / s, 1));
    expect(moved.y, closeTo(before.y + 20 / s, 1));
    expect(moved.width, before.width, reason: 'a move never resizes');
    expect(c.selection.ids, <String>['a']);

    // Selected now, with its touch-sized handles showing: a drag from the
    // middle of the element must still move it, not grab a handle.
    await _fingerDrag(
        tester, tester.getCenter(_element('a')), const Offset(-30, 20));
    final JetRect movedAgain = _bounds(c, 'a');
    expect(movedAgain.x, closeTo(moved.x - 30 / s, 1));
    expect(movedAgain.y, closeTo(moved.y + 20 / s, 1));
    expect(movedAgain.width, before.width,
        reason: 'the body of a selected element is a move target');

    c.undo();
    expect(_bounds(c, 'a'), moved, reason: 'each drag is one undo step');
  });

  testWidgets(
      'T2 move: a drag on a neighbour moves it, not the selected element',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));
    final JetRect a0 = _bounds(c, 'a');
    final JetRect b0 = _bounds(c, 'b');
    final double s = c.viewScale;

    // At this zoom b's centre lies inside a's bottom-right touch target, which
    // leans out of a. The body under the finger wins.
    await _fingerDrag(
        tester, tester.getCenter(_element('b')), const Offset(10, 40));

    expect(_bounds(c, 'a'), a0, reason: 'the selected element is untouched');
    expect(_bounds(c, 'b').y, closeTo(b0.y + 40 / s, 1));
    expect(c.selection.ids, <String>['b']);
  });

  testWidgets('T3 pan: a finger drag on empty canvas scrolls and edits nothing',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    c.setZoomPercent(100); // past fit-width, so the page overflows and scrolls
    await tester.pumpAndSettle();
    final ReportDefinition before = c.definition;
    final Offset pageBefore = tester.getTopLeft(find.byKey(kDesignPageKey));

    // From low on the visible canvas, well below both elements, towards the
    // top-left: the content follows the finger, so the page moves up.
    final Offset start =
        tester.getRect(find.byKey(kDesignCanvasKey)).bottomCenter -
            const Offset(0, 150);
    await _fingerDrag(tester, start, const Offset(-80, -120));

    final Offset pageAfter = tester.getTopLeft(find.byKey(kDesignPageKey));
    expect(pageAfter.dy, lessThan(pageBefore.dy),
        reason: 'the viewport scrolled with the finger');
    expect(c.definition, before, reason: 'panning never edits the report');
    expect(c.selection.ids, isEmpty,
        reason: 'a touch drag on empty canvas is not a marquee');
  });

  testWidgets('T4 resize: a finger drag on a handle resizes the element',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));
    final JetRect before = _bounds(c, 'a');
    final double s = c.viewScale;

    await _fingerDrag(tester, tester.getCenter(find.byKey(_bottomRightKey)),
        const Offset(60, 40));

    final JetRect after = _bounds(c, 'a');
    expect(after.x, before.x, reason: 'the opposite corner is the anchor');
    expect(after.y, before.y);
    expect(after.width, closeTo(before.width + 60 / s, 1));
    expect(after.height, closeTo(before.height + 40 / s, 1));
  });

  testWidgets('T5 handle target: a touch handle is at least 44 × 44',
      (WidgetTester tester) async {
    await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));

    final Size hit = tester.getSize(find.byKey(_bottomRightKey));
    expect(hit.width, greaterThanOrEqualTo(44));
    expect(hit.height, greaterThanOrEqualTo(44));
  });

  testWidgets(
      'T6 long press on an element selects it and opens its context menu',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);

    await tester.longPressAt(tester.getCenter(_element('b')),
        kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();

    expect(c.selection.ids, <String>['b']);
    expect(find.byKey(_menuCutKey), findsOneWidget);
  });

  testWidgets(
      'T6 long press on empty canvas opens the menu and keeps the selection',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));
    final ReportDefinition before = c.definition;

    final Offset page = tester.getTopLeft(find.byKey(kDesignPageKey));
    final double s = c.viewScale;
    await tester.longPressAt(page + Offset(500 * s, 150 * s),
        kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();

    expect(find.byKey(_menuPasteKey), findsOneWidget);
    expect(c.selection.ids, <String>['a'],
        reason: 'a long press is not a tap; it never reselects');
    expect(c.definition, before);
  });

  testWidgets('T7 the multi-select toggle appears only after a finger press',
      (WidgetTester tester) async {
    await _pumpPhone(tester);
    expect(find.byKey(_multiSelectKey), findsNothing,
        reason: 'nothing has touched the canvas yet');

    await tester.tapAt(tester.getCenter(_element('a')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byKey(_multiSelectKey), findsNothing,
        reason: 'a mouse has shift-click and marquee; it gets no toggle');

    await _fingerTap(tester, tester.getCenter(_element('a')));
    expect(find.byKey(_multiSelectKey), findsOneWidget);
    expect(tester.getSize(find.byKey(_multiSelectKey)).width,
        greaterThanOrEqualTo(44));

    await tester.tapAt(tester.getCenter(_element('b')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byKey(_multiSelectKey), findsNothing,
        reason: 'back on a mouse, the toggle goes away');
  });

  testWidgets(
      'T8 multi-select: with the toggle on, a tap adds or removes an element',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));
    await _fingerTap(tester, tester.getCenter(find.byKey(_multiSelectKey)));

    await _fingerTap(tester, tester.getCenter(_element('b')));
    expect(c.selection.ids.toSet(), <String>{'a', 'b'});

    final Offset page = tester.getTopLeft(find.byKey(kDesignPageKey));
    final double s = c.viewScale;
    await _fingerTap(tester, page + Offset(500 * s, 150 * s));
    expect(c.selection.ids.toSet(), <String>{'a', 'b'},
        reason: 'an empty tap in multi-select keeps the selection');

    await _fingerTap(tester, tester.getCenter(_element('a')));
    expect(c.selection.ids, <String>['b'], reason: 'a second tap removes it');

    // Off again: a tap goes back to replacing the selection.
    await _fingerTap(tester, tester.getCenter(find.byKey(_multiSelectKey)));
    await _fingerTap(tester, tester.getCenter(_element('a')));
    expect(c.selection.ids, <String>['a']);
  });

  testWidgets(
      'T8 multi-select: a finger drag on a selected element moves them all',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));
    await _fingerTap(tester, tester.getCenter(find.byKey(_multiSelectKey)));
    await _fingerTap(tester, tester.getCenter(_element('b')));
    final JetRect a0 = _bounds(c, 'a');
    final JetRect b0 = _bounds(c, 'b');
    final double s = c.viewScale;

    await _fingerDrag(
        tester, tester.getCenter(_element('a')), const Offset(10, 40));

    expect(c.selection.ids.toSet(), <String>{'a', 'b'},
        reason: 'pressing a selected element must not toggle it out');
    expect(_bounds(c, 'a').x, closeTo(a0.x + 10 / s, 1));
    expect(_bounds(c, 'b').x, closeTo(b0.x + 10 / s, 1));
    expect(_bounds(c, 'b').y, closeTo(b0.y + 40 / s, 1));
  });

  testWidgets(
      'T8 multi-select: dragging an unselected element joins it and moves all',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));
    await _fingerTap(tester, tester.getCenter(find.byKey(_multiSelectKey)));
    final JetRect a0 = _bounds(c, 'a');
    final JetRect b0 = _bounds(c, 'b');
    final double s = c.viewScale;

    await _fingerDrag(
        tester, tester.getCenter(_element('b')), const Offset(10, 40));

    expect(c.selection.ids.toSet(), <String>{'a', 'b'});
    expect(_bounds(c, 'a').y, closeTo(a0.y + 40 / s, 1));
    expect(_bounds(c, 'b').y, closeTo(b0.y + 40 / s, 1));
  });

  testWidgets(
      'T9 align: two elements selected by finger align left from Arrange',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));
    await _fingerTap(tester, tester.getCenter(find.byKey(_multiSelectKey)));
    await _fingerTap(tester, tester.getCenter(_element('b')));
    expect(c.selection.length, 2);

    // At phone width the top bar scrolls; bring Arrange into view first.
    await tester.ensureVisible(find.byKey(kArrangeButtonKey));
    await tester.pumpAndSettle();
    await _fingerTap(tester, tester.getCenter(find.byKey(kArrangeButtonKey)));
    await _fingerTap(tester, tester.getCenter(find.byKey(_alignLeftKey)));

    expect(_bounds(c, 'a').x, 40);
    expect(_bounds(c, 'b').x, 40, reason: 'aligned to the leftmost edge');
    expect(_bounds(c, 'b').y, 220, reason: 'align-left moves only x');
  });

  testWidgets(
      'T4 resize: a finger drag on the band handle resizes by the full distance',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await _pumpPhone(tester, _fixture(bandHeight: 300));
    final Offset page = tester.getTopLeft(find.byKey(kDesignPageKey));
    final double s = c.viewScale;
    // Clear of both elements and their 32pt hit slop at this zoom.
    await _fingerTap(tester, page + Offset(350 * s, 200 * s));
    expect(c.selection.bandId, 'detail');

    await _fingerDrag(tester, tester.getCenter(find.byKey(_bandHandleKey)),
        const Offset(0, 40));

    expect(_band(c).height, closeTo(300 + 40 / s, 1),
        reason: 'the slop a finger travels before the drag registers counts');
  });

  testWidgets(
      'T5 handle target: at the paper edge the target reaches past it, and '
      'grabs there', (WidgetTester tester) async {
    // Flush with the band's top-left, which sits one page margin (36pt, 9px at
    // this zoom) inside the paper: most of the corner's target lies off the
    // paper, and must still be hit there.
    final JetReportDesignerController c = await _pumpPhone(
        tester,
        _fixture(elements: const <ReportElement>[
          TextElement(
            id: 'a',
            bounds: JetRect(x: 0, y: 0, width: 200, height: 60),
            text: 'A',
          ),
        ]));
    await _fingerTap(tester, tester.getCenter(_element('a')));
    final Rect page = tester.getRect(find.byKey(kDesignPageKey));
    final Rect target = tester.getRect(find.byKey(_topLeftKey));
    expect(target.left, lessThan(page.left),
        reason: 'the target leans out of the element, past the paper');
    expect(target.width, greaterThanOrEqualTo(44));

    // Grab the target at its outer corner, away from the drawn square.
    final JetRect before = _bounds(c, 'a');
    final double s = c.viewScale;
    await _fingerDrag(
        tester, target.topLeft + const Offset(3, 3), const Offset(40, 40));
    final JetRect after = _bounds(c, 'a');
    expect(after.x, closeTo(before.x + 40 / s, 1));
    expect(after.x + after.width, closeTo(before.x + before.width, 0.01),
        reason: 'the far corner is the anchor');
  });

  testWidgets(
      'T6 long press in multi-select adds the pressed element before the menu',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));
    await _fingerTap(tester, tester.getCenter(find.byKey(_multiSelectKey)));

    await tester.longPressAt(tester.getCenter(_element('b')),
        kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();

    expect(find.byKey(_menuCutKey), findsOneWidget);
    expect(c.selection.ids.toSet(), <String>{'a', 'b'},
        reason: 'the menu must act on the element under the finger too');
  });

  testWidgets('T7 a mouse press on the toggle itself takes it away',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _pumpPhone(tester);
    await _fingerTap(tester, tester.getCenter(_element('a')));
    await _fingerTap(tester, tester.getCenter(find.byKey(_multiSelectKey)));

    await tester.tapAt(tester.getCenter(find.byKey(_multiSelectKey)),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byKey(_multiSelectKey), findsNothing);

    // And multi-select went with it: a mouse click replaces the selection.
    await tester.tapAt(tester.getCenter(_element('b')),
        kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(c.selection.ids, <String>['b']);
  });
}
