# Frame, Text-metrics & Paint backends (Spec 006) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless display-list IR (`PageFrame`), the headless text-measurement seam (`TextMeasurer`/`FontRegistry` over an in-house TTF metrics parser), and the first paint backend (`CanvasPainter`), proven by painting hand-authored frames.

**Architecture:** Three coupled sub-seams under `lib/src/rendering/`: `frame/` (pure-Dart positioned primitives), `text/` (pure-Dart font metrics + line-level measurement), `paint/` (`ReportPainter` abstraction + `CanvasPainter`, the only `dart:ui` file). The `TextMeasurer` owns line-breaking and emits laid-out lines; backends draw a line as one native run without re-wrapping. Design: `docs/superpowers/specs/2026-06-07-frame-text-paint-design.md`.

**Tech Stack:** Dart/Flutter; `dart:typed_data`/`ByteData` for TTF parsing; `dart:ui` (CanvasPainter only); `flutter_test` (incl. `matchesGoldenFile`). No new package dependencies.

---

## Pre-procured assets (already committed on this branch)

The bundled default font is **already in the tree** (commit `build(rendering): procure bundled default font…`) — implementation never touches the network:

- `packages/jet_print/lib/src/rendering/text/fonts/default_font_data.dart` — `final Uint8List kDefaultFontBytes` (Latin subset of Noto Sans Regular, base64-embedded).
- `packages/jet_print/lib/src/rendering/text/fonts/OFL.txt` — SIL OFL 1.1.
- `packages/jet_print/tool/fonts/NotoSans-subset.ttf` — provenance source (23 KB).
- `packages/jet_print/tool/generate_default_font.dart` — regenerator (`dart run tool/generate_default_font.dart`).

**Reference metrics of the bundled font** (used in test assertions below): `unitsPerEm = 1000`; `hhea` ascent/descent/lineGap = `1069 / -293 / 0`; glyph advances (font units): `space=260`, `A=639`, `i=258`, `M=907`, `W=930`, `period=268`. At `fontSize = 10`, `scale = 0.01`, so `lineAscent = 10.69`, `lineHeight = (1069 + 293 + 0)·0.01 = 13.62`, `width('A') = 6.39`, `width('M') = 9.07`, `width(' ') = 2.60`. Floating-point: assert with `closeTo(_, 1e-6)`.

## Shell notes

- Run Dart/Flutter commands from the package dir: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test …`.
- Run **git** with an explicit repo path to avoid CWD drift: `git -C /Users/ahmeturel/Projects/oss/jet-print …`.
- After each task: `cd packages/jet_print && dart format . && flutter analyze` must be clean before committing.

## File structure

| File | Responsibility |
|---|---|
| `lib/src/rendering/text/text_measurer.dart` | `TextMeasurer` interface + `MeasuredText` + `TextLine` value types |
| `lib/src/rendering/frame/primitive.dart` | sealed `FramePrimitive` + 5 variants + `PathCommand` |
| `lib/src/rendering/frame/page_frame.dart` | immutable `PageFrame` (primitives + `PageFormat`) |
| `lib/src/rendering/frame/frame_builder.dart` | `FrameBuilder` write-side → `PageFrame` |
| `lib/src/rendering/text/font_metrics.dart` | `FontMetrics` (scaled-by-caller font-unit metrics + cmap/advances) |
| `lib/src/rendering/text/font_format_exception.dart` | `FontFormatException` |
| `lib/src/rendering/text/ttf/ttf_metrics.dart` | `parseTtfMetrics(Uint8List) → FontMetrics` |
| `lib/src/rendering/text/font_registry.dart` | `FontRegistry` (byte-keyed; `registerDefault`) |
| `lib/src/rendering/text/metrics_text_measurer.dart` | default measurer (advances, wrap, geometry) |
| `lib/src/rendering/paint/report_painter.dart` | `ReportPainter` abstraction + `paintFrame` walk |
| `lib/src/rendering/paint/canvas_painter.dart` | `CanvasPainter` (`dart:ui`) |
| `test/rendering/**` | white-box tests (allowlisted for `src/` imports) |

**Remove in Task 11:** `lib/src/domain/domain.dart`, `lib/src/rendering/rendering.dart`, `test/domain/domain_test.dart`, `test/rendering/rendering_test.dart`.

---

### Task 1: Text contract types (`TextMeasurer` / `MeasuredText` / `TextLine`)

**Files:**
- Create: `lib/src/rendering/text/text_measurer.dart`
- Test: `test/rendering/text/text_measurer_types_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/text/text_measurer_types_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  test('TextLine has value equality and a readable toString', () {
    const TextLine a =
        TextLine(text: 'Hi', width: 6.39, top: 0, baseline: 10.69, height: 13.62);
    const TextLine b =
        TextLine(text: 'Hi', width: 6.39, top: 0, baseline: 10.69, height: 13.62);
    const TextLine c =
        TextLine(text: 'Ho', width: 6.39, top: 0, baseline: 10.69, height: 13.62);
    expect(a, b);
    expect(a, isNot(c));
    expect(a.toString(), 'TextLine("Hi", w: 6.39, top: 0.0, base: 10.69)');
  });

  test('MeasuredText carries lines, size, and firstAscent', () {
    const TextLine l =
        TextLine(text: 'A', width: 6.39, top: 0, baseline: 10.69, height: 13.62);
    const MeasuredText m = MeasuredText(
        lines: <TextLine>[l], size: JetSize(6.39, 13.62), firstAscent: 10.69);
    expect(m.lines.single, l);
    expect(m.size, const JetSize(6.39, 13.62));
    expect(m.firstAscent, 10.69);
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`text_measurer.dart` missing).

Run: `cd packages/jet_print && flutter test test/rendering/text/text_measurer_types_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Implement**

```dart
// lib/src/rendering/text/text_measurer.dart
/// The text-measurement seam (spec 006): a headless interface that turns text +
/// style into laid-out **lines**. Backends draw each line as one native run
/// without re-wrapping, so line breaks are identical across backends.
library;

import '../../domain/geometry.dart';
import '../../domain/styles/text_style.dart';

/// Measures text into laid-out lines. Pure Dart — no `dart:ui`.
abstract class TextMeasurer {
  /// Lays out [text] in [style], wrapping at [maxWidth] when non-null.
  MeasuredText measure(String text, JetTextStyle style, {double? maxWidth});
}

/// The result of [TextMeasurer.measure]: laid-out [lines] and the wrapped block
/// [size]. [firstAscent] is the baseline offset of the first line.
class MeasuredText {
  /// Creates a measured-text result.
  const MeasuredText({
    required this.lines,
    required this.size,
    required this.firstAscent,
  });

  /// The laid-out lines, top to bottom.
  final List<TextLine> lines;

  /// The wrapped block size (max line width × total height), in points.
  final JetSize size;

  /// Baseline offset of the first line from the block top, in points.
  final double firstAscent;
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
  String toString() => 'TextLine("$text", w: $width, top: $top, base: $baseline)';
}
```

- [ ] **Step 4: Run — expect PASS.** `flutter test test/rendering/text/text_measurer_types_test.dart`

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/rendering/text/text_measurer.dart packages/jet_print/test/rendering/text/text_measurer_types_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(rendering): TextMeasurer interface + MeasuredText/TextLine (006)"
```

---

### Task 2: Frame primitives (sealed `FramePrimitive` + variants + `PathCommand`)

**Files:**
- Create: `lib/src/rendering/frame/primitive.dart`
- Test: `test/rendering/frame/primitive_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/frame/primitive_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  test('primitives are value-equal and carry an optional elementId', () {
    const TextLine line =
        TextLine(text: 'Hi', width: 6.0, top: 0, baseline: 10, height: 13);
    final TextRunPrimitive a = TextRunPrimitive(
      bounds: const JetRect(x: 1, y: 2, width: 30, height: 13),
      lines: const <TextLine>[line],
      style: JetTextStyle.fallback,
      fontFamily: 'JetSans',
      elementId: 'e1',
    );
    final TextRunPrimitive b = TextRunPrimitive(
      bounds: const JetRect(x: 1, y: 2, width: 30, height: 13),
      lines: const <TextLine>[line],
      style: JetTextStyle.fallback,
      fontFamily: 'JetSans',
      elementId: 'e1',
    );
    expect(a, b);
    expect(a.elementId, 'e1');
  });

  test('rect/line/path primitives compare by value', () {
    const RectPrimitive r1 = RectPrimitive(
        bounds: JetRect(x: 0, y: 0, width: 10, height: 4),
        fill: JetColor(0xFF112233));
    const RectPrimitive r2 = RectPrimitive(
        bounds: JetRect(x: 0, y: 0, width: 10, height: 4),
        fill: JetColor(0xFF112233));
    expect(r1, r2);

    const PathPrimitive p1 = PathPrimitive(
      bounds: JetRect(x: 0, y: 0, width: 5, height: 5),
      commands: <PathCommand>[MoveTo(JetOffset(0, 0)), LineTo(JetOffset(5, 5)), ClosePath()],
      stroke: JetColor.black,
    );
    const PathPrimitive p2 = PathPrimitive(
      bounds: JetRect(x: 0, y: 0, width: 5, height: 5),
      commands: <PathCommand>[MoveTo(JetOffset(0, 0)), LineTo(JetOffset(5, 5)), ClosePath()],
      stroke: JetColor.black,
    );
    expect(p1, p2);
  });

  test('image primitive compares its bytes by value', () {
    final ImagePrimitive i1 = ImagePrimitive(
        bounds: const JetRect(x: 0, y: 0, width: 8, height: 8),
        bytes: Uint8List.fromList(<int>[1, 2, 3]));
    final ImagePrimitive i2 = ImagePrimitive(
        bounds: const JetRect(x: 0, y: 0, width: 8, height: 8),
        bytes: Uint8List.fromList(<int>[1, 2, 3]));
    expect(i1, i2);
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`primitive.dart` missing).

- [ ] **Step 3: Implement**

```dart
// lib/src/rendering/frame/primitive.dart
/// Positioned display-list primitives (spec 006): the WYSIWYG contract between
/// layout and paint. Pure-Dart geometry; each primitive carries its originating
/// element id for designer hit-testing.
library;

import 'dart:typed_data';

import '../../domain/elements/image_source.dart';
import '../../domain/geometry.dart';
import '../../domain/styles/color.dart';
import '../../domain/styles/text_style.dart';
import '../text/text_measurer.dart';

/// A single positioned primitive on a page.
sealed class FramePrimitive {
  /// Creates a primitive bounded by [bounds] (page points), optionally tagged
  /// with the originating [elementId].
  const FramePrimitive({required this.bounds, this.elementId});

  /// Position and size, in page points.
  final JetRect bounds;

  /// The originating element's id, or null (e.g. chrome).
  final String? elementId;
}

/// Pre-broken text: the measurer's [lines] drawn without re-wrapping.
final class TextRunPrimitive extends FramePrimitive {
  /// Creates a text run.
  const TextRunPrimitive({
    required super.bounds,
    required this.lines,
    required this.style,
    required this.fontFamily,
    super.elementId,
  });

  /// Laid-out lines (the painter never re-wraps these).
  final List<TextLine> lines;

  /// Text appearance (color/size/weight/italic/align).
  final JetTextStyle style;

  /// The resolved font family the painter must render with.
  final String fontFamily;

  @override
  bool operator ==(Object other) =>
      other is TextRunPrimitive &&
      other.bounds == bounds &&
      other.elementId == elementId &&
      other.style == style &&
      other.fontFamily == fontFamily &&
      _listEquals(other.lines, lines);

  @override
  int get hashCode =>
      Object.hash(bounds, elementId, style, fontFamily, Object.hashAll(lines));

  @override
  String toString() =>
      'TextRunPrimitive($bounds, lines: ${lines.length}, "$fontFamily")';
}

/// A raster image; [bytes] are encoded (PNG/JPEG), decoded by the painter.
final class ImagePrimitive extends FramePrimitive {
  /// Creates an image primitive.
  const ImagePrimitive({
    required super.bounds,
    required this.bytes,
    this.fit = JetBoxFit.contain,
    super.elementId,
  });

  /// Encoded image bytes.
  final Uint8List bytes;

  /// How the image fills [bounds].
  final JetBoxFit fit;

  @override
  bool operator ==(Object other) {
    if (other is! ImagePrimitive ||
        other.bounds != bounds ||
        other.elementId != elementId ||
        other.fit != fit ||
        other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(bounds, elementId, fit, Object.hashAll(bytes));

  @override
  String toString() => 'ImagePrimitive($bounds, ${bytes.length}B, $fit)';
}

/// A straight stroked line from [start] to [end].
final class LinePrimitive extends FramePrimitive {
  /// Creates a line primitive.
  const LinePrimitive({
    required super.bounds,
    required this.start,
    required this.end,
    required this.color,
    this.strokeWidth = 1.0,
    super.elementId,
  });

  /// Start point, in page points.
  final JetOffset start;

  /// End point, in page points.
  final JetOffset end;

  /// Stroke color.
  final JetColor color;

  /// Stroke width, in points.
  final double strokeWidth;

  @override
  bool operator ==(Object other) =>
      other is LinePrimitive &&
      other.bounds == bounds &&
      other.elementId == elementId &&
      other.start == start &&
      other.end == end &&
      other.color == color &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode =>
      Object.hash(bounds, elementId, start, end, color, strokeWidth);

  @override
  String toString() => 'LinePrimitive($start -> $end, $color)';
}

/// A rectangle with optional [fill] and/or [stroke].
final class RectPrimitive extends FramePrimitive {
  /// Creates a rectangle primitive.
  const RectPrimitive({
    required super.bounds,
    this.fill,
    this.stroke,
    this.strokeWidth = 1.0,
    super.elementId,
  });

  /// Fill color, or null for no fill.
  final JetColor? fill;

  /// Stroke color, or null for no stroke.
  final JetColor? stroke;

  /// Stroke width, in points.
  final double strokeWidth;

  @override
  bool operator ==(Object other) =>
      other is RectPrimitive &&
      other.bounds == bounds &&
      other.elementId == elementId &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode =>
      Object.hash(bounds, elementId, fill, stroke, strokeWidth);

  @override
  String toString() => 'RectPrimitive($bounds, fill: $fill, stroke: $stroke)';
}

/// A polyline/polygon path with optional [fill] and/or [stroke].
final class PathPrimitive extends FramePrimitive {
  /// Creates a path primitive.
  const PathPrimitive({
    required super.bounds,
    required this.commands,
    this.fill,
    this.stroke,
    this.strokeWidth = 1.0,
    super.elementId,
  });

  /// The path commands, in order.
  final List<PathCommand> commands;

  /// Fill color, or null.
  final JetColor? fill;

  /// Stroke color, or null.
  final JetColor? stroke;

  /// Stroke width, in points.
  final double strokeWidth;

  @override
  bool operator ==(Object other) =>
      other is PathPrimitive &&
      other.bounds == bounds &&
      other.elementId == elementId &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.strokeWidth == strokeWidth &&
      _listEquals(other.commands, commands);

  @override
  int get hashCode => Object.hash(
      bounds, elementId, fill, stroke, strokeWidth, Object.hashAll(commands));

  @override
  String toString() => 'PathPrimitive($bounds, ${commands.length} cmds)';
}

/// A single path instruction.
sealed class PathCommand {
  /// Const base constructor.
  const PathCommand();
}

/// Move the pen to [to] without drawing.
final class MoveTo extends PathCommand {
  /// Creates a move command.
  const MoveTo(this.to);

  /// Target point.
  final JetOffset to;

  @override
  bool operator ==(Object other) => other is MoveTo && other.to == to;

  @override
  int get hashCode => Object.hash('MoveTo', to);

  @override
  String toString() => 'MoveTo($to)';
}

/// Draw a line to [to].
final class LineTo extends PathCommand {
  /// Creates a line command.
  const LineTo(this.to);

  /// Target point.
  final JetOffset to;

  @override
  bool operator ==(Object other) => other is LineTo && other.to == to;

  @override
  int get hashCode => Object.hash('LineTo', to);

  @override
  String toString() => 'LineTo($to)';
}

/// Close the current sub-path.
final class ClosePath extends PathCommand {
  /// Creates a close command.
  const ClosePath();

  @override
  bool operator ==(Object other) => other is ClosePath;

  @override
  int get hashCode => 'ClosePath'.hashCode;

  @override
  String toString() => 'ClosePath()';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

- [ ] **Step 4: Run — expect PASS.** `flutter test test/rendering/frame/primitive_test.dart`

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/rendering/frame/primitive.dart packages/jet_print/test/rendering/frame/primitive_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(rendering): sealed FramePrimitive variants + PathCommand (006)"
```

---

### Task 3: `PageFrame` + `FrameBuilder`

**Files:**
- Create: `lib/src/rendering/frame/page_frame.dart`, `lib/src/rendering/frame/frame_builder.dart`
- Test: `test/rendering/frame/frame_builder_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/frame/frame_builder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

void main() {
  const RectPrimitive rect = RectPrimitive(
      bounds: JetRect(x: 0, y: 0, width: 10, height: 4), fill: JetColor.black);

  test('FrameBuilder accumulates primitives into an immutable PageFrame', () {
    final FrameBuilder b = FrameBuilder(PageFormat.a4Portrait)..add(rect);
    final PageFrame frame = b.build();
    expect(frame.page, PageFormat.a4Portrait);
    expect(frame.primitives, <Object>[rect]);
    expect(() => frame.primitives.add(rect), throwsUnsupportedError);
  });

  test('PageFrame is value-equal over page + primitives', () {
    final PageFrame a = (FrameBuilder(PageFormat.a4Portrait)..add(rect)).build();
    final PageFrame b = (FrameBuilder(PageFormat.a4Portrait)..add(rect)).build();
    expect(a, b);
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

```dart
// lib/src/rendering/frame/page_frame.dart
/// A painted page's display list (spec 006): a flat, immutable list of
/// positioned primitives plus the page geometry. The WYSIWYG hand-off to paint.
library;

import '../../domain/page_format.dart';
import 'primitive.dart';

/// An immutable page frame: [primitives] positioned on [page].
class PageFrame {
  /// Creates a page frame; [primitives] is copied into an unmodifiable list.
  PageFrame({required this.page, required List<FramePrimitive> primitives})
      : primitives = List<FramePrimitive>.unmodifiable(primitives);

  /// The physical page.
  final PageFormat page;

  /// The positioned primitives, in paint order.
  final List<FramePrimitive> primitives;

  @override
  bool operator ==(Object other) {
    if (other is! PageFrame ||
        other.page != page ||
        other.primitives.length != primitives.length) {
      return false;
    }
    for (var i = 0; i < primitives.length; i++) {
      if (other.primitives[i] != primitives[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(page, Object.hashAll(primitives));

  @override
  String toString() => 'PageFrame(${primitives.length} primitives)';
}
```

```dart
// lib/src/rendering/frame/frame_builder.dart
/// Write-side builder for a [PageFrame] (spec 006): renderers append primitives,
/// then [build] snapshots them into an immutable frame.
library;

import '../../domain/page_format.dart';
import 'page_frame.dart';
import 'primitive.dart';

/// Accumulates [FramePrimitive]s for one [page].
class FrameBuilder {
  /// Creates a builder for [page].
  FrameBuilder(this.page);

  /// The page being built.
  final PageFormat page;

  final List<FramePrimitive> _primitives = <FramePrimitive>[];

  /// Appends [primitive] in paint order.
  void add(FramePrimitive primitive) => _primitives.add(primitive);

  /// Snapshots the accumulated primitives into an immutable [PageFrame].
  PageFrame build() => PageFrame(page: page, primitives: _primitives);
}
```

- [ ] **Step 4: Run — expect PASS.** `flutter test test/rendering/frame/frame_builder_test.dart`

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/rendering/frame/page_frame.dart packages/jet_print/lib/src/rendering/frame/frame_builder.dart packages/jet_print/test/rendering/frame/frame_builder_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(rendering): PageFrame + FrameBuilder (006)"
```

---

### Task 4: `FontMetrics` + `FontFormatException`

**Files:**
- Create: `lib/src/rendering/text/font_metrics.dart`, `lib/src/rendering/text/font_format_exception.dart`
- Test: `test/rendering/text/font_metrics_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/text/font_metrics_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/text/font_format_exception.dart';
import 'package:jet_print/src/rendering/text/font_metrics.dart';

void main() {
  const FontMetrics m = FontMetrics(
    unitsPerEm: 1000,
    ascent: 1069,
    descent: -293,
    lineGap: 0,
    cmap: <int, int>{0x41: 34},
    advanceWidths: <int>[0, 260, 639],
    defaultAdvance: 0,
  );

  test('maps codepoints to glyphs; unmapped -> 0 (.notdef)', () {
    expect(m.glyphForCodepoint(0x41), 34);
    expect(m.glyphForCodepoint(0x5A), 0);
  });

  test('returns advances; out-of-range -> defaultAdvance', () {
    expect(m.advanceForGlyph(2), 639);
    expect(m.advanceForGlyph(99), 0);
  });

  test('FontFormatException carries a message', () {
    expect(const FontFormatException('bad').toString(),
        contains('bad'));
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

```dart
// lib/src/rendering/text/font_format_exception.dart
/// Thrown when font bytes cannot be parsed (spec 006). Structural — fail fast.
library;

/// A malformed or unsupported font file.
class FontFormatException implements Exception {
  /// Creates the exception with a human-readable [message].
  const FontFormatException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'FontFormatException: $message';
}
```

```dart
// lib/src/rendering/text/font_metrics.dart
/// Parsed, scale-free font metrics (spec 006): values are in font units; callers
/// scale by `fontSize / unitsPerEm`.
library;

/// Glyph metrics needed for measurement: advances + a codepoint→glyph map.
class FontMetrics {
  /// Creates font metrics (all linear values in font units).
  const FontMetrics({
    required this.unitsPerEm,
    required this.ascent,
    required this.descent,
    required this.lineGap,
    required Map<int, int> cmap,
    required List<int> advanceWidths,
    required this.defaultAdvance,
  })  : _cmap = cmap,
        _advanceWidths = advanceWidths;

  /// Font design units per em (the scale denominator).
  final int unitsPerEm;

  /// Ascender (font units, typically positive).
  final double ascent;

  /// Descender (font units, typically negative).
  final double descent;

  /// Recommended extra line gap (font units).
  final double lineGap;

  final Map<int, int> _cmap;
  final List<int> _advanceWidths;

  /// Advance used for glyphs outside [advanceWidths].
  final int defaultAdvance;

  /// Glyph id for [codepoint]; 0 (.notdef) when unmapped.
  int glyphForCodepoint(int codepoint) => _cmap[codepoint] ?? 0;

  /// Advance width (font units) for [glyphId]; [defaultAdvance] if out of range.
  int advanceForGlyph(int glyphId) =>
      (glyphId >= 0 && glyphId < _advanceWidths.length)
          ? _advanceWidths[glyphId]
          : defaultAdvance;
}
```

- [ ] **Step 4: Run — expect PASS.** `flutter test test/rendering/text/font_metrics_test.dart`

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/rendering/text/font_metrics.dart packages/jet_print/lib/src/rendering/text/font_format_exception.dart packages/jet_print/test/rendering/text/font_metrics_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(rendering): FontMetrics + FontFormatException (006)"
```

---

### Task 5: TTF metrics parser (`parseTtfMetrics`)

**Files:**
- Create: `lib/src/rendering/text/ttf/ttf_metrics.dart`
- Test: `test/rendering/text/ttf_metrics_test.dart`

Note: the test loads the **committed subset TTF** from `tool/fonts/NotoSans-subset.ttf` via `dart:io` (works under `flutter test`), and asserts the reference metrics from the plan header.

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/text/ttf_metrics_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/text/font_format_exception.dart';
import 'package:jet_print/src/rendering/text/font_metrics.dart';
import 'package:jet_print/src/rendering/text/ttf/ttf_metrics.dart';

import '../../support/workspace.dart';

void main() {
  final Directory root = findWorkspaceRoot();
  final Uint8List bytes = File(
    '${root.path}/packages/jet_print/tool/fonts/NotoSans-subset.ttf',
  ).readAsBytesSync();

  test('parses head/hhea/hmtx/cmap of the bundled subset font', () {
    final FontMetrics m = parseTtfMetrics(bytes);
    expect(m.unitsPerEm, 1000);
    expect(m.ascent, 1069);
    expect(m.descent, -293);
    expect(m.lineGap, 0);
    // cmap maps Latin + Turkish; advances match the known values (font units).
    expect(m.advanceForGlyph(m.glyphForCodepoint(0x20)), 260); // space
    expect(m.advanceForGlyph(m.glyphForCodepoint(0x41)), 639); // A
    expect(m.advanceForGlyph(m.glyphForCodepoint(0x4D)), 907); // M
    expect(m.advanceForGlyph(m.glyphForCodepoint(0x2E)), 268); // period
    expect(m.glyphForCodepoint(0x015F), isNonZero); // 'ş' present
    expect(m.glyphForCodepoint(0xFFFF), 0); // unmapped -> .notdef
  });

  test('throws FontFormatException on truncated bytes', () {
    expect(() => parseTtfMetrics(Uint8List.fromList(<int>[0, 1, 0, 0])),
        throwsA(isA<FontFormatException>()));
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`ttf_metrics.dart` missing).

- [ ] **Step 3: Implement**

```dart
// lib/src/rendering/text/ttf/ttf_metrics.dart
/// In-house TTF/OTF **metrics** parser (spec 006): reads head/hhea/maxp/hmtx/cmap
/// only (no glyf/outlines). Pure Dart via [ByteData]. Deterministic.
library;

import 'dart:typed_data';

import '../font_format_exception.dart';
import '../font_metrics.dart';

/// Parses the metric tables of [bytes]. Throws [FontFormatException] on a
/// malformed or unsupported font.
FontMetrics parseTtfMetrics(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const FontFormatException('Too short for an offset table.');
  }
  final ByteData d = ByteData.sublistView(bytes);
  final int numTables = d.getUint16(4);

  final Map<String, int> tableOffset = <String, int>{};
  var p = 12;
  for (var i = 0; i < numTables; i++) {
    if (p + 16 > bytes.length) {
      throw const FontFormatException('Truncated table directory.');
    }
    final String tag = String.fromCharCodes(bytes, p, p + 4);
    tableOffset[tag] = d.getUint32(p + 8);
    p += 16;
  }

  int require(String tag) {
    final int? off = tableOffset[tag];
    if (off == null) {
      throw FontFormatException('Missing required "$tag" table.');
    }
    return off;
  }

  // head: unitsPerEm @ +18.
  final int head = require('head');
  final int unitsPerEm = d.getUint16(head + 18);
  if (unitsPerEm == 0) {
    throw const FontFormatException('Invalid unitsPerEm (0).');
  }

  // hhea: ascender @ +4, descender @ +6, lineGap @ +8, numberOfHMetrics @ +34.
  final int hhea = require('hhea');
  final double ascent = d.getInt16(hhea + 4).toDouble();
  final double descent = d.getInt16(hhea + 6).toDouble();
  final double lineGap = d.getInt16(hhea + 8).toDouble();
  final int numberOfHMetrics = d.getUint16(hhea + 34);

  // maxp: numGlyphs @ +4.
  final int numGlyphs = d.getUint16(require('maxp') + 4);

  // hmtx: numberOfHMetrics longHorMetric records (advanceWidth u16, lsb i16).
  final int hmtx = require('hmtx');
  final List<int> advances = List<int>.filled(numGlyphs, 0);
  var lastAdvance = 0;
  for (var g = 0; g < numGlyphs; g++) {
    if (g < numberOfHMetrics) {
      lastAdvance = d.getUint16(hmtx + g * 4);
    }
    advances[g] = lastAdvance; // glyphs past the last record reuse its advance
  }

  // cmap: pick the best Unicode BMP subtable.
  final int cmap = require('cmap');
  final int subCount = d.getUint16(cmap + 2);
  var bestOffset = -1;
  var bestScore = -1;
  var q = cmap + 4;
  for (var i = 0; i < subCount; i++) {
    final int plat = d.getUint16(q);
    final int enc = d.getUint16(q + 2);
    final int off = d.getUint32(q + 4);
    final int score = (plat == 3 && enc == 1)
        ? 3
        : (plat == 0)
            ? 2
            : (plat == 3 && enc == 0)
                ? 1
                : 0;
    if (score > bestScore) {
      bestScore = score;
      bestOffset = cmap + off;
    }
    q += 8;
  }
  if (bestOffset < 0) {
    throw const FontFormatException('No usable cmap subtable.');
  }

  return FontMetrics(
    unitsPerEm: unitsPerEm,
    ascent: ascent,
    descent: descent,
    lineGap: lineGap,
    cmap: _parseCmap(d, bestOffset),
    advanceWidths: advances,
    defaultAdvance: advances.isNotEmpty ? advances[0] : 0,
  );
}

Map<int, int> _parseCmap(ByteData d, int o) {
  final int format = d.getUint16(o);
  switch (format) {
    case 4:
      return _parseCmapFormat4(d, o);
    case 6:
      final int first = d.getUint16(o + 6);
      final int count = d.getUint16(o + 8);
      return <int, int>{
        for (var i = 0; i < count; i++) first + i: d.getUint16(o + 10 + i * 2),
      };
    case 0:
      return <int, int>{
        for (var c = 0; c < 256; c++) c: d.getUint8(o + 6 + c),
      };
    default:
      throw FontFormatException('Unsupported cmap format $format.');
  }
}

Map<int, int> _parseCmapFormat4(ByteData d, int o) {
  final int segX2 = d.getUint16(o + 6);
  final int segCount = segX2 ~/ 2;
  final int endBase = o + 14;
  final int startBase = endBase + segX2 + 2; // +2 reservedPad
  final int deltaBase = startBase + segX2;
  final int rangeBase = deltaBase + segX2;

  final Map<int, int> map = <int, int>{};
  for (var s = 0; s < segCount; s++) {
    final int end = d.getUint16(endBase + s * 2);
    final int start = d.getUint16(startBase + s * 2);
    final int delta = d.getUint16(deltaBase + s * 2);
    final int rangeOffset = d.getUint16(rangeBase + s * 2);
    if (start == 0xFFFF) continue;
    for (var c = start; c <= end; c++) {
      int g;
      if (rangeOffset == 0) {
        g = (c + delta) & 0xFFFF;
      } else {
        final int gi = rangeBase + s * 2 + rangeOffset + (c - start) * 2;
        g = d.getUint16(gi);
        if (g != 0) g = (g + delta) & 0xFFFF;
      }
      if (g != 0) map[c] = g;
    }
  }
  return map;
}
```

- [ ] **Step 4: Run — expect PASS.** `flutter test test/rendering/text/ttf_metrics_test.dart`

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/rendering/text/ttf/ttf_metrics.dart packages/jet_print/test/rendering/text/ttf_metrics_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(rendering): in-house TTF metrics parser (006)"
```

---

### Task 6: `FontRegistry`

**Files:**
- Create: `lib/src/rendering/text/font_registry.dart`
- Test: `test/rendering/text/font_registry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/text/font_registry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';

void main() {
  test('registerDefault wires the bundled font; metrics resolve', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    expect(reg.hasDefault, isTrue);
    final m = reg.metricsFor(null);
    expect(m.unitsPerEm, 1000);
    expect(m.advanceForGlyph(m.glyphForCodepoint(0x41)), 639); // 'A'
    expect(reg.bytesFor(null).isNotEmpty, isTrue);
  });

  test('unknown family falls back to the default', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    expect(reg.resolveFamily('Nope'), FontRegistry.defaultFamily);
    expect(reg.metricsFor('Nope').unitsPerEm, 1000);
  });

  test('a registered family resolves to itself', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final bytes = reg.bytesFor(null);
    reg.register('Body', bytes);
    expect(reg.resolveFamily('Body'), 'Body');
  });

  test('no default and no match throws StateError', () {
    expect(() => FontRegistry().metricsFor('x'), throwsStateError);
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

```dart
// lib/src/rendering/text/font_registry.dart
/// Holds registered font bytes keyed by family/weight/italic (spec 006). The
/// bundled default is just a pre-registered entry; the SAME bytes drive
/// measurement (parsed to [FontMetrics]) and painting (loaded by backends).
library;

import 'dart:typed_data';

import '../../domain/styles/text_style.dart';
import 'font_metrics.dart';
import 'fonts/default_font_data.dart';
import 'ttf/ttf_metrics.dart';

/// A registry of font variants. Byte-oriented and headless.
class FontRegistry {
  final Map<String, _FontEntry> _entries = <String, _FontEntry>{};

  /// The family the bundled default registers under.
  static const String defaultFamily = 'JetSans';

  /// Registers [bytes] for [family]/[weight]/[italic], parsing its metrics now.
  void register(
    String family,
    Uint8List bytes, {
    JetFontWeight weight = JetFontWeight.normal,
    bool italic = false,
  }) {
    _entries[_key(family, weight, italic)] =
        _FontEntry(bytes, parseTtfMetrics(bytes));
  }

  /// Registers the bundled default under [defaultFamily]. Pass [bytes] to
  /// override (e.g. tests); otherwise the embedded font is used.
  void registerDefault({Uint8List? bytes}) =>
      register(defaultFamily, bytes ?? kDefaultFontBytes);

  /// Whether the default font has been registered.
  bool get hasDefault =>
      _entries.containsKey(_key(defaultFamily, JetFontWeight.normal, false));

  /// Metrics for the resolved variant (falls back to the default).
  FontMetrics metricsFor(
    String? family, {
    JetFontWeight weight = JetFontWeight.normal,
    bool italic = false,
  }) =>
      _resolve(family, weight, italic).metrics;

  /// Raw bytes for the resolved variant (for backends to embed/load).
  Uint8List bytesFor(
    String? family, {
    JetFontWeight weight = JetFontWeight.normal,
    bool italic = false,
  }) =>
      _resolve(family, weight, italic).bytes;

  /// The family name a backend should render with after fallback.
  String resolveFamily(
    String? family, {
    JetFontWeight weight = JetFontWeight.normal,
    bool italic = false,
  }) {
    if (family != null &&
        (_entries.containsKey(_key(family, weight, italic)) ||
            _entries.containsKey(_key(family, weight, false)) ||
            _entries.containsKey(_key(family, JetFontWeight.normal, false)))) {
      return family;
    }
    return defaultFamily;
  }

  _FontEntry _resolve(String? family, JetFontWeight weight, bool italic) {
    final String fam = family ?? defaultFamily;
    final _FontEntry? entry = _entries[_key(fam, weight, italic)] ??
        _entries[_key(fam, weight, false)] ??
        _entries[_key(fam, JetFontWeight.normal, false)] ??
        _entries[_key(defaultFamily, JetFontWeight.normal, false)];
    if (entry == null) {
      throw StateError(
          'No font registered for "$fam" and no default; call registerDefault().');
    }
    return entry;
  }

  static String _key(String family, JetFontWeight weight, bool italic) =>
      '$family|${weight.name}|$italic';
}

class _FontEntry {
  _FontEntry(this.bytes, this.metrics);
  final Uint8List bytes;
  final FontMetrics metrics;
}
```

- [ ] **Step 4: Run — expect PASS.** `flutter test test/rendering/text/font_registry_test.dart`

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/rendering/text/font_registry.dart packages/jet_print/test/rendering/text/font_registry_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(rendering): byte-keyed FontRegistry with bundled default (006)"
```

---

### Task 7: `MetricsTextMeasurer` (advances · wrap · geometry)

**Files:**
- Create: `lib/src/rendering/text/metrics_text_measurer.dart`
- Test: `test/rendering/text/metrics_text_measurer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/text/metrics_text_measurer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  final FontRegistry reg = FontRegistry()..registerDefault();
  final MetricsTextMeasurer measurer = MetricsTextMeasurer(reg);
  const JetTextStyle s10 = JetTextStyle(fontSize: 10);

  test('single line: advance, ascent, line height, size', () {
    final MeasuredText m = measurer.measure('A', s10);
    expect(m.lines, hasLength(1));
    final TextLine l = m.lines.single;
    expect(l.text, 'A');
    expect(l.width, closeTo(6.39, 1e-6)); // 639 * 0.01
    expect(l.top, 0);
    expect(l.baseline, closeTo(10.69, 1e-6)); // 1069 * 0.01
    expect(l.height, closeTo(13.62, 1e-6)); // (1069 + 293) * 0.01
    expect(m.size.width, closeTo(6.39, 1e-6));
    expect(m.size.height, closeTo(13.62, 1e-6));
    expect(m.firstAscent, closeTo(10.69, 1e-6));
  });

  test('hard breaks: each \\n starts a new line; blank lines preserved', () {
    final MeasuredText m = measurer.measure('A\n\nM', s10);
    expect(m.lines.map((TextLine l) => l.text).toList(), <String>['A', '', 'M']);
    expect(m.lines[1].width, 0); // blank middle line, full line height
    expect(m.lines[1].top, closeTo(13.62, 1e-6));
    expect(m.lines[2].baseline, closeTo(2 * 13.62 + 10.69, 1e-6));
    expect(m.size.height, closeTo(3 * 13.62, 1e-6));
  });

  test('empty string -> one empty line of full height', () {
    final MeasuredText m = measurer.measure('', s10);
    expect(m.lines.single.text, '');
    expect(m.size.height, closeTo(13.62, 1e-6));
  });

  test('greedy wrap preserves literal whitespace at the break', () {
    // 'M M M' at maxWidth 25: 'M M ' (23.34) fits; adding 'M' (32.41) overflows.
    final MeasuredText m = measurer.measure('M M M', s10, maxWidth: 25);
    expect(m.lines.map((TextLine l) => l.text).toList(), <String>['M M ', 'M']);
    expect(m.lines.first.width, closeTo(23.34, 1e-6)); // 9.07+2.60+9.07+2.60
  });

  test('runs of spaces and leading whitespace are not collapsed', () {
    final MeasuredText m = measurer.measure('  A', s10); // no maxWidth
    expect(m.lines.single.text, '  A');
    expect(m.lines.single.width, closeTo(2 * 2.60 + 6.39, 1e-6));
  });

  test('a tab is measured as a single space', () {
    final MeasuredText tab = measurer.measure('A\tA', s10);
    final MeasuredText spc = measurer.measure('A A', s10);
    expect(tab.lines.single.width, closeTo(spc.lines.single.width, 1e-6));
  });

  test('a word wider than maxWidth gets its own overflowing line', () {
    final MeasuredText m = measurer.measure('MMMM', s10, maxWidth: 5);
    expect(m.lines, hasLength(1));
    expect(m.lines.single.width, closeTo(4 * 9.07, 1e-6));
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

```dart
// lib/src/rendering/text/metrics_text_measurer.dart
/// Default [TextMeasurer] (spec 006): measures glyph advances via [FontMetrics],
/// greedily word-wraps while preserving literal whitespace, and lays out lines.
library;

import '../../domain/geometry.dart';
import '../../domain/styles/text_style.dart';
import 'font_metrics.dart';
import 'font_registry.dart';
import 'text_measurer.dart';

/// Measures text using registered font metrics. Deterministic, headless.
class MetricsTextMeasurer implements TextMeasurer {
  /// Creates a measurer backed by [registry].
  MetricsTextMeasurer(this._registry);

  final FontRegistry _registry;

  @override
  MeasuredText measure(String text, JetTextStyle style, {double? maxWidth}) {
    final FontMetrics m = _registry.metricsFor(style.fontFamily,
        weight: style.weight, italic: style.italic);
    final double scale = style.fontSize / m.unitsPerEm;
    final double lineAscent = m.ascent * scale;
    final double lineHeight = (m.ascent - m.descent + m.lineGap) * scale;

    double advanceOf(String s) {
      var w = 0.0;
      for (final int rune in s.runes) {
        final int cp = rune == 0x09 ? 0x20 : rune; // tab -> space
        w += m.advanceForGlyph(m.glyphForCodepoint(cp)) * scale;
      }
      return w;
    }

    final List<TextLine> lines = <TextLine>[];
    void emit(String content) {
      final int i = lines.length;
      lines.add(TextLine(
        text: content,
        width: advanceOf(content),
        top: i * lineHeight,
        baseline: i * lineHeight + lineAscent,
        height: lineHeight,
      ));
    }

    for (final String segment in text.split('\n')) {
      if (maxWidth == null) {
        emit(segment);
      } else {
        for (final String piece in _wrap(segment, maxWidth, advanceOf)) {
          emit(piece);
        }
      }
    }

    var maxW = 0.0;
    for (final TextLine l in lines) {
      if (l.width > maxW) maxW = l.width;
    }
    return MeasuredText(
      lines: lines,
      size: JetSize(maxW, lines.length * lineHeight),
      firstAscent: lineAscent,
    );
  }

  /// Greedy wrap. Tokenizes into alternating non-space/space runs (preserving
  /// every character) and packs tokens until the next would exceed [maxWidth].
  static List<String> _wrap(
      String segment, double maxWidth, double Function(String) advanceOf) {
    final List<String> tokens = _tokenize(segment);
    if (tokens.isEmpty) return <String>[''];
    final List<String> out = <String>[];
    var line = '';
    for (final String token in tokens) {
      if (line.isNotEmpty && advanceOf(line + token) > maxWidth) {
        out.add(line);
        line = token;
      } else {
        line += token;
      }
    }
    out.add(line);
    return out;
  }

  static List<String> _tokenize(String s) {
    final List<String> tokens = <String>[];
    final StringBuffer buf = StringBuffer();
    bool? space;
    for (final int rune in s.runes) {
      final bool isSpace = rune == 0x20 || rune == 0x09;
      if (space != null && isSpace != space) {
        tokens.add(buf.toString());
        buf.clear();
      }
      buf.writeCharCode(rune);
      space = isSpace;
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    return tokens;
  }
}
```

- [ ] **Step 4: Run — expect PASS.** `flutter test test/rendering/text/metrics_text_measurer_test.dart`

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/rendering/text/metrics_text_measurer.dart packages/jet_print/test/rendering/text/metrics_text_measurer_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(rendering): line-level MetricsTextMeasurer (006)"
```

---

### Task 8: `ReportPainter` abstraction + `paintFrame` walk

**Files:**
- Create: `lib/src/rendering/paint/report_painter.dart`
- Test: `test/rendering/paint/paint_frame_test.dart`

- [ ] **Step 1: Write the failing test** (a recording fake — no `dart:ui`)

```dart
// test/rendering/paint/paint_frame_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';

class _Recorder implements ReportPainter {
  final List<String> calls = <String>[];
  @override
  Future<void> prepare(PageFrame frame) async => calls.add('prepare');
  @override
  void beginPage(PageFormat format) => calls.add('beginPage');
  @override
  void drawTextRun(TextRunPrimitive p) => calls.add('text');
  @override
  void drawImage(ImagePrimitive p) => calls.add('image');
  @override
  void drawLine(LinePrimitive p) => calls.add('line');
  @override
  void drawRect(RectPrimitive p) => calls.add('rect');
  @override
  void drawPath(PathPrimitive p) => calls.add('path');
  @override
  void endPage() => calls.add('endPage');
}

void main() {
  test('paintFrame prepares, brackets the page, and dispatches in order',
      () async {
    final PageFrame frame = (FrameBuilder(PageFormat.a4Portrait)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 4, height: 4),
              fill: JetColor.black))
          ..add(const LinePrimitive(
              bounds: JetRect(x: 0, y: 0, width: 4, height: 0),
              start: JetOffset(0, 0),
              end: JetOffset(4, 0),
              color: JetColor.black)))
        .build();
    final _Recorder rec = _Recorder();
    await paintFrame(frame, rec);
    expect(rec.calls,
        <String>['prepare', 'beginPage', 'rect', 'line', 'endPage']);
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement**

```dart
// lib/src/rendering/paint/report_painter.dart
/// The paint-backend abstraction (spec 006): backends implement these calls over
/// the frame's primitives. [prepare] does async asset resolution (font load,
/// image decode) so the synchronous draw walk stays backend-agnostic.
library;

import '../../domain/page_format.dart';
import '../frame/page_frame.dart';
import '../frame/primitive.dart';

/// A backend that paints a [PageFrame]'s primitives.
abstract class ReportPainter {
  /// Resolves async assets for [frame] before painting (default: no-op).
  Future<void> prepare(PageFrame frame) async {}

  /// Begins a page of size [format].
  void beginPage(PageFormat format);

  /// Draws a text run.
  void drawTextRun(TextRunPrimitive primitive);

  /// Draws an image.
  void drawImage(ImagePrimitive primitive);

  /// Draws a line.
  void drawLine(LinePrimitive primitive);

  /// Draws a rectangle.
  void drawRect(RectPrimitive primitive);

  /// Draws a path.
  void drawPath(PathPrimitive primitive);

  /// Ends the page.
  void endPage();
}

/// Paints [frame] with [painter]: prepare → beginPage → primitives → endPage.
/// The switch is exhaustive (no `default`) so a new primitive is a compile error
/// until every backend handles it.
Future<void> paintFrame(PageFrame frame, ReportPainter painter) async {
  await painter.prepare(frame);
  painter.beginPage(frame.page);
  for (final FramePrimitive primitive in frame.primitives) {
    switch (primitive) {
      case TextRunPrimitive():
        painter.drawTextRun(primitive);
      case ImagePrimitive():
        painter.drawImage(primitive);
      case LinePrimitive():
        painter.drawLine(primitive);
      case RectPrimitive():
        painter.drawRect(primitive);
      case PathPrimitive():
        painter.drawPath(primitive);
    }
  }
  painter.endPage();
}
```

- [ ] **Step 4: Run — expect PASS.** `flutter test test/rendering/paint/paint_frame_test.dart`

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/rendering/paint/report_painter.dart packages/jet_print/test/rendering/paint/paint_frame_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(rendering): ReportPainter abstraction + paintFrame walk (006)"
```

---

### Task 9: `CanvasPainter` (`dart:ui`) + Canvas smoke golden

**Files:**
- Create: `lib/src/rendering/paint/canvas_painter.dart`
- Test: `test/rendering/paint/canvas_painter_golden_test.dart`
- Golden (generated): `test/rendering/paint/goldens/canvas_fixture.png`

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/paint/canvas_painter_golden_test.dart
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paints a fixture frame (text + rect + line) to a smoke golden',
      () async {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final MetricsTextMeasurer measurer = MetricsTextMeasurer(reg);
    final MeasuredText m =
        measurer.measure('Invoice', const JetTextStyle(fontSize: 24));

    const PageFormat page =
        PageFormat(width: 120, height: 60, margins: JetEdgeInsets.all(0));
    final PageFrame frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 120, height: 60),
              fill: JetColor(0xFFFFFFFF)))
          ..add(TextRunPrimitive(
              bounds: const JetRect(x: 6, y: 8, width: 110, height: 30),
              lines: m.lines,
              style: const JetTextStyle(fontSize: 24),
              fontFamily: reg.resolveFamily(null)))
          ..add(const LinePrimitive(
              bounds: JetRect(x: 6, y: 44, width: 108, height: 0),
              start: JetOffset(6, 44),
              end: JetOffset(114, 44),
              color: JetColor.black,
              strokeWidth: 1)))
        .build();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final ReportPainter painter = CanvasPainter(canvas, reg);
    await paintFrame(frame, painter);
    final ui.Image image = await recorder
        .endRecording()
        .toImage(page.width.toInt(), page.height.toInt());

    await expectLater(
        image, matchesGoldenFile('goldens/canvas_fixture.png'));
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`canvas_painter.dart` missing).

- [ ] **Step 3: Implement**

```dart
// lib/src/rendering/paint/canvas_painter.dart
/// The on-screen paint backend (spec 006): the ONLY rendering file that imports
/// Flutter / `dart:ui`. Draws the same line-level runs the measurer produced.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../domain/page_format.dart';
import '../../domain/styles/color.dart';
import '../../domain/styles/text_style.dart';
import '../frame/page_frame.dart';
import '../frame/primitive.dart';
import '../text/font_registry.dart';
import 'report_painter.dart';

/// Paints a [PageFrame] onto a `dart:ui` [ui.Canvas].
class CanvasPainter implements ReportPainter {
  /// Creates a painter drawing to [_canvas], resolving fonts via [_registry].
  CanvasPainter(this._canvas, this._registry);

  final ui.Canvas _canvas;
  final FontRegistry _registry;
  final Map<ImagePrimitive, ui.Image> _decoded = <ImagePrimitive, ui.Image>{};
  static final Set<String> _loadedFamilies = <String>{};

  @override
  Future<void> prepare(PageFrame frame) async {
    for (final FramePrimitive p in frame.primitives) {
      if (p is TextRunPrimitive) {
        await _ensureFont(p.fontFamily);
      } else if (p is ImagePrimitive) {
        final ui.Codec codec = await ui.instantiateImageCodec(p.bytes);
        _decoded[p] = (await codec.getNextFrame()).image;
      }
    }
  }

  Future<void> _ensureFont(String family) async {
    if (_loadedFamilies.contains(family)) return;
    await ui.loadFontFromList(_registry.bytesFor(family), fontFamily: family);
    _loadedFamilies.add(family);
  }

  @override
  void beginPage(PageFormat format) {}

  @override
  void endPage() {}

  @override
  void drawTextRun(TextRunPrimitive p) {
    final ui.Color color = ui.Color(p.style.color.argb);
    for (final line in p.lines) {
      if (line.text.isEmpty) continue;
      final ui.ParagraphBuilder pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        fontFamily: p.fontFamily,
        fontSize: p.style.fontSize,
      ))
        ..pushStyle(ui.TextStyle(
            color: color, fontFamily: p.fontFamily, fontSize: p.style.fontSize))
        ..addText(line.text);
      final ui.Paragraph para = pb.build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      final double extra = p.bounds.width - line.width;
      final double dx = switch (p.style.align) {
        JetTextAlign.center => p.bounds.x + extra / 2,
        JetTextAlign.right => p.bounds.x + extra,
        JetTextAlign.left || JetTextAlign.justify => p.bounds.x,
      };
      _canvas.drawParagraph(para, ui.Offset(dx, p.bounds.y + line.top));
    }
  }

  @override
  void drawImage(ImagePrimitive p) {
    final ui.Image? img = _decoded[p];
    if (img == null) return;
    _canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromLTWH(p.bounds.x, p.bounds.y, p.bounds.width, p.bounds.height),
      ui.Paint(),
    );
  }

  @override
  void drawLine(LinePrimitive p) {
    _canvas.drawLine(
      ui.Offset(p.start.dx, p.start.dy),
      ui.Offset(p.end.dx, p.end.dy),
      ui.Paint()
        ..color = ui.Color(p.color.argb)
        ..strokeWidth = p.strokeWidth
        ..style = ui.PaintingStyle.stroke,
    );
  }

  @override
  void drawRect(RectPrimitive p) {
    final ui.Rect r =
        ui.Rect.fromLTWH(p.bounds.x, p.bounds.y, p.bounds.width, p.bounds.height);
    final JetColor? fill = p.fill;
    if (fill != null) {
      _canvas.drawRect(r, ui.Paint()..color = ui.Color(fill.argb));
    }
    final JetColor? stroke = p.stroke;
    if (stroke != null) {
      _canvas.drawRect(
          r,
          ui.Paint()
            ..color = ui.Color(stroke.argb)
            ..strokeWidth = p.strokeWidth
            ..style = ui.PaintingStyle.stroke);
    }
  }

  @override
  void drawPath(PathPrimitive p) {
    final ui.Path path = ui.Path();
    for (final PathCommand c in p.commands) {
      switch (c) {
        case MoveTo():
          path.moveTo(c.to.dx, c.to.dy);
        case LineTo():
          path.lineTo(c.to.dx, c.to.dy);
        case ClosePath():
          path.close();
      }
    }
    final JetColor? fill = p.fill;
    if (fill != null) {
      _canvas.drawPath(path, ui.Paint()..color = ui.Color(fill.argb));
    }
    final JetColor? stroke = p.stroke;
    if (stroke != null) {
      _canvas.drawPath(
          path,
          ui.Paint()
            ..color = ui.Color(stroke.argb)
            ..strokeWidth = p.strokeWidth
            ..style = ui.PaintingStyle.stroke);
    }
  }
}
```

- [ ] **Step 4: Generate the golden, then run to verify PASS**

Run: `cd packages/jet_print && flutter test --update-goldens test/rendering/paint/canvas_painter_golden_test.dart`
Then: `flutter test test/rendering/paint/canvas_painter_golden_test.dart`
Expected: PASS. A new `test/rendering/paint/goldens/canvas_fixture.png` is created. (Pixel golden is smoke-level / platform-pinned to this machine; the data goldens are the real guard.)

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/lib/src/rendering/paint/canvas_painter.dart packages/jet_print/test/rendering/paint/canvas_painter_golden_test.dart packages/jet_print/test/rendering/paint/goldens/canvas_fixture.png
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "feat(rendering): CanvasPainter (dart:ui) + Canvas smoke golden (006)"
```

---

### Task 10: Architecture-test extension (rendering seam) + parity placeholder

**Files:**
- Modify: `test/architecture/layer_boundaries_test.dart`
- Create: `test/rendering/parity_test.dart`

- [ ] **Step 1: Write the failing test** — append a rendering-seam group inside `main()` of `test/architecture/layer_boundaries_test.dart`, after the expression-seam group's closing `});`:

```dart
  group('layer boundaries — rendering seam', () {
    final Directory renderingDir =
        Directory('${root.path}/packages/jet_print/lib/src/rendering');
    List<File> renderingFiles() => renderingDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((FileSystemEntity f) => f.path.endsWith('.dart'))
        .toList();

    test('the rendering seam has source files to check (no false green)', () {
      expect(renderingDir.existsSync(), isTrue);
      expect(renderingFiles(), isNotEmpty);
    });

    test('rendering imports no designer seam', () {
      final List<String> violations = <String>[];
      for (final File file in renderingFiles()) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (uri.contains('designer')) violations.add('${file.path} -> $uri');
        }
      }
      expect(violations, isEmpty,
          reason: 'Rendering must not depend on the designer seam:\n'
              '${violations.join('\n')}');
    });

    test('only paint/canvas_painter.dart imports dart:ui / Flutter UI', () {
      final List<String> violations = <String>[];
      for (final File file in renderingFiles()) {
        final String path = file.path.replaceAll(r'\', '/');
        final bool isCanvasPainter =
            path.endsWith('/paint/canvas_painter.dart');
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (_isFlutterUi(uri) && !isCanvasPainter) {
            violations.add('${file.path} -> $uri');
          }
        }
      }
      expect(violations, isEmpty,
          reason: 'Only CanvasPainter may import dart:ui; frame/text/'
              'report_painter must stay headless:\n${violations.join('\n')}');
    });
  });
```

And the parity placeholder:

```dart
// test/rendering/parity_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cross-backend pixel/text parity', () {
    // Deferred to spec 009: parity needs a second, structurally-different
    // backend (PdfPainter/ImagePainter). 006 proves the parity MECHANISM via the
    // line-break-determinism data goldens (measurer tests) + a Canvas smoke
    // golden. See blueprint §15.6.
  }, skip: 'cross-backend parity lands with PDF/PNG backends in spec 009');
}
```

- [ ] **Step 2: Run — expect PASS** (the new rendering rules already hold for the code written in Tasks 1–9).

Run: `cd packages/jet_print && flutter test test/architecture/layer_boundaries_test.dart test/rendering/parity_test.dart`
Expected: rendering-seam group passes; parity test reported as skipped.

- [ ] **Step 3: (sanity) Temporarily prove the guard bites** — add `import 'dart:ui';` to `lib/src/rendering/frame/primitive.dart`, run the architecture test, confirm the "only canvas_painter" test FAILS, then revert the import and confirm green. (Do not commit the temporary edit.)

- [ ] **Step 4: Run the full suite — expect PASS.** `cd packages/jet_print && flutter test`

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format . && flutter analyze
git -C /Users/ahmeturel/Projects/oss/jet-print add packages/jet_print/test/architecture/layer_boundaries_test.dart packages/jet_print/test/rendering/parity_test.dart
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "test(rendering): enforce rendering-seam boundary; defer parity to 009 (006)"
```

---

### Task 11: Retire the scaffold placeholders + CHANGELOG

**Files:**
- Delete: `lib/src/domain/domain.dart`, `lib/src/rendering/rendering.dart`, `test/domain/domain_test.dart`, `test/rendering/rendering_test.dart`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Confirm the quartet is orphaned**

Run: `grep -rn "ReportDocument\|ReportLayout" packages/jet_print/lib packages/jet_print/test packages/jet_print/../../apps --include="*.dart"`
Expected: matches only inside the four files about to be deleted. (If anything else references them, stop and report.)

- [ ] **Step 2: Delete the four files**

```bash
git -C /Users/ahmeturel/Projects/oss/jet-print rm \
  packages/jet_print/lib/src/domain/domain.dart \
  packages/jet_print/lib/src/rendering/rendering.dart \
  packages/jet_print/test/domain/domain_test.dart \
  packages/jet_print/test/rendering/rendering_test.dart
```

- [ ] **Step 3: Add the CHANGELOG entry** — insert this bullet under `## Unreleased` → `### Added`, after the spec-005b bullet:

```markdown
- Frame, text-metrics & paint backends (spec 006): the rendering display-list
  and first paint backend. `PageFrame` + `FrameBuilder` build a flat list of
  positioned `FramePrimitive`s (text run / image / line / rect / path, each
  tagged with its originating element id). A headless text seam — an in-house
  TTF/OTF **metrics** parser (`parseTtfMetrics`), a byte-keyed `FontRegistry`
  with a bundled Latin default font (Noto Sans, OFL), and a line-level
  `TextMeasurer` (`MetricsTextMeasurer`) that owns word-wrapping — guarantees
  **deterministic line breaks** across backends. A `ReportPainter` abstraction
  (with async `prepare`) and the backend-agnostic `paintFrame` walk drive
  `CanvasPainter` (`dart:ui`). The architecture test now enforces that only
  `CanvasPainter` may import `dart:ui`; `frame/` and `text/` stay headless.
  Cross-backend pixel parity arrives with the PDF/PNG backends in 009. Replaces
  the `ReportDocument`/`ReportLayout` scaffold placeholders.
```

- [ ] **Step 4: Run the full suite + analyze — expect PASS / clean.**

Run: `cd packages/jet_print && flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass (the deleted placeholder tests are gone; nothing else referenced them).

- [ ] **Step 5: Commit**

```bash
cd packages/jet_print && dart format .
git -C /Users/ahmeturel/Projects/oss/jet-print add -A
git -C /Users/ahmeturel/Projects/oss/jet-print commit -m "refactor(rendering): retire ReportDocument/ReportLayout scaffold; changelog (006)"
```

---

## Self-Review

**Spec coverage** (against `2026-06-07-frame-text-paint-design.md`):
- §3 seam layout → Tasks 1–9 create every listed file; §10 boundary rule → Task 10.
- §4 frame primitives + `PageFrame`/`FrameBuilder` → Tasks 2–3.
- §5.1 `FontMetrics`/TTF parser → Tasks 4–5; §5.2 `FontRegistry` → Task 6; §5.3 measurer (advances, hard breaks, whitespace-preserving wrap, `top`/`baseline`, empty→one line, tab=space) → Task 7.
- §6 `ReportPainter` async `prepare` + `paintFrame` + `CanvasPainter` (`line.top` origin, align, image decode) → Tasks 8–9.
- §7 error handling: unregistered font→default (Task 6), `.notdef` (Tasks 4/5/7), empty/blank/whitespace (Task 7), malformed→`FontFormatException` (Task 5), no-default→`StateError` (Task 6).
- §8 tests: ttf metrics, measurer metrics, frame snapshot (data), paint-walk fake, Canvas smoke golden, parity placeholder, boundary test → Tasks 5,7,2–3,8,9,10.
- §9 scaffold retirement → Task 11. Deferred-export convention → no `jet_print.dart` change (intentional).

**Placeholder scan:** none — every code step has complete code; reference metric numbers are concrete (from the committed font); fp assertions use `closeTo`.

**Type consistency:** `TextLine(text,width,top,baseline,height)`, `MeasuredText(lines,size,firstAscent)`, `FramePrimitive(bounds,elementId)` + five variants, `PathCommand` (`MoveTo`/`LineTo`/`ClosePath`), `PageFrame(page,primitives)`, `FrameBuilder(page).add().build()`, `FontMetrics(unitsPerEm,ascent,descent,lineGap,cmap,advanceWidths,defaultAdvance)`, `parseTtfMetrics(Uint8List)`, `FontRegistry.{register,registerDefault,hasDefault,metricsFor,bytesFor,resolveFamily,defaultFamily}`, `MetricsTextMeasurer(registry)`, `ReportPainter.{prepare,beginPage,drawTextRun,drawImage,drawLine,drawRect,drawPath,endPage}` + `paintFrame`, `CanvasPainter(canvas,registry)` — used identically across tasks. Build order respects dependencies: text result types (T1) precede frame primitives that reference `TextLine` (T2); `FontMetrics`/parser/registry (T4–6) precede the measurer (T7); frame + painter abstraction (T8) precede `CanvasPainter` (T9).
