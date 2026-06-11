/// The visual ruler strips: a thin chrome band of tick lines and locale-aware
/// millimetre labels along one canvas edge.
///
/// Design-time chrome only (like the band separators / badges) — drawn directly,
/// never through the shared render pipeline, so it never appears in preview or
/// export (FR-014). All measurement is delegated to the pure [RulerScale]; this
/// file only turns ticks into pixels. Tick *lines* are painted (cheap); the
/// number *labels* are real positioned [Text] widgets, so they pick up the
/// active locale's number formatting and stay findable by widget tests.
library;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'design_tunables.dart';
import 'ruler_scale.dart';

/// Stable key for the horizontal (top) ruler strip (test seam).
const Key kHorizontalRulerKey =
    ValueKey<String>('jet_print.designer.ruler.horizontal');

/// Stable key for the vertical (left) ruler strip (test seam).
const Key kVerticalRulerKey =
    ValueKey<String>('jet_print.designer.ruler.vertical');

/// Stable key for the blank corner box at the rulers' intersection (test seam).
const Key kRulerCornerKey = ValueKey<String>('jet_print.designer.ruler.corner');

/// Which edge a ruler runs along.
enum RulerAxis {
  /// The top ruler — measures the page's horizontal (x) axis.
  horizontal,

  /// The left ruler — measures the page's vertical (y) axis.
  vertical,
}

/// The resolved chrome palette for the ruler strips (sourced from the theme by
/// the canvas, kept here as plain colours so the strip carries no theme import).
class RulerColors {
  /// Creates a ruler palette.
  const RulerColors({
    required this.background,
    required this.tick,
    required this.label,
    required this.border,
  });

  /// Strip fill.
  final Color background;

  /// Tick-line colour.
  final Color tick;

  /// Label-text colour.
  final Color label;

  /// The 1px rule between the strip and the canvas.
  final Color border;
}

/// One ruler strip: a [RulerScale] rendered as tick lines + millimetre labels.
class RulerOverlay extends StatelessWidget {
  /// Creates a ruler for [axis].
  ///
  /// [originPx] is the strip pixel of page-0 (`pageOffset − scrollOffset`),
  /// [pxPerMm] the live pixels-per-mm (`viewScale · kPointsPerMm`), and
  /// [lengthPx] the strip's main-axis length.
  const RulerOverlay({
    required this.axis,
    required this.originPx,
    required this.pxPerMm,
    required this.lengthPx,
    required this.colors,
    super.key,
  });

  /// The edge this ruler runs along.
  final RulerAxis axis;

  /// Strip pixel of page-coordinate 0.
  final double originPx;

  /// Current pixels per millimetre.
  final double pxPerMm;

  /// Strip length, in pixels.
  final double lengthPx;

  /// Resolved chrome palette.
  final RulerColors colors;

  /// Major-tick line length, in px (minor ticks are half).
  static const double _majorTickLength = 7;
  static const double _minorTickLength = 4;
  static const double _labelFontSize = 9;

  bool get _horizontal => axis == RulerAxis.horizontal;

  @override
  Widget build(BuildContext context) {
    // Locale-aware integer label formatting (thousands grouping per locale).
    final NumberFormat fmt =
        NumberFormat.decimalPattern(Localizations.localeOf(context).toString());
    final RulerScale scale = RulerScale(
      originPx: originPx,
      pxPerMm: pxPerMm,
      lengthPx: lengthPx,
      minLabelGapPx: kRulerMinLabelGapPx,
      stepLadderMm: kRulerStepLadderMm,
      minorDivisions: kRulerMinorDivisions,
      minMinorGapPx: kRulerMinMinorGapPx,
      formatLabel: fmt.format,
    );
    final List<RulerTick> ticks = scale.ticks;

    return DecoratedBox(
      key: _horizontal ? kHorizontalRulerKey : kVerticalRulerKey,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          // The rule sits on the edge that touches the canvas.
          bottom: _horizontal
              ? BorderSide(color: colors.border)
              : BorderSide.none,
          right:
              _horizontal ? BorderSide.none : BorderSide(color: colors.border),
        ),
      ),
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: _RulerLinesPainter(
                  axis: axis,
                  ticks: ticks,
                  tickColor: colors.tick,
                ),
              ),
            ),
            for (final RulerTick t in ticks)
              if (t.label case final String label) _label(label, t.offsetPx),
          ],
        ),
      ),
    );
  }

  /// A single numeric label anchored just past its major tick: to the right of
  /// the line on the top ruler, below it (rotated to read upward) on the left.
  Widget _label(String text, double offsetPx) {
    final Widget glyph = Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: colors.label,
        fontSize: _labelFontSize,
        height: 1,
      ),
    );
    if (_horizontal) {
      return Positioned(left: offsetPx + 2, top: 2, child: glyph);
    }
    return Positioned(
      top: offsetPx + 2,
      left: 1,
      child: RotatedBox(quarterTurns: 3, child: glyph),
    );
  }
}

/// A blank box filling the rulers' intersection corner — deliberately empty (no
/// measurement is meaningful there, FR-013).
class RulerCorner extends StatelessWidget {
  /// Creates the corner box with [colors].
  const RulerCorner({required this.colors, super.key});

  /// Resolved chrome palette (uses the same background + border as the strips).
  final RulerColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: kRulerCornerKey,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          bottom: BorderSide(color: colors.border),
          right: BorderSide(color: colors.border),
        ),
      ),
    );
  }
}

/// Paints the tick lines for one strip. Majors are drawn longer than minors; both
/// hang from the edge that touches the canvas (the strip's inner edge).
class _RulerLinesPainter extends CustomPainter {
  const _RulerLinesPainter({
    required this.axis,
    required this.ticks,
    required this.tickColor,
  });

  final RulerAxis axis;
  final List<RulerTick> ticks;
  final Color tickColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = tickColor
      ..strokeWidth = 1;
    final bool horizontal = axis == RulerAxis.horizontal;
    for (final RulerTick t in ticks) {
      final double len = t.isMajor
          ? RulerOverlay._majorTickLength
          : RulerOverlay._minorTickLength;
      if (horizontal) {
        // Inner edge is the bottom; ticks rise from it.
        canvas.drawLine(
          Offset(t.offsetPx, size.height),
          Offset(t.offsetPx, size.height - len),
          paint,
        );
      } else {
        // Inner edge is the right; ticks reach in from it.
        canvas.drawLine(
          Offset(size.width, t.offsetPx),
          Offset(size.width - len, t.offsetPx),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RulerLinesPainter old) =>
      old.axis != axis ||
      old.tickColor != tickColor ||
      !_sameTicks(old.ticks, ticks);

  static bool _sameTicks(List<RulerTick> a, List<RulerTick> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].offsetPx != b[i].offsetPx || a[i].isMajor != b[i].isMajor) {
        return false;
      }
    }
    return true;
  }
}
