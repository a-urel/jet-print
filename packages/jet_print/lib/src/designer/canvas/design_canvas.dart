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
import 'ruler_metrics.dart';
import 'ruler_overlay.dart';
import 'selection_overlay.dart';
import 'zoom_math.dart';

/// Stable widget key for the interactive canvas (test seam).
const Key kDesignCanvasKey = ValueKey<String>('jet_print.designer.canvas');

/// Stable widget key for the paper page surface (test seam).
const Key kDesignPageKey = ValueKey<String>('jet_print.designer.page');

/// Stable widget key for the backmost alignment-grid layer (test seam, 015).
const Key kDesignGridKey = ValueKey<String>('jet_print.designer.grid');

// --- Paper palette -----------------------------------------------------------
// The design surface represents a sheet of printed paper, so the design-time
// chrome drawn on it (border, shadow, grid, badges) uses a constant,
// theme-independent palette in every theme. The page fill itself is the one
// exception: pure white in light mode, but a *slight* gray (slate-200) in dark
// mode so the sheet does not glare against the dark canvas. It stays light
// enough that the dark print content emitted onto it (e.g. dark text) still
// reads correctly — a genuinely dark page would hide that content. The actual
// exported/printed artifact is always white (that is the render pipeline, not
// this chrome). Only the surrounding canvas and app chrome follow the theme.
const Color _paperColor = Color(0xFFFFFFFF);
const Color _paperColorDark = Color(0xFFE2E8F0); // slate-200 (dark-mode sheet)
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
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);
  static const double _doubleTapSlop = 24;

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
      layout,
      page,
      slop: kHandleHitSize / 2 / transform.scale,
    );

    // Manual double-tap: a second tap near the first (within the window) brings
    // the Properties inspector forward for whatever this tap selects — without a
    // DoubleTapGestureRecognizer delaying the single-tap select.
    final bool near = _isDoubleTap(localPosition);

    if (hit == null) {
      // Defer band/report/clear classification — and any double-tap focus — to
      // tap-up: if this press turns into a drag (marquee or a band-handle
      // resize) the tap is cancelled and the selection is left alone.
      // Shift+empty leaves the selection as-is.
      _emptyTapPage = _shiftPressed ? null : page;
      _emptyTapWasDouble = near && !_shiftPressed;
      _trackTap(localPosition, near: near);
      return;
    }

    _emptyTapPage = null;
    _emptyTapWasDouble = false;
    if (_shiftPressed) {
      controller.toggleSelection(hit); // extend/contract multi-selection
    } else {
      controller.select(hit);
    }
    // Shift-taps are multi-selection gestures, not double-taps: the second
    // shift-tap just toggled the element back OUT of the selection, so a focus
    // request would land on an empty inspector.
    if (near && !_shiftPressed) controller.requestPropertiesFocus();
    _trackTap(localPosition, near: near);
  }

  /// Resolves the selection on a secondary (right) button press, BEFORE the
  /// context menu opens, so the menu acts on what was clicked (FR-010). Runs from
  /// a raw [Listener] (which sees the pointer-down ahead of the gesture arena, so
  /// the resulting `notifyListeners` rebuilds the menu's enabled states against
  /// the just-updated selection — `ShadContextMenuRegion` opens the menu itself):
  ///
  ///  * hit an element NOT in the selection → select just that element;
  ///  * hit an element already in the (multi-)selection → keep the selection;
  ///  * hit empty canvas → leave the selection unchanged (never deselects).
  void _handleSecondaryTapDown(
    Offset localPosition,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
    DesignTimeLayout layout,
  ) {
    final JetOffset page =
        transform.screenToPage(JetOffset(localPosition.dx, localPosition.dy));
    final String? hit = hitTestElement(
      layout,
      page,
      slop: kHandleHitSize / 2 / transform.scale,
    );
    if (hit == null) return; // empty canvas: keep the current selection
    if (!controller.selection.contains(hit)) controller.select(hit);
  }

  /// Whether [position] is close enough to the previous tap (still within the
  /// un-lapsed window) to count as the second tap of a double-tap.
  bool _isDoubleTap(Offset position) =>
      _lastTapPosition != null &&
      (_lastTapPosition! - position).distance < _doubleTapSlop;

  /// Updates double-tap tracking after a tap at [position]: a [near] tap (the
  /// second of a pair) consumes the anchor so a third tap won't also fire; a far
  /// tap becomes the new anchor, lapsing after [_doubleTapWindow].
  void _trackTap(Offset position, {required bool near}) {
    _doubleTapTimer?.cancel();
    if (near) {
      _lastTapPosition = null;
    } else {
      _lastTapPosition = position;
      _doubleTapTimer = Timer(_doubleTapWindow, () => _lastTapPosition = null);
    }
  }

  /// Drops a pending empty-area tap (its press became a drag, or was cancelled).
  void _cancelEmptyTap() {
    _emptyTapPage = null;
    _emptyTapWasDouble = false;
  }

  /// Tap-up: complete an empty-area tap as a band/report/clear selection. A press
  /// that became a drag fired `onTapCancel` (clearing [_emptyTapPage]) first, so
  /// this only runs for a genuine tap on no element.
  void _handleTap(
      JetReportDesignerController controller, DesignTimeLayout layout) {
    final JetOffset? page = _emptyTapPage;
    final bool wasDouble = _emptyTapWasDouble;
    _emptyTapPage = null;
    _emptyTapWasDouble = false;
    if (page == null) return;
    // A genuine tap on no element selects the band/report (or clears). On a
    // double-tap, bring the Properties inspector forward for it — but not when
    // the tap cleared the selection (there is nothing to inspect).
    if (_selectEmptyTarget(page, controller, layout) && wasDouble) {
      controller.requestPropertiesFocus();
    }
  }

  /// Classifies an empty (no-element) page point: inside a band → select it;
  /// elsewhere on the paper (margins / flow gap) → select the report; off the
  /// paper → clear. Returns whether it selected a band or the report (false when
  /// it cleared) — so a double-tap only brings the inspector forward when there
  /// is something to inspect.
  bool _selectEmptyTarget(
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
      return false;
    }
    final String? band = layout.bandIdAt(page);
    if (band != null) {
      controller.selectBand(band);
    } else {
      controller.selectReport();
    }
    return true;
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
        controller.zoomBy(event.scrollDelta.dy > 0 ? 0.9 : 1.1);
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
    final String? hit = hitTestElement(layout, page,
        slop: kHandleHitSize / 2 / transform.scale);
    if (hit == null) {
      // Empty-area drag → marquee (rubber-band) selection. Cancel any pending
      // empty-tap classification (this press is a drag, not a tap).
      _cancelEmptyTap();
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
          for (final placed in layout.bands)
            for (final element in placed.band.elements)
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
    final String? bandId = layout.bandIdNear(page);
    if (bandId == null) return;
    controller.createElement(
      type,
      bandId: bandId,
      at: layout.toBandLocal(bandId, page),
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
    final String? bandId = layout.bandIdNear(page);
    if (bandId == null) return;
    if (data.isCollection) {
      // A collection nests under the scope that owns the drop band (furniture /
      // once-bands resolve to the root master scope).
      final DetailScope? enclosing =
          findScopeOfBand(controller.definition, bandId);
      controller.createListWithBand(
        enclosing?.id ?? controller.definition.body.root.id,
        collectionField: data.fieldName,
      );
      return;
    }
    controller.createBoundElement(
      bandId: bandId,
      at: layout.toBandLocal(bandId, page),
      expression: '\$F{${data.fieldName}}',
    );
  }

  /// The canvas right-click menu: Cut / Copy / Paste / — / Duplicate / Delete,
  /// built from the same `ShadContextMenuItem` the Arrange menu uses (FR-002).
  /// Cut/Copy/Duplicate/Delete enable on [JetReportDesignerController.canCopy]
  /// and Paste on `canPaste` — the same predicates the toolbar reads, so the two
  /// surfaces cannot diverge (FR-005a, FR-012). Each item invokes the matching
  /// controller op and the menu closes on tap (FR-003, FR-011). The trailing
  /// shortcut hint reuses the platform glyph helper (⌘/Ctrl+); Delete has no
  /// modifier, so it carries no trailing glyph (FR-014a).
  List<Widget> _contextMenuItems(
    JetReportDesignerController controller,
    JetPrintLocalizations l10n,
  ) {
    ShadContextMenuItem item(
      String id,
      IconData icon,
      String label,
      String shortcutLetter, {
      required bool enabled,
      required VoidCallback op,
    }) {
      final String hint = shortcutHint(shortcutLetter);
      return ShadContextMenuItem(
        key: ValueKey<String>('jet_print.designer.menu.$id'),
        enabled: enabled,
        leading: Icon(icon, size: 16),
        trailing: hint.isEmpty ? null : Text(hint),
        onPressed: op,
        child: Text(label),
      );
    }

    final bool canCopy = controller.canCopy;
    return <Widget>[
      item('cut', LucideIcons.scissors, l10n.actionCutTooltip, 'X',
          enabled: canCopy, op: controller.cut),
      item('copy', LucideIcons.copy, l10n.actionCopyTooltip, 'C',
          enabled: canCopy, op: controller.copy),
      item('paste', LucideIcons.clipboard, l10n.actionPasteTooltip, 'V',
          enabled: controller.canPaste, op: controller.paste),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: ShadSeparator.horizontal(margin: EdgeInsets.zero),
      ),
      item('duplicate', LucideIcons.copyPlus, l10n.menuDuplicate, 'D',
          enabled: canCopy, op: controller.duplicate),
      item('delete', LucideIcons.trash2, l10n.menuDelete, '',
          enabled: canCopy, op: controller.delete),
    ];
  }

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
            // Trigger a fit when:
            //   (1) first load AND a fit mode is active (skip if the user
            //       already has a manual zoom — i.e. mode == none),
            //   (2) an explicit fit was requested (fitToView button / shortcut),
            //   (3) the viewport changed while a sticky fit mode is active.
            if ((!_viewInitialized && fitModeActive) ||
                controller.fitRequest != _appliedFitRequest ||
                (fitModeActive && viewportChanged)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _viewInitialized = true;
                _appliedFitRequest = controller.fitRequest;
                _lastFitViewport = viewport;
                final double fitted =
                    controller.viewFitMode == JetViewFitMode.page
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

  Widget _buildPage(
    JetReportDesignerController controller,
    DesignTimeLayout layout,
    DesignTimeLayout displayLayout,
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
          // Pure white in light mode; a slight gray (slate-200) in dark mode so
          // the sheet does not glare against the dark canvas (the chrome below
          // stays fixed — it reads on either light fill).
          final bool dark = ShadTheme.of(context).brightness == Brightness.dark;
          return KeyedSubtree(
            key: _pageKey,
            child: DecoratedBox(
              key: kDesignPageKey,
              decoration: BoxDecoration(
                color: dark ? _paperColorDark : _paperColor,
                border: const Border.fromBorderSide(
                    BorderSide(color: _paperBorderColor)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: _paperShadowColor,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: <Widget>[
                  // Backmost: the 5 mm alignment grid (design-only chrome, drawn
                  // per band at the snap step so a drawn line lands on a snap
                  // target). Constructed only when visible; sits behind band
                  // chrome, elements, and all overlays so it never obscures
                  // content (FR-003 / D5). Absent from preview/export by
                  // construction — it is not in the shared render pipeline.
                  if (controller.gridEnabled)
                    Positioned.fill(
                      key: kDesignGridKey,
                      child: CustomPaint(
                        painter: _GridPainter(
                          layout: displayLayout,
                          scale: scale,
                          color: _gridColor,
                        ),
                      ),
                    ),
                  // Band-structure chrome (design-only; not element appearance).
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BandChromePainter(
                        layout: displayLayout,
                        scale: scale,
                        separatorColor: _bandSeparatorColor,
                      ),
                    ),
                  ),
                  // Multi-column label cue (spec 035): the editable cell
                  // boundary + read-only ghost columns. Drawn above band chrome,
                  // below element appearance; absent unless a grid is active.
                  if (labelGridCue(controller.definition, displayLayout)
                      case final LabelGridCue cue)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LabelGridPainter(
                          cue: cue,
                          scale: scale,
                          color: _labelGridCueColor,
                        ),
                      ),
                    ),
                  // Band-type captions, one per band, anchored at each band's
                  // top-left corner. Drawn below element appearance so an element
                  // sharing the corner visually wins; they never capture pointers.
                  ..._bandBadges(controller, displayLayout, scale),
                  // Element appearance via the shared render pipeline (cached).
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FrameCustomPainter(
                        picture: _picture,
                        scale: scale,
                        revision: _renderedFrameVersion,
                      ),
                    ),
                  ),
                  // Per-element regions: accessibility + test hooks. They do not
                  // capture pointers (the canvas gesture detector handles hit-testing),
                  // so the canvas still owns select/move. Drawn from the display
                  // layout so the hit regions ride along with the live picture.
                  ..._elementRegions(controller, displayLayout, scale,
                      JetPrintLocalizations.of(context)),
                  // Selection chrome (outline + handles), on top. Fed the DISPLAY
                  // layout so the outline + handles ride the same clamped geometry
                  // as the element picture during a live move/resize (spec 038).
                  Positioned.fill(
                    child: DesignerSelectionOverlay(
                        layout: displayLayout, scale: scale),
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

  /// One badge per band, anchored at the page's left edge and each band's top.
  /// Anchoring at the page edge (left: 0) rather than the content margin keeps
  /// the caption in the empty left-margin gutter so it never sits on top of the
  /// first element (which starts at the margin). The badge size is constant (UI
  /// chrome), so captions stay legible at any zoom; only the top anchor scales
  /// with the view.
  List<Widget> _bandBadges(
    JetReportDesignerController controller,
    DesignTimeLayout layout,
    double scale,
  ) {
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final List<Widget> badges = <Widget>[];
    for (final PlacedBand placed in layout.bands) {
      badges.add(Positioned(
        // Keyed by the band's stable id so duplicate band types (e.g. several
        // group headers) never produce a duplicate key.
        key: ValueKey<String>('jet_print.designer.bandBadge.${placed.id}'),
        left: 0,
        top: placed.rect.y * scale,
        child: IgnorePointer(
          child: _BandBadge(caption: bandTypeLabel(placed.band.type, l10n)),
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
    for (final PlacedBand placed in layout.bands) {
      for (final element in placed.band.elements) {
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
/// Paints the 5 mm alignment grid as backmost design-time chrome (spec 015).
///
/// Per band, it draws vertical lines at [gridLineOffsets] of the band width and
/// horizontal lines at [gridLineOffsets] of the band height — each offset
/// measured from the band's content origin and scaled to pixels — clipped to the
/// band rect. Because the offsets are exact multiples of [kGridStep] (the same
/// step the snap geometry uses), every drawn line lands on a snap target. The
/// helper coarsens then hides the grid at low zoom so it never smears into a
/// solid fill. Like [_BandChromePainter] this draws directly on the page's
/// scaled surface, outside the shared render pipeline — so it is never present
/// in preview/export (FR-016).
class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.layout,
    required this.scale,
    required this.color,
  });

  final DesignTimeLayout layout;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final JetRect band in layout.bandRects) {
      final double left = band.x * scale;
      final double top = band.y * scale;
      final double right = (band.x + band.width) * scale;
      final double bottom = (band.y + band.height) * scale;
      final Rect bandRect = Rect.fromLTRB(left, top, right, bottom);

      canvas.save();
      canvas.clipRect(bandRect);
      // Vertical lines: multiples of the step across the band width, from the
      // band's left content edge.
      for (final double x in gridLineOffsets(band.width, kGridStep, scale,
          kGridMinLineGapPx, kGridMaxCoarsenFactor)) {
        final double px = left + x * scale;
        canvas.drawLine(Offset(px, top), Offset(px, bottom), line);
      }
      // Horizontal lines: multiples of the step down the band height, from the
      // band's top content edge.
      for (final double y in gridLineOffsets(band.height, kGridStep, scale,
          kGridMinLineGapPx, kGridMaxCoarsenFactor)) {
        final double py = top + y * scale;
        canvas.drawLine(Offset(left, py), Offset(right, py), line);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.scale != scale ||
      oldDelegate.layout != layout ||
      oldDelegate.color != color;
}

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

/// Draws the multi-column label cue (spec 035): the editable cell's boundary
/// plus faint read-only ghost outlines for the remaining columns. Design-only
/// chrome — non-interactive, never part of the shared render pipeline.
class _LabelGridPainter extends CustomPainter {
  const _LabelGridPainter({
    required this.cue,
    required this.scale,
    required this.color,
  });

  final LabelGridCue cue;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    Rect scaled(JetRect r) => Rect.fromLTWH(
        r.x * scale, r.y * scale, r.width * scale, r.height * scale);
    canvas.drawRect(scaled(cue.cell), stroke);
    for (final JetRect g in cue.ghosts) {
      canvas.drawRect(scaled(g), stroke);
    }
  }

  @override
  bool shouldRepaint(_LabelGridPainter oldDelegate) =>
      oldDelegate.cue != cue ||
      oldDelegate.scale != scale ||
      oldDelegate.color != color;
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
            fontSize: 9,
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
        const Icon(LucideIcons.filePlus, size: 32, color: _emptyHintColor),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _emptyHintColor),
        ),
      ],
    );
  }
}
