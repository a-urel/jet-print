/// The selection chrome painted over the canvas: outlines, resize handles, and
/// live snap guides.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/band.dart';
import '../../domain/geometry.dart';
import '../controller/band_walker.dart';
import '../controller/jet_report_designer_controller.dart';
import '../controller/selection.dart';
import '../controller/snapping.dart';
import '../designer_scope.dart';
import '../l10n/jet_print_localizations.dart';
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
      {required this.layout,
      required this.scale,
      this.touchTargets = false,
      super.key});

  /// The current design-time layout (element → page rect).
  final DesignTimeLayout layout;

  /// The active zoom factor.
  final double scale;

  /// When true, resize handles + the band divider present a finger-sized hit
  /// area ([kHandleHitSizeTouch]); the drawn handle is unchanged.
  final bool touchTargets;

  @override
  State<DesignerSelectionOverlay> createState() =>
      _DesignerSelectionOverlayState();
}

class _DesignerSelectionOverlayState extends State<DesignerSelectionOverlay> {
  /// Cumulative pointer delta (page points) for the active handle drag.
  Offset _resizeDelta = Offset.zero;

  /// Cumulative pointer delta (page points) for the active band-divider drag.
  Offset _bandResizeDelta = Offset.zero;

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

  /// Long-press-drag resize: the same effect as the pan-drag, driven by the
  /// cumulative long-press offset. On touch a press-hold-then-drag on the small
  /// handle is the natural grab; routing it through the SAME resize also makes
  /// the handle win the gesture arena over the canvas context-menu's long-press
  /// (so pressing a handle resizes instead of opening the menu — the desktop
  /// pan-drag path is unchanged).
  void _onHandleLongPressMove(
    JetReportDesignerController controller,
    LongPressMoveUpdateDetails details,
  ) {
    _resizeDelta = details.localOffsetFromOrigin / widget.scale;
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
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);

    // Report and band selections get their own minimal chrome (the report is a
    // fixed-format sheet → outline only; a band resizes vertically → one
    // divider handle). Neither uses the element outline/handle machinery.
    if (selection.isReport) return _reportChrome();
    final String? selectedBand = selection.bandId;
    if (selectedBand != null) {
      return _bandChrome(controller, selectedBand, colors, l10n);
    }

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

    // Geometry comes straight from the (display) layout, which already bakes any
    // in-progress move / resize / band-resize through the single `clampToBand`
    // authority — so the chrome can never exceed the band (spec 038, FR-002).
    JetRect? rectFor(String id) => widget.layout.elementRect(id);

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
          children.add(_handle(controller, single, position, r, colors, l10n));
        }
      }
    }

    return Stack(children: children);
  }

  /// Chrome for a selected report/page: an outline around the whole sheet, with
  /// no resize handles (the page is a fixed format, not interactively resizable).
  Widget _reportChrome() => Stack(children: <Widget>[
        _outline(JetRect(
          x: 0,
          y: 0,
          width: widget.layout.size.width,
          height: widget.layout.size.height,
        )),
      ]);

  /// Chrome for a selected band: an outline at the band's (possibly previewed)
  /// height plus a single vertical divider handle on the growth-facing edge —
  /// the bottom for a flow band, the top for a bottom-anchored footer (which
  /// grows upward). No element-style corner/side handles: a band only resizes
  /// vertically.
  Widget _bandChrome(
    JetReportDesignerController controller,
    String bandId,
    ShadColorScheme colors,
    JetPrintLocalizations l10n,
  ) {
    final JetRect? bandRect = widget.layout.bandRect(bandId);
    if (bandRect == null) return const SizedBox.shrink();
    final Band? band = findBand(controller.definition, bandId);
    final bool footer =
        band != null && DesignTimeLayout.isBottomAnchored(band.type);
    final double height =
        controller.bandResizePreviewHeight(bandId) ?? bandRect.height;
    // Anchor the fixed edge; the other edge is where the divider sits and moves.
    final double top =
        footer ? bandRect.y + bandRect.height - height : bandRect.y;
    final double edgeY = footer ? top : top + height;
    return Stack(children: <Widget>[
      _outline(JetRect(
          x: bandRect.x, y: top, width: bandRect.width, height: height)),
      _bandHandle(controller, bandId, footer, bandRect.x + bandRect.width / 2,
          edgeY, colors, l10n),
    ]);
  }

  /// The single vertical band-divider handle: a horizontal grip centered on
  /// [centerX] at the growth edge [edgeY] (page points), with a vertical resize
  /// cursor. Dragging it drives the controller's band resize; a [footer] grows
  /// from its top edge, so an upward drag enlarges it.
  Widget _bandHandle(
    JetReportDesignerController controller,
    String bandId,
    bool footer,
    double centerX,
    double edgeY,
    ShadColorScheme colors,
    JetPrintLocalizations l10n,
  ) {
    final double hit =
        widget.touchTargets ? kHandleHitSizeTouch : kHandleHitSize;
    const double barWidth = 28;
    return Positioned(
      left: centerX * widget.scale - barWidth / 2,
      top: edgeY * widget.scale - hit / 2,
      width: barWidth,
      height: hit,
      // One merged semantics node: a named, button-role handle (FR-024).
      child: MergeSemantics(
        child: Semantics(
          label: l10n.resizeBandHandle,
          button: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              key: const ValueKey<String>('jet_print.designer.bandHandle'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                _bandResizeDelta = Offset.zero;
                controller.beginBandResize(bandId);
              },
              onPanUpdate: (DragUpdateDetails d) {
                _bandResizeDelta += d.delta / widget.scale;
                controller.updateBandResize(
                    footer ? -_bandResizeDelta.dy : _bandResizeDelta.dy);
              },
              onPanEnd: (_) => controller.commitBandResize(),
              onPanCancel: controller.cancelBandResize,
              // Long-press-drag resizes the band too, so a touch hold on the
              // divider wins over the canvas menu's long-press (desktop unchanged).
              onLongPressStart: (_) {
                _bandResizeDelta = Offset.zero;
                controller.beginBandResize(bandId);
              },
              onLongPressMoveUpdate: (LongPressMoveUpdateDetails d) {
                _bandResizeDelta = d.localOffsetFromOrigin / widget.scale;
                controller.updateBandResize(
                    footer ? -_bandResizeDelta.dy : _bandResizeDelta.dy);
              },
              onLongPressEnd: (_) => controller.commitBandResize(),
              onLongPressCancel: controller.cancelBandResize,
              child: Center(
                child: SizedBox(
                  width: barWidth,
                  height: kHandleVisualSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.background,
                      border: Border.all(color: _accent, width: 1.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
    final String? band = controller.activeBandId;
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
    JetPrintLocalizations l10n,
  ) {
    final ({double x, double y}) center = _handleCenter(position, pageRect);
    final double hit =
        widget.touchTargets ? kHandleHitSizeTouch : kHandleHitSize;
    // The handle is centered on its element edge/corner and rides the same
    // (clamped) display geometry as the outline, so it stays visually attached to
    // the selection box everywhere. It is a screen-space grab affordance: at a
    // band edge the small square may overlap the border by half its size — the
    // selection BOX itself stays in-band (the element is clamped), only the grab
    // square overflows, matching the convention in mainstream design tools
    // (spec 038, 2026-06-20 clarification).
    return Positioned(
      left: center.x * widget.scale - hit / 2,
      top: center.y * widget.scale - hit / 2,
      width: hit,
      height: hit,
      // One merged semantics node: a directional, button-role handle (FR-024).
      child: MergeSemantics(
        child: Semantics(
          label: _handleLabel(position, l10n),
          button: true,
          child: MouseRegion(
            cursor: resizeCursorForHandle(position),
            // On macOS the diagonal system cursor renders as a plain arrow, so
            // overpaint the native diagonal NSCursor for corners (a no-op for
            // edges / non-macOS). onEnter covers a static enter; onHover re-asserts
            // it after Flutter activates the system cursor on entry. The tracked
            // cursor stays a real SystemMouseCursor, so edges never desync.
            onEnter: (_) => applyNativeCornerCursor(position),
            onHover: (_) => applyNativeCornerCursor(position),
            child: GestureDetector(
              key: handleKey(position),
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => _onHandleStart(controller, id, position),
              onPanUpdate: (DragUpdateDetails d) =>
                  _onHandleUpdate(controller, d),
              onPanEnd: (_) => controller.commitResize(),
              onPanCancel: controller.cancelResize,
              // Long-press-drag resizes too (touch: a hold on the small handle
              // would otherwise lose the arena to the canvas menu's long-press).
              onLongPressStart: (_) => _onHandleStart(controller, id, position),
              onLongPressMoveUpdate: (LongPressMoveUpdateDetails d) =>
                  _onHandleLongPressMove(controller, d),
              onLongPressEnd: (_) => controller.commitResize(),
              onLongPressCancel: controller.cancelResize,
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
        ),
      ),
    );
  }

  /// The localized accessible name for the resize handle at [position].
  String _handleLabel(ResizeHandle position, JetPrintLocalizations l10n) {
    switch (position) {
      case ResizeHandle.topLeft:
        return l10n.resizeHandleTopLeft;
      case ResizeHandle.top:
        return l10n.resizeHandleTop;
      case ResizeHandle.topRight:
        return l10n.resizeHandleTopRight;
      case ResizeHandle.right:
        return l10n.resizeHandleRight;
      case ResizeHandle.bottomRight:
        return l10n.resizeHandleBottomRight;
      case ResizeHandle.bottom:
        return l10n.resizeHandleBottom;
      case ResizeHandle.bottomLeft:
        return l10n.resizeHandleBottomLeft;
      case ResizeHandle.left:
        return l10n.resizeHandleLeft;
    }
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
