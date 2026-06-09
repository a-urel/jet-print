// Each resize handle must show the directional mouse cursor that matches the
// edge(s) it drags, so hovering the selection chrome communicates what a drag
// will do (FR-009 affordance). Drives the public designer only; locates handles
// by their stable `jet_print.designer.handle.<pos>` keys.
//
// The cursor is platform-dependent for the four CORNERS: Windows/Linux/web have
// the diagonal `resizeUpLeftDownRight` / `resizeUpRightDownLeft` system cursors,
// but macOS's public NSCursor set has no diagonal — so on macOS the library uses
// its own cursor that drives the (private) macOS window-resize NSCursor. These
// tests pin both branches via `debugDefaultTargetPlatformOverride` (reset in a
// `finally`, since the binding's end-of-test invariant check runs before any
// `addTearDown`).
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import '../support/designer_harness.dart';

Finder _handle(ResizeHandle position) =>
    find.byKey(ValueKey<String>('jet_print.designer.handle.${position.name}'));

MouseCursor _activeCursor() =>
    RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

// The straight-axis cursor each edge handle must expose (same on every platform).
const Map<ResizeHandle, SystemMouseCursor> _edgeCursor =
    <ResizeHandle, SystemMouseCursor>{
  ResizeHandle.top: SystemMouseCursors.resizeUpDown,
  ResizeHandle.bottom: SystemMouseCursors.resizeUpDown,
  ResizeHandle.left: SystemMouseCursors.resizeLeftRight,
  ResizeHandle.right: SystemMouseCursors.resizeLeftRight,
};

// The diagonal system cursor each corner exposes on non-macOS platforms.
const Map<ResizeHandle, SystemMouseCursor> _cornerSystemCursor =
    <ResizeHandle, SystemMouseCursor>{
  ResizeHandle.topLeft: SystemMouseCursors.resizeUpLeftDownRight,
  ResizeHandle.bottomRight: SystemMouseCursors.resizeUpLeftDownRight,
  ResizeHandle.topRight: SystemMouseCursors.resizeUpRightDownLeft,
  ResizeHandle.bottomLeft: SystemMouseCursors.resizeUpRightDownLeft,
};

Future<TestGesture> _mouse(WidgetTester tester) async {
  final TestGesture gesture =
      await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  return gesture;
}

void main() {
  testWidgets('on non-macOS, each handle exposes the matching system cursor',
      (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final JetReportDesignerController controller =
          await pumpDesignerWith(tester);
      controller.createElement(DesignerToolType.shape,
          bandIndex: 1, at: const JetOffset(40, 40));
      await tester.pumpAndSettle();
      expect(controller.selection.singleOrNull, isNotNull,
          reason: 'a freshly created element is selected, so handles are shown');

      final TestGesture gesture = await _mouse(tester);
      final Map<ResizeHandle, SystemMouseCursor> expected =
          <ResizeHandle, SystemMouseCursor>{
        ..._edgeCursor,
        ..._cornerSystemCursor,
      };
      for (final MapEntry<ResizeHandle, SystemMouseCursor> entry
          in expected.entries) {
        await gesture.moveTo(tester.getCenter(_handle(entry.key)));
        await tester.pump();
        expect(_activeCursor(), entry.value,
            reason: 'the ${entry.key.name} handle must show ${entry.value}');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('corner cursors win over overlapping edge handles when zoomed out',
      (WidgetTester tester) async {
    // Zoomed out, the fixed-size (16px) handle hit areas overlap: each edge
    // handle reaches over its adjacent corners. The corner cursor must still win
    // at the corner — otherwise the corner shows a straight ↕/↔ cursor. Platform
    // is irrelevant to z-order; pin it so the expected cursor is deterministic.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final JetReportDesignerController controller =
          await pumpDesignerWith(tester);
      controller.createElement(DesignerToolType.shape,
          bandIndex: 1, at: const JetOffset(40, 40));
      await tester.pumpAndSettle();
      controller.setViewScale(0.25); // element ~24×12px → handles overlap
      await tester.pumpAndSettle();

      final TestGesture gesture = await _mouse(tester);
      for (final MapEntry<ResizeHandle, SystemMouseCursor> entry
          in _cornerSystemCursor.entries) {
        await gesture.moveTo(Offset.zero); // leave any prior region first
        await tester.pump();
        await gesture.moveTo(tester.getCenter(_handle(entry.key)));
        await tester.pump();
        expect(_activeCursor(), entry.value,
            reason: 'the ${entry.key.name} corner must keep its diagonal cursor '
                'even when an edge handle overlaps it');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('on macOS, corners use a native diagonal resize cursor',
      (WidgetTester tester) async {
    // macOS has no public diagonal system cursor, so the library substitutes its
    // own cursor (driving the macOS window-resize NSCursor). Edges keep the
    // ordinary system cursors. We can't assert the rendered NSCursor, but we can
    // assert the corners no longer resolve to a (wrong) plain system cursor.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final JetReportDesignerController controller =
          await pumpDesignerWith(tester);
      controller.createElement(DesignerToolType.shape,
          bandIndex: 1, at: const JetOffset(40, 40));
      await tester.pumpAndSettle();

      final TestGesture gesture = await _mouse(tester);

      // Edges still use the ordinary (macOS-supported) system cursors.
      for (final MapEntry<ResizeHandle, SystemMouseCursor> entry
          in _edgeCursor.entries) {
        await gesture.moveTo(tester.getCenter(_handle(entry.key)));
        await tester.pump();
        expect(_activeCursor(), entry.value,
            reason:
                'the ${entry.key.name} edge keeps its system cursor on macOS');
      }

      // Corners resolve to the library's diagonal cursor (not a system cursor),
      // tagged NWSE (↖↘) for TL/BR and NESW (↗↙) for TR/BL.
      const Map<ResizeHandle, String> diagonalTag = <ResizeHandle, String>{
        ResizeHandle.topLeft: 'NWSE',
        ResizeHandle.bottomRight: 'NWSE',
        ResizeHandle.topRight: 'NESW',
        ResizeHandle.bottomLeft: 'NESW',
      };
      for (final MapEntry<ResizeHandle, String> entry in diagonalTag.entries) {
        await gesture.moveTo(Offset.zero);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(_handle(entry.key)));
        await tester.pump();
        final MouseCursor cursor = _activeCursor();
        expect(cursor, isNot(isA<SystemMouseCursor>()),
            reason: 'macOS corner must not fall back to a plain system cursor');
        expect(cursor.toString(), contains(entry.value),
            reason: 'the ${entry.key.name} corner must use the ${entry.value} '
                'diagonal cursor');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
