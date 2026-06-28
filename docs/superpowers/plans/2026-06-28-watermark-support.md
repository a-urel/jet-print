# Watermark Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a report-level watermark — a faint, rotated **text** ("DRAFT") or **image** (logo) drawn behind every page's content — rendering identically on preview, PDF, PNG, and print.

**Architecture:** A new immutable `Watermark` value object on `PageFurniture`. The paint layer gains a general `rotation` capability (a base-primitive field + a centralized transform wrap in `paintFrame`, implemented per backend). At page assembly a single pre-built watermark primitive is prepended (bottom of z-order) to every page's frame. All three paint backends converge on `paintFrame`, so the watermark appears everywhere by construction.

**Tech Stack:** Dart / Flutter, `flutter_test` (incl. `matchesGoldenFile`), `package:pdf` (PDF backend), `package:vector_math` (`Matrix4` for the PDF transform).

## Global Constraints

- Run `flutter`/`dart`/`git` per repo convention: `flutter`/`dart` from `packages/jet_print`; `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (flutter leaves cwd inside the package).
- **No schema-version bump.** `watermark` is an additive omit-when-null field. Old JSON decodes with `watermark == null`. `kReportDefinitionSchemaVersion` stays `2`.
- **Existing goldens MUST stay byte-identical.** With no watermark and `rotation == 0`/`opacity == 1.0` defaults, every existing primitive and frame is unchanged. If any existing golden diffs, STOP and inspect — do not regenerate.
- **WYSIWYG (Constitution IV):** every visible change goes through `paintFrame`; never special-case one backend's geometry.
- Pure layers stay pure: `domain/` imports no Flutter rendering/`dart:ui`; `rendering/frame` and `rendering/layout` import no `dart:ui` (only `rendering/paint/canvas_painter.dart` and the rasterizer touch `dart:ui`).
- Dartdoc every new public member; `dart format` + clean `flutter analyze` gate before each commit.
- Branch is already `043-watermark-support`.

---

## File Map

- **Create** `packages/jet_print/lib/src/domain/watermark.dart` — the `Watermark` value object (Task 1).
- **Create** `packages/jet_print/lib/src/rendering/watermark_primitive.dart` — pure `buildWatermarkPrimitive(...)` (Task 6).
- **Modify** `packages/jet_print/lib/src/domain/report_definition.dart` — `PageFurniture.watermark` + comment fix (Task 2).
- **Modify** `packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart` — encode/decode watermark (Task 3).
- **Modify** `packages/jet_print/lib/src/rendering/frame/primitive.dart` — base `rotation`, `ImagePrimitive.opacity`, all 5 `==`/`hashCode` (Task 4).
- **Modify** `packages/jet_print/lib/src/rendering/paint/report_painter.dart` — `pushTransform`/`popTransform` + `paintFrame` wrap (Task 5).
- **Modify** `packages/jet_print/lib/src/rendering/paint/canvas_painter.dart` — transform impl + image opacity (Task 5).
- **Modify** `packages/jet_print/lib/src/rendering/layout/report_layouter.dart` — thread + prepend watermark (Task 7).
- **Modify** `packages/jet_print/lib/src/rendering/export/pdf_painter.dart` — PDF transform + image opacity (Task 8, the spike).
- **Modify** any test fake `ReportPainter` (Task 5 grep).
- Public export: add `watermark.dart` to the package's public library (Task 2 — wherever `report_definition.dart` is exported).

---

## Task 1: `Watermark` value object

**Files:**
- Create: `packages/jet_print/lib/src/domain/watermark.dart`
- Test: `packages/jet_print/test/domain/watermark_test.dart`

**Interfaces:**
- Produces: `class Watermark` with const ctor `Watermark({String? text, JetTextStyle textStyle, Uint8List? imageBytes, JetBoxFit imageFit, double opacity, double angleDegrees})`, `copyWith(...)`, `toJson()`, `Watermark.fromJson(Map)`, value `==`/`hashCode`. Defaults: `textStyle = JetTextStyle.fallback`, `imageFit = JetBoxFit.contain`, `opacity = 0.15`, `angleDegrees = -45`.

- [ ] **Step 1: Write the failing test.**

```dart
// packages/jet_print/test/domain/watermark_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/watermark.dart';

void main() {
  group('Watermark', () {
    test('defaults: opacity 0.15, angle -45, contain', () {
      const wm = Watermark(text: 'DRAFT');
      expect(wm.opacity, 0.15);
      expect(wm.angleDegrees, -45);
      expect(wm.imageFit, JetBoxFit.contain);
      expect(wm.textStyle, JetTextStyle.fallback);
      expect(wm.imageBytes, isNull);
    });

    test('opacity is clamped to 0..1', () {
      expect(const Watermark(text: 'x', opacity: 5).opacity, 1.0);
      expect(const Watermark(text: 'x', opacity: -1).opacity, 0.0);
    });

    test('value equality (text variant)', () {
      const a = Watermark(text: 'DRAFT', angleDegrees: -30);
      const b = Watermark(text: 'DRAFT', angleDegrees: -30);
      const c = Watermark(text: 'DRAFT', angleDegrees: 0);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('value equality compares image bytes', () {
      final a = Watermark(imageBytes: Uint8List.fromList(<int>[1, 2, 3]));
      final b = Watermark(imageBytes: Uint8List.fromList(<int>[1, 2, 3]));
      final c = Watermark(imageBytes: Uint8List.fromList(<int>[1, 2, 9]));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith replaces only named fields', () {
      const a = Watermark(text: 'DRAFT', opacity: 0.2);
      expect(a.copyWith(opacity: 0.5).opacity, 0.5);
      expect(a.copyWith(opacity: 0.5).text, 'DRAFT');
    });

    test('JSON round-trips the text variant', () {
      const a = Watermark(
          text: 'CONFIDENTIAL',
          opacity: 0.2,
          angleDegrees: -30,
          textStyle: JetTextStyle(fontSize: 72));
      expect(Watermark.fromJson(a.toJson()), a);
    });

    test('JSON round-trips the image variant', () {
      final a = Watermark(
          imageBytes: Uint8List.fromList(<int>[10, 20, 30, 40]),
          imageFit: JetBoxFit.cover,
          opacity: 0.1);
      expect(Watermark.fromJson(a.toJson()), a);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `cd packages/jet_print && flutter test test/domain/watermark_test.dart`
Expected: FAIL — `watermark.dart` does not exist / `Watermark` undefined.

- [ ] **Step 3: Write the implementation.**

```dart
// packages/jet_print/lib/src/domain/watermark.dart
/// A report-level watermark: faint text OR image drawn behind every page,
/// rotated by [angleDegrees] and dimmed by [opacity]. Pure domain (no
/// rendering/`dart:ui`). Set [text] OR [imageBytes], not both — if both are
/// non-null, the renderer draws the text (see `buildWatermarkPrimitive`).
library;

import 'dart:typed_data';

import 'elements/image_source.dart';
import 'styles/text_style.dart';

/// An immutable watermark description carried by `PageFurniture.watermark`.
class Watermark {
  /// Creates a watermark. [opacity] is clamped to 0..1. Use [text] for a text
  /// watermark or [imageBytes] for an image watermark.
  const Watermark({
    this.text,
    this.textStyle = JetTextStyle.fallback,
    this.imageBytes,
    this.imageFit = JetBoxFit.contain,
    double opacity = 0.15,
    this.angleDegrees = -45,
  }) : opacity = opacity < 0
            ? 0
            : opacity > 1
                ? 1
                : opacity;

  /// Reads a [Watermark] from its [toJson] map.
  factory Watermark.fromJson(Map<String, Object?> json) => Watermark(
        text: json['text'] as String?,
        textStyle: json['textStyle'] == null
            ? JetTextStyle.fallback
            : JetTextStyle.fromJson(
                (json['textStyle']! as Map).cast<String, Object?>()),
        imageBytes: json['imageBytes'] == null
            ? null
            : base64Decode(json['imageBytes']! as String),
        imageFit: json['imageFit'] == null
            ? JetBoxFit.contain
            : JetBoxFit.values.byName(json['imageFit']! as String),
        opacity: (json['opacity']! as num).toDouble(),
        angleDegrees: (json['angleDegrees']! as num).toDouble(),
      );

  /// The watermark caption, or null for an image watermark.
  final String? text;

  /// Appearance of [text]. The renderer multiplies the color's alpha by
  /// [opacity].
  final JetTextStyle textStyle;

  /// Encoded image bytes (PNG/JPEG), or null for a text watermark.
  final Uint8List? imageBytes;

  /// How the image fills its centered box.
  final JetBoxFit imageFit;

  /// 0..1; the watermark's overall opacity. 0 draws nothing.
  final double opacity;

  /// Rotation in degrees, about the page center. Default -45 (bottom-left to
  /// top-right).
  final double angleDegrees;

  /// A copy with the given fields replaced. Cannot clear [text]/[imageBytes]
  /// back to null (construct a new [Watermark] for that).
  Watermark copyWith({
    String? text,
    JetTextStyle? textStyle,
    Uint8List? imageBytes,
    JetBoxFit? imageFit,
    double? opacity,
    double? angleDegrees,
  }) =>
      Watermark(
        text: text ?? this.text,
        textStyle: textStyle ?? this.textStyle,
        imageBytes: imageBytes ?? this.imageBytes,
        imageFit: imageFit ?? this.imageFit,
        opacity: opacity ?? this.opacity,
        angleDegrees: angleDegrees ?? this.angleDegrees,
      );

  /// Serializes to a JSON-safe map (image bytes base64; omit-when-null).
  Map<String, Object?> toJson() => <String, Object?>{
        if (text != null) 'text': text,
        'textStyle': textStyle.toJson(),
        if (imageBytes != null) 'imageBytes': base64Encode(imageBytes!),
        'imageFit': imageFit.name,
        'opacity': opacity,
        'angleDegrees': angleDegrees,
      };

  @override
  bool operator ==(Object other) {
    if (other is! Watermark ||
        other.text != text ||
        other.textStyle != textStyle ||
        other.imageFit != imageFit ||
        other.opacity != opacity ||
        other.angleDegrees != angleDegrees) {
      return false;
    }
    final Uint8List? a = imageBytes;
    final Uint8List? b = other.imageBytes;
    if ((a == null) != (b == null)) return false;
    if (a != null && b != null) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
      text,
      textStyle,
      imageFit,
      opacity,
      angleDegrees,
      imageBytes == null ? null : Object.hashAll(imageBytes!));

  @override
  String toString() => 'Watermark(${text != null ? 'text "$text"' : 'image'}, '
      'opacity: $opacity, angle: $angleDegrees)';
}
```

`base64Encode`/`base64Decode` come from `dart:convert` — add `import 'dart:convert';` at the top alongside `dart:typed_data`.

- [ ] **Step 4: Run to verify it passes.**

Run: `cd packages/jet_print && flutter test test/domain/watermark_test.dart`
Expected: PASS (all 7 tests).

- [ ] **Step 5: Analyze + format, then commit.**

```bash
cd packages/jet_print && dart format lib/src/domain/watermark.dart test/domain/watermark_test.dart && flutter analyze lib/src/domain/watermark.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/watermark.dart packages/jet_print/test/domain/watermark_test.dart
git commit -m "feat(domain): Watermark value object (text|image, opacity, angle)"
```

---

## Task 2: `PageFurniture.watermark` field

**Files:**
- Modify: `packages/jet_print/lib/src/domain/report_definition.dart:29-92`
- Test: `packages/jet_print/test/domain/report_definition_test.dart` (extend; if absent, create with just the watermark group)

**Interfaces:**
- Consumes: `Watermark` (Task 1).
- Produces: `PageFurniture({..., Watermark? watermark})`, `PageFurniture.watermark`, `copyWith({..., Watermark? watermark})`. `copyWith` cannot null-out `watermark` (matches every existing furniture slot).

- [ ] **Step 1: Write the failing test.**

```dart
// add to test/domain/report_definition_test.dart
import 'package:jet_print/src/domain/watermark.dart';
// ...
group('PageFurniture.watermark', () {
  test('defaults to null and is held', () {
    expect(const PageFurniture().watermark, isNull);
    const wm = Watermark(text: 'DRAFT');
    expect(const PageFurniture(watermark: wm).watermark, wm);
  });
  test('participates in equality', () {
    const a = PageFurniture(watermark: Watermark(text: 'DRAFT'));
    const b = PageFurniture(watermark: Watermark(text: 'DRAFT'));
    const c = PageFurniture(watermark: Watermark(text: 'OTHER'));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
  test('copyWith sets watermark', () {
    const wm = Watermark(text: 'DRAFT');
    expect(const PageFurniture().copyWith(watermark: wm).watermark, wm);
  });
});
```

- [ ] **Step 2: Run to verify it fails.**

Run: `cd packages/jet_print && flutter test test/domain/report_definition_test.dart`
Expected: FAIL — `PageFurniture` has no `watermark` named parameter.

- [ ] **Step 3: Implement.** In `report_definition.dart`, add the import, the constructor param, field, `copyWith` param+wiring, `==`, `hashCode`, `toString`, and fix the reserved-`background` comment.

Add near the other imports (line ~16-22):
```dart
import 'watermark.dart';
```

Constructor (after `this.background,`):
```dart
  const PageFurniture({
    this.pageHeader,
    this.pageFooter,
    this.columnHeader,
    this.columnFooter,
    this.background,
    this.watermark,
  });
```

Field — replace the existing `background` doc block (lines 51-52) with:
```dart
  /// **Reserved** — not laid out (future frame/border layer).
  final Band? background;

  /// The page watermark (faint text/image behind content), or null. Unlike the
  /// reserved [background] band, this is laid out on every page.
  final Watermark? watermark;
```

`copyWith` (add param + wiring):
```dart
  PageFurniture copyWith({
    Band? pageHeader,
    Band? pageFooter,
    Band? columnHeader,
    Band? columnFooter,
    Band? background,
    Watermark? watermark,
  }) =>
      PageFurniture(
        pageHeader: pageHeader ?? this.pageHeader,
        pageFooter: pageFooter ?? this.pageFooter,
        columnHeader: columnHeader ?? this.columnHeader,
        columnFooter: columnFooter ?? this.columnFooter,
        background: background ?? this.background,
        watermark: watermark ?? this.watermark,
      );
```

`==` — add `&& other.watermark == watermark` to the chain. `hashCode`:
```dart
  @override
  int get hashCode => Object.hash(pageHeader, pageFooter, columnHeader,
      columnFooter, background, watermark);
```

`toString` — add to the list: `if (watermark != null) 'watermark',`.

Also update the class-level doc comment (lines 24-28) — the phrase listing `background` as reserved is fine, but append: watermark is laid out (not reserved). Minimal: change nothing else.

- [ ] **Step 4: Run to verify it passes.**

Run: `cd packages/jet_print && flutter test test/domain/report_definition_test.dart`
Expected: PASS.

- [ ] **Step 5: Export the type.** Confirm `Watermark` is reachable from the package's public API. Find the public library file:

Run: `cd packages/jet_print && grep -rn "report_definition.dart" lib/jet_print.dart lib/*.dart`
If `report_definition.dart` is exported there, add an adjacent `export 'src/domain/watermark.dart';` line in the same file (mirror the surrounding `export` style). If exports are barrel-style via `src/`, follow that pattern instead.

- [ ] **Step 6: Analyze + format, commit.**

```bash
cd packages/jet_print && dart format lib/src/domain/report_definition.dart && flutter analyze lib/src/domain/report_definition.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/report_definition.dart packages/jet_print/test/domain/report_definition_test.dart packages/jet_print/lib/
git commit -m "feat(domain): PageFurniture.watermark + export; background comment fix"
```

---

## Task 3: Watermark serialization

**Files:**
- Modify: `packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart:53-67, 190-203`
- Test: `packages/jet_print/test/domain/serialization/report_definition_codec_test.dart` (extend)

**Interfaces:**
- Consumes: `Watermark.toJson`/`fromJson` (Task 1), `PageFurniture.watermark` (Task 2).
- Produces: round-trip of `furniture.watermark` through `encodeDefinition`/`decodeDefinition`; no schema-version change.

- [ ] **Step 1: Write the failing test.**

```dart
// add to report_definition_codec_test.dart
import 'package:jet_print/src/domain/watermark.dart';
// ...
test('round-trips a text watermark with no schema bump', () {
  final def = _minimalDef().copyWithFurniture(
      const PageFurniture(watermark: Watermark(text: 'DRAFT', opacity: 0.2)));
  final Map<String, Object?> json =
      encodeDefinition(def, ElementCodecRegistry.standard());
  expect(json['schemaVersion'], 2);
  final ReportDefinition back =
      decodeDefinition(json, ElementCodecRegistry.standard());
  expect(back.furniture.watermark, const Watermark(text: 'DRAFT', opacity: 0.2));
});

test('absent watermark decodes to null (old documents)', () {
  final def = _minimalDef();
  final Map<String, Object?> json =
      encodeDefinition(def, ElementCodecRegistry.standard());
  expect((json['furniture'] as Map?)?.containsKey('watermark') ?? false, isFalse);
  expect(decodeDefinition(json, ElementCodecRegistry.standard())
      .furniture.watermark, isNull);
});
```

> Mirror the file's existing helpers for `_minimalDef()`, `copyWithFurniture` (or inline a `ReportDefinition(... furniture: ...)`), and `ElementCodecRegistry.standard()` — read the top of the existing test file first and reuse whatever constructor pattern it already uses. The behavioral asserts (schemaVersion 2, round-trip equality, absent→null) are the point.

- [ ] **Step 2: Run to verify it fails.**

Run: `cd packages/jet_print && flutter test test/domain/serialization/report_definition_codec_test.dart`
Expected: FAIL — encoded furniture has no `watermark` key; decoded watermark is null after round-trip of a non-null watermark.

- [ ] **Step 3: Implement.** Add the import `import '../watermark.dart';` to the codec. Extend `_encodeFurniture` (the watermark needs no `registry`):

```dart
Map<String, Object?> _encodeFurniture(
    PageFurniture f, ElementCodecRegistry registry) {
  return <String, Object?>{
    if (f.pageHeader != null)
      'pageHeader': _encodeBand(f.pageHeader!, registry),
    if (f.pageFooter != null)
      'pageFooter': _encodeBand(f.pageFooter!, registry),
    if (f.columnHeader != null)
      'columnHeader': _encodeBand(f.columnHeader!, registry),
    if (f.columnFooter != null)
      'columnFooter': _encodeBand(f.columnFooter!, registry),
    if (f.background != null)
      'background': _encodeBand(f.background!, registry),
    if (f.watermark != null) 'watermark': f.watermark!.toJson(),
  };
}
```

Extend `_decodeFurniture`:
```dart
  return PageFurniture(
    pageHeader: _decodeBandOrNull(f['pageHeader'], registry),
    pageFooter: _decodeBandOrNull(f['pageFooter'], registry),
    columnHeader: _decodeBandOrNull(f['columnHeader'], registry),
    columnFooter: _decodeBandOrNull(f['columnFooter'], registry),
    background: _decodeBandOrNull(f['background'], registry),
    watermark: f['watermark'] == null
        ? null
        : Watermark.fromJson((f['watermark']! as Map).cast<String, Object?>()),
  );
```

- [ ] **Step 4: Run to verify it passes.**

Run: `cd packages/jet_print && flutter test test/domain/serialization/report_definition_codec_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + format, commit.**

```bash
cd packages/jet_print && dart format lib/src/domain/serialization/report_definition_codec.dart && flutter analyze lib/src/domain/serialization/report_definition_codec.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart packages/jet_print/test/domain/serialization/report_definition_codec_test.dart
git commit -m "feat(serialization): encode/decode PageFurniture.watermark (no schema bump)"
```

---

## Task 4: Primitive `rotation` + `ImagePrimitive.opacity`

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/frame/primitive.dart`
- Test: `packages/jet_print/test/rendering/frame/primitive_test.dart` (extend; create if absent)

**Interfaces:**
- Produces: `FramePrimitive.rotation` (double, radians, default `0`) on the sealed base; `ImagePrimitive.opacity` (double, default `1.0`); both folded into every subclass `==`/`hashCode`. All 5 subclass constructors accept optional `super.rotation`.

- [ ] **Step 1: Write the failing test.**

```dart
// packages/jet_print/test/rendering/frame/primitive_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

void main() {
  const b = JetRect(x: 0, y: 0, width: 10, height: 10);

  test('rotation defaults to 0 on every primitive', () {
    expect(const RectPrimitive(bounds: b).rotation, 0);
    expect(
        const LinePrimitive(
                bounds: b,
                start: JetOffset(0, 0),
                end: JetOffset(1, 1),
                color: JetColor.black)
            .rotation,
        0);
  });

  test('rotation breaks equality (base field is compared)', () {
    const a = RectPrimitive(bounds: b, fill: JetColor.black);
    const c =
        RectPrimitive(bounds: b, fill: JetColor.black, rotation: 0.5);
    expect(a, isNot(c));
    expect(a.hashCode, isNot(c.hashCode));
  });

  test('ImagePrimitive.opacity defaults to 1.0 and is compared', () {
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);
    final a = ImagePrimitive(bounds: b, bytes: bytes);
    final c = ImagePrimitive(bounds: b, bytes: bytes, opacity: 0.15);
    expect(a.opacity, 1.0);
    expect(a, isNot(c));
    expect(a.hashCode, isNot(c.hashCode));
  });
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/frame/primitive_test.dart`
Expected: FAIL — no `rotation` param on `RectPrimitive`; no `opacity` on `ImagePrimitive`.

- [ ] **Step 3: Implement.** In `primitive.dart`:

Base class (lines 15-25):
```dart
sealed class FramePrimitive {
  /// Creates a primitive bounded by [bounds] (page points), optionally tagged
  /// with the originating [elementId] and rotated by [rotation].
  const FramePrimitive(
      {required this.bounds, this.elementId, this.rotation = 0});

  /// Position and size, in page points.
  final JetRect bounds;

  /// The originating element's id, or null (e.g. chrome).
  final String? elementId;

  /// Clockwise rotation in radians, applied about [bounds]'s center by the
  /// paint layer. Default 0 (no rotation) — keeps existing frames byte-identical.
  final double rotation;
}
```

For EACH of the 5 subclasses: add `super.rotation,` to the constructor parameter list, add `other.rotation == rotation &&` to `==`, and add `rotation` to the `Object.hash(...)` argument list. Worked examples:

`TextRunPrimitive`:
```dart
  const TextRunPrimitive({
    required super.bounds,
    required this.lines,
    required this.style,
    required this.fontFamily,
    super.elementId,
    super.rotation,
  });
  // == : add `other.rotation == rotation &&`
  // hashCode: Object.hash(bounds, elementId, rotation, style, fontFamily,
  //   Object.hashAll(lines));
```

`ImagePrimitive` (also gains `opacity`):
```dart
  const ImagePrimitive({
    required super.bounds,
    required this.bytes,
    this.fit = JetBoxFit.contain,
    this.opacity = 1.0,
    super.elementId,
    super.rotation,
  });

  /// Encoded image bytes.
  final Uint8List bytes;

  /// How the image fills [bounds].
  final JetBoxFit fit;

  /// 0..1 constant opacity applied when drawing. Default 1.0 (opaque).
  final double opacity;

  @override
  bool operator ==(Object other) {
    if (other is! ImagePrimitive ||
        other.bounds != bounds ||
        other.elementId != elementId ||
        other.rotation != rotation ||
        other.fit != fit ||
        other.opacity != opacity ||
        other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
      bounds, elementId, rotation, fit, opacity, Object.hashAll(bytes));
```

`LinePrimitive`, `RectPrimitive`, `PathPrimitive`: add `super.rotation,` to the constructor, `other.rotation == rotation &&` to `==`, and `rotation` into the `Object.hash(...)` list (place it right after `elementId` for consistency).

- [ ] **Step 4: Run to verify it passes.**

Run: `cd packages/jet_print && flutter test test/rendering/frame/primitive_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full frame + rendering suite (regression).**

Run: `cd packages/jet_print && flutter test test/rendering`
Expected: PASS — defaults keep all existing primitives equal and all goldens byte-identical. If a golden diffs, STOP (a default leaked).

- [ ] **Step 6: Analyze + format, commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/frame/primitive.dart test/rendering/frame/primitive_test.dart && flutter analyze lib/src/rendering/frame/primitive.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/frame/primitive.dart packages/jet_print/test/rendering/frame/primitive_test.dart
git commit -m "feat(frame): primitive rotation + ImagePrimitive opacity (defaults inert)"
```

---

## Task 5: Paint interface transform + Canvas implementation + image opacity

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/paint/report_painter.dart`
- Modify: `packages/jet_print/lib/src/rendering/paint/canvas_painter.dart`
- Modify: any test fake `ReportPainter` (grep — Step 0)
- Test: `packages/jet_print/test/rendering/paint/report_painter_test.dart` (extend; create if absent)

**Interfaces:**
- Consumes: `FramePrimitive.rotation`, `ImagePrimitive.opacity` (Task 4); `JetOffset` (`domain/geometry.dart`).
- Produces: `ReportPainter.pushTransform(JetOffset center, double radians)` + `popTransform()`; `paintFrame` wraps each rotated primitive's draw in push/pop; `CanvasPainter` implements both via `Canvas.save/translate/rotate/restore` and applies `opacity` in `drawImage`.

- [ ] **Step 0: Find every `ReportPainter` implementer (so none breaks the abstract contract).**

Run: `cd packages/jet_print && grep -rln "implements ReportPainter\|extends ReportPainter" lib test`
Expected: `canvas_painter.dart`, `pdf_painter.dart`, and possibly a test fake. Note each — every one needs `pushTransform`/`popTransform`. PdfPainter gets a real impl in Task 8; here give it a **temporary no-op** (`void pushTransform(JetOffset c, double r) {}` / `void popTransform() {}`) so the package compiles, with a `// TODO(Task 8): real PDF transform` marker. Give any test fake a recording or no-op impl.

- [ ] **Step 1: Write the failing test** (a recording fake asserts the wrap):

```dart
// packages/jet_print/test/rendering/paint/report_painter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';

class _RecordingPainter implements ReportPainter {
  final List<String> calls = <String>[];
  @override
  void beginPage(PageFormat format) => calls.add('begin');
  @override
  void endPage() => calls.add('end');
  @override
  void pushTransform(JetOffset center, double radians) =>
      calls.add('push(${center.dx},${center.dy},$radians)');
  @override
  void popTransform() => calls.add('pop');
  @override
  void drawRect(RectPrimitive p) => calls.add('rect');
  @override
  void drawTextRun(TextRunPrimitive p) => calls.add('text');
  @override
  void drawImage(ImagePrimitive p) => calls.add('image');
  @override
  void drawLine(LinePrimitive p) => calls.add('line');
  @override
  void drawPath(PathPrimitive p) => calls.add('path');
}

void main() {
  const page = PageFormat(width: 100, height: 100, margins: JetEdgeInsets.all(0));

  test('rotated primitive is wrapped in push/pop about its center', () async {
    final frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 10, y: 20, width: 40, height: 60),
              fill: JetColor.black,
              rotation: 0.5)))
        .build();
    final p = _RecordingPainter();
    await paintFrame(frame, p);
    // center = (10+20, 20+30) = (30, 50)
    expect(p.calls, <String>['begin', 'push(30.0,50.0,0.5)', 'rect', 'pop', 'end']);
  });

  test('unrotated primitive is NOT wrapped', () async {
    final frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 1, height: 1),
              fill: JetColor.black)))
        .build();
    final p = _RecordingPainter();
    await paintFrame(frame, p);
    expect(p.calls, <String>['begin', 'rect', 'end']);
  });
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/paint/report_painter_test.dart`
Expected: FAIL — `pushTransform`/`popTransform` not in `ReportPainter`.

- [ ] **Step 3: Implement the interface + wrap.** In `report_painter.dart` add `import '../../domain/geometry.dart';`, two abstract methods, and the wrap:

```dart
abstract class ReportPainter {
  Future<void> prepare(PageFrame frame) async {}
  void beginPage(PageFormat format);

  /// Pushes a rotation of [radians] about [center] (page points). Paired with
  /// [popTransform]. Backends save/restore their own graphics state.
  void pushTransform(JetOffset center, double radians);

  /// Restores the state saved by the matching [pushTransform].
  void popTransform();

  void drawTextRun(TextRunPrimitive primitive);
  // ...unchanged drawImage/drawLine/drawRect/drawPath/endPage...
}

Future<void> paintFrame(PageFrame frame, ReportPainter painter) async {
  await painter.prepare(frame);
  painter.beginPage(frame.page);
  for (final FramePrimitive primitive in frame.primitives) {
    final bool rotated = primitive.rotation != 0;
    if (rotated) {
      final JetRect b = primitive.bounds;
      painter.pushTransform(
          JetOffset(b.x + b.width / 2, b.y + b.height / 2), primitive.rotation);
    }
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
    if (rotated) painter.popTransform();
  }
  painter.endPage();
}
```

- [ ] **Step 4: Implement in `CanvasPainter`.** Add `import '../../domain/geometry.dart';`, the two methods, and opacity in `drawImage`:

```dart
  @override
  void pushTransform(JetOffset center, double radians) {
    _canvas.save();
    _canvas.translate(center.dx, center.dy);
    _canvas.rotate(radians);
    _canvas.translate(-center.dx, -center.dy);
  }

  @override
  void popTransform() => _canvas.restore();

  @override
  void drawImage(ImagePrimitive p) {
    final ui.Image? img = _decoded[p];
    if (img == null) return;
    final ImageFit fit = computeImageFit(
        p.fit, p.bounds, img.width.toDouble(), img.height.toDouble());
    _canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(fit.src.x, fit.src.y, fit.src.width, fit.src.height),
      ui.Rect.fromLTWH(fit.dst.x, fit.dst.y, fit.dst.width, fit.dst.height),
      ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, p.opacity),
    );
  }
```

> `Paint.color`'s alpha is the image draw opacity for `drawImageRect`; RGB is ignored for images. At `opacity == 1.0` this is identical to the previous `ui.Paint()` (opaque) — existing image goldens stay byte-identical.

Add the temporary no-op (or real, per Task 9) to `PdfPainter` and any fake found in Step 0.

- [ ] **Step 5: Run to verify it passes.**

Run: `cd packages/jet_print && flutter test test/rendering/paint/report_painter_test.dart`
Expected: PASS.

- [ ] **Step 6: Full rendering suite (regression — opacity default + interface change must not move goldens).**

Run: `cd packages/jet_print && flutter test test/rendering`
Expected: PASS, goldens byte-identical.

- [ ] **Step 7: Analyze + format, commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/paint/report_painter.dart lib/src/rendering/paint/canvas_painter.dart lib/src/rendering/export/pdf_painter.dart test/rendering/paint/report_painter_test.dart && flutter analyze lib/src/rendering/paint
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/paint/ packages/jet_print/lib/src/rendering/export/pdf_painter.dart packages/jet_print/test/rendering/paint/report_painter_test.dart
git commit -m "feat(paint): pushTransform/popTransform wrap + Canvas rotation & image opacity"
```

---

## Task 6: Pure watermark-primitive builder

**Files:**
- Create: `packages/jet_print/lib/src/rendering/watermark_primitive.dart`
- Test: `packages/jet_print/test/rendering/watermark_primitive_test.dart`

**Interfaces:**
- Consumes: `Watermark` (Task 1), `TextMeasurer`/`MeasuredText` (`rendering/text/text_measurer.dart`), `PageFormat`, primitives + `rotation`/`opacity` (Task 4).
- Produces: `FramePrimitive? buildWatermarkPrimitive(Watermark wm, PageFormat page, TextMeasurer measurer)` — a centered, rotated `TextRunPrimitive` (text, color alpha × opacity) or `ImagePrimitive` (50%-page centered box, `opacity` set), or `null` when nothing should draw.

- [ ] **Step 1: Write the failing test.**

```dart
// packages/jet_print/test/rendering/watermark_primitive_test.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/watermark.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/watermark_primitive.dart';

void main() {
  final measurer = MetricsTextMeasurer(FontRegistry()..registerDefault());
  const page = PageFormat(width: 400, height: 600, margins: JetEdgeInsets.all(20));

  test('text watermark → centered, rotated, alpha-scaled TextRunPrimitive', () {
    const wm = Watermark(
        text: 'DRAFT',
        opacity: 0.5,
        angleDegrees: -45,
        textStyle: JetTextStyle(fontSize: 80, color: JetColor(0xFF000000)));
    final p = buildWatermarkPrimitive(wm, page, measurer)! as TextRunPrimitive;
    expect(p.bounds.width, page.width); // full-width box → align centers it
    expect(p.style.align, JetTextAlign.center);
    expect(p.rotation, closeTo(-45 * math.pi / 180, 1e-9));
    // 0xFF alpha × 0.5 = 0x80
    expect((p.style.color.argb >> 24) & 0xff, 0x80);
  });

  test('image watermark → centered ImagePrimitive carrying opacity & fit', () {
    final wm = Watermark(
        imageBytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        imageFit: JetBoxFit.cover,
        opacity: 0.2,
        angleDegrees: 0);
    final p = buildWatermarkPrimitive(wm, page, measurer)! as ImagePrimitive;
    expect(p.opacity, 0.2);
    expect(p.fit, JetBoxFit.cover);
    expect(p.rotation, 0);
    // centered box
    expect(p.bounds.x + p.bounds.width / 2, closeTo(page.width / 2, 1e-9));
    expect(p.bounds.y + p.bounds.height / 2, closeTo(page.height / 2, 1e-9));
  });

  test('opacity 0 → null', () {
    expect(buildWatermarkPrimitive(
        const Watermark(text: 'x', opacity: 0), page, measurer), isNull);
  });

  test('empty/whitespace text and no image → null', () {
    expect(buildWatermarkPrimitive(
        const Watermark(text: '   '), page, measurer), isNull);
    expect(buildWatermarkPrimitive(
        const Watermark(), page, measurer), isNull);
  });

  test('both text and image set → text wins', () {
    final wm = Watermark(
        text: 'DRAFT', imageBytes: Uint8List.fromList(<int>[1, 2, 3]));
    expect(buildWatermarkPrimitive(wm, page, measurer), isA<TextRunPrimitive>());
  });
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/watermark_primitive_test.dart`
Expected: FAIL — `watermark_primitive.dart` / `buildWatermarkPrimitive` undefined.

- [ ] **Step 3: Implement.**

```dart
// packages/jet_print/lib/src/rendering/watermark_primitive.dart
/// Builds the single positioned primitive for a page watermark (pure: no
/// `dart:ui`). Centered on the full page rect, rotated by the watermark angle,
/// dimmed by its opacity. Text takes precedence when both text and image are set.
library;

import 'dart:math' as math;

import '../domain/page_format.dart';
import '../domain/styles/color.dart';
import '../domain/styles/text_style.dart';
import '../domain/watermark.dart';
import 'frame/primitive.dart';
import 'text/text_measurer.dart';

/// Returns the watermark primitive for [page], or null when nothing should be
/// drawn (opacity 0, empty text, or no content). The result is identical for
/// every page (the page size is constant), so callers build it once.
FramePrimitive? buildWatermarkPrimitive(
    Watermark wm, PageFormat page, TextMeasurer measurer) {
  if (wm.opacity <= 0) return null;
  final double radians = wm.angleDegrees * math.pi / 180;

  final String? text = wm.text;
  if (text != null && text.trim().isNotEmpty) {
    final MeasuredText m = measurer.measure(text, wm.textStyle);
    final double height = m.lines.isEmpty
        ? 0
        : m.lines.last.top + m.lines.last.height;
    final JetColor faded = _scaleAlpha(wm.textStyle.color, wm.opacity);
    return TextRunPrimitive(
      bounds: JetRect(
          x: 0, y: (page.height - height) / 2, width: page.width, height: height),
      lines: m.lines,
      style: wm.textStyle.copyWith(color: faded, align: JetTextAlign.center),
      fontFamily: m.fontFamily,
      rotation: radians,
    );
  }

  final image = wm.imageBytes;
  if (image != null && image.isNotEmpty) {
    final double w = page.width * 0.5;
    final double h = page.height * 0.5;
    return ImagePrimitive(
      bounds: JetRect(
          x: (page.width - w) / 2, y: (page.height - h) / 2, width: w, height: h),
      bytes: image,
      fit: wm.imageFit,
      opacity: wm.opacity,
      rotation: radians,
    );
  }
  return null;
}

JetColor _scaleAlpha(JetColor c, double factor) {
  final int a = (((c.argb >> 24) & 0xff) * factor).round().clamp(0, 255);
  return JetColor((a << 24) | (c.argb & 0x00ffffff));
}
```

> VERIFY before trusting: that `MeasuredText` exposes `.lines` (`List<TextLine>`) and `.fontFamily` (the text renderer at `text_element_renderer.dart:30-37` uses exactly these), and `TextLine` has `.top`/`.height`. If `measure` requires `maxWidth`, omit it (watermark text is one unwrapped line).

- [ ] **Step 4: Run to verify it passes.**

Run: `cd packages/jet_print && flutter test test/rendering/watermark_primitive_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Analyze + format, commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/watermark_primitive.dart test/rendering/watermark_primitive_test.dart && flutter analyze lib/src/rendering/watermark_primitive.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/watermark_primitive.dart packages/jet_print/test/rendering/watermark_primitive_test.dart
git commit -m "feat(rendering): pure buildWatermarkPrimitive (centered, rotated, dimmed)"
```

---

## Task 7: Thread the watermark through layout (prepend per page)

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/layout/report_layouter.dart` (LazyLayout ctor + fields ~87-135; `buildPage` ~272; `layoutLazyDefinition` ~393-735)
- Test: `packages/jet_print/test/rendering/layout/report_layouter_watermark_test.dart`

**Interfaces:**
- Consumes: `buildWatermarkPrimitive` (Task 6), `def.furniture.watermark`, `_measurer` (already on `ReportLayouter`).
- Produces: every page frame begins with the watermark primitive when `furniture.watermark` is set and non-empty; nothing changes otherwise.

- [ ] **Step 1: Write the failing test.**

```dart
// packages/jet_print/test/rendering/layout/report_layouter_watermark_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/watermark.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
// + the project's usual imports to build a tiny ReportDefinition + fill it.
// Read an existing test in test/rendering/layout/ and copy its setup helpers
// (FilledReport build, ReportLayouter().layoutLazyDefinition, etc.).

void main() {
  test('watermark is the FIRST primitive on every page', () {
    final def = _tinyDef(watermark: const Watermark(
        text: 'DRAFT', textStyle: JetTextStyle(fontSize: 48)));
    final layout = _layout(def); // ReportLayouter().layoutLazyDefinition(def, filled)
    final frame = layout.buildPage(0);
    expect(frame.primitives.first, isA<TextRunPrimitive>());
    expect((frame.primitives.first as TextRunPrimitive).rotation, isNot(0));
  });

  test('no watermark → no extra primitive (byte-identical to before)', () {
    final def = _tinyDef(watermark: null);
    final layout = _layout(def);
    final frame = layout.buildPage(0);
    expect(frame.primitives.whereType<TextRunPrimitive>()
        .where((p) => p.rotation != 0), isEmpty);
  });
}
```

> Build `_tinyDef`/`_layout` by mirroring the nearest existing layouter test (e.g. `test/rendering/layout/report_layouter_test.dart`) — reuse its `FilledReport` construction and `ReportLayouter().layoutLazyDefinition(def, filled)` call. The two assertions (watermark is `primitives.first`; absent → none) are the deliverable.

- [ ] **Step 2: Run to verify it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/layout/report_layouter_watermark_test.dart`
Expected: FAIL — no watermark primitive emitted.

- [ ] **Step 3: Implement.**

(a) Add imports to `report_layouter.dart` (with the other rendering imports):
```dart
import '../watermark_primitive.dart';
```
(`FramePrimitive` is already importable via `frame/primitive.dart`; confirm it's imported, add if missing.)

(b) `LazyLayout._` — add a field + ctor param:
```dart
  // field, near _bodyBottom:
  final FramePrimitive? _watermark;
  // ctor param (named, optional):
  FramePrimitive? watermark,
  // initializer:
  _watermark = watermark,
```

(c) `buildPage` — prepend the watermark FIRST, before the title/body loop:
```dart
  PageFrame buildPage(int index) {
    if (index < 0 || index >= pageCount) {
      throw RangeError.range(index, 0, pageCount - 1, 'index');
    }
    final FrameBuilder fb = FrameBuilder(_page);

    final FramePrimitive? wm = _watermark;
    if (wm != null) fb.add(wm); // bottom of z-order: painted behind content

    // ...unchanged title/body/header/footer logic...
```

(d) `layoutLazyDefinition` — build the watermark once (where `_measurer`/`def.furniture` are in scope, near the reserved-slot logging ~410) and pass it to `LazyLayout._`:
```dart
    final Watermark? wmDef = def.furniture.watermark;
    final FramePrimitive? watermark = wmDef == null
        ? null
        : buildWatermarkPrimitive(wmDef, def.page, _measurer);
    // ...
    return LazyLayout._(
      page: page,
      // ...all existing args unchanged...
      onElementPrint: onElementPrint,
      watermark: watermark,
    );
```
Add `import '../../domain/watermark.dart';` for the `Watermark?` local type.

- [ ] **Step 4: Run to verify it passes.**

Run: `cd packages/jet_print && flutter test test/rendering/layout/report_layouter_watermark_test.dart`
Expected: PASS.

- [ ] **Step 5: Full rendering suite (regression).**

Run: `cd packages/jet_print && flutter test test/rendering`
Expected: PASS, goldens byte-identical (no watermark in existing fixtures).

- [ ] **Step 6: Analyze + format, commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/layout/report_layouter.dart test/rendering/layout/report_layouter_watermark_test.dart && flutter analyze lib/src/rendering/layout/report_layouter.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/layout/report_layouter.dart packages/jet_print/test/rendering/layout/report_layouter_watermark_test.dart
git commit -m "feat(layout): prepend page watermark as bottom-z primitive"
```

---

## Task 8: PDF backend — rotation + image opacity (the spike)

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/export/pdf_painter.dart`
- Test: `packages/jet_print/test/rendering/export/pdf_painter_watermark_test.dart`

**Interfaces:**
- Consumes: `pushTransform`/`popTransform` contract (Task 5); `ImagePrimitive.opacity` (Task 4).
- Produces: real `PdfPainter.pushTransform`/`popTransform` (replacing the Task-5 no-op) honoring PDF's bottom-left origin (`_mapY`); `drawImage` wrapped in a constant-`/ca` opacity context.

> **Spike note (from the spec):** PDF rotation must account for the y-flip — a `radians` clockwise rotation in jet (y-down) space is `-radians` in PDF (y-up) space, about the y-flipped center. Verify with the golden in Step 5 before considering this task done; if the rotation is mirrored, flip the sign.

- [ ] **Step 1: Write the failing test** (structural — assert the painter does not throw and image opacity wraps a graphics-state; a visual golden lands in Task 9 Step 5):

```dart
// packages/jet_print/test/rendering/export/pdf_painter_watermark_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/export/pdf_painter.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';

void main() {
  const page = PageFormat(width: 100, height: 100, margins: JetEdgeInsets.all(0));

  test('paints a rotated rect watermark to a PDF without throwing', () async {
    final frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 20, y: 20, width: 60, height: 20),
              fill: JetColor(0x26000000),
              rotation: -0.785)))
        .build();
    final painter = PdfPainter(); // mirror the real ctor used in pdf tests
    await paintFrame(frame, painter);
    final Uint8List bytes = painter.save(); // or whatever the existing API is
    expect(bytes, isNotEmpty);
  });
}
```

> Read an existing `pdf_painter` test first to copy the exact `PdfPainter` construction and document-bytes accessor (constructor args, `save()`/`document` getter). The behavioral point: a rotated primitive and an opacity image paint without throwing and produce non-empty PDF bytes.

- [ ] **Step 2: Run to verify it fails (or errors on the no-op TODO).**

Run: `cd packages/jet_print && flutter test test/rendering/export/pdf_painter_watermark_test.dart`
Expected: FAIL/compile — the Task-5 no-op `pushTransform` does not rotate (and the test may assert non-empty bytes which the no-op still passes — so ALSO drive this with the Task-9 golden). If the no-op makes Step 1 pass trivially, rely on Step 5's golden as the real gate.

- [ ] **Step 3: Implement transform.** In `pdf_painter.dart` add `import 'package:vector_math/vector_math_64.dart' show Matrix4;` (confirm `package:pdf` already pulls vector_math; if the import path differs, use the one `PdfGraphics.setTransform` expects). Replace the no-op:

```dart
  @override
  void pushTransform(JetOffset center, double radians) {
    final PdfGraphics g = _g;
    final double cx = center.dx;
    final double cy = _mapY(center.dy); // PDF y-up
    g.saveContext();
    // jet rotates clockwise in y-down space; PDF is y-up → negate.
    g.setTransform(Matrix4.identity()
      ..translate(cx, cy)
      ..rotateZ(-radians)
      ..translate(-cx, -cy));
  }

  @override
  void popTransform() => _g.restoreContext();
```

Add `import '../../domain/geometry.dart';` if `JetOffset` is not already imported.

- [ ] **Step 4: Implement image opacity.** Wrap the existing `drawImage` body in a constant-`/ca` context. Add a sibling to `_withAlpha`:

```dart
  static void _withOpacity(PdfGraphics g, double opacity, void Function() draw) {
    if (opacity >= 1.0) {
      draw();
      return;
    }
    g.saveContext();
    g.setGraphicState(PdfGraphicState(opacity: opacity));
    draw();
    g.restoreContext();
  }
```

and wrap the body of `drawImage`:
```dart
  @override
  void drawImage(ImagePrimitive p) {
    final _DecodedImage? decoded = _decoded[p];
    if (decoded == null) return;
    _withOpacity(_g, p.opacity, () {
      final PdfGraphics g = _g;
      // ...existing embed + computeImageFit + saveContext/clip/drawImage/restore...
    });
  }
```

- [ ] **Step 5: Verify (visual golden — the real gate).** Add a one-page PDF→PNG (or direct canvas) golden of an image watermark behind a rect, then inspect it renders dimmed and correctly oriented. Reuse the rasterizer or the project's existing PDF golden harness if one exists; otherwise assert via the canvas raster path in Task 9 (preferred — Canvas already verified). If no PDF raster harness exists, this step is the canvas/raster golden in Task 9 and you confirm the PDF path only structurally here. Document which.

Run: `cd packages/jet_print && flutter test test/rendering/export/pdf_painter_watermark_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + format, commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/export/pdf_painter.dart test/rendering/export/pdf_painter_watermark_test.dart && flutter analyze lib/src/rendering/export/pdf_painter.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/export/pdf_painter.dart packages/jet_print/test/rendering/export/pdf_painter_watermark_test.dart
git commit -m "feat(pdf): watermark rotation (y-flip aware) + image /ca opacity"
```

---

## Task 9: Goldens + full verification sweep

**Files:**
- Test: `packages/jet_print/test/rendering/paint/watermark_golden_test.dart` (new)
- Verification only otherwise.

- [ ] **Step 1: Write a Canvas preview golden (diagonal DRAFT text).** Mirror `test/rendering/paint/canvas_painter_golden_test.dart`'s harness:

```dart
// packages/jet_print/test/rendering/paint/watermark_golden_test.dart
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/domain/watermark.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/paint/canvas_painter.dart';
import 'package:jet_print/src/rendering/paint/report_painter.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/watermark_primitive.dart';

void main() {
  test('diagonal DRAFT text watermark behind a white page', () async {
    final reg = FontRegistry()..registerDefault();
    const page = PageFormat(width: 200, height: 200, margins: JetEdgeInsets.all(0));
    final wmPrim = buildWatermarkPrimitive(
        const Watermark(
            text: 'DRAFT',
            opacity: 0.2,
            angleDegrees: -45,
            textStyle: JetTextStyle(fontSize: 56, color: JetColor(0xFF000000))),
        page,
        MetricsTextMeasurer(reg))!;
    final frame = (FrameBuilder(page)
          ..add(const RectPrimitive(
              bounds: JetRect(x: 0, y: 0, width: 200, height: 200),
              fill: JetColor(0xFFFFFFFF)))
          ..add(wmPrim))
        .build();

    final recorder = ui.PictureRecorder();
    final ReportPainter painter = CanvasPainter(ui.Canvas(recorder), reg);
    await paintFrame(frame, painter);
    final ui.Image image =
        await recorder.endRecording().toImage(200, 200);
    await expectLater(image, matchesGoldenFile('goldens/watermark_text.png'));
  });
}
```

- [ ] **Step 2: Add an image-watermark RASTER golden** (image opacity divergence only shows in raster). In the same file, build a `Watermark(imageBytes: <small solid PNG>, opacity: 0.2)`, prepend its primitive over a white rect, render via the same canvas path (or `PageRasterizer().rasterize(frame, reg)`), and `matchesGoldenFile('goldens/watermark_image.png')`. Reuse the `_solidPng` helper from `canvas_painter_golden_test.dart` (copy it in).

- [ ] **Step 3: Generate the new goldens.**

Run: `cd packages/jet_print && flutter test --update-goldens test/rendering/paint/watermark_golden_test.dart`
Then open `test/rendering/paint/goldens/watermark_text.png` and `watermark_image.png` and EYEBALL them: DRAFT must run diagonally (bottom-left→top-right), faint; the image must be dimmed and centered. If wrong, fix the builder/painter — do not accept a bad golden.

- [ ] **Step 4: Run the new goldens clean.**

Run: `cd packages/jet_print && flutter test test/rendering/paint/watermark_golden_test.dart`
Expected: PASS.

- [ ] **Step 5: Full verification sweep.**

```bash
cd packages/jet_print
flutter analyze                                             # clean
dart format --output=none --set-exit-if-changed lib test    # clean
flutter test                                                # ALL green; EXISTING goldens byte-identical
```
Expected: all green. **If any pre-existing golden changed, STOP and inspect** — the watermark path must be inert when unused.

- [ ] **Step 6: Playground smoke (the library's consumer must still build).**

```bash
cd apps/jet_print_playground && flutter analyze && flutter test
```
Expected: green.

- [ ] **Step 7: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/rendering/paint/watermark_golden_test.dart packages/jet_print/test/rendering/paint/goldens/
git commit -m "test(watermark): preview + raster goldens; verify existing goldens unchanged"
```

---

## Self-Review

**Spec coverage:**
- Watermark value object (text|image, opacity, angle) → Task 1.
- `PageFurniture.watermark` placement + `background` comment fix → Task 2.
- Serialization (omit-when-null, base64, no schema bump) → Task 3.
- Rotation paint capability (base `rotation` + all 5 `==`/`hashCode`) + `ImagePrimitive.opacity` → Task 4.
- `pushTransform`/`popTransform` interface + `paintFrame` wrap + Canvas impl + Canvas image opacity → Task 5.
- Centered/rotated/dimmed primitive construction (text-wins, no-op cases) → Task 6.
- Per-page bottom-z injection through layout → Task 7.
- PDF rotation (y-flip spike) + PDF `/ca` image opacity → Task 8.
- Preview golden + raster golden + existing-goldens-unchanged guard + sweep → Task 9.
- Error handling: opacity 0 / empty text → null (Task 6); both-set → text wins (Task 6); undecodable image → existing `drawImage` null-guard, unchanged (Tasks 5/8). copyWith-can't-null + no auto-fit documented (Task 1 dartdoc).

**Type consistency:** `buildWatermarkPrimitive(Watermark, PageFormat, TextMeasurer) → FramePrimitive?` is produced in Task 6 and consumed in Task 7. `pushTransform(JetOffset, double)`/`popTransform()` defined in Task 5, implemented (no-op) Task 5 / (real) Task 8. `ImagePrimitive.opacity` defined Task 4, set Task 6, honored Task 5 (Canvas) + Task 8 (PDF). `Watermark` ctor/fields identical across Tasks 1-3, 6-7.

**Placeholder scan:** Tests that say "mirror the existing harness" (Tasks 3, 7, 8 Step 1) name the exact file to copy and state the concrete assertions to keep — the behavioral deliverable is explicit, only the local fixture-builder boilerplate is delegated to the neighbouring test's established pattern (repeating it verbatim would require pasting unrelated 100-line fixtures). All code-bearing steps show full code.

**Known risk:** Task 8 (PDF transform y-flip sign) is the one place a backend can diverge; its golden (Task 9 Step 3 eyeball + structural test) is the gate. The Canvas path (which also drives PNG) is fully covered earlier, so a PDF-only issue cannot reach preview/PNG output.
