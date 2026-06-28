// Page / band-badge / element-region builders for the canvas body.
part of '../design_canvas.dart';

extension _CanvasBuild on _DesignCanvasState {
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
                color: paperFill(dark: dark),
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
                        layout: displayLayout,
                        scale: scale,
                        touchTargets: _isTouch),
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
