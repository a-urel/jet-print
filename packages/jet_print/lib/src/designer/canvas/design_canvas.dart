/// The interactive WYSIWYG design surface.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerDeviceKind,
        PointerPanZoomUpdateEvent,
        PointerScrollEvent,
        PointerSignalEvent;
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/geometry.dart';
import '../../domain/report_band.dart';
import '../controller/jet_report_designer_controller.dart';
import '../designer_scope.dart';
import '../interaction/canvas_shortcuts.dart';
import '../l10n/band_type_label.dart';
import '../l10n/element_type_label.dart';
import '../l10n/jet_print_localizations.dart';
import 'canvas_view_transform.dart';
import 'design_time_frame.dart';
import 'design_time_layout.dart';
import 'design_tunables.dart';
import 'field_drag_data.dart';
import 'frame_custom_painter.dart';
import 'hit_testing.dart';
import 'selection_overlay.dart';

/// Stable widget key for the interactive canvas (test seam).
const Key kDesignCanvasKey = ValueKey<String>('jet_print.designer.canvas');

/// Stable widget key for the paper page surface (test seam).
const Key kDesignPageKey = ValueKey<String>('jet_print.designer.page');

// --- Paper palette -----------------------------------------------------------
// The design surface represents a sheet of printed paper, so it (and the
// design-time chrome drawn on it) is painted with a constant, theme-independent
// "paper" palette in every theme. The report content is emitted with print
// colors (e.g. dark text), which only read correctly on white — so a dark page
// in dark mode would both look wrong and hide content. Only the surrounding
// canvas and the app chrome follow the light/dark theme.
const Color _paperColor = Color(0xFFFFFFFF);
const Color _paperBorderColor = Color(0xFFE2E8F0); // slate-200
const Color _paperShadowColor = Color(0x1A000000); // black 10%
const Color _bandSeparatorColor = Color(0x14000000); // black 8%
const Color _badgeBackgroundColor = Color(0xFFF1F5F9); // slate-100
const Color _badgeForegroundColor = Color(0xFF64748B); // slate-500
const Color _badgeBorderColor = Color(0xFFE2E8F0); // slate-200

/// The live design surface: it paints element *appearance* through the shared
/// render pipeline (cached as a `ui.Picture`) and layers direct-manipulation
/// interaction on top — drop-to-create, click-to-select, and (added by later
/// stories) move/resize/marquee, all against the shared [JetReportDesignerController].
class DesignCanvas extends StatefulWidget {
  /// Creates the canvas. The controller is read from the enclosing
  /// [DesignerScope].
  const DesignCanvas({super.key});

  @override
  State<DesignCanvas> createState() => _DesignCanvasState();
}

class _DesignCanvasState extends State<DesignCanvas> {
  final DesignTimeFrameBuilder _frameBuilder = DesignTimeFrameBuilder();
  final FocusNode _focusNode =
      FocusNode(debugLabel: 'jet_print.designer.canvas');
  final GlobalKey _pageKey = GlobalKey();

  ui.Picture? _picture;
  int _renderedRevision = -1;
  bool _building = false;

  /// Whether the initial fit-to-width has been applied, and the fit-request
  /// generation last honored (the controller bumps it on `fitToView`).
  bool _viewInitialized = false;
  int _appliedFitRequest = 0;

  /// Live body-drag move state: the page point where the drag began, and
  /// whether a selection move is in progress.
  JetOffset? _panStartPage;
  bool _movingSelection = false;

  /// Live marquee (rubber-band) state, in page coordinates.
  JetOffset? _marqueeStartPage;
  JetRect? _marqueeRect;
  bool _marqueeing = false;

  /// The page point of a press that landed on no element, pending tap-up. On a
  /// real tap it classifies into a band/report/clear selection; if the press
  /// instead becomes a drag (marquee, or a band-handle resize) the tap is
  /// cancelled and this is discarded — so band/page selection never fights an
  /// in-progress drag.
  JetOffset? _emptyTapPage;

  /// Manual double-tap detection (avoids a DoubleTapGestureRecognizer, which
  /// would delay single-tap select). Tracks the last tap's position + a reset
  /// timer; a second tap near it on any element brings the Properties
  /// inspector forward for it.
  Offset? _lastTapPosition;
  Timer? _doubleTapTimer;
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);

  static const double _viewportPadding = 32;

  /// Pointer kinds whose drags drive canvas interactions (move / marquee /
  /// resize). The trackpad is excluded so a two-finger trackpad pan scrolls the
  /// viewport instead of starting a rubber-band selection.
  static const Set<PointerDeviceKind> _interactionDevices = <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  /// Scroll controllers for the 2D page viewport (vertical outer, horizontal
  /// inner). They drive the scrollbars and let fit/zoom recenter the page.
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();

  /// A stable per-element key on each element's hit region, so a selection from
  /// another surface (the Outline/Properties panels) can scroll it into view.
  final Map<String, GlobalKey> _elementKeys = <String, GlobalKey>{};

  /// The controller we are subscribed to for scroll-into-view, and the last
  /// single-element selection we scrolled to (so we only react to *changes*).
  JetReportDesignerController? _boundController;
  String? _lastEnsuredSelectionId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to the controller for the scroll-into-view side effect (the
    // build path already rebuilds via DesignerScope's InheritedNotifier).
    final JetReportDesignerController controller =
        DesignerScope.of(context, listen: false);
    if (!identical(controller, _boundController)) {
      _boundController?.removeListener(_handleSelectionForScroll);
      _boundController = controller;
      _lastEnsuredSelectionId = controller.selection.singleOrNull;
      _boundController!.addListener(_handleSelectionForScroll);
    }
  }

  /// When the single-element selection changes (typically from an Outline row or
  /// Properties field), scroll that element into the viewport so the user sees
  /// what they selected (FR-007 / SC-005). A no-op when it is already visible.
  void _handleSelectionForScroll() {
    final JetReportDesignerController? controller = _boundController;
    if (controller == null) return;
    final String? id = controller.selection.singleOrNull;
    if (id == _lastEnsuredSelectionId) return;
    _lastEnsuredSelectionId = id;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = _elementKeys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _boundController?.removeListener(_handleSelectionForScroll);
    _doubleTapTimer?.cancel();
    _picture?.dispose();
    _focusNode.dispose();
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  /// Re-records the committed frame off the build path (the element renderers
  /// run here, never on a pan/zoom/drag frame). Coalesces rapid edits: only one
  /// record runs at a time, and it re-checks for newer changes on completion.
  void _maybeRebuild(JetReportDesignerController controller) {
    if (_building || controller.revision == _renderedRevision) return;
    _building = true;
    final int revision = controller.revision;
    final DesignTimeLayout layout = DesignTimeLayout.of(controller.template);
    _frameBuilder
        .recordFrame(_frameBuilder.build(controller.template, layout))
        .then((ui.Picture picture) {
      _building = false;
      if (!mounted) {
        picture.dispose();
        return;
      }
      setState(() {
        _picture?.dispose();
        _picture = picture;
        _renderedRevision = revision;
      });
      _maybeRebuild(controller); // coalesce any change that arrived meanwhile
    });
  }

  /// The zoom that fits the page width into [viewport] (with padding), clamped to
  /// the allowed zoom range. Centering + vertical reach are handled by the scroll
  /// viewport, so this only needs the scale.
  double _fitScale(JetSize content, Size viewport) {
    final double usable = viewport.width - 2 * _viewportPadding;
    final double raw = usable <= 0 ? 1.0 : usable / content.width;
    return raw.clamp(kMinZoom, kMaxZoom);
  }

  void _handleTapDown(
    Offset localPosition,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
    DesignTimeLayout layout,
  ) {
    _focusNode.requestFocus();
    final JetOffset page =
        transform.screenToPage(JetOffset(localPosition.dx, localPosition.dy));
    final String? hit = hitTestElement(
      controller.template,
      layout,
      page,
      slop: kHandleHitSize / 2 / transform.scale,
    );
    if (hit == null) {
      // Defer band/report/clear classification to tap-up: if this press turns
      // into a drag (marquee or a band-handle resize) the tap is cancelled and
      // the selection is left alone. Shift+empty leaves the selection as-is.
      _emptyTapPage = _shiftPressed ? null : page;
      return;
    }
    _emptyTapPage = null;
    if (_shiftPressed) {
      controller.toggleSelection(hit); // extend/contract multi-selection
    } else {
      controller.select(hit);
    }

    // Manual double-tap: a second tap near the first brings the Properties
    // inspector forward for the tapped element — without a
    // DoubleTapGestureRecognizer delaying the single-tap select above.
    // Shift-taps are multi-selection gestures, not double-taps: the second
    // shift-tap just toggled the element back OUT of the selection, so a
    // focus request would land on an empty inspector.
    final bool near = _lastTapPosition != null &&
        (_lastTapPosition! - localPosition).distance < 24;
    if (near) {
      _doubleTapTimer?.cancel();
      _lastTapPosition = null;
      if (!_shiftPressed) controller.requestPropertiesFocus();
      return;
    }
    _lastTapPosition = localPosition;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(_doubleTapWindow, () => _lastTapPosition = null);
  }

  /// Tap-up: complete an empty-area tap as a band/report/clear selection. A press
  /// that became a drag fired `onTapCancel` (clearing [_emptyTapPage]) first, so
  /// this only runs for a genuine tap on no element.
  void _handleTap(
      JetReportDesignerController controller, DesignTimeLayout layout) {
    final JetOffset? page = _emptyTapPage;
    _emptyTapPage = null;
    if (page == null) return;
    _selectEmptyTarget(page, controller, layout);
  }

  /// Classifies an empty (no-element) page point: inside a band → select it;
  /// elsewhere on the paper (margins / flow gap) → select the report; off the
  /// paper → clear.
  void _selectEmptyTarget(
    JetOffset page,
    JetReportDesignerController controller,
    DesignTimeLayout layout,
  ) {
    final JetSize size = layout.size;
    final bool onPaper = page.dx >= 0 &&
        page.dx <= size.width &&
        page.dy >= 0 &&
        page.dy <= size.height;
    if (!onPaper) {
      controller.clearSelection();
      return;
    }
    final int? band = layout.bandAt(page);
    if (band != null) {
      controller.selectBand(band);
    } else {
      controller.selectReport();
    }
  }

  bool get _shiftPressed =>
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftRight);

  /// Mouse wheel: Ctrl/⌘ + wheel zooms (FR-020); a plain wheel scrolls the page.
  /// Both axes are routed explicitly (nested scroll views otherwise let the
  /// inner axis swallow a cross-axis scroll). The signal is claimed via the
  /// resolver so the scroll views never also act on it.
  void _handlePointerSignal(
      PointerSignalEvent event, JetReportDesignerController controller) {
    if (event is! PointerScrollEvent) return;
    final bool zoom = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    GestureBinding.instance.pointerSignalResolver.register(event,
        (PointerSignalEvent _) {
      if (zoom) {
        controller.setViewScale(
            controller.viewScale * (event.scrollDelta.dy > 0 ? 0.9 : 1.1));
      } else {
        _scrollBy(event.scrollDelta);
      }
    });
  }

  /// Two-finger trackpad pan → scroll the page (opposite the finger movement, so
  /// it follows the platform's natural-scrolling convention). Handled here rather
  /// than by the scroll views, which mis-route a 2D pan across nested axes.
  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) =>
      _scrollBy(-event.localPanDelta);

  /// Applies a scroll [delta] to the page viewport, per axis, clamped to range.
  void _scrollBy(Offset delta) {
    if (delta.dy != 0 && _vScroll.hasClients) {
      _vScroll.jumpTo((_vScroll.offset + delta.dy)
          .clamp(0.0, _vScroll.position.maxScrollExtent));
    }
    if (delta.dx != 0 && _hScroll.hasClients) {
      _hScroll.jumpTo((_hScroll.offset + delta.dx)
          .clamp(0.0, _hScroll.position.maxScrollExtent));
    }
  }

  void _handlePanStart(
    Offset localPosition,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
    DesignTimeLayout layout,
  ) {
    final JetOffset page =
        transform.screenToPage(JetOffset(localPosition.dx, localPosition.dy));
    final String? hit = hitTestElement(controller.template, layout, page,
        slop: kHandleHitSize / 2 / transform.scale);
    if (hit == null) {
      // Empty-area drag → marquee (rubber-band) selection. Cancel any pending
      // empty-tap classification (this press is a drag, not a tap).
      _emptyTapPage = null;
      _movingSelection = false;
      _marqueeing = true;
      _marqueeStartPage = page;
      setState(() =>
          _marqueeRect = JetRect(x: page.dx, y: page.dy, width: 0, height: 0));
      return;
    }
    if (!controller.selection.contains(hit)) controller.select(hit);
    _panStartPage = page;
    _movingSelection = true;
    controller.beginMove();
  }

  void _handlePanUpdate(
    Offset localPosition,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
  ) {
    final JetOffset page =
        transform.screenToPage(JetOffset(localPosition.dx, localPosition.dy));
    if (_marqueeing && _marqueeStartPage != null) {
      setState(() => _marqueeRect = _rectFromPoints(_marqueeStartPage!, page));
      return;
    }
    final JetOffset? start = _panStartPage;
    if (!_movingSelection || start == null) return;
    controller.updateMove(
      JetOffset(page.dx - start.dx, page.dy - start.dy),
      threshold: kSnapThresholdPx / transform.scale,
      bypassSnap: _altPressed,
    );
  }

  static JetRect _rectFromPoints(JetOffset a, JetOffset b) {
    final double x = a.dx < b.dx ? a.dx : b.dx;
    final double y = a.dy < b.dy ? a.dy : b.dy;
    return JetRect(
        x: x, y: y, width: (a.dx - b.dx).abs(), height: (a.dy - b.dy).abs());
  }

  bool _encloses(JetRect outer, JetRect inner) =>
      inner.x >= outer.x &&
      inner.y >= outer.y &&
      inner.x + inner.width <= outer.x + outer.width &&
      inner.y + inner.height <= outer.y + outer.height;

  bool get _altPressed =>
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.altLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.altRight);

  void _handlePanEnd(
      JetReportDesignerController controller, DesignTimeLayout layout) {
    if (_marqueeing) {
      final JetRect? rect = _marqueeRect;
      _marqueeing = false;
      _marqueeStartPage = null;
      if (rect != null && (rect.width > 1 || rect.height > 1)) {
        controller.selectElements(<String>[
          for (final band in controller.template.bands)
            for (final element in band.elements)
              if (layout.elementRect(element.id) case final JetRect r
                  when _encloses(rect, r))
                element.id,
        ]);
      }
      setState(() => _marqueeRect = null);
      return;
    }
    if (!_movingSelection) return;
    _movingSelection = false;
    _panStartPage = null;
    controller.commitMove();
  }

  void _handleDrop(
    DesignerToolType type,
    Offset globalOffset,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
    DesignTimeLayout layout,
  ) {
    final RenderObject? object = _pageKey.currentContext?.findRenderObject();
    if (object is! RenderBox) return;
    final Offset local = object.globalToLocal(globalOffset);
    final JetOffset page =
        JetOffset(local.dx / transform.scale, local.dy / transform.scale);
    final int? bandIndex = layout.bandIndexAt(page);
    if (bandIndex == null) return;
    controller.createElement(
      type,
      bandIndex: bandIndex,
      at: layout.toBandLocal(bandIndex, page),
    );
  }

  /// Drops a field dragged from the Data Source panel, creating a text element
  /// bound to `$F{fieldName}` at the drop point (US2 / FR-011). Same coordinate
  /// math as [_handleDrop]; a drop outside any band is ignored.
  void _handleFieldDrop(
    FieldDragData data,
    Offset globalOffset,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
    DesignTimeLayout layout,
  ) {
    final RenderObject? object = _pageKey.currentContext?.findRenderObject();
    if (object is! RenderBox) return;
    final Offset local = object.globalToLocal(globalOffset);
    final JetOffset page =
        JetOffset(local.dx / transform.scale, local.dy / transform.scale);
    final int? bandIndex = layout.bandIndexAt(page);
    if (bandIndex == null) return;
    controller.createBoundElement(
      bandIndex: bandIndex,
      at: layout.toBandLocal(bandIndex, page),
      expression: '\$F{${data.fieldName}}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final DesignTimeLayout layout = DesignTimeLayout.of(controller.template);
    final bool isEmpty =
        !controller.template.bands.any((band) => band.elements.isNotEmpty);

    // Re-record the committed picture when the model changes (off the build path).
    if (controller.revision != _renderedRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeRebuild(controller);
      });
    }

    return CanvasShortcuts(
      controller: controller,
      child: Focus(
        key: kDesignCanvasKey,
        focusNode: _focusNode,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size viewport = constraints.biggest;
            // Apply the initial fit-to-width once, and again whenever a fit is
            // requested — off the build path (it mutates the controller + scroll).
            if (!_viewInitialized ||
                controller.fitRequest != _appliedFitRequest) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _viewInitialized = true;
                _appliedFitRequest = controller.fitRequest;
                controller.setViewScale(_fitScale(layout.size, viewport));
                if (_vScroll.hasClients) _vScroll.jumpTo(0);
                if (_hScroll.hasClients) _hScroll.jumpTo(0);
              });
            }

            final double scale = controller.viewScale;
            final double pageW = layout.size.width * scale;
            final double pageH = layout.size.height * scale;
            // The scroll content is the page plus padding, but never smaller than
            // the viewport — so a page that fits is centered, and a larger one
            // scrolls. The page is centered within that content.
            final double contentW =
                math.max(pageW + 2 * _viewportPadding, viewport.width);
            final double contentH =
                math.max(pageH + 2 * _viewportPadding, viewport.height);
            final JetOffset pageOffset =
                JetOffset((contentW - pageW) / 2, (contentH - pageH) / 2);
            final CanvasViewTransform transform =
                CanvasViewTransform(scale: scale, pan: pageOffset);
            final bool vScrollable = contentH > viewport.height + 0.5;
            final bool hScrollable = contentW > viewport.width + 0.5;
            final Color thumbColor = colors.foreground.withValues(alpha: 0.4);

            final Widget content = Listener(
              onPointerSignal: (PointerSignalEvent event) =>
                  _handlePointerSignal(event, controller),
              onPointerPanZoomUpdate: _handlePanZoomUpdate,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                supportedDevices: _interactionDevices,
                onTapDown: (TapDownDetails d) => _handleTapDown(
                    d.localPosition, controller, transform, layout),
                onTap: () => _handleTap(controller, layout),
                onTapCancel: () => _emptyTapPage = null,
                onPanStart: (DragStartDetails d) => _handlePanStart(
                    d.localPosition, controller, transform, layout),
                onPanUpdate: (DragUpdateDetails d) =>
                    _handlePanUpdate(d.localPosition, controller, transform),
                onPanEnd: (DragEndDetails d) =>
                    _handlePanEnd(controller, layout),
                child: SizedBox(
                  width: contentW,
                  height: contentH,
                  child: ColoredBox(
                    color: colors.muted,
                    child: Stack(
                      children: <Widget>[
                        Positioned(
                          left: pageOffset.dx,
                          top: pageOffset.dy,
                          width: pageW,
                          height: pageH,
                          child: _buildPage(
                              controller, layout, scale, colors, isEmpty),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );

            // 2D scroll viewport with scrollbars. Drag-to-scroll is disabled (see
            // _CanvasScrollBehavior) so canvas drags win; the wheel/trackpad and
            // the scrollbars still scroll the oversized page.
            // The scroll views provide the scrolling mechanism + clipping; the
            // scrollbars are drawn as a fixed overlay pinned to the viewport edges
            // (a horizontal bar nested inside the vertical scroll view would scroll
            // away with the content). Both are driven by the same controllers.
            return Stack(
              children: <Widget>[
                ScrollConfiguration(
                  behavior: const _CanvasScrollBehavior(),
                  child: SingleChildScrollView(
                    controller: _vScroll,
                    child: SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      child: content,
                    ),
                  ),
                ),
                if (vScrollable)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: hScrollable ? 8 : 0,
                    width: 8,
                    child: _CanvasScrollbar(
                      key: const ValueKey<String>(
                          'jet_print.designer.scrollbar.vertical'),
                      controller: _vScroll,
                      axis: Axis.vertical,
                      color: thumbColor,
                    ),
                  ),
                if (hScrollable)
                  Positioned(
                    left: 0,
                    right: vScrollable ? 8 : 0,
                    bottom: 0,
                    height: 8,
                    child: _CanvasScrollbar(
                      key: const ValueKey<String>(
                          'jet_print.designer.scrollbar.horizontal'),
                      controller: _hScroll,
                      axis: Axis.horizontal,
                      color: thumbColor,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPage(
    JetReportDesignerController controller,
    DesignTimeLayout layout,
    double scale,
    ShadColorScheme colors,
    bool isEmpty,
  ) {
    return DragTarget<FieldDragData>(
      onAcceptWithDetails: (DragTargetDetails<FieldDragData> details) {
        _handleFieldDrop(details.data, details.offset, controller,
            CanvasViewTransform(scale: scale), layout);
      },
      builder: (BuildContext context, _, __) => DragTarget<DesignerToolType>(
        onAcceptWithDetails: (DragTargetDetails<DesignerToolType> details) {
          _handleDrop(details.data, details.offset, controller,
              CanvasViewTransform(scale: scale), layout);
        },
        builder: (BuildContext context, _, __) {
          return KeyedSubtree(
            key: _pageKey,
            child: DecoratedBox(
              key: kDesignPageKey,
              decoration: const BoxDecoration(
                color: _paperColor,
                border:
                    Border.fromBorderSide(BorderSide(color: _paperBorderColor)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _paperShadowColor,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: <Widget>[
                  // Band-structure chrome (design-only; not element appearance).
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BandChromePainter(
                        layout: layout,
                        scale: scale,
                        separatorColor: _bandSeparatorColor,
                      ),
                    ),
                  ),
                  // Band-type captions, one per band, anchored at each band's
                  // top-left corner. Drawn below element appearance so an element
                  // sharing the corner visually wins; they never capture pointers.
                  ..._bandBadges(controller, layout, scale),
                  // Element appearance via the shared render pipeline (cached).
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FrameCustomPainter(
                        picture: _picture,
                        scale: scale,
                        revision: _renderedRevision,
                      ),
                    ),
                  ),
                  // Per-element regions: accessibility + test hooks. They do not
                  // capture pointers (the canvas gesture detector handles hit-testing),
                  // so the canvas still owns select/move.
                  ..._elementRegions(controller, layout, scale,
                      JetPrintLocalizations.of(context)),
                  // Selection chrome (outline + handles), on top.
                  Positioned.fill(
                    child:
                        DesignerSelectionOverlay(layout: layout, scale: scale),
                  ),
                  // Marquee rubber-band, while dragging on empty canvas.
                  if (_marqueeRect case final JetRect m)
                    Positioned(
                      key: const ValueKey<String>('jet_print.designer.marquee'),
                      left: m.x * scale,
                      top: m.y * scale,
                      width: m.width * scale,
                      height: m.height * scale,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.08),
                            border: Border.all(color: colors.primary, width: 1),
                          ),
                        ),
                      ),
                    ),
                  // Centered "drop something here" hint while the design is empty.
                  if (isEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: _EmptyHint(
                            message: JetPrintLocalizations.of(context)
                                .surfaceEmptyHint,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// One badge per band, anchored at the band's top-left corner. The badge size
  /// is constant (UI chrome), so captions stay legible at any zoom; only the
  /// anchor position scales with the view.
  List<Widget> _bandBadges(
    JetReportDesignerController controller,
    DesignTimeLayout layout,
    double scale,
  ) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final List<Widget> badges = <Widget>[];
    final List<ReportBand> bands = controller.template.bands;
    for (int i = 0; i < bands.length; i++) {
      final JetRect? rect = layout.bandRect(i);
      if (rect == null) continue;
      badges.add(Positioned(
        // Keyed by index so duplicate band types (e.g. several group headers)
        // never produce a duplicate key.
        key: ValueKey<String>('jet_print.designer.bandBadge.$i'),
        left: rect.x * scale,
        top: rect.y * scale,
        child: IgnorePointer(
          child: _BandBadge(caption: bandTypeLabel(bands[i].type, l10n)),
        ),
      ));
    }
    return badges;
  }

  List<Widget> _elementRegions(
    JetReportDesignerController controller,
    DesignTimeLayout layout,
    double scale,
    JetPrintLocalizations l10n,
  ) {
    final List<Widget> regions = <Widget>[];
    for (final band in controller.template.bands) {
      for (final element in band.elements) {
        final JetRect? rect = layout.elementRect(element.id);
        if (rect == null) continue;
        final GlobalKey regionKey =
            _elementKeys.putIfAbsent(element.id, () => GlobalKey());
        regions.add(Positioned(
          left: rect.x * scale,
          top: rect.y * scale,
          width: rect.width * scale,
          height: rect.height * scale,
          // KeyedSubtree carries the GlobalKey used for scroll-into-view; the
          // Semantics keeps its own stable ValueKey (a11y + test seam). The
          // accessible name is localized (e.g. "Text element heading1").
          child: KeyedSubtree(
            key: regionKey,
            child: Semantics(
              key: ValueKey<String>('jet_print.designer.element.${element.id}'),
              // `container` makes each element its own semantics node (a screen
              // reader announces one element per stop) rather than merging the
              // page's decorative band badges into one giant node.
              container: true,
              label: l10n.elementSemanticLabel(
                  elementTypeLabel(element, l10n), element.id),
              button: true,
              selected: controller.selection.contains(element.id),
              child: const SizedBox.expand(),
            ),
          ),
        ));
      }
    }
    return regions;
  }
}

/// Scroll behavior for the page viewport. Drag/pan scrolling by the scroll views
/// is fully disabled (empty [dragDevices]) — the canvas owns all pointer drags
/// (move / marquee / resize) and routes wheel + trackpad scrolling to the scroll
/// controllers itself (see `_handlePointerSignal` / `_handlePanZoomUpdate`), so a
/// 2D trackpad pan scrolls both axes instead of being swallowed by one nested
/// scroll view. The library supplies its own [RawScrollbar]s, so the behavior
/// adds neither a scrollbar nor an overscroll indicator.
class _CanvasScrollBehavior extends ScrollBehavior {
  const _CanvasScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{};

  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// A minimal scrollbar pinned to a viewport edge, driven by a [ScrollController].
/// Drawn as a fixed overlay (not inside the scroll view) so it stays at the
/// viewport edge; the thumb is draggable. Renders nothing until the controller
/// has dimensions.
class _CanvasScrollbar extends StatelessWidget {
  const _CanvasScrollbar({
    required this.controller,
    required this.axis,
    required this.color,
    super.key,
  });

  final ScrollController controller;
  final Axis axis;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        if (!controller.hasClients || !controller.position.haveDimensions) {
          return const SizedBox.expand();
        }
        final ScrollPosition pos = controller.position;
        final double maxExtent = pos.maxScrollExtent;
        if (maxExtent <= 0) return const SizedBox.expand();
        final double viewport = pos.viewportDimension;
        final double pixels = pos.pixels.clamp(0.0, maxExtent);
        final bool vertical = axis == Axis.vertical;
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final double track = vertical ? c.maxHeight : c.maxWidth;
            final double thumb =
                (track * viewport / (viewport + maxExtent)).clamp(24.0, track);
            final double range = track - thumb;
            final double thumbPos =
                range <= 0 ? 0 : range * (pixels / maxExtent);
            return Stack(
              children: <Widget>[
                Positioned(
                  left: vertical ? 0 : thumbPos,
                  top: vertical ? thumbPos : 0,
                  right: vertical ? 0 : null,
                  bottom: vertical ? null : 0,
                  width: vertical ? null : thumb,
                  height: vertical ? thumb : null,
                  child: GestureDetector(
                    onPanUpdate: (DragUpdateDetails d) {
                      if (range <= 0) return;
                      final double delta = vertical ? d.delta.dy : d.delta.dx;
                      controller.jumpTo((pixels + delta * maxExtent / range)
                          .clamp(0.0, maxExtent));
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Draws subtle separators between bands so the report's vertical structure is
/// visible on the design surface. This is design-time chrome (band boundaries),
/// not element appearance, so it is drawn directly rather than through the
/// shared element pipeline.
class _BandChromePainter extends CustomPainter {
  const _BandChromePainter({
    required this.layout,
    required this.scale,
    required this.separatorColor,
  });

  final DesignTimeLayout layout;
  final double scale;
  final Color separatorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = separatorColor
      ..strokeWidth = 1;
    // Each band is delineated top and bottom, so the bottom-anchored footer and
    // the empty flow gap above it read as distinct regions on the sheet.
    for (final JetRect band in layout.bandRects) {
      final double top = band.y * scale;
      final double bottom = (band.y + band.height) * scale;
      canvas.drawLine(Offset(0, top), Offset(size.width, top), line);
      canvas.drawLine(Offset(0, bottom), Offset(size.width, bottom), line);
    }
  }

  @override
  bool shouldRepaint(_BandChromePainter oldDelegate) =>
      oldDelegate.scale != scale ||
      oldDelegate.layout != layout ||
      oldDelegate.separatorColor != separatorColor;
}

/// A small, subtle caption naming a band's role, sat flush in the band's
/// top-left corner (a "tab" — only the bottom-right corner is rounded). This is
/// the band-identity affordance every report designer surfaces; it uses the
/// fixed paper-chrome palette (not the app theme) so it reads on the white page
/// in every theme, and stays muted so it never competes with band content.
class _BandBadge extends StatelessWidget {
  const _BandBadge({required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _badgeBackgroundColor,
        border: Border.fromBorderSide(BorderSide(color: _badgeBorderColor)),
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          caption,
          style: const TextStyle(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            color: _badgeForegroundColor,
          ),
        ),
      ),
    );
  }
}

/// A centered hint shown while the design has no elements, so an empty surface
/// reads as "drop something here" rather than a blank void (FR-023 edge case).
/// It sits over the white page, so it uses the fixed paper-chrome foreground
/// (not the theme) to stay legible on paper in every theme.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(LucideIcons.filePlus,
            size: 32, color: _badgeForegroundColor),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _badgeForegroundColor),
        ),
      ],
    );
  }
}
