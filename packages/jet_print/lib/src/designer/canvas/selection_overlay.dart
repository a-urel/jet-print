/// The selection chrome painted over the canvas: outlines, resize handles, and
/// live snap guides.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/geometry.dart';
import '../controller/jet_report_designer_controller.dart';
import '../controller/selection.dart';
import '../controller/snapping.dart';
import '../designer_scope.dart';
import 'design_time_layout.dart';
import 'design_tunables.dart';
import 'diagonal_resize_cursor.dart';
import 'resize_handle.dart';

/// A stable per-handle key (test seam): `jet_print.designer.handle.<pos>`.
Key handleKey(ResizeHandle position) =>
    ValueKey<String>('jet_print.designer.handle.${position.name}');

const Color _accent = Color(0xFF2563EB);

/// Draws a selection outline around every selected element, eight resize handles
/// around the single selected element, the live resize preview, and any active
/// snap guides.
///
/// Positioned inside the page widget (local coords = `page-points × scale`).
/// Handles are interactive: dragging one drives the controller's resize
/// interaction (FR-009). They are drawn at a fixed screen size so they stay
/// grabbable at any zoom.
class DesignerSelectionOverlay extends StatefulWidget {
  /// Creates the overlay for [layout] at [scale].
  const DesignerSelectionOverlay(
      {required this.layout, required this.scale, super.key});

  /// The current design-time layout (element → page rect).
  final DesignTimeLayout layout;

  /// The active zoom factor.
  final double scale;

  @override
  State<DesignerSelectionOverlay> createState() =>
      _DesignerSelectionOverlayState();
}

class _DesignerSelectionOverlayState extends State<DesignerSelectionOverlay> {
  /// Cumulative pointer delta (page points) for the active handle drag.
  Offset _resizeDelta = Offset.zero;

  void _onHandleStart(
    JetReportDesignerController controller,
    String id,
    ResizeHandle handle,
  ) {
    _resizeDelta = Offset.zero;
    controller.beginResize(id, handle);
  }

  void _onHandleUpdate(
    JetReportDesignerController controller,
    DragUpdateDetails details,
  ) {
    _resizeDelta += details.delta / widget.scale;
    controller.updateResize(
      JetOffset(_resizeDelta.dx, _resizeDelta.dy),
      threshold: kSnapThresholdPx / widget.scale,
      bypassSnap: _altPressed,
    );
  }

  bool get _altPressed =>
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.altLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.altRight);

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final Selection selection = controller.selection;
    if (selection.isEmpty) return const SizedBox.shrink();

    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final JetOffset move = controller.moveDelta ?? const JetOffset(0, 0);
    final List<Widget> children = <Widget>[];

    // Snap guides live in a single ALWAYS-PRESENT layer (its contents vary, not
    // its position in this list). This keeps the overlay's child structure
    // stable so an appearing/disappearing guide never unmounts the keyed,
    // gesture-owning resize handles mid-drag — which would dispose the active
    // recognizer and silently drop the resize (leaving the preview + guide
    // frozen on the canvas). Drawn first → behind the outline and handles.
    children.add(Positioned.fill(
      child: IgnorePointer(
        child: Stack(children: _guideWidgets(controller)),
      ),
    ));

    JetRect? rectFor(String id) {
      final JetRect? preview = controller.previewBoundsFor(id);
      if (preview != null) {
        // Resize preview is band-relative; convert to page coords.
        final int? band = controller.activeBand;
        final JetRect? bandRect =
            band == null ? null : widget.layout.bandRect(band);
        if (bandRect != null) {
          return JetRect(
              x: bandRect.x + preview.x,
              y: bandRect.y + preview.y,
              width: preview.width,
              height: preview.height);
        }
      }
      final JetRect? rect = widget.layout.elementRect(id);
      if (rect == null) return null;
      return JetRect(
          x: rect.x + move.dx,
          y: rect.y + move.dy,
          width: rect.width,
          height: rect.height);
    }

    for (final String id in selection.ids) {
      final JetRect? r = rectFor(id);
      if (r != null) children.add(_outline(r));
    }

    final String? single = selection.singleOrNull;
    if (single != null) {
      final JetRect? r = rectFor(single);
      if (r != null) {
        // Edges first, corners last. The 16px hit areas overlap when the element
        // is small/zoomed out, and the frontmost (last-added) MouseRegion/handle
        // wins the cursor and the drag — so corners must sit on top of edges to
        // keep their diagonal cursor (and a diagonal resize) at the corner.
        for (final ResizeHandle position in _handlePaintOrder) {
          children.add(_handle(controller, single, position, r, colors));
        }
      }
    }

    return Stack(children: children);
  }

  /// Handle z-order (back to front): the four edges, then the four corners on
  /// top, so an overlapping edge hit area never masks a corner.
  static const List<ResizeHandle> _handlePaintOrder = <ResizeHandle>[
    ResizeHandle.top,
    ResizeHandle.right,
    ResizeHandle.bottom,
    ResizeHandle.left,
    ResizeHandle.topLeft,
    ResizeHandle.topRight,
    ResizeHandle.bottomRight,
    ResizeHandle.bottomLeft,
  ];

  List<Widget> _guideWidgets(JetReportDesignerController controller) {
    final List<SnapGuide> guides = controller.activeGuides;
    final int? band = controller.activeBand;
    if (guides.isEmpty || band == null) return const <Widget>[];
    final JetRect? bandRect = widget.layout.bandRect(band);
    if (bandRect == null) return const <Widget>[];
    final double scale = widget.scale;
    return <Widget>[
      for (final SnapGuide g in guides)
        if (g.axis == SnapAxis.vertical)
          Positioned(
            left: (bandRect.x + g.position) * scale,
            top: bandRect.y * scale,
            width: 1,
            height: bandRect.height * scale,
            child: const ColoredBox(color: Color(0xFFEF4444)),
          )
        else
          Positioned(
            left: bandRect.x * scale,
            top: (bandRect.y + g.position) * scale,
            width: bandRect.width * scale,
            height: 1,
            child: const ColoredBox(color: Color(0xFFEF4444)),
          ),
    ];
  }

  Widget _outline(JetRect pageRect) {
    return Positioned(
      left: pageRect.x * widget.scale,
      top: pageRect.y * widget.scale,
      width: pageRect.width * widget.scale,
      height: pageRect.height * widget.scale,
      child: const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border:
                Border.fromBorderSide(BorderSide(color: _accent, width: 1.5)),
          ),
        ),
      ),
    );
  }

  Widget _handle(
    JetReportDesignerController controller,
    String id,
    ResizeHandle position,
    JetRect pageRect,
    ShadColorScheme colors,
  ) {
    final ({double x, double y}) center = _handleCenter(position, pageRect);
    const double hit = kHandleHitSize;
    return Positioned(
      left: center.x * widget.scale - hit / 2,
      top: center.y * widget.scale - hit / 2,
      width: hit,
      height: hit,
      child: MouseRegion(
        cursor: resizeCursorForHandle(position),
        child: GestureDetector(
          key: handleKey(position),
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _onHandleStart(controller, id, position),
          onPanUpdate: (DragUpdateDetails d) => _onHandleUpdate(controller, d),
          onPanEnd: (_) => controller.commitResize(),
          onPanCancel: controller.cancelResize,
          child: Center(
            child: SizedBox(
              width: kHandleVisualSize,
              height: kHandleVisualSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.background,
                  border: Border.all(color: _accent, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ({double x, double y}) _handleCenter(ResizeHandle position, JetRect r) {
    final double left = r.x;
    final double cx = r.x + r.width / 2;
    final double right = r.x + r.width;
    final double top = r.y;
    final double cy = r.y + r.height / 2;
    final double bottom = r.y + r.height;
    return switch (position) {
      ResizeHandle.topLeft => (x: left, y: top),
      ResizeHandle.top => (x: cx, y: top),
      ResizeHandle.topRight => (x: right, y: top),
      ResizeHandle.right => (x: right, y: cy),
      ResizeHandle.bottomRight => (x: right, y: bottom),
      ResizeHandle.bottom => (x: cx, y: bottom),
      ResizeHandle.bottomLeft => (x: left, y: bottom),
      ResizeHandle.left => (x: left, y: cy),
    };
  }
}
