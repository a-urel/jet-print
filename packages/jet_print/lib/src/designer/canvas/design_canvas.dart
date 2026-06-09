/// The interactive WYSIWYG design surface.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/services.dart' show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/elements/text_element.dart';
import '../../domain/geometry.dart';
import '../../domain/report_band.dart';
import '../../domain/report_element.dart';
import '../controller/jet_report_designer_controller.dart';
import '../designer_scope.dart';
import '../interaction/canvas_shortcuts.dart';
import '../l10n/jet_print_localizations.dart';
import 'canvas_view_transform.dart';
import 'design_time_frame.dart';
import 'design_time_layout.dart';
import 'design_tunables.dart';
import 'frame_custom_painter.dart';
import 'hit_test.dart';
import 'inline_text_editor.dart';
import 'selection_overlay.dart';

/// Stable widget key for the interactive canvas (test seam).
const Key kDesignCanvasKey = ValueKey<String>('jet_print.designer.canvas');

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
  final FocusNode _focusNode = FocusNode(debugLabel: 'jet_print.designer.canvas');
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

  /// The id of the text element being inline-edited (double-click), or null.
  String? _editingId;

  /// Manual double-tap detection (avoids a DoubleTapGestureRecognizer, which
  /// would delay single-tap select). Tracks the last tap's position + a reset
  /// timer; a second tap near it on a text element opens the inline editor.
  Offset? _lastTapPosition;
  Timer? _doubleTapTimer;
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);

  static const double _viewportPadding = 32;

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    _picture?.dispose();
    _focusNode.dispose();
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

  CanvasViewTransform _fitToWidth(JetSize content, Size viewport) {
    final double usable = viewport.width - 2 * _viewportPadding;
    final double raw = usable <= 0 ? 1.0 : usable / content.width;
    final double scale = raw.clamp(kMinZoom, kMaxZoom);
    final double panX = (viewport.width - content.width * scale) / 2;
    return CanvasViewTransform(
      scale: scale,
      pan: JetOffset(panX < _viewportPadding ? _viewportPadding : panX,
          _viewportPadding),
    );
  }

  void _handleTapDown(
    Offset localPosition,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
    DesignTimeLayout layout,
  ) {
    _focusNode.requestFocus();
    final JetOffset page = transform
        .screenToPage(JetOffset(localPosition.dx, localPosition.dy));
    final String? hit = hitTestElement(
      controller.template,
      layout,
      page,
      slop: kHandleHitSize / 2 / transform.scale,
    );
    if (hit == null) {
      if (!_shiftPressed) controller.clearSelection();
    } else if (_shiftPressed) {
      controller.toggleSelection(hit); // extend/contract multi-selection
    } else {
      controller.select(hit);
    }

    // Manual double-tap: a second tap near the first on a text element opens
    // the inline editor — without a DoubleTapGestureRecognizer delaying the
    // single-tap select above.
    final bool near = _lastTapPosition != null &&
        (_lastTapPosition! - localPosition).distance < 24;
    if (near && hit != null && _findElement(controller, hit) is TextElement) {
      _doubleTapTimer?.cancel();
      _lastTapPosition = null;
      setState(() => _editingId = hit);
      return;
    }
    _lastTapPosition = localPosition;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(_doubleTapWindow, () => _lastTapPosition = null);
  }

  bool get _shiftPressed =>
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftLeft) ||
      HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.shiftRight);

  /// Trackpad/wheel: scroll pans; Ctrl/⌘+scroll zooms (FR-020).
  void _handlePointerSignal(
      PointerSignalEvent event, JetReportDesignerController controller) {
    if (event is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      controller.setViewScale(controller.viewScale *
          (event.scrollDelta.dy > 0 ? 0.9 : 1.1));
    } else {
      controller.setViewPan(JetOffset(
        controller.viewPan.dx - event.scrollDelta.dx,
        controller.viewPan.dy - event.scrollDelta.dy,
      ));
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
      // Empty-area drag → marquee (rubber-band) selection.
      _movingSelection = false;
      _marqueeing = true;
      _marqueeStartPage = page;
      setState(() => _marqueeRect =
          JetRect(x: page.dx, y: page.dy, width: 0, height: 0));
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

  ReportElement? _findElement(JetReportDesignerController controller, String id) {
    for (final band in controller.template.bands) {
      for (final ReportElement e in band.elements) {
        if (e.id == id) return e;
      }
    }
    return null;
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

  @override
  Widget build(BuildContext context) {
    final JetReportDesignerController controller = DesignerScope.of(context);
    final ShadColorScheme colors = ShadTheme.of(context).colorScheme;
    final DesignTimeLayout layout = DesignTimeLayout.of(controller.template);
    final bool isEmpty = !controller.template.bands
        .any((band) => band.elements.isNotEmpty);

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
          // requested — off the build path (it mutates the controller).
          if (!_viewInitialized || controller.fitRequest != _appliedFitRequest) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _viewInitialized = true;
              _appliedFitRequest = controller.fitRequest;
              final CanvasViewTransform fit =
                  _fitToWidth(layout.size, viewport);
              controller.setView(fit.scale, fit.pan);
            });
          }
          final CanvasViewTransform transform = CanvasViewTransform(
              scale: controller.viewScale, pan: controller.viewPan);
          final double scale = transform.scale;
          final double pageW = layout.size.width * scale;
          final double pageH = layout.size.height * scale;

          return Listener(
            onPointerSignal: (PointerSignalEvent event) =>
                _handlePointerSignal(event, controller),
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) =>
                _handleTapDown(d.localPosition, controller, transform, layout),
            onPanStart: (DragStartDetails d) =>
                _handlePanStart(d.localPosition, controller, transform, layout),
            onPanUpdate: (DragUpdateDetails d) =>
                _handlePanUpdate(d.localPosition, controller, transform),
            onPanEnd: (DragEndDetails d) => _handlePanEnd(controller, layout),
            child: ColoredBox(
              color: colors.muted,
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: transform.pan.dx,
                    top: transform.pan.dy,
                    width: pageW,
                    height: pageH,
                    child: _buildPage(
                      controller,
                      layout,
                      scale,
                      colors,
                    ),
                  ),
                  if (isEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: _EmptyHint(
                            message:
                                JetPrintLocalizations.of(context).surfaceEmptyHint,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
  ) {
    return DragTarget<DesignerToolType>(
      onAcceptWithDetails: (DragTargetDetails<DesignerToolType> details) {
        _handleDrop(details.data, details.offset, controller,
            CanvasViewTransform(scale: scale), layout);
      },
      builder: (BuildContext context, _, __) {
        return DecoratedBox(
          key: _pageKey,
          decoration: BoxDecoration(
            color: colors.card,
            border: Border.all(color: colors.border),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.foreground.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
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
                    separatorColor: colors.border,
                  ),
                ),
              ),
              // Band-type captions, one per band, anchored at each band's
              // top-left corner. Drawn below element appearance so an element
              // sharing the corner visually wins; they never capture pointers.
              ..._bandBadges(controller, layout, scale, colors),
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
              ..._elementRegions(controller, layout, scale),
              // Selection chrome (outline + handles), on top.
              Positioned.fill(
                child: DesignerSelectionOverlay(layout: layout, scale: scale),
              ),
              // Inline text editor over the element being double-click-edited.
              if (_editingId case final String editId)
                if (layout.elementRect(editId) case final JetRect er)
                  if (_findElement(controller, editId) case final TextElement t)
                    Positioned(
                      left: er.x * scale,
                      top: er.y * scale,
                      width: er.width * scale < 80 ? 80 : er.width * scale,
                      // Height intentionally unconstrained: the input sizes to
                      // its natural height (a text element can be shorter than
                      // the field's minimum).
                      child: InlineTextEditor(
                        initialText: t.text,
                        onCommit: (String value) {
                          controller.setText(editId, value);
                          if (mounted) setState(() => _editingId = null);
                        },
                        onCancel: () {
                          if (mounted) setState(() => _editingId = null);
                        },
                      ),
                    ),
              // Marquee rubber-band, while dragging on empty canvas.
              if (_marqueeRect case final JetRect m)
                Positioned(
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
            ],
          ),
        );
      },
    );
  }

  /// One badge per band, anchored at the band's top-left corner. The badge size
  /// is constant (UI chrome), so captions stay legible at any zoom; only the
  /// anchor position scales with the view.
  List<Widget> _bandBadges(
    JetReportDesignerController controller,
    DesignTimeLayout layout,
    double scale,
    ShadColorScheme colors,
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
          child: _BandBadge(
            caption: _bandTypeLabel(bands[i].type, l10n),
            colors: colors,
          ),
        ),
      ));
    }
    return badges;
  }

  /// Maps a [BandType] to its localized design-surface caption. A `switch`
  /// (rather than a map) so a newly added band type is a compile error here
  /// until it is given a caption.
  String _bandTypeLabel(BandType type, JetPrintLocalizations l10n) {
    switch (type) {
      case BandType.title:
        return l10n.bandTypeTitle;
      case BandType.pageHeader:
        return l10n.bandTypePageHeader;
      case BandType.columnHeader:
        return l10n.bandTypeColumnHeader;
      case BandType.groupHeader:
        return l10n.bandTypeGroupHeader;
      case BandType.detail:
        return l10n.bandTypeDetail;
      case BandType.groupFooter:
        return l10n.bandTypeGroupFooter;
      case BandType.columnFooter:
        return l10n.bandTypeColumnFooter;
      case BandType.pageFooter:
        return l10n.bandTypePageFooter;
      case BandType.summary:
        return l10n.bandTypeSummary;
      case BandType.background:
        return l10n.bandTypeBackground;
      case BandType.noData:
        return l10n.bandTypeNoData;
    }
  }

  List<Widget> _elementRegions(
    JetReportDesignerController controller,
    DesignTimeLayout layout,
    double scale,
  ) {
    final List<Widget> regions = <Widget>[];
    for (final band in controller.template.bands) {
      for (final element in band.elements) {
        final JetRect? rect = layout.elementRect(element.id);
        if (rect == null) continue;
        regions.add(Positioned(
          left: rect.x * scale,
          top: rect.y * scale,
          width: rect.width * scale,
          height: rect.height * scale,
          child: Semantics(
            key: ValueKey<String>('jet_print.designer.element.${element.id}'),
            label: '${element.typeKey} ${element.id}',
            button: true,
            selected: controller.selection.contains(element.id),
            child: const SizedBox.expand(),
          ),
        ));
      }
    }
    return regions;
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
      ..color = separatorColor.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final JetRect band in layout.bandRects) {
      final double y = (band.y + band.height) * scale;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
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
/// the band-identity affordance every report designer surfaces; it is muted so
/// it never competes with the element content placed within the band.
class _BandBadge extends StatelessWidget {
  const _BandBadge({required this.caption, required this.colors});

  final String caption;
  final ShadColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.85),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
        borderRadius: const BorderRadius.only(
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          caption,
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            color: colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// A centered hint shown while the design has no elements, so an empty surface
/// reads as "drop something here" rather than a blank void (FR-023 edge case).
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message, required this.colors});

  final String message;
  final ShadColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(LucideIcons.filePlus, size: 32, color: colors.mutedForeground),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.mutedForeground),
        ),
      ],
    );
  }
}
