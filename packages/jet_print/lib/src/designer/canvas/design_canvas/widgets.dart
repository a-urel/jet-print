// Small canvas widgets: scroll behavior/scrollbar, band badge, empty hint.
part of '../design_canvas.dart';

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
