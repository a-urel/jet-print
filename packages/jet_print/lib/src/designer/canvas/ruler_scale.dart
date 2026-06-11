/// Pure tick-layout for one ruler strip.
///
/// [RulerScale] turns the canvas's view numbers (where page-0 sits on the strip,
/// how many pixels a millimetre spans, how long the strip is) into an ordered
/// list of [RulerTick]s — labelled "major" ticks at round millimetre values plus
/// finer unlabelled subdivisions. The hard, regression-prone behaviour lives
/// here: alignment exactness, an adaptive "nice-step" labelled interval so labels
/// never crowd or vanish (SC-002/SC-004/FR-010), and a subdivision floor.
///
/// It imports **only `dart:math`** — no Flutter, no domain, no tunables — so it
/// is unit-testable without a widget (Principle III) and carries no view/render
/// coupling (the ladder/divisions/floor are injected by the caller, FR-016).
library;

/// One tick on a ruler strip.
class RulerTick {
  /// Creates a tick at [offsetPx] along the strip. A [label] (non-null only for
  /// a [isMajor] tick) is the formatted millimetre value.
  const RulerTick({
    required this.offsetPx,
    required this.label,
    required this.isMajor,
  });

  /// Pixel offset along the strip (0 = strip start).
  final double offsetPx;

  /// Formatted mm label for a major tick; `null` for a minor subdivision.
  final String? label;

  /// Whether this is a labelled major tick (drawn longer) or a minor one.
  final bool isMajor;

  @override
  String toString() =>
      'RulerTick($offsetPx, ${label ?? '·'}, ${isMajor ? 'major' : 'minor'})';
}

/// Computes the visible [ticks] for one ruler from pure view numbers.
class RulerScale {
  /// Creates a scale and eagerly lays out its [ticks].
  ///
  /// [originPx] is the strip pixel of page-coordinate 0 (`pageOffset −
  /// scrollOffset`; may be negative when the page is scrolled). [pxPerMm] is the
  /// current pixels-per-millimetre (`viewScale · kPointsPerMm`). [lengthPx] is
  /// the strip length. Only ticks inside `[0, lengthPx]` are emitted.
  ///
  /// [minLabelGapPx] is the minimum pixel spacing between labelled ticks;
  /// [stepLadderMm] the ascending "nice number" candidate steps; [minorDivisions]
  /// how many parts a labelled step is divided into; [minMinorGapPx] the pixel
  /// floor below which subdivision is suppressed. [formatLabel] renders a mm
  /// integer to its (locale-aware) label — injected so this type stays
  /// intl/Flutter-free.
  RulerScale({
    required this.originPx,
    required this.pxPerMm,
    required this.lengthPx,
    required this.minLabelGapPx,
    required this.stepLadderMm,
    required this.minorDivisions,
    required this.minMinorGapPx,
    required this.formatLabel,
  });

  /// Strip pixel of page-coordinate 0.
  final double originPx;

  /// Current pixels per millimetre.
  final double pxPerMm;

  /// Strip length, in pixels.
  final double lengthPx;

  /// Minimum pixels between two labelled ticks.
  final double minLabelGapPx;

  /// Ascending nice-number ladder of candidate labelled steps (mm).
  final List<int> stepLadderMm;

  /// How many subdivisions a labelled step is split into.
  final int minorDivisions;

  /// Pixel floor below which minor subdivision is suppressed.
  final double minMinorGapPx;

  /// Renders an integer-millimetre value to its label.
  final String Function(int mm) formatLabel;

  /// The visible ticks, in strictly increasing [RulerTick.offsetPx] order.
  late final List<RulerTick> ticks = _layout();

  /// The chosen labelled interval, in millimetres: the smallest ladder value
  /// whose on-screen spacing clears [minLabelGapPx], clamped to the ladder's
  /// largest entry at an extreme zoom-out.
  int _labelledStepMm() {
    for (final int step in stepLadderMm) {
      if (step * pxPerMm >= minLabelGapPx) return step;
    }
    return stepLadderMm.last;
  }

  List<RulerTick> _layout() {
    if (lengthPx <= 0 || pxPerMm <= 0 || stepLadderMm.isEmpty) {
      return const <RulerTick>[];
    }
    final int stepMm = _labelledStepMm();

    // Subdivide the labelled step, but collapse to majors-only if the minor
    // spacing would fall below the pixel floor (keeps ticks from smearing at
    // extreme zoom).
    final double minorStepMm = stepMm / minorDivisions;
    final int divisions =
        (minorStepMm * pxPerMm >= minMinorGapPx) ? minorDivisions : 1;
    final double tickStepMm = stepMm / divisions;

    // The minor-index range whose ticks land inside [0, lengthPx].
    final double mmAtStart = (0 - originPx) / pxPerMm;
    final double mmAtEnd = (lengthPx - originPx) / pxPerMm;
    final int firstIndex = (mmAtStart / tickStepMm).ceil();
    final int lastIndex = (mmAtEnd / tickStepMm).floor();

    final List<RulerTick> result = <RulerTick>[];
    for (int i = firstIndex; i <= lastIndex; i++) {
      final bool isMajor = i % divisions == 0;
      if (isMajor) {
        // Compute the major from its integer mm so alignment is float-exact.
        final int mm = (i ~/ divisions) * stepMm;
        result.add(RulerTick(
          offsetPx: originPx + mm * pxPerMm,
          label: formatLabel(mm),
          isMajor: true,
        ));
      } else {
        result.add(RulerTick(
          offsetPx: originPx + i * tickStepMm * pxPerMm,
          label: null,
          isMajor: false,
        ));
      }
    }
    return result;
  }
}
