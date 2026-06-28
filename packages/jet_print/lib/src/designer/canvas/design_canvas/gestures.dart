// Pointer interaction for the design canvas: tap / secondary-tap / pan /
// marquee / pointer-signal handling, split out of `design_canvas.dart` as an
// extension so it keeps full private access to the canvas's interaction state.
part of '../design_canvas.dart';

const Duration _doubleTapWindow = Duration(milliseconds: 300);
const double _doubleTapSlop = 24;

extension _CanvasGestures on _DesignCanvasState {
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
    _panningViewport = false;
    if (hit == null) {
      // Empty-area drag. On touch, pan the viewport (scroll) — there is no
      // wheel/trackpad and the scrollbar is too thin to grab with a finger.
      // On mouse, start a marquee (rubber-band) selection. Either way cancel
      // any pending empty-tap classification (this press is a drag, not a tap).
      _cancelEmptyTap();
      _movingSelection = false;
      _marqueeing = false;
      if (_isTouch) {
        _panningViewport = true;
        return;
      }
      _marqueeing = true;
      _marqueeStartPage = page;
      _rebuild(() =>
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
    Offset delta,
    JetReportDesignerController controller,
    CanvasViewTransform transform,
  ) {
    if (_panningViewport) {
      // Drag-to-pan: scroll the page with the finger (negated so the content
      // follows the drag, matching the trackpad pan-zoom convention).
      _scrollBy(-delta);
      return;
    }
    final JetOffset page =
        transform.screenToPage(JetOffset(localPosition.dx, localPosition.dy));
    if (_marqueeing && _marqueeStartPage != null) {
      _rebuild(() => _marqueeRect = _rectFromPoints(_marqueeStartPage!, page));
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
    if (_panningViewport) {
      _panningViewport = false;
      return;
    }
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
      _rebuild(() => _marqueeRect = null);
      return;
    }
    if (!_movingSelection) return;
    _movingSelection = false;
    _panStartPage = null;
    controller.commitMove();
  }

}
