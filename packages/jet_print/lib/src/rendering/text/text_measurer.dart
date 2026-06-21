/// The text-measurement seam (spec 006): a headless interface that turns text +
/// style into laid-out **lines**. Backends draw each line as one native run
/// without re-wrapping, so line breaks are identical across backends.
library;

import '../../domain/geometry.dart';
import '../../domain/styles/text_style.dart';

/// VM-consistent double stringification for toString() methods.
///
/// On web (JS), `double.toString()` omits the trailing `.0` for integer-valued
/// doubles. This reproduces the VM output on both platforms.
String _d(double v) {
  if (v.isFinite && v == v.truncateToDouble() && v.abs() < 1e21) {
    return '${v.toStringAsFixed(0)}.0';
  }
  return v.toString();
}

/// Measures text into laid-out lines. Pure Dart — no `dart:ui`.
abstract class TextMeasurer {
  /// Lays out [text] in [style], wrapping at [maxWidth] when non-null.
  MeasuredText measure(String text, JetTextStyle style, {double? maxWidth});
}

/// The result of [TextMeasurer.measure]: laid-out [lines] and the wrapped block
/// [size]. [firstAscent] is the baseline offset of the first line. [fontFamily]
/// is the registry-resolved base family the measurer actually measured with —
/// the painter renders the same family, so measurement and rendering cannot pick
/// different families (006 amendment for 007a).
class MeasuredText {
  /// Creates a measured-text result.
  const MeasuredText({
    required this.lines,
    required this.size,
    required this.firstAscent,
    required this.fontFamily,
  });

  /// The laid-out lines, top to bottom.
  final List<TextLine> lines;

  /// The wrapped block size (max line width × total height), in points.
  final JetSize size;

  /// Baseline offset of the first line from the block top, in points.
  final double firstAscent;

  /// The registry-resolved base font family used for measurement.
  final String fontFamily;
}

/// One laid-out line: literal [text] (whitespace preserved) plus geometry.
class TextLine {
  /// Creates a laid-out line.
  const TextLine({
    required this.text,
    required this.width,
    required this.top,
    required this.baseline,
    required this.height,
  });

  /// The line's literal characters (no whitespace collapse or trim).
  final String text;

  /// Measured advance width, in points.
  final double width;

  /// Line-box top offset from the block top, in points (paragraph-origin
  /// backends, e.g. Canvas, draw here).
  final double top;

  /// Baseline offset from the block top = [top] + lineAscent, in points
  /// (baseline-origin backends, e.g. PDF, draw here).
  final double baseline;

  /// Line-box height, in points.
  final double height;

  @override
  bool operator ==(Object other) =>
      other is TextLine &&
      other.text == text &&
      other.width == width &&
      other.top == top &&
      other.baseline == baseline &&
      other.height == height;

  @override
  int get hashCode => Object.hash(text, width, top, baseline, height);

  @override
  String toString() =>
      'TextLine("$text", w: ${_d(width)}, top: ${_d(top)}, base: ${_d(baseline)})';
}
