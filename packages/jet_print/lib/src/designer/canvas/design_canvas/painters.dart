// CustomPainters for the canvas backdrop (grid, band chrome, label grid).
part of '../design_canvas.dart';

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
