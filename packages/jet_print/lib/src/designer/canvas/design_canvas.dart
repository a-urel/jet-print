/// The interactive WYSIWYG design surface.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerDeviceKind,
        PointerDownEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerPanZoomUpdateEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        kSecondaryButton;
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/detail_scope.dart';
import '../../domain/geometry.dart';
import '../../domain/report_definition.dart';
import '../controller/band_walker.dart';
import '../controller/jet_report_designer_controller.dart';
import '../controller/view_fit_mode.dart';
import '../designer_font_scope.dart';
import '../designer_scope.dart';
import '../interaction/canvas_shortcuts.dart';
import '../l10n/band_type_label.dart';
import '../l10n/element_type_label.dart';
import '../l10n/jet_print_localizations.dart';
import '../platform_shortcut.dart';
import 'canvas_view_transform.dart';
import 'design_time_frame.dart';
import 'design_time_layout.dart';
import 'design_tunables.dart';
import 'field_drag_data.dart';
import 'frame_custom_painter.dart';
import 'grid_geometry.dart';
import 'hit_testing.dart';
import 'label_grid_geometry.dart';
import 'paper_palette.dart';
import 'ruler_metrics.dart';
import 'ruler_overlay.dart';
import 'selection_overlay.dart';
import 'zoom_math.dart';

part 'design_canvas/gestures.dart';
part 'design_canvas/drop_menu.dart';
part 'design_canvas/build_helpers.dart';
part 'design_canvas/painters.dart';
part 'design_canvas/widgets.dart';

/// Stable widget key for the interactive canvas (test seam).
const Key kDesignCanvasKey = ValueKey<String>('jet_print.designer.canvas');

/// Stable widget key for the paper page surface (test seam).
const Key kDesignPageKey = ValueKey<String>('jet_print.designer.page');

/// Stable widget key for the backmost alignment-grid layer (test seam, 015).
const Key kDesignGridKey = ValueKey<String>('jet_print.designer.grid');

// --- Paper palette -----------------------------------------------------------
// The design surface represents a sheet of printed paper, so the design-time
// chrome drawn on it (border, shadow, grid, badges) uses a constant,
// theme-independent palette in every theme. The page fill itself comes from the
// shared `paper_palette` (white in light, slate-200 in dark) so the Properties
// page thumbnail renders the identical paper; see that file for the rationale.
const Color _paperBorderColor = Color(0xFFE2E8F0); // slate-200
const Color _paperShadowColor = Color(0x1A000000); // black 10%
const Color _bandSeparatorColor = Color(0x14000000); // black 8%
// The alignment grid is paper chrome, lighter than the band separators so it
// recedes behind content (FR-003 / research D7).
const Color _gridColor = Color(0x0D000000); // black ~5%
// Band-type badges use a cool indigo tint so they read as designer annotations,
// distinct from element content. Fixed (not theme-derived) like the rest of the
// paper chrome, so they stay legible on the white sheet in any theme.
const Color _badgeBackgroundColor = Color(0xFFEEF2FF); // indigo-50
const Color _badgeForegroundColor = Color(0xFF4F46E5); // indigo-600
const Color _badgeBorderColor = Color(0xFFC7D2FE); // indigo-200
// The empty-canvas hint keeps the neutral slate it always had — it is a paper
// prompt, not a band annotation.
const Color _emptyHintColor = Color(0xFF64748B); // slate-500
// The label-grid cue stroke — a faint slate outline for the editable cell
// boundary and the read-only ghost columns (design-only chrome).
const Color _labelGridCueColor = Color(0x553B82F6); // slate/blue @ ~33%

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
  /// Built in [didChangeDependencies] around the designer's hoisted
  /// [DesignerFontScope] registry (021), so the canvas measures and paints
  /// with exactly the family set the Properties panel's picker enumerates.
  late DesignTimeFrameBuilder _frameBuilder;
  bool _frameBuilderReady = false;
  final FocusNode _focusNode =
      FocusNode(debugLabel: 'jet_print.designer.canvas');
  final GlobalKey _pageKey = GlobalKey();

  ui.Picture? _picture;
  int _renderedFrameVersion = -1;
  bool _building = false;

  /// Whether the initial fit-to-width has been applied, and the fit-request
  /// generation last honored (the controller bumps it on `fitToView`).
  bool _viewInitialized = false;
  int _appliedFitRequest = 0;

  /// Guards the one-shot viewport-width-based default-zoom decision (desktop
  /// opens at 100%, phones keep the fit-to-width default), and carries the
  /// "apply 100% on the next post-frame" intent from the build to the callback.
  bool _defaultZoomResolved = false;
  bool _desktopDefaultPending = false;

  /// The viewport size at the last applied fit; lets a steady viewport avoid
  /// re-fitting every frame while a sticky fit mode is active.
  Size? _lastFitViewport;

  /// Live body-drag move state: the page point where the drag began, and
  /// whether a selection move is in progress.
  JetOffset? _panStartPage;
  bool _movingSelection = false;

  /// Live marquee (rubber-band) state, in page coordinates.
  JetOffset? _marqueeStartPage;
  JetRect? _marqueeRect;
  bool _marqueeing = false;

  /// Whether a one-finger drag is panning (scrolling) the viewport. On touch
  /// there is no wheel/trackpad and dragging the thin scrollbar is impractical,
  /// so an empty-canvas drag scrolls the page instead of marquee-selecting
  /// (the natural mobile gesture). Mouse input keeps marquee select.
  bool _panningViewport = false;

  /// The page point of a press that landed on no element, pending tap-up. On a
  /// real tap it classifies into a band/report/clear selection; if the press
  /// instead becomes a drag (marquee, or a band-handle resize) the tap is
  /// cancelled and this is discarded — so band/page selection never fights an
  /// in-progress drag.
  JetOffset? _emptyTapPage;

  /// Whether the pending empty-area tap is the second of a double-tap, so its
  /// tap-up brings the Properties inspector forward (once it has selected the
  /// band or report). Paired with [_emptyTapPage]; cleared whenever that is.
  bool _emptyTapWasDouble = false;

  /// Manual double-tap detection (avoids a DoubleTapGestureRecognizer, which
  /// would delay single-tap select). Tracks the last tap's position + a reset
  /// timer; a second tap near it — on an element, a band, or the report —
  /// brings the Properties inspector forward for whatever it selects.
  Offset? _lastTapPosition;
  Timer? _doubleTapTimer;

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

  /// Explicit handle on the right-click menu so a primary press anywhere on the
  /// canvas dismisses it. The region's own tap-to-hide loses the gesture arena
  /// to the (deliberately deeper) canvas detector, and the region's child sits
  /// inside the menu's TapRegion group — so without this, a click on empty
  /// canvas left the menu open while a click on the chrome closed it.
  final ShadContextMenuController _contextMenu = ShadContextMenuController();

  /// The pointer's current page position (points) while hovering the canvas, or
  /// null on exit. Only the ruler strips listen to it, so a hover repaints two
  /// thin overlays — never the cached page picture (research D5).
  final ValueNotifier<JetOffset?> _hoverPage = ValueNotifier<JetOffset?>(null);

  /// The device kind of the most recent pointer-down over the canvas. Drives
  /// touch-sized grab affordances (larger resize handles + scrollbars) without
  /// a `Platform` check — a mouse on a touchscreen laptop keeps pixel
  /// precision, a finger on the same device gets fat targets.
  PointerDeviceKind _pointerKind = PointerDeviceKind.mouse;

  bool get _isTouch => _pointerKind == PointerDeviceKind.touch;

  void _updatePointerKind(PointerDeviceKind kind) {
    if (kind == _pointerKind) return;
    setState(() => _pointerKind = kind);
  }

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
    // Build the frame builder once, around the designer's hoisted font
    // registry (021) — the canvas then measures and paints with exactly the
    // family set the Properties panel's picker enumerates.
    if (!_frameBuilderReady) {
      _frameBuilder =
          DesignTimeFrameBuilder(fonts: DesignerFontScope.of(context));
      _frameBuilderReady = true;
    }
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
    _contextMenu.dispose();
    _picture?.dispose();
    _focusNode.dispose();
    _vScroll.dispose();
    _hScroll.dispose();
    _hoverPage.dispose();
    super.dispose();
  }

  /// Re-records the displayed frame off the build path (the element renderers
  /// run here, never on a raw pan/zoom frame). The frame follows the live drag:
  /// it is recorded from [JetReportDesignerController.displayDefinition] (the
  /// committed model plus any in-progress move/resize) and keyed on
  /// `frameVersion` (which ticks on every drag preview), so a drag re-records in
  /// realtime. Coalesces rapid edits: only one record runs at a time, and it
  /// re-checks for newer changes on completion — so a fast drag drops
  /// intermediate frames instead of queuing a record per pointer move.
  void _maybeRebuild(JetReportDesignerController controller) {
    if (_building || controller.frameVersion == _renderedFrameVersion) return;
    _building = true;
    final int version = controller.frameVersion;
    final ReportDefinition definition = controller.displayDefinition;
    final DesignTimeLayout layout = DesignTimeLayout.of(definition);
    _frameBuilder
        .recordFrame(_frameBuilder.build(definition, layout))
        .then((ui.Picture picture) {
      _building = false;
      if (!mounted) {
        picture.dispose();
        return;
      }
      setState(() {
        _picture?.dispose();
        _picture = picture;
        _renderedFrameVersion = version;
      });
      _maybeRebuild(controller); // coalesce any change that arrived meanwhile
    });
  }

  /// Proxy for [setState] callable from the canvas's `part` extensions: the
  /// analyzer flags `setState` as a protected member when reached through an
  /// extension, so the gesture/drop/build extensions rebuild through this.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    // Two layouts, split by role. The committed [layout] drives click hit-testing
    // and the selection overlay (which builds its previews by *adding* the live
    // move/resize delta to committed positions — feeding it the already-moved
    // geometry would double-count). The [displayLayout] reflects any in-progress
    // drag (move/resize/band-resize) and draws everything that represents the
    // model — the cached picture, grid, band separators, badges, hit regions — so
    // they reflow together in realtime. Idle (and during element move/resize,
    // which never changes band geometry) the two are identical; only a band
    // resize makes them diverge, which is exactly where the reflow is wanted. When
    // idle, `displayDefinition` is the same instance, so the layout is
    // reused rather than recomputed.
    final DesignTimeLayout layout = DesignTimeLayout.of(controller.definition);
    final ReportDefinition displayed = controller.displayDefinition;
    final DesignTimeLayout displayLayout =
        identical(displayed, controller.definition)
            ? layout
            : DesignTimeLayout.of(displayed);
    final bool isEmpty = !allBands(controller.definition)
        .any((band) => band.elements.isNotEmpty);

    // Re-record the displayed picture whenever the displayed frame changes (off
    // the build path) — a committed edit or a live move/resize preview, both of
    // which tick `frameVersion`.
    if (controller.frameVersion != _renderedFrameVersion) {
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
            // Rulers are fixed chrome along the top + left edges: when enabled,
            // the scroll viewport is inset by their thickness, so the page area
            // the canvas lays out and fits is the full area minus the strips.
            final double rulerInset =
                controller.rulersEnabled ? kRulerThickness : 0;
            final Size viewport = Size(
              math.max(0, constraints.biggest.width - rulerInset),
              math.max(0, constraints.biggest.height - rulerInset),
            );
            // Apply a fit (1) on first load, (2) whenever a fit is explicitly
            // requested, or (3) when the viewport changes while a sticky fit
            // mode is active — all off the build path (it mutates the controller
            // + scroll). The chosen formula follows the controller's fit mode.
            final bool fitModeActive =
                controller.viewFitMode != JetViewFitMode.none;
            final bool viewportChanged = _lastFitViewport != viewport;
            // Default zoom by the page-area width, decided once: a desktop-class
            // viewport opens at 100% (actual size); a phone-class one keeps the
            // fit-to-width default. Only overrides the framework default (mode
            // width) — an explicit host fit choice is left alone. Read from the
            // live viewport (not MediaQuery, which a test's setSurfaceSize does
            // not move). The controller mutation is deferred to the post-frame
            // callback (it notifies DesignerScope, which cannot rebuild mid-build).
            if (!_defaultZoomResolved) {
              _defaultZoomResolved = true;
              _desktopDefaultPending = fitModeActive &&
                  controller.viewFitMode == JetViewFitMode.width &&
                  defaultFitForScreenWidth(viewport.width) ==
                      JetViewFitMode.none;
            }
            // Trigger a fit — but ONLY while a fit mode is active, so a manual
            // zoom (mode == none) is never overwritten — when:
            //   (1) first load,
            //   (2) an explicit fit was requested (fitToView button / shortcut),
            //   (3) the viewport changed.
            // Gating clause (2) on fitModeActive too matters on a remount (e.g.
            // a resize crossing the panel-collapse breakpoint): `_appliedFitRequest`
            // resets while the controller's `fitRequest` persists, so without the
            // guard a stale mismatch would re-fit a manually-zoomed canvas.
            if (_desktopDefaultPending) {
              _desktopDefaultPending = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _viewInitialized = true;
                _lastFitViewport = viewport;
                if (controller.viewFitMode == JetViewFitMode.width) {
                  controller.setZoomPercent(100); // mode → none, scale → 1.0
                }
              });
            } else if (fitModeActive &&
                (!_viewInitialized ||
                    controller.fitRequest != _appliedFitRequest ||
                    viewportChanged)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _viewInitialized = true;
                _appliedFitRequest = controller.fitRequest;
                _lastFitViewport = viewport;
                final double fitted = controller.viewFitMode ==
                        JetViewFitMode.page
                    ? fitPageScale(layout.size, viewport, _viewportPadding)
                    : fitWidthScale(layout.size, viewport, _viewportPadding);
                controller.setViewScale(fitted);
                if (_vScroll.hasClients) _vScroll.jumpTo(0);
                if (_hScroll.hasClients) _hScroll.jumpTo(0);
              });
            } else if (!_viewInitialized) {
              // Mode is none on first mount (e.g. after a remount following a
              // resize): mark initialized without touching the scale — the
              // controller already holds the user's manual zoom.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _viewInitialized = true;
                _lastFitViewport = viewport;
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

            // Track the pointer's page position for the ruler markers via the
            // Listener's own onPointerHover (no button) and onPointerMove (button
            // down). Hover events stop firing once a drag begins, so without the
            // move handler the marker would freeze exactly while moving/resizing;
            // a raw Listener still sees every pointer-move over its subtree
            // regardless of which gesture won the arena, so the marker tracks the
            // pointer through a body move, a resize handle, or a band drag alike.
            // A MouseRegion in this subtree would swallow trackpad pan-zoom
            // scrolling, so exit-clearing is handled by a MouseRegion wrapping the
            // whole canvas (outside the gesture path). The notifier is private to
            // the rulers, so a pointer move never rebuilds the canvas (D5).
            void trackPointer(Offset localPosition) =>
                _hoverPage.value = transform.screenToPage(
                    JetOffset(localPosition.dx, localPosition.dy));
            final Widget content = Listener(
              onPointerSignal: (PointerSignalEvent event) =>
                  _handlePointerSignal(event, controller),
              onPointerPanZoomUpdate: _handlePanZoomUpdate,
              onPointerHover: (PointerHoverEvent e) =>
                  trackPointer(e.localPosition),
              onPointerMove: (PointerMoveEvent e) =>
                  trackPointer(e.localPosition),
              // Resolve selection on a secondary (right) button press, before the
              // ShadContextMenuRegion opens the menu (FR-010). A raw Listener sees
              // the down event ahead of the gesture arena, so the selection (and
              // its notify) is in place by the time the menu paints its items.
              onPointerDown: (PointerDownEvent e) {
                _updatePointerKind(e.kind);
                if (e.buttons == kSecondaryButton) {
                  _handleSecondaryTapDown(
                      e.localPosition, controller, transform, layout);
                } else if (_contextMenu.isOpen) {
                  // Dismiss the open menu on any primary press over the canvas
                  // (the raw Listener fires regardless of who wins the gesture
                  // arena); the press then acts on the canvas as usual.
                  _contextMenu.hide();
                }
              },
              // The right-click menu wraps the canvas gesture layer. It sits
              // ABOVE the canvas GestureDetector so the (deeper) canvas detector
              // wins the primary-tap/pan arena — select, marquee and drag keep
              // working — while secondary-click (which the canvas detector
              // ignores) falls through to the region to open the menu. Selection
              // is resolved first by the Listener's secondary onPointerDown
              // (FR-010); the region then opens the menu at the pointer.
              child: ShadContextMenuRegion(
                key: const ValueKey<String>(
                    'jet_print.designer.canvas.contextMenu'),
                controller: _contextMenu,
                longPressEnabled: true,
                // The menu opens on long-press / right-click ONLY. The region
                // defaults tapEnabled to true on iOS/Android, which opens the
                // menu on a plain touch-down — that hijacked taps/drags on the
                // resize handles (a finger-down on a handle showed the menu
                // instead of resizing). Disable it so touch matches desktop:
                // tap selects, long-press shows the menu, handles resize.
                tapEnabled: false,
                items: _contextMenuItems(controller, l10n),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  supportedDevices: _interactionDevices,
                  onTapDown: (TapDownDetails d) => _handleTapDown(
                      d.localPosition, controller, transform, layout),
                  onTap: () => _handleTap(controller, layout),
                  onTapCancel: _cancelEmptyTap,
                  onPanStart: (DragStartDetails d) => _handlePanStart(
                      d.localPosition, controller, transform, layout),
                  onPanUpdate: (DragUpdateDetails d) => _handlePanUpdate(
                      d.localPosition, d.delta, controller, transform),
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
                            child: _buildPage(controller, layout, displayLayout,
                                scale, colors, isEmpty),
                          ),
                        ],
                      ),
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
            // The scroll viewport + its scrollbar overlays, as one unit so the
            // rulers can inset it without disturbing the scrollbar geometry.
            final double barThickness = _isTouch ? 20 : 8;
            final Widget viewportStack = Stack(
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
                    bottom: hScrollable ? barThickness : 0,
                    width: barThickness,
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
                    right: vScrollable ? barThickness : 0,
                    bottom: 0,
                    height: barThickness,
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

            // The viewport always sits inside one stable Stack > Positioned, so
            // toggling the rulers (which only changes the inset and adds/removes
            // strips) never reparents the scroll views onto their controllers.
            final List<Widget> layers = <Widget>[
              Positioned(
                left: rulerInset,
                top: rulerInset,
                right: 0,
                bottom: 0,
                child: viewportStack,
              ),
            ];

            if (controller.rulersEnabled) {
              // A page point p maps to a strip pixel by p·scale + pageOffset −
              // scrollOffset; the origin handed to each ruler is the strip pixel
              // of page-0. Zoom/selection repaints arrive via the controller, but
              // panning is a raw scroll (no controller notify) and hover is in a
              // private notifier — so each strip is wrapped in an AnimatedBuilder
              // on (its scroll controller + the hover notifier), behind a
              // RepaintBoundary, so a pointer move repaints only the strip.
              final double pxPerMm = scale * kPointsPerMm;
              // The selection's union extent (page points), recomputed per build
              // so it tracks move/resize for free; null clears the highlight.
              // Measured against the *displayed* layout (committed model plus any
              // in-progress element move/resize), so the ruler highlight follows
              // the drag in realtime rather than snapping on mouse-up. Idle, the
              // displayed layout equals the committed one, so this is unchanged.
              final JetRect? extent =
                  selectionExtent(displayLayout, controller.selection);
              final RulerColors rulerColors = RulerColors(
                background: colors.card,
                tick: colors.mutedForeground,
                label: colors.mutedForeground,
                border: colors.border,
                marker: colors.primary,
                highlight: colors.primary.withValues(alpha: 0.18),
              );
              layers.addAll(<Widget>[
                Positioned(
                  left: rulerInset,
                  top: 0,
                  right: 0,
                  height: kRulerThickness,
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation:
                          Listenable.merge(<Listenable>[_hScroll, _hoverPage]),
                      builder: (BuildContext context, Widget? _) {
                        final double originPx = pageOffset.dx -
                            (_hScroll.hasClients ? _hScroll.offset : 0);
                        final JetOffset? hover = _hoverPage.value;
                        return RulerOverlay(
                          axis: RulerAxis.horizontal,
                          originPx: originPx,
                          pxPerMm: pxPerMm,
                          lengthPx: viewport.width,
                          colors: rulerColors,
                          markerPx: hover == null
                              ? null
                              : originPx + hover.dx * scale,
                          highlightStartPx: extent == null
                              ? null
                              : originPx + extent.x * scale,
                          highlightEndPx: extent == null
                              ? null
                              : originPx + (extent.x + extent.width) * scale,
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: rulerInset,
                  width: kRulerThickness,
                  bottom: 0,
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation:
                          Listenable.merge(<Listenable>[_vScroll, _hoverPage]),
                      builder: (BuildContext context, Widget? _) {
                        final double originPx = pageOffset.dy -
                            (_vScroll.hasClients ? _vScroll.offset : 0);
                        final JetOffset? hover = _hoverPage.value;
                        return RulerOverlay(
                          axis: RulerAxis.vertical,
                          originPx: originPx,
                          pxPerMm: pxPerMm,
                          lengthPx: viewport.height,
                          colors: rulerColors,
                          markerPx: hover == null
                              ? null
                              : originPx + hover.dy * scale,
                          highlightStartPx: extent == null
                              ? null
                              : originPx + extent.y * scale,
                          highlightEndPx: extent == null
                              ? null
                              : originPx + (extent.y + extent.height) * scale,
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  width: kRulerThickness,
                  height: kRulerThickness,
                  child: RulerCorner(colors: rulerColors),
                ),
              ]);
            }

            // A thin exit-only MouseRegion around the whole canvas clears the
            // hover marker when the pointer leaves (it carries no onHover, so it
            // does not interfere with trackpad pan-zoom inside).
            return MouseRegion(
              opaque: false,
              onExit: (_) => _hoverPage.value = null,
              child: Stack(children: layers),
            );
          },
        ),
      ),
    );
  }

}
