// Cursor tracking + selection-extent highlight on the rulers (spec 014, C5 /
// FR-011, FR-012, US4). Drives the public designer; locates the hover marker and
// the highlight band by their stable keys within each ruler strip.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

const Key _kHorizontalRuler =
    ValueKey<String>('jet_print.designer.ruler.horizontal');
const Key _kVerticalRuler =
    ValueKey<String>('jet_print.designer.ruler.vertical');
const Key _kMarker = ValueKey<String>('jet_print.designer.ruler.marker');
const Key _kHighlight = ValueKey<String>('jet_print.designer.ruler.highlight');

Finder _in(Key ruler, Key part) =>
    find.descendant(of: find.byKey(ruler), matching: find.byKey(part));

Finder _element(String id) =>
    find.byKey(ValueKey<String>('jet_print.designer.element.$id'));

Future<TestGesture> _hoverAt(WidgetTester tester, Offset position) async {
  final TestGesture gesture =
      await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: position);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(position);
  await tester.pump();
  return gesture;
}

void main() {
  group('rulers — hover marker (C5.1, C5.2)', () {
    testWidgets('hovering places a marker at the pointer X (top) and Y (left)',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);
      final Offset target = tester.getCenter(find.byKey(kDesignPageKey));
      await _hoverAt(tester, target);

      expect(_in(_kHorizontalRuler, _kMarker), findsOneWidget);
      expect(_in(_kVerticalRuler, _kMarker), findsOneWidget);
      expect(tester.getRect(_in(_kHorizontalRuler, _kMarker)).center.dx,
          closeTo(target.dx, 1.5));
      expect(tester.getRect(_in(_kVerticalRuler, _kMarker)).center.dy,
          closeTo(target.dy, 1.5));
    });

    testWidgets('the marker tracks the pointer during a drag (button down)',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);
      final Rect page = tester.getRect(find.byKey(kDesignPageKey));
      final Offset start = page.center;
      final Offset end = start + const Offset(40, 30);

      // A button-down drag emits onPointerMove (not onPointerHover), so this
      // exercises the path that keeps the marker live while moving/resizing.
      final TestGesture g =
          await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      addTearDown(() => g.up());
      await g.moveTo(end);
      await tester.pump();

      expect(_in(_kHorizontalRuler, _kMarker), findsOneWidget);
      expect(_in(_kVerticalRuler, _kMarker), findsOneWidget);
      expect(tester.getRect(_in(_kHorizontalRuler, _kMarker)).center.dx,
          closeTo(end.dx, 1.5),
          reason: 'the top-ruler marker follows the pointer X during a drag');
      expect(tester.getRect(_in(_kVerticalRuler, _kMarker)).center.dy,
          closeTo(end.dy, 1.5),
          reason: 'the left-ruler marker follows the pointer Y during a drag');
    });

    testWidgets('the marker clears when the pointer leaves the canvas',
        (WidgetTester tester) async {
      await pumpDesignerWith(tester);
      final TestGesture gesture =
          await _hoverAt(tester, tester.getCenter(find.byKey(kDesignPageKey)));
      expect(_in(_kHorizontalRuler, _kMarker), findsOneWidget);

      await gesture.moveTo(tester.getCenter(find.byKey(kTopBarKey)));
      await tester.pump();

      expect(_in(_kHorizontalRuler, _kMarker), findsNothing);
      expect(_in(_kVerticalRuler, _kMarker), findsNothing);
    });
  });

  group('rulers — selection extent highlight (C5.3–6)', () {
    testWidgets('a single selection highlights its span on both rulers (C5.3)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.createElement(DesignerToolType.barcode,
          bandId: 'detail', at: const JetOffset(40, 30));
      await tester.pumpAndSettle();
      final String id = c.selection.singleOrNull!;
      final Rect el = tester.getRect(_element(id));

      expect(_in(_kHorizontalRuler, _kHighlight), findsOneWidget);
      expect(_in(_kVerticalRuler, _kHighlight), findsOneWidget);
      final Rect h = tester.getRect(_in(_kHorizontalRuler, _kHighlight));
      final Rect v = tester.getRect(_in(_kVerticalRuler, _kHighlight));
      expect(h.left, closeTo(el.left, 1.5));
      expect(h.right, closeTo(el.right, 1.5));
      expect(v.top, closeTo(el.top, 1.5));
      expect(v.bottom, closeTo(el.bottom, 1.5));
    });

    testWidgets('a multi-selection highlights one combined union span (C5.4)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.createElement(DesignerToolType.text,
          bandId: 'detail', at: const JetOffset(20, 20));
      final String a = c.selection.singleOrNull!;
      c.createElement(DesignerToolType.text,
          bandId: 'detail', at: const JetOffset(180, 90));
      final String b = c.selection.singleOrNull!;
      c.selectElements(<String>[a, b]);
      await tester.pumpAndSettle();

      // One combined highlight per ruler, spanning the outer edges of both.
      expect(_in(_kHorizontalRuler, _kHighlight), findsOneWidget);
      final Rect ra = tester.getRect(_element(a));
      final Rect rb = tester.getRect(_element(b));
      final Rect h = tester.getRect(_in(_kHorizontalRuler, _kHighlight));
      expect(h.left, closeTo(ra.left, 1.5)); // a is left-most
      expect(h.right, closeTo(rb.right, 1.5)); // b is right-most
    });

    testWidgets('moving the selection updates the highlight span (C5.5)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.createElement(DesignerToolType.shape,
          bandId: 'detail', at: const JetOffset(30, 30));
      await tester.pumpAndSettle();
      final double before =
          tester.getRect(_in(_kHorizontalRuler, _kHighlight)).left;

      c.moveBy(const JetOffset(60, 0));
      await tester.pumpAndSettle();

      expect(tester.getRect(_in(_kHorizontalRuler, _kHighlight)).left,
          greaterThan(before),
          reason: 'the highlight tracks the moved selection');
    });

    testWidgets('a LIVE move updates the highlight in realtime, before commit',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.createElement(DesignerToolType.shape,
          bandId: 'detail', at: const JetOffset(30, 30));
      await tester.pumpAndSettle();
      final double before =
          tester.getRect(_in(_kHorizontalRuler, _kHighlight)).left;

      // Drag in progress — no commitMove() yet.
      c.beginMove();
      c.updateMove(const JetOffset(60, 0));
      await tester.pump();

      expect(tester.getRect(_in(_kHorizontalRuler, _kHighlight)).left,
          greaterThan(before),
          reason:
              'the highlight follows the drag, not just the committed move');
    });

    testWidgets('a LIVE resize grows the highlight in realtime, before commit',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.createElement(DesignerToolType.shape,
          bandId: 'detail', at: const JetOffset(30, 30));
      await tester.pumpAndSettle();
      final String id = c.selection.singleOrNull!;
      final double widthBefore =
          tester.getRect(_in(_kHorizontalRuler, _kHighlight)).width;

      // Resize drag in progress — no commitResize() yet.
      c.beginResize(id, ResizeHandle.bottomRight);
      c.updateResize(const JetOffset(50, 0));
      await tester.pump();

      expect(tester.getRect(_in(_kHorizontalRuler, _kHighlight)).width,
          greaterThan(widthBefore),
          reason:
              'the highlight grows with a live resize, not just on mouse-up');
    });

    testWidgets('a live band resize grows the band highlight on the left ruler',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.selectBand('pageHeader');
      await tester.pumpAndSettle();
      final double before =
          tester.getRect(_in(_kVerticalRuler, _kHighlight)).height;

      // Band-resize drag in progress — no commitBandResize() yet.
      c.beginBandResize('pageHeader');
      c.updateBandResize(50);
      await tester.pump();

      expect(tester.getRect(_in(_kVerticalRuler, _kHighlight)).height,
          greaterThan(before),
          reason: 'the band span reflows live, before mouse-up');
    });

    testWidgets('clearing the selection removes the highlight (C5.6)',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.createElement(DesignerToolType.image,
          bandId: 'detail', at: const JetOffset(30, 30));
      await tester.pumpAndSettle();
      expect(_in(_kHorizontalRuler, _kHighlight), findsOneWidget);

      c.clearSelection();
      await tester.pumpAndSettle();

      expect(_in(_kHorizontalRuler, _kHighlight), findsNothing);
      expect(_in(_kVerticalRuler, _kHighlight), findsNothing);
    });
  });

  group('rulers — highlight clamp (C5.7)', () {
    testWidgets('a selection extending past the strip is clamped to it',
        (WidgetTester tester) async {
      final JetReportDesignerController c = await pumpDesignerWith(tester);
      c.createElement(DesignerToolType.barcode,
          bandId: 'detail', at: const JetOffset(40, 30));
      await tester.pumpAndSettle();
      // Zoom in hard so the element's extent overruns the visible strip.
      for (int i = 0; i < 6; i++) {
        c.zoomIn();
      }
      await tester.pumpAndSettle();

      final Rect ruler = tester.getRect(find.byKey(_kHorizontalRuler));
      final Rect h = tester.getRect(_in(_kHorizontalRuler, _kHighlight));
      expect(h.left, greaterThanOrEqualTo(ruler.left - 0.5));
      expect(h.right, lessThanOrEqualTo(ruler.right + 0.5),
          reason: 'the highlight never draws past the strip edge');
    });
  });
}
