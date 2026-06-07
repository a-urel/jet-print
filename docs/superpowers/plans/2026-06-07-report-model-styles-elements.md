# Report Model — Styles & Element Types (Spec 003 · Part 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the *visual* report model — style value types (color, text style, box style) and the remaining element types (shape, image, barcode) with their JSON codecs — building on the Part 1 foundation, fully test-driven.

**Architecture:** Pure-Dart additions under `packages/jet_print/lib/src/domain/` (no `dart:ui`/Flutter; the existing layer-boundary test enforces this). Element types extend the Part 1 `ReportElement` base and register `{codec}` pairs with the existing `ElementCodecRegistry` — zero core edits, per the blueprint's extension point. `TextElement` is retrofitted with a `JetTextStyle` that serializes **sparsely** (omitted when default) so Part 1's wire format and tests are preserved. A `registerBuiltInElementCodecs` helper wires all four built-in element types into a registry.

**Tech Stack:** Dart 3.6+ (`sealed class`, enhanced enums), `dart:convert` (base64) and `dart:typed_data` (`Uint8List`) — both pure Dart, allowed in the domain seam; `flutter_test` for tests. No new package dependencies.

**Scope (this plan = 003 Part 2):** `JetColor`, `JetTextStyle` (+ `JetTextAlign`, `JetFontWeight`), `JetBoxStyle`; retrofit `TextElement` with style; `ShapeElement` (+ `ShapeKind`); `JetImageSource` (url/field/bytes) + `JetBoxFit` + `ImageElement`; `BarcodeElement` (+ `BarcodeSymbology`); the four element codecs; `registerBuiltInElementCodecs`.
**Deferred (later specs):** `ReportParameter`/`ReportVariable`/`ReportGroup` and expression bindings move to the 004 (data) / 005 (expressions) timeframe, where their semantics are concrete. Element data (text, barcode `data`, image `field`) stays a literal `String`/reference now; expression evaluation arrives in 005.

**Design decisions baked into the schema (veto before execution if any is wrong):**
- **Color** serializes as a human-inspectable hex string `#AARRGGBB` (e.g. `#FF1A73E8`); in memory it's an ARGB32 `int`.
- **Text style** is sparse-serialized on `TextElement` (no `style` key when equal to `JetTextStyle.fallback`), keeping Part 1's `{type,id,bounds,text}` wire shape intact.
- **Image sources**: `url`, `field`, `bytes` (base64). No asset-key source.
- **Barcode symbologies**: `qrCode`, `code128`, `ean13`, `dataMatrix`.

**Prerequisite:** Part 1 (spec 003 Part 1) must be present (geometry, element model, codec registry, serialization). Branch from `main` once Part 1 is merged, or from `003-report-model-serialization`:
```bash
git checkout 003-report-model-serialization && git checkout -b 003b-report-model-styles-elements
```
All paths are relative to the repo root `/Users/ahmeturel/Projects/oss/jet-print`.

## File Structure

Created/modified under `packages/jet_print/lib/src/domain/`:

| File | Responsibility |
|---|---|
| `styles/color.dart` | `JetColor` (ARGB32 int; hex-string JSON) |
| `styles/text_style.dart` | `JetTextAlign`, `JetFontWeight` enums + `JetTextStyle` (+ `fallback`) |
| `styles/box_style.dart` | `JetBoxStyle` (fill/stroke/strokeWidth) |
| `elements/text_element.dart` | **modified** — add `JetTextStyle style` |
| `elements/shape_element.dart` | `ShapeKind` enum + `ShapeElement` |
| `elements/image_source.dart` | sealed `JetImageSource` (`UrlImageSource`/`FieldImageSource`/`BytesImageSource`) + `JetBoxFit` |
| `elements/image_element.dart` | `ImageElement` |
| `elements/barcode_element.dart` | `BarcodeSymbology` enum + `BarcodeElement` |
| `serialization/text_element_codec.dart` | **modified** — sparse style |
| `serialization/shape_element_codec.dart` | `ShapeElementCodec` |
| `serialization/image_element_codec.dart` | `ImageElementCodec` |
| `serialization/barcode_element_codec.dart` | `BarcodeElementCodec` |
| `serialization/built_in_element_codecs.dart` | `registerBuiltInElementCodecs(registry)` |

Tests mirror these under `packages/jet_print/test/domain/...`.

---

### Task 1: JetColor

**Files:**
- Create: `packages/jet_print/lib/src/domain/styles/color.dart`
- Test: `packages/jet_print/test/domain/styles/color_test.dart`

- [ ] **Step 1: Write the failing test** — create `packages/jet_print/test/domain/styles/color_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/color.dart';

void main() {
  group('JetColor', () {
    test('fromARGB packs channels into argb', () {
      expect(const JetColor.fromARGB(0xFF, 0x1A, 0x73, 0xE8).argb, 0xFF1A73E8);
    });

    test('round-trips through an #AARRGGBB hex string', () {
      const JetColor color = JetColor(0xFF1A73E8);
      expect(color.toJson(), '#FF1A73E8');
      expect(JetColor.fromJson(color.toJson()), color);
    });

    test('accepts #RRGGBB (assumes opaque alpha)', () {
      expect(JetColor.fromJson('#1A73E8'), const JetColor(0xFF1A73E8));
    });

    test('exposes black as opaque 0xFF000000', () {
      expect(JetColor.black, const JetColor(0xFF000000));
      expect(JetColor.black.toJson(), '#FF000000');
    });

    test('has value equality', () {
      expect(const JetColor(0x80FF0000), const JetColor(0x80FF0000));
      expect(const JetColor(0x80FF0000) == const JetColor(0xFF00FF00), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test packages/jet_print/test/domain/styles/color_test.dart` → FAIL (`JetColor` undefined).

- [ ] **Step 3: Write minimal implementation** — create `packages/jet_print/lib/src/domain/styles/color.dart`:

```dart
/// A pure-Dart color value (no `dart:ui`).
library;

/// An immutable ARGB32 color. Serialized as a human-inspectable hex string
/// `#AARRGGBB` (Constitution V); in memory it is a packed [argb] int.
class JetColor {
  /// Creates a color from a packed 0xAARRGGBB value.
  const JetColor(this.argb);

  /// Creates a color from 0–255 alpha/red/green/blue channels.
  const JetColor.fromARGB(int a, int r, int g, int b)
      : argb = (a << 24) | (r << 16) | (g << 8) | b;

  /// Parses `#AARRGGBB` or `#RRGGBB` (the latter assumes opaque alpha).
  factory JetColor.fromJson(String hex) {
    var h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length == 6) {
      h = 'FF$h';
    }
    if (h.length != 8) {
      throw FormatException('Invalid color hex "$hex".');
    }
    return JetColor(int.parse(h, radix: 16));
  }

  /// Opaque black.
  static const JetColor black = JetColor(0xFF000000);

  /// The packed 0xAARRGGBB value.
  final int argb;

  /// Serializes to an uppercase `#AARRGGBB` hex string.
  String toJson() =>
      '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  @override
  bool operator ==(Object other) => other is JetColor && other.argb == argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() => 'JetColor(${toJson()})';
}
```

- [ ] **Step 4: Run test to verify it passes** — `flutter test packages/jet_print/test/domain/styles/color_test.dart` → PASS. Also `dart format` the new files and `flutter analyze packages/jet_print` → clean.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/styles/color.dart packages/jet_print/test/domain/styles/color_test.dart
git commit -m "feat(domain): add JetColor value type with hex serialization"
```

---

### Task 2: JetTextStyle (+ JetTextAlign, JetFontWeight)

**Files:**
- Create: `packages/jet_print/lib/src/domain/styles/text_style.dart`
- Test: `packages/jet_print/test/domain/styles/text_style_test.dart`

- [ ] **Step 1: Write the failing test** — create `packages/jet_print/test/domain/styles/text_style_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';

void main() {
  group('JetTextStyle', () {
    test('fallback has sensible defaults', () {
      const JetTextStyle s = JetTextStyle.fallback;
      expect(s.fontFamily, isNull);
      expect(s.fontSize, 12);
      expect(s.weight, JetFontWeight.normal);
      expect(s.italic, isFalse);
      expect(s.color, JetColor.black);
      expect(s.align, JetTextAlign.left);
    });

    test('round-trips a fully specified style', () {
      const JetTextStyle s = JetTextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        weight: JetFontWeight.bold,
        italic: true,
        color: JetColor(0xFF1A73E8),
        align: JetTextAlign.right,
      );
      expect(JetTextStyle.fromJson(s.toJson()), s);
    });

    test('omits fontFamily from JSON when null', () {
      expect(JetTextStyle.fallback.toJson().containsKey('fontFamily'), isFalse);
    });

    test('has value equality', () {
      expect(const JetTextStyle(fontSize: 14), const JetTextStyle(fontSize: 14));
      expect(const JetTextStyle(fontSize: 14) == const JetTextStyle(fontSize: 15),
          isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test packages/jet_print/test/domain/styles/text_style_test.dart` → FAIL (`JetTextStyle` undefined).

- [ ] **Step 3: Write minimal implementation** — create `packages/jet_print/lib/src/domain/styles/text_style.dart`:

```dart
/// Text styling for the report model (pure Dart, no `dart:ui`).
library;

import 'color.dart';

/// Horizontal text alignment within an element's bounds.
enum JetTextAlign { left, center, right, justify }

/// Coarse font weight; mapped to concrete OS weights by the renderer.
enum JetFontWeight { normal, medium, semiBold, bold }

/// Immutable text appearance. JSON omits [fontFamily] when null; other fields
/// are always present.
class JetTextStyle {
  /// Creates a text style; every field has a default (see [fallback]).
  const JetTextStyle({
    this.fontFamily,
    this.fontSize = 12,
    this.weight = JetFontWeight.normal,
    this.italic = false,
    this.color = JetColor.black,
    this.align = JetTextAlign.left,
  });

  /// Reads a [JetTextStyle] from its [toJson] map.
  factory JetTextStyle.fromJson(Map<String, Object?> json) => JetTextStyle(
        fontFamily: json['fontFamily'] as String?,
        fontSize: (json['fontSize']! as num).toDouble(),
        weight: JetFontWeight.values.byName(json['weight']! as String),
        italic: json['italic']! as bool,
        color: JetColor.fromJson(json['color']! as String),
        align: JetTextAlign.values.byName(json['align']! as String),
      );

  /// The default style (12pt, normal, upright, black, left-aligned).
  static const JetTextStyle fallback = JetTextStyle();

  /// Font family name, or null to use the renderer's default font.
  final String? fontFamily;

  /// Font size, in points.
  final double fontSize;

  /// Font weight.
  final JetFontWeight weight;

  /// Whether the text is italic.
  final bool italic;

  /// Text color.
  final JetColor color;

  /// Horizontal alignment.
  final JetTextAlign align;

  /// Serializes to a JSON-safe map (omitting [fontFamily] when null).
  Map<String, Object?> toJson() => <String, Object?>{
        if (fontFamily != null) 'fontFamily': fontFamily,
        'fontSize': fontSize,
        'weight': weight.name,
        'italic': italic,
        'color': color.toJson(),
        'align': align.name,
      };

  @override
  bool operator ==(Object other) =>
      other is JetTextStyle &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.weight == weight &&
      other.italic == italic &&
      other.color == color &&
      other.align == align;

  @override
  int get hashCode =>
      Object.hash(fontFamily, fontSize, weight, italic, color, align);

  @override
  String toString() => 'JetTextStyle($fontSize, ${weight.name})';
}
```

- [ ] **Step 4: Run test to verify it passes** — `flutter test packages/jet_print/test/domain/styles/text_style_test.dart` → PASS. `dart format` + `flutter analyze packages/jet_print` → clean.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/styles/text_style.dart packages/jet_print/test/domain/styles/text_style_test.dart
git commit -m "feat(domain): add JetTextStyle with text align and font weight enums"
```

---

### Task 3: JetBoxStyle

**Files:**
- Create: `packages/jet_print/lib/src/domain/styles/box_style.dart`
- Test: `packages/jet_print/test/domain/styles/box_style_test.dart`

- [ ] **Step 1: Write the failing test** — create `packages/jet_print/test/domain/styles/box_style_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';

void main() {
  group('JetBoxStyle', () {
    test('none has no fill/stroke and unit stroke width', () {
      expect(JetBoxStyle.none.fill, isNull);
      expect(JetBoxStyle.none.stroke, isNull);
      expect(JetBoxStyle.none.strokeWidth, 1.0);
    });

    test('round-trips a filled, stroked box', () {
      const JetBoxStyle style = JetBoxStyle(
        fill: JetColor(0x11000000),
        stroke: JetColor(0xFF000000),
        strokeWidth: 2,
      );
      expect(JetBoxStyle.fromJson(style.toJson()), style);
    });

    test('omits null fill/stroke from JSON', () {
      final Map<String, Object?> json = JetBoxStyle.none.toJson();
      expect(json.containsKey('fill'), isFalse);
      expect(json.containsKey('stroke'), isFalse);
      expect(json['strokeWidth'], 1.0);
    });

    test('has value equality', () {
      expect(const JetBoxStyle(strokeWidth: 3), const JetBoxStyle(strokeWidth: 3));
      expect(const JetBoxStyle(strokeWidth: 3) == JetBoxStyle.none, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test packages/jet_print/test/domain/styles/box_style_test.dart` → FAIL (`JetBoxStyle` undefined).

- [ ] **Step 3: Write minimal implementation** — create `packages/jet_print/lib/src/domain/styles/box_style.dart`:

```dart
/// Fill/stroke styling for shapes and boxes (pure Dart).
library;

import 'color.dart';

/// Immutable box appearance: an optional [fill], an optional [stroke], and a
/// [strokeWidth] (points). JSON omits null fill/stroke.
class JetBoxStyle {
  /// Creates a box style.
  const JetBoxStyle({this.fill, this.stroke, this.strokeWidth = 1.0});

  /// Reads a [JetBoxStyle] from its [toJson] map.
  factory JetBoxStyle.fromJson(Map<String, Object?> json) => JetBoxStyle(
        fill: json['fill'] is String
            ? JetColor.fromJson(json['fill']! as String)
            : null,
        stroke: json['stroke'] is String
            ? JetColor.fromJson(json['stroke']! as String)
            : null,
        strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1.0,
      );

  /// No fill, no stroke, unit stroke width.
  static const JetBoxStyle none = JetBoxStyle();

  /// Fill color, or null for no fill.
  final JetColor? fill;

  /// Stroke (border/line) color, or null for no stroke.
  final JetColor? stroke;

  /// Stroke width, in points.
  final double strokeWidth;

  /// Serializes to a JSON-safe map (omitting null fill/stroke).
  Map<String, Object?> toJson() => <String, Object?>{
        if (fill != null) 'fill': fill!.toJson(),
        if (stroke != null) 'stroke': stroke!.toJson(),
        'strokeWidth': strokeWidth,
      };

  @override
  bool operator ==(Object other) =>
      other is JetBoxStyle &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode => Object.hash(fill, stroke, strokeWidth);

  @override
  String toString() => 'JetBoxStyle(fill: $fill, stroke: $stroke, $strokeWidth)';
}
```

- [ ] **Step 4: Run test to verify it passes** — `flutter test packages/jet_print/test/domain/styles/box_style_test.dart` → PASS. `dart format` + `flutter analyze packages/jet_print` → clean.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/styles/box_style.dart packages/jet_print/test/domain/styles/box_style_test.dart
git commit -m "feat(domain): add JetBoxStyle (fill/stroke) value type"
```

---

### Task 4: Retrofit TextElement with JetTextStyle (sparse codec)

**Files:**
- Modify: `packages/jet_print/lib/src/domain/elements/text_element.dart`
- Modify: `packages/jet_print/lib/src/domain/serialization/text_element_codec.dart`
- Test: `packages/jet_print/test/domain/elements/text_element_style_test.dart`

> **Compatibility note:** `style` defaults to `JetTextStyle.fallback` and the codec writes a `style` key **only when non-default**, so the Part 1 wire shape `{type,id,bounds,text}` and the existing `text_element_test.dart` / `element_codec_test.dart` remain valid. Do not edit those Part 1 tests.

- [ ] **Step 1: Write the failing test** — create `packages/jet_print/test/domain/elements/text_element_style_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('text', const TextElementCodec());

void main() {
  group('TextElement style', () {
    test('defaults to the fallback style', () {
      const TextElement e = TextElement(
        id: 't',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        text: 'x',
      );
      expect(e.style, JetTextStyle.fallback);
    });

    test('default-style text omits the "style" key (Part 1 wire shape)', () {
      final ElementCodecRegistry registry = _registry();
      const TextElement e = TextElement(
        id: 't',
        bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
        text: 'x',
      );
      expect(registry.encode(e).containsKey('style'), isFalse);
    });

    test('styled text round-trips its style', () {
      final ElementCodecRegistry registry = _registry();
      const TextElement e = TextElement(
        id: 'title',
        bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
        text: 'INVOICE',
        style: JetTextStyle(
          fontSize: 20,
          weight: JetFontWeight.bold,
          color: JetColor(0xFF1A73E8),
          align: JetTextAlign.center,
        ),
      );
      expect(registry.encode(e).containsKey('style'), isTrue);
      expect(registry.decode(registry.encode(e)), e);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test packages/jet_print/test/domain/elements/text_element_style_test.dart` → FAIL (`style` param undefined on `TextElement`).

- [ ] **Step 3: Write minimal implementation**

Replace the entire contents of `packages/jet_print/lib/src/domain/elements/text_element.dart` with:

```dart
/// A static or (later) data-bound text element.
library;

import '../geometry.dart';
import '../report_element.dart';
import '../styles/text_style.dart';

/// Renders [text] within its [bounds] using [style]. For this iteration [text]
/// is a literal string; expression binding arrives with the expression engine
/// (spec 005).
class TextElement extends ReportElement {
  /// Creates a text element.
  const TextElement({
    required super.id,
    required super.bounds,
    required this.text,
    this.style = JetTextStyle.fallback,
  });

  /// The literal text to render.
  final String text;

  /// Text appearance.
  final JetTextStyle style;

  @override
  String get typeKey => 'text';

  @override
  bool operator ==(Object other) =>
      other is TextElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.text == text &&
      other.style == style;

  @override
  int get hashCode => Object.hash(id, bounds, text, style);

  @override
  String toString() => 'TextElement($id, "$text")';
}
```

Replace the entire contents of `packages/jet_print/lib/src/domain/serialization/text_element_codec.dart` with:

```dart
/// JSON codec for [TextElement].
library;

import '../elements/text_element.dart';
import '../geometry.dart';
import '../styles/text_style.dart';
import 'element_codec.dart';

/// Serializes [TextElement] to/from its field map. The `style` key is written
/// only when the style is non-default, preserving the compact wire shape for
/// unstyled text.
class TextElementCodec extends ElementCodec<TextElement> {
  /// Const constructor (the codec is stateless).
  const TextElementCodec();

  @override
  TextElement fromJson(Map<String, Object?> json) => TextElement(
        id: json['id']! as String,
        bounds: JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        text: json['text']! as String,
        style: json['style'] is Map
            ? JetTextStyle.fromJson(
                (json['style']! as Map).cast<String, Object?>())
            : JetTextStyle.fallback,
      );

  @override
  Map<String, Object?> toJson(TextElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'text': element.text,
        if (element.style != JetTextStyle.fallback)
          'style': element.style.toJson(),
      };
}
```

- [ ] **Step 4: Run tests to verify they pass** — run the new test AND the Part 1 tests that touch text, confirming nothing regressed:

```
flutter test packages/jet_print/test/domain/elements/text_element_style_test.dart
flutter test packages/jet_print/test/domain/elements/text_element_test.dart
flutter test packages/jet_print/test/domain/serialization/element_codec_test.dart
```
Expected: all PASS. `dart format` the touched files + `flutter analyze packages/jet_print` → clean.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/elements/text_element.dart packages/jet_print/lib/src/domain/serialization/text_element_codec.dart packages/jet_print/test/domain/elements/text_element_style_test.dart
git commit -m "feat(domain): add sparse text styling to TextElement"
```

---

### Task 5: ShapeElement (+ ShapeKind) and ShapeElementCodec

**Files:**
- Create: `packages/jet_print/lib/src/domain/elements/shape_element.dart`
- Create: `packages/jet_print/lib/src/domain/serialization/shape_element_codec.dart`
- Test: `packages/jet_print/test/domain/elements/shape_element_test.dart`

- [ ] **Step 1: Write the failing test** — create `packages/jet_print/test/domain/elements/shape_element_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/shape_element_codec.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('shape', const ShapeElementCodec());

void main() {
  group('ShapeElement', () {
    test('is a ReportElement with the "shape" type key', () {
      const ShapeElement s = ShapeElement(
        id: 's',
        bounds: JetRect(x: 0, y: 0, width: 100, height: 0),
        kind: ShapeKind.line,
      );
      expect(s, isA<ReportElement>());
      expect(s.typeKey, 'shape');
      expect(s.style, JetBoxStyle.none);
      expect(s.flipDiagonal, isFalse);
    });

    test('round-trips a rectangle with a box style', () {
      final ElementCodecRegistry registry = _registry();
      const ShapeElement s = ShapeElement(
        id: 'box',
        bounds: JetRect(x: 1, y: 2, width: 50, height: 30),
        kind: ShapeKind.rectangle,
        style: JetBoxStyle(
          fill: JetColor(0x11000000),
          stroke: JetColor(0xFF000000),
          strokeWidth: 2,
        ),
      );
      expect(registry.decode(registry.encode(s)), s);
    });

    test('round-trips a flipped line', () {
      final ElementCodecRegistry registry = _registry();
      const ShapeElement s = ShapeElement(
        id: 'rule',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        kind: ShapeKind.line,
        flipDiagonal: true,
      );
      expect(registry.decode(registry.encode(s)), s);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test packages/jet_print/test/domain/elements/shape_element_test.dart` → FAIL (`ShapeElement` undefined).

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/elements/shape_element.dart`:

```dart
/// A line or rectangle shape element.
library;

import '../geometry.dart';
import '../report_element.dart';
import '../styles/box_style.dart';

/// The kind of [ShapeElement].
enum ShapeKind {
  /// A straight line across the element's [ReportElement.bounds] box.
  line,

  /// A rectangle filling the element's [ReportElement.bounds] box.
  rectangle,
}

/// A vector shape ([kind]) drawn within [bounds] using [style]. For a
/// [ShapeKind.line], [flipDiagonal] selects the bottom-left→top-right diagonal
/// instead of the default top-left→bottom-right.
class ShapeElement extends ReportElement {
  /// Creates a shape element.
  const ShapeElement({
    required super.id,
    required super.bounds,
    required this.kind,
    this.style = JetBoxStyle.none,
    this.flipDiagonal = false,
  });

  /// Whether this is a line or a rectangle.
  final ShapeKind kind;

  /// Fill/stroke appearance.
  final JetBoxStyle style;

  /// For lines only: use the opposite diagonal when true.
  final bool flipDiagonal;

  @override
  String get typeKey => 'shape';

  @override
  bool operator ==(Object other) =>
      other is ShapeElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.kind == kind &&
      other.style == style &&
      other.flipDiagonal == flipDiagonal;

  @override
  int get hashCode => Object.hash(id, bounds, kind, style, flipDiagonal);

  @override
  String toString() => 'ShapeElement($id, ${kind.name})';
}
```

Create `packages/jet_print/lib/src/domain/serialization/shape_element_codec.dart`:

```dart
/// JSON codec for [ShapeElement].
library;

import '../elements/shape_element.dart';
import '../geometry.dart';
import '../styles/box_style.dart';
import 'element_codec.dart';

/// Serializes [ShapeElement] to/from its field map.
class ShapeElementCodec extends ElementCodec<ShapeElement> {
  /// Const constructor (the codec is stateless).
  const ShapeElementCodec();

  @override
  ShapeElement fromJson(Map<String, Object?> json) => ShapeElement(
        id: json['id']! as String,
        bounds: JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        kind: ShapeKind.values.byName(json['kind']! as String),
        style: json['style'] is Map
            ? JetBoxStyle.fromJson((json['style']! as Map).cast<String, Object?>())
            : JetBoxStyle.none,
        flipDiagonal: (json['flipDiagonal'] as bool?) ?? false,
      );

  @override
  Map<String, Object?> toJson(ShapeElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'kind': element.kind.name,
        if (element.style != JetBoxStyle.none) 'style': element.style.toJson(),
        if (element.flipDiagonal) 'flipDiagonal': true,
      };
}
```

- [ ] **Step 4: Run test to verify it passes** — `flutter test packages/jet_print/test/domain/elements/shape_element_test.dart` → PASS. `dart format` + `flutter analyze packages/jet_print` → clean.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/elements/shape_element.dart packages/jet_print/lib/src/domain/serialization/shape_element_codec.dart packages/jet_print/test/domain/elements/shape_element_test.dart
git commit -m "feat(domain): add ShapeElement (line/rectangle) with codec"
```

---

### Task 6: JetImageSource (url/field/bytes) + JetBoxFit

**Files:**
- Create: `packages/jet_print/lib/src/domain/elements/image_source.dart`
- Test: `packages/jet_print/test/domain/elements/image_source_test.dart`

- [ ] **Step 1: Write the failing test** — create `packages/jet_print/test/domain/elements/image_source_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';

void main() {
  group('JetImageSource', () {
    test('UrlImageSource round-trips', () {
      const JetImageSource s = UrlImageSource('https://example.com/logo.png');
      expect(s.toJson(), <String, Object?>{
        'kind': 'url',
        'url': 'https://example.com/logo.png',
      });
      expect(JetImageSource.fromJson(s.toJson()), s);
    });

    test('FieldImageSource round-trips', () {
      const JetImageSource s = FieldImageSource('product_image');
      expect(JetImageSource.fromJson(s.toJson()), s);
    });

    test('BytesImageSource round-trips through base64', () {
      final JetImageSource s = BytesImageSource(Uint8List.fromList(<int>[1, 2, 3, 250]));
      final JetImageSource back = JetImageSource.fromJson(s.toJson());
      expect(back, isA<BytesImageSource>());
      expect((back as BytesImageSource).bytes, <int>[1, 2, 3, 250]);
    });

    test('throws on an unknown source kind', () {
      expect(
        () => JetImageSource.fromJson(<String, Object?>{'kind': 'satellite'}),
        throwsFormatException,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test packages/jet_print/test/domain/elements/image_source_test.dart` → FAIL (`JetImageSource` undefined).

- [ ] **Step 3: Write minimal implementation** — create `packages/jet_print/lib/src/domain/elements/image_source.dart`:

```dart
/// Where an [ImageElement] gets its bytes from (pure Dart).
library;

import 'dart:convert';
import 'dart:typed_data';

/// How an image is scaled to fit its element bounds.
enum JetBoxFit { contain, cover, fill, none }

/// The source of an image: a network [UrlImageSource], a data-bound
/// [FieldImageSource] (resolved at fill time, spec 005), or embedded
/// [BytesImageSource] (base64 in JSON, fully portable). Tagged by a `kind` key.
sealed class JetImageSource {
  /// Const base constructor.
  const JetImageSource();

  /// Reads a [JetImageSource] from its [toJson] map (dispatch on `kind`).
  factory JetImageSource.fromJson(Map<String, Object?> json) {
    final Object? kind = json['kind'];
    switch (kind) {
      case 'url':
        return UrlImageSource(json['url']! as String);
      case 'field':
        return FieldImageSource(json['field']! as String);
      case 'bytes':
        return BytesImageSource(base64Decode(json['base64']! as String));
      default:
        throw FormatException('Unknown image source kind "$kind".');
    }
  }

  /// Serializes to a JSON-safe map including the `kind` discriminator.
  Map<String, Object?> toJson();
}

/// An image fetched from a network [url] at render time.
class UrlImageSource extends JetImageSource {
  /// Creates a URL image source.
  const UrlImageSource(this.url);

  /// The http(s) URL.
  final String url;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': 'url', 'url': url};

  @override
  bool operator ==(Object other) => other is UrlImageSource && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// An image whose bytes come from a data [field], resolved at fill time.
class FieldImageSource extends JetImageSource {
  /// Creates a field-bound image source.
  const FieldImageSource(this.field);

  /// The data field name.
  final String field;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'kind': 'field', 'field': field};

  @override
  bool operator ==(Object other) =>
      other is FieldImageSource && other.field == field;

  @override
  int get hashCode => field.hashCode;
}

/// An image with [bytes] embedded directly (base64-encoded in JSON).
class BytesImageSource extends JetImageSource {
  /// Creates an embedded-bytes image source.
  BytesImageSource(this.bytes);

  /// The raw image bytes.
  final Uint8List bytes;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'kind': 'bytes', 'base64': base64Encode(bytes)};

  @override
  bool operator ==(Object other) {
    if (other is! BytesImageSource || other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);
}
```

- [ ] **Step 4: Run test to verify it passes** — `flutter test packages/jet_print/test/domain/elements/image_source_test.dart` → PASS. `dart format` + `flutter analyze packages/jet_print` → clean.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/elements/image_source.dart packages/jet_print/test/domain/elements/image_source_test.dart
git commit -m "feat(domain): add JetImageSource (url/field/bytes) and JetBoxFit"
```

---

### Task 7: ImageElement and ImageElementCodec

**Files:**
- Create: `packages/jet_print/lib/src/domain/elements/image_element.dart`
- Create: `packages/jet_print/lib/src/domain/serialization/image_element_codec.dart`
- Test: `packages/jet_print/test/domain/elements/image_element_test.dart`

- [ ] **Step 1: Write the failing test** — create `packages/jet_print/test/domain/elements/image_element_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/image_element_codec.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('image', const ImageElementCodec());

void main() {
  group('ImageElement', () {
    test('is a ReportElement with the "image" type key and default fit', () {
      const ImageElement e = ImageElement(
        id: 'logo',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        source: UrlImageSource('https://example.com/logo.png'),
      );
      expect(e, isA<ReportElement>());
      expect(e.typeKey, 'image');
      expect(e.fit, JetBoxFit.contain);
    });

    test('round-trips with a url source and explicit fit', () {
      final ElementCodecRegistry registry = _registry();
      const ImageElement e = ImageElement(
        id: 'logo',
        bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
        source: UrlImageSource('https://example.com/logo.png'),
        fit: JetBoxFit.cover,
      );
      expect(registry.decode(registry.encode(e)), e);
    });

    test('round-trips with a field source', () {
      final ElementCodecRegistry registry = _registry();
      const ImageElement e = ImageElement(
        id: 'photo',
        bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
        source: FieldImageSource('product_image'),
      );
      expect(registry.decode(registry.encode(e)), e);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test packages/jet_print/test/domain/elements/image_element_test.dart` → FAIL (`ImageElement` undefined).

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/elements/image_element.dart`:

```dart
/// An image element.
library;

import '../geometry.dart';
import '../report_element.dart';
import 'image_source.dart';

/// Draws an image from [source], scaled to [bounds] per [fit].
class ImageElement extends ReportElement {
  /// Creates an image element.
  const ImageElement({
    required super.id,
    required super.bounds,
    required this.source,
    this.fit = JetBoxFit.contain,
  });

  /// Where the image comes from.
  final JetImageSource source;

  /// How the image is scaled into [bounds].
  final JetBoxFit fit;

  @override
  String get typeKey => 'image';

  @override
  bool operator ==(Object other) =>
      other is ImageElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.source == source &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(id, bounds, source, fit);

  @override
  String toString() => 'ImageElement($id, ${fit.name})';
}
```

Create `packages/jet_print/lib/src/domain/serialization/image_element_codec.dart`:

```dart
/// JSON codec for [ImageElement].
library;

import '../elements/image_element.dart';
import '../elements/image_source.dart';
import '../geometry.dart';
import 'element_codec.dart';

/// Serializes [ImageElement] to/from its field map.
class ImageElementCodec extends ElementCodec<ImageElement> {
  /// Const constructor (the codec is stateless).
  const ImageElementCodec();

  @override
  ImageElement fromJson(Map<String, Object?> json) => ImageElement(
        id: json['id']! as String,
        bounds: JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        source: JetImageSource.fromJson(
            (json['source']! as Map).cast<String, Object?>()),
        fit: JetBoxFit.values.byName(json['fit']! as String),
      );

  @override
  Map<String, Object?> toJson(ImageElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'source': element.source.toJson(),
        'fit': element.fit.name,
      };
}
```

- [ ] **Step 4: Run test to verify it passes** — `flutter test packages/jet_print/test/domain/elements/image_element_test.dart` → PASS. `dart format` + `flutter analyze packages/jet_print` → clean.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/elements/image_element.dart packages/jet_print/lib/src/domain/serialization/image_element_codec.dart packages/jet_print/test/domain/elements/image_element_test.dart
git commit -m "feat(domain): add ImageElement with codec"
```

---

### Task 8: BarcodeElement (+ BarcodeSymbology) and BarcodeElementCodec

**Files:**
- Create: `packages/jet_print/lib/src/domain/elements/barcode_element.dart`
- Create: `packages/jet_print/lib/src/domain/serialization/barcode_element_codec.dart`
- Test: `packages/jet_print/test/domain/elements/barcode_element_test.dart`

- [ ] **Step 1: Write the failing test** — create `packages/jet_print/test/domain/elements/barcode_element_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/barcode_element_codec.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/styles/color.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('barcode', const BarcodeElementCodec());

void main() {
  group('BarcodeElement', () {
    test('is a ReportElement with the "barcode" type key and black default', () {
      const BarcodeElement e = BarcodeElement(
        id: 'qr',
        bounds: JetRect(x: 0, y: 0, width: 40, height: 40),
        symbology: BarcodeSymbology.qrCode,
        data: 'https://example.com/inv/42',
      );
      expect(e, isA<ReportElement>());
      expect(e.typeKey, 'barcode');
      expect(e.color, JetColor.black);
    });

    test('round-trips each symbology', () {
      final ElementCodecRegistry registry = _registry();
      for (final BarcodeSymbology symbology in BarcodeSymbology.values) {
        final BarcodeElement e = BarcodeElement(
          id: 'b_${symbology.name}',
          bounds: const JetRect(x: 0, y: 0, width: 60, height: 30),
          symbology: symbology,
          data: '12345678',
          color: const JetColor(0xFF202020),
        );
        expect(registry.decode(registry.encode(e)), e);
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test packages/jet_print/test/domain/elements/barcode_element_test.dart` → FAIL (`BarcodeElement` undefined).

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/elements/barcode_element.dart`:

```dart
/// A 1D/2D barcode element.
library;

import '../geometry.dart';
import '../report_element.dart';
import '../styles/color.dart';

/// The barcode symbology (encoding) to render.
enum BarcodeSymbology {
  /// 2D QR code.
  qrCode,

  /// 1D Code 128 (alphanumeric).
  code128,

  /// 1D EAN-13 / UPC retail code.
  ean13,

  /// 2D Data Matrix.
  dataMatrix,
}

/// Encodes [data] as a [symbology] barcode drawn in [color] within [bounds].
/// For this iteration [data] is a literal string; expression binding arrives
/// with the expression engine (spec 005).
class BarcodeElement extends ReportElement {
  /// Creates a barcode element.
  const BarcodeElement({
    required super.id,
    required super.bounds,
    required this.symbology,
    required this.data,
    this.color = JetColor.black,
  });

  /// The barcode encoding.
  final BarcodeSymbology symbology;

  /// The literal data to encode.
  final String data;

  /// Foreground (bar) color.
  final JetColor color;

  @override
  String get typeKey => 'barcode';

  @override
  bool operator ==(Object other) =>
      other is BarcodeElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.symbology == symbology &&
      other.data == data &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, bounds, symbology, data, color);

  @override
  String toString() => 'BarcodeElement($id, ${symbology.name})';
}
```

Create `packages/jet_print/lib/src/domain/serialization/barcode_element_codec.dart`:

```dart
/// JSON codec for [BarcodeElement].
library;

import '../elements/barcode_element.dart';
import '../geometry.dart';
import '../styles/color.dart';
import 'element_codec.dart';

/// Serializes [BarcodeElement] to/from its field map.
class BarcodeElementCodec extends ElementCodec<BarcodeElement> {
  /// Const constructor (the codec is stateless).
  const BarcodeElementCodec();

  @override
  BarcodeElement fromJson(Map<String, Object?> json) => BarcodeElement(
        id: json['id']! as String,
        bounds: JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        symbology: BarcodeSymbology.values.byName(json['symbology']! as String),
        data: json['data']! as String,
        color: json['color'] is String
            ? JetColor.fromJson(json['color']! as String)
            : JetColor.black,
      );

  @override
  Map<String, Object?> toJson(BarcodeElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'symbology': element.symbology.name,
        'data': element.data,
        if (element.color != JetColor.black) 'color': element.color.toJson(),
      };
}
```

- [ ] **Step 4: Run test to verify it passes** — `flutter test packages/jet_print/test/domain/elements/barcode_element_test.dart` → PASS. `dart format` + `flutter analyze packages/jet_print` → clean.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/elements/barcode_element.dart packages/jet_print/lib/src/domain/serialization/barcode_element_codec.dart packages/jet_print/test/domain/elements/barcode_element_test.dart
git commit -m "feat(domain): add BarcodeElement with codec"
```

---

### Task 9: registerBuiltInElementCodecs + full multi-element round-trip

**Files:**
- Create: `packages/jet_print/lib/src/domain/serialization/built_in_element_codecs.dart`
- Test: `packages/jet_print/test/domain/serialization/built_in_round_trip_test.dart`

- [ ] **Step 1: Write the failing test** — create `packages/jet_print/test/domain/serialization/built_in_round_trip_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/built_in_element_codecs.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';

void main() {
  test('registerBuiltInElementCodecs round-trips all four element types', () {
    final ElementCodecRegistry registry = ElementCodecRegistry();
    registerBuiltInElementCodecs(registry);

    const ReportTemplate template = ReportTemplate(
      name: 'Showcase',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
          type: BandType.pageHeader,
          height: 80,
          elements: <ReportElement>[
            TextElement(
              id: 'title',
              bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
              text: 'INVOICE',
              style: JetTextStyle(
                fontSize: 20,
                weight: JetFontWeight.bold,
                align: JetTextAlign.center,
              ),
            ),
            ShapeElement(
              id: 'rule',
              bounds: JetRect(x: 0, y: 30, width: 200, height: 0),
              kind: ShapeKind.line,
              style: JetBoxStyle(stroke: JetColor(0xFF000000)),
            ),
            ImageElement(
              id: 'logo',
              bounds: JetRect(x: 220, y: 0, width: 60, height: 30),
              source: UrlImageSource('https://example.com/logo.png'),
            ),
            BarcodeElement(
              id: 'qr',
              bounds: JetRect(x: 220, y: 40, width: 40, height: 40),
              symbology: BarcodeSymbology.qrCode,
              data: 'https://example.com/inv/42',
            ),
          ],
        ),
      ],
    );

    final String wire = jsonEncode(encodeTemplate(template, registry));
    final ReportTemplate decoded = decodeTemplate(
      (jsonDecode(wire) as Map).cast<String, Object?>(),
      registry,
    );
    expect(encodeTemplate(decoded, registry),
        equals(encodeTemplate(template, registry)));
    expect(decoded.bands.single.elements.length, 4);
    expect(decoded.bands.single.elements[0], isA<TextElement>());
    expect(decoded.bands.single.elements[1], isA<ShapeElement>());
    expect(decoded.bands.single.elements[2], isA<ImageElement>());
    expect(decoded.bands.single.elements[3], isA<BarcodeElement>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — `flutter test packages/jet_print/test/domain/serialization/built_in_round_trip_test.dart` → FAIL (`registerBuiltInElementCodecs` undefined).

- [ ] **Step 3: Write minimal implementation** — create `packages/jet_print/lib/src/domain/serialization/built_in_element_codecs.dart`:

```dart
/// Convenience registration of the built-in element codecs.
library;

import 'barcode_element_codec.dart';
import 'element_codec.dart';
import 'image_element_codec.dart';
import 'shape_element_codec.dart';
import 'text_element_codec.dart';

/// Registers all element types shipped with the library (`text`, `shape`,
/// `image`, `barcode`) into [registry]. Consumers add their own types with
/// further `registry.register(...)` calls (Constitution II — open/closed).
void registerBuiltInElementCodecs(ElementCodecRegistry registry) {
  registry
    ..register('text', const TextElementCodec())
    ..register('shape', const ShapeElementCodec())
    ..register('image', const ImageElementCodec())
    ..register('barcode', const BarcodeElementCodec());
}
```

- [ ] **Step 4: Run test to verify it passes** — `flutter test packages/jet_print/test/domain/serialization/built_in_round_trip_test.dart` → PASS. `dart format` + `flutter analyze packages/jet_print` → clean.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/serialization/built_in_element_codecs.dart packages/jet_print/test/domain/serialization/built_in_round_trip_test.dart
git commit -m "feat(domain): add registerBuiltInElementCodecs and full round-trip test"
```

---

### Task 10: Full-suite green, analyzer, format, CHANGELOG

**Files:**
- Modify: `packages/jet_print/CHANGELOG.md`

- [ ] **Step 1: Architecture/layer-boundary test** — `flutter test packages/jet_print/test/architecture/layer_boundaries_test.dart` → PASS (the new `styles/` and `elements/` files import no `dart:ui`/Flutter; `dart:convert`/`dart:typed_data` are pure Dart and allowed).

- [ ] **Step 2: Formatter** — `dart format --output=none --set-exit-if-changed .` → exit 0 (run `dart format .` first if needed; include any reformatted files in the Step 5 commit).

- [ ] **Step 3: Analyzer** — `flutter analyze` → "No issues found!".

- [ ] **Step 4: Full suite** — `flutter test packages/jet_print` → PASS; report the count (expected ~140).

- [ ] **Step 5: Update the changelog** — add to the `## Unreleased` / `### Added` section of `packages/jet_print/CHANGELOG.md`:

```markdown
- Visual model completion (spec 003 Part 2): style value types (`JetColor`
  with hex serialization, `JetTextStyle`, `JetBoxStyle`); text styling on
  `TextElement` (sparse-serialized); new element types `ShapeElement`
  (line/rectangle), `ImageElement` (url/field/base64-bytes sources, `JetBoxFit`),
  and `BarcodeElement` (QR / Code128 / EAN-13 / Data Matrix); and
  `registerBuiltInElementCodecs` to wire all four built-in element codecs.
```

- [ ] **Step 6: Commit**

```bash
git add packages/jet_print/CHANGELOG.md
git commit -m "docs(domain): changelog for styles and element types (003 Part 2)"
```

---

## Self-Review

**1. Spec coverage** (Part-2 scope):
- Color / text style / box style value types → Tasks 1, 2, 3 ✓
- Text styling on `TextElement` (sparse, Part-1-compatible) → Task 4 ✓
- `ShapeElement` (line/rectangle) + codec → Task 5 ✓
- Image source model (url/field/bytes) + `JetBoxFit` → Task 6 ✓
- `ImageElement` + codec → Task 7 ✓
- `BarcodeElement` (4 symbologies) + codec → Task 8 ✓
- Built-in codec registration + full multi-element JSON round-trip → Task 9 ✓
- Layer-boundary purity, green gates, changelog → Task 10 ✓
- Deferred (params/variables/groups/bindings) → explicitly out of scope for 004/005.

**2. Placeholder scan:** No "TBD/TODO/handle errors appropriately". Every code step is complete and compilable. Task 9's round-trip test uses a single `const ReportTemplate` literal with a `<ReportElement>[...]` list of the four element types.

**3. Type consistency:** Names are stable across tasks — `JetColor(argb)` / `JetColor.black` / hex `#AARRGGBB`; `JetTextStyle` (`fontFamily?`, `fontSize`, `weight:JetFontWeight`, `italic`, `color:JetColor`, `align:JetTextAlign`) / `JetTextStyle.fallback`; `JetBoxStyle(fill?,stroke?,strokeWidth)` / `JetBoxStyle.none`; `TextElement(id,bounds,text,style)`; `ShapeElement(id,bounds,kind:ShapeKind,style:JetBoxStyle,flipDiagonal)` typeKey `'shape'`; `JetImageSource` sealed (`UrlImageSource(url)` kind `'url'`, `FieldImageSource(field)` kind `'field'`, `BytesImageSource(bytes)` kind `'bytes'`+`base64`) / `JetBoxFit{contain,cover,fill,none}`; `ImageElement(id,bounds,source,fit)` typeKey `'image'`; `BarcodeElement(id,bounds,symbology:BarcodeSymbology,data,color)` typeKey `'barcode'`, `BarcodeSymbology{qrCode,code128,ean13,dataMatrix}`; codecs `Text/Shape/Image/BarcodeElementCodec`; `registerBuiltInElementCodecs(registry)` keys `'text'/'shape'/'image'/'barcode'`. Each codec's `toJson`/`fromJson` key sets match. Sparse keys (`style` on text/shape, `flipDiagonal`, `color` on barcode, `fill`/`stroke` on box, `fontFamily`) are written conditionally and read with the matching default — symmetric.
