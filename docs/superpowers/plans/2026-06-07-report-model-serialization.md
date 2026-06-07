# Report Model & Serialization (Spec 003 · Part 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart foundation of the report model — geometry value types, an extensible element model (Text + UnknownElement), an element codec registry, and versioned JSON serialization with a migration framework — all under the `domain` seam, fully test-driven.

**Architecture:** Implements the inner two boxes of the engine blueprint ([2026-06-07-report-engine-design.md](../specs/2026-06-07-report-engine-design.md), spec 003). Everything lives under `packages/jet_print/lib/src/domain/` and imports **no** `dart:ui` / Flutter UI (the existing layer-boundary test enforces this automatically by scanning that directory). Elements serialize through an `ElementCodecRegistry` keyed by a string `type`, so new element types persist with zero core edits; unregistered types round-trip losslessly via `UnknownElement`. The top-level `decodeTemplate` validates `schemaVersion` and runs ordered migrations for older files.

**Tech Stack:** Dart 3.6+ / Flutter SDK (package depends on Flutter but the domain seam uses only `dart:core`); `flutter_test` for tests; `dart:convert` only in tests (to prove real JSON-string round-trips). No new package dependencies.

**Scope (this plan = 003 Part 1):** geometry (`JetSize`/`JetOffset`/`JetEdgeInsets`/`JetRect`), `PageFormat`, `ReportElement` + `TextElement` + `UnknownElement`, `ElementCodec`/`ElementCodecRegistry`/`TextElementCodec`, `ReportBand`/`BandType`/`ReportTemplate`, `SchemaMigration`/`runMigrations`, `encodeTemplate`/`decodeTemplate`, `ReportFormatException`.
**Deferred to 003 Part 2 (separate plan):** image/line-rect/barcode element types and their codecs; style value types (color/font/border/alignment); `ReportParameter`/`ReportVariable`/`ReportGroup` and field/expression bindings; real `vN→vN+1` migrations. The existing `ReportDocument`/`ReportLayout` stubs are left untouched (still green) and are removed when the rendering pipeline lands (spec 006+).

**Before you start:** create the feature branch (or let the worktrees skill do it):
```bash
git checkout main && git checkout -b 003-report-model-serialization
```
All paths below are relative to the repo root `/Users/ahmeturel/Projects/oss/jet-print`.

## File Structure

Created under `packages/jet_print/lib/src/domain/`:

| File | Responsibility |
|---|---|
| `geometry.dart` | Pure-Dart value types: `JetSize`, `JetOffset`, `JetEdgeInsets`, `JetRect` (equality + JSON) |
| `page_format.dart` | `PageFormat` (page size + margins; `a4Portrait` preset) |
| `report_element.dart` | `ReportElement` abstract base (`id`, `bounds`, `typeKey`) |
| `elements/text_element.dart` | `TextElement` — the fundamental element |
| `unknown_element.dart` | `UnknownElement` — preserves raw JSON of unregistered types |
| `report_band.dart` | `BandType` enum + `ReportBand` (type, height, elements) |
| `report_template.dart` | `ReportTemplate` (name, page, bands) |
| `serialization/report_format_exception.dart` | `ReportFormatException` |
| `serialization/element_codec.dart` | `ElementCodec` + `ElementCodecRegistry` |
| `serialization/text_element_codec.dart` | `TextElementCodec` |
| `serialization/migration.dart` | `SchemaMigration` + `runMigrations` |
| `serialization/report_codec.dart` | `kReportSchemaVersion`, `encodeTemplate`, `decodeTemplate` |

Test files mirror these under `packages/jet_print/test/domain/` and `.../test/domain/serialization/`.

---

### Task 1: Geometry value types

**Files:**
- Create: `packages/jet_print/lib/src/domain/geometry.dart`
- Test: `packages/jet_print/test/domain/geometry_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/geometry_test.dart`:

```dart
// Pure-Dart geometry value types (spec 003). No Flutter UI import — proving the
// domain seam stays headless.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';

void main() {
  group('JetSize', () {
    test('round-trips through JSON', () {
      const JetSize size = JetSize(120, 48);
      expect(JetSize.fromJson(size.toJson()), size);
    });
    test('has value equality', () {
      expect(const JetSize(1, 2), const JetSize(1, 2));
      expect(const JetSize(1, 2) == const JetSize(2, 1), isFalse);
    });
  });

  group('JetOffset', () {
    test('round-trips through JSON', () {
      const JetOffset offset = JetOffset(8, -4);
      expect(JetOffset.fromJson(offset.toJson()), offset);
    });
  });

  group('JetEdgeInsets', () {
    test('round-trips through JSON', () {
      const JetEdgeInsets insets =
          JetEdgeInsets(left: 1, top: 2, right: 3, bottom: 4);
      expect(JetEdgeInsets.fromJson(insets.toJson()), insets);
    });
    test('.all sets every side equal', () {
      expect(const JetEdgeInsets.all(5),
          const JetEdgeInsets(left: 5, top: 5, right: 5, bottom: 5));
    });
  });

  group('JetRect', () {
    test('round-trips through JSON', () {
      const JetRect rect = JetRect(x: 10, y: 20, width: 100, height: 40);
      expect(JetRect.fromJson(rect.toJson()), rect);
    });
    test('exposes zero as the empty rect', () {
      expect(JetRect.zero, const JetRect(x: 0, y: 0, width: 0, height: 0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test packages/jet_print/test/domain/geometry_test.dart`
Expected: FAIL — compile error, `Couldn't resolve the package 'jet_print'`-style or `geometry.dart` not found / `JetSize` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/geometry.dart`:

```dart
/// Pure-Dart geometry value types for the report model.
///
/// These deliberately mirror the *shape* of `dart:ui`'s geometry types but carry
/// **no Flutter dependency**, so the domain seam stays headless and
/// platform-agnostic (Constitution II; enforced by the layer-boundary test). All
/// types are immutable, use value equality, and round-trip through JSON.
library;

/// An immutable width/height pair, in logical points.
class JetSize {
  /// Creates a size of [width] x [height] points.
  const JetSize(this.width, this.height);

  /// Reads a [JetSize] from its [toJson] map.
  factory JetSize.fromJson(Map<String, Object?> json) =>
      JetSize((json['w']! as num).toDouble(), (json['h']! as num).toDouble());

  /// Horizontal extent, in points.
  final double width;

  /// Vertical extent, in points.
  final double height;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{'w': width, 'h': height};

  @override
  bool operator ==(Object other) =>
      other is JetSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'JetSize($width, $height)';
}

/// An immutable (dx, dy) displacement, in logical points.
class JetOffset {
  /// Creates an offset of ([dx], [dy]) points.
  const JetOffset(this.dx, this.dy);

  /// Reads a [JetOffset] from its [toJson] map.
  factory JetOffset.fromJson(Map<String, Object?> json) =>
      JetOffset((json['dx']! as num).toDouble(), (json['dy']! as num).toDouble());

  /// Horizontal displacement, in points.
  final double dx;

  /// Vertical displacement, in points.
  final double dy;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{'dx': dx, 'dy': dy};

  @override
  bool operator ==(Object other) =>
      other is JetOffset && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'JetOffset($dx, $dy)';
}

/// Immutable inset distances for the four sides of a box, in logical points.
class JetEdgeInsets {
  /// Creates insets with explicit per-side values.
  const JetEdgeInsets({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Creates insets with the same [value] on every side.
  const JetEdgeInsets.all(double value)
      : left = value,
        top = value,
        right = value,
        bottom = value;

  /// Reads [JetEdgeInsets] from its [toJson] map.
  factory JetEdgeInsets.fromJson(Map<String, Object?> json) => JetEdgeInsets(
        left: (json['l']! as num).toDouble(),
        top: (json['t']! as num).toDouble(),
        right: (json['r']! as num).toDouble(),
        bottom: (json['b']! as num).toDouble(),
      );

  /// Inset from the left edge, in points.
  final double left;

  /// Inset from the top edge, in points.
  final double top;

  /// Inset from the right edge, in points.
  final double right;

  /// Inset from the bottom edge, in points.
  final double bottom;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() =>
      <String, Object?>{'l': left, 't': top, 'r': right, 'b': bottom};

  @override
  bool operator ==(Object other) =>
      other is JetEdgeInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'JetEdgeInsets($left, $top, $right, $bottom)';
}

/// An immutable axis-aligned rectangle: top-left at ([x], [y]) with [width] x
/// [height], all in logical points.
class JetRect {
  /// Creates a rectangle.
  const JetRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Reads a [JetRect] from its [toJson] map.
  factory JetRect.fromJson(Map<String, Object?> json) => JetRect(
        x: (json['x']! as num).toDouble(),
        y: (json['y']! as num).toDouble(),
        width: (json['w']! as num).toDouble(),
        height: (json['h']! as num).toDouble(),
      );

  /// The empty rectangle at the origin.
  static const JetRect zero = JetRect(x: 0, y: 0, width: 0, height: 0);

  /// Left edge, in points.
  final double x;

  /// Top edge, in points.
  final double y;

  /// Width, in points.
  final double width;

  /// Height, in points.
  final double height;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() =>
      <String, Object?>{'x': x, 'y': y, 'w': width, 'h': height};

  @override
  bool operator ==(Object other) =>
      other is JetRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'JetRect($x, $y, $width, $height)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test packages/jet_print/test/domain/geometry_test.dart`
Expected: PASS (all tests green).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/geometry.dart packages/jet_print/test/domain/geometry_test.dart
git commit -m "feat(domain): add pure-Dart geometry value types"
```

---

### Task 2: PageFormat

**Files:**
- Create: `packages/jet_print/lib/src/domain/page_format.dart`
- Test: `packages/jet_print/test/domain/page_format_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/page_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';

void main() {
  group('PageFormat', () {
    test('round-trips through JSON', () {
      const PageFormat page = PageFormat(
        width: 595.28,
        height: 841.89,
        margins: JetEdgeInsets.all(28.35),
      );
      expect(PageFormat.fromJson(page.toJson()), page);
    });

    test('a4Portrait preset is taller than it is wide', () {
      expect(PageFormat.a4Portrait.height,
          greaterThan(PageFormat.a4Portrait.width));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test packages/jet_print/test/domain/page_format_test.dart`
Expected: FAIL — `page_format.dart` / `PageFormat` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/page_format.dart`:

```dart
/// The physical page a report is laid out onto.
library;

import 'geometry.dart';

/// An immutable page description: a [width] x [height] sheet (in logical points)
/// with [margins]. Defaults are provided for common formats.
class PageFormat {
  /// Creates a page format.
  const PageFormat({
    required this.width,
    required this.height,
    required this.margins,
  });

  /// Reads a [PageFormat] from its [toJson] map.
  factory PageFormat.fromJson(Map<String, Object?> json) => PageFormat(
        width: (json['width']! as num).toDouble(),
        height: (json['height']! as num).toDouble(),
        margins:
            JetEdgeInsets.fromJson((json['margins']! as Map).cast<String, Object?>()),
      );

  /// ISO A4 portrait (595.28 x 841.89 pt) with ~1 cm margins.
  static const PageFormat a4Portrait = PageFormat(
    width: 595.28,
    height: 841.89,
    margins: JetEdgeInsets.all(28.35),
  );

  /// Page width, in points.
  final double width;

  /// Page height, in points.
  final double height;

  /// Page margins, in points.
  final JetEdgeInsets margins;

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{
        'width': width,
        'height': height,
        'margins': margins.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is PageFormat &&
      other.width == width &&
      other.height == height &&
      other.margins == margins;

  @override
  int get hashCode => Object.hash(width, height, margins);

  @override
  String toString() => 'PageFormat(${width}x$height, $margins)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test packages/jet_print/test/domain/page_format_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/page_format.dart packages/jet_print/test/domain/page_format_test.dart
git commit -m "feat(domain): add PageFormat value type"
```

---

### Task 3: ReportElement base + TextElement

**Files:**
- Create: `packages/jet_print/lib/src/domain/report_element.dart`
- Create: `packages/jet_print/lib/src/domain/elements/text_element.dart`
- Test: `packages/jet_print/test/domain/elements/text_element_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/elements/text_element_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';

void main() {
  group('TextElement', () {
    const TextElement element = TextElement(
      id: 'title',
      bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
      text: 'Invoice',
    );

    test('is a ReportElement with the "text" type key', () {
      expect(element, isA<ReportElement>());
      expect(element.typeKey, 'text');
    });

    test('exposes id, bounds, and text', () {
      expect(element.id, 'title');
      expect(element.bounds, const JetRect(x: 0, y: 0, width: 200, height: 24));
      expect(element.text, 'Invoice');
    });

    test('has value equality', () {
      expect(
        element,
        const TextElement(
          id: 'title',
          bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
          text: 'Invoice',
        ),
      );
      expect(element == const TextElement(
        id: 'title',
        bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
        text: 'Different',
      ), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test packages/jet_print/test/domain/elements/text_element_test.dart`
Expected: FAIL — `report_element.dart` / `text_element.dart` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/report_element.dart`:

```dart
/// The base type for everything placed on a band.
library;

import 'geometry.dart';

/// An immutable element definition positioned at absolute [bounds] within its
/// band. Concrete subtypes (text, image, line, barcode, …) add their own fields
/// and a stable [typeKey] used for serialization dispatch.
abstract class ReportElement {
  /// Creates an element with a unique [id] and absolute [bounds].
  const ReportElement({required this.id, required this.bounds});

  /// Stable, unique identifier within a template (used for selection/binding).
  final String id;

  /// Absolute position and size within the owning band, in points.
  final JetRect bounds;

  /// Stable string key identifying this element's type for serialization.
  /// Must be unique per registered type (see `ElementCodecRegistry`).
  String get typeKey;
}
```

Create `packages/jet_print/lib/src/domain/elements/text_element.dart`:

```dart
/// A static or (later) data-bound text element.
library;

import '../geometry.dart';
import '../report_element.dart';

/// Renders [text] within its [bounds]. For this iteration [text] is a literal
/// string; expression binding arrives with the expression engine (spec 005).
class TextElement extends ReportElement {
  /// Creates a text element.
  const TextElement({
    required super.id,
    required super.bounds,
    required this.text,
  });

  /// The literal text to render.
  final String text;

  @override
  String get typeKey => 'text';

  @override
  bool operator ==(Object other) =>
      other is TextElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, bounds, text);

  @override
  String toString() => 'TextElement($id, "$text")';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test packages/jet_print/test/domain/elements/text_element_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/report_element.dart packages/jet_print/lib/src/domain/elements/text_element.dart packages/jet_print/test/domain/elements/text_element_test.dart
git commit -m "feat(domain): add ReportElement base and TextElement"
```

---

### Task 4: UnknownElement

**Files:**
- Create: `packages/jet_print/lib/src/domain/unknown_element.dart`
- Test: `packages/jet_print/test/domain/unknown_element_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/unknown_element_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/unknown_element.dart';

void main() {
  group('UnknownElement', () {
    test('is a ReportElement that reports the original type key', () {
      final UnknownElement element = UnknownElement(
        typeKey: 'sparkline',
        rawJson: <String, Object?>{
          'type': 'sparkline',
          'id': 'spark1',
          'bounds': <String, Object?>{'x': 1, 'y': 2, 'w': 30, 'h': 10},
          'series': <Object?>[1, 2, 3],
        },
      );
      expect(element, isA<ReportElement>());
      expect(element.typeKey, 'sparkline');
      expect(element.id, 'spark1');
      expect(element.bounds, const JetRect(x: 1, y: 2, width: 30, height: 10));
    });

    test('falls back to empty id and zero bounds when absent', () {
      final UnknownElement element = UnknownElement(
        typeKey: 'mystery',
        rawJson: <String, Object?>{'type': 'mystery'},
      );
      expect(element.id, '');
      expect(element.bounds, JetRect.zero);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test packages/jet_print/test/domain/unknown_element_test.dart`
Expected: FAIL — `unknown_element.dart` / `UnknownElement` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/unknown_element.dart`:

```dart
/// Preserves an element whose type is not registered in this build.
library;

import 'geometry.dart';
import 'report_element.dart';

/// A [ReportElement] standing in for a type-key this build does not recognize.
///
/// It keeps the element's original JSON verbatim ([rawJson]) so the template
/// round-trips **losslessly** (Constitution V) — a report authored in a newer
/// build, or by a plugin, is never silently dropped when opened here. It exposes
/// best-effort [id]/[bounds] (if present in the JSON) so it can still render a
/// visible placeholder.
class UnknownElement extends ReportElement {
  /// Wraps [rawJson] for the unrecognized [typeKey].
  UnknownElement({required this.typeKey, required this.rawJson})
      : super(
          id: rawJson['id'] is String ? rawJson['id']! as String : '',
          bounds: _readBounds(rawJson['bounds']),
        );

  @override
  final String typeKey;

  /// The element's original JSON, preserved byte-for-byte for round-tripping.
  final Map<String, Object?> rawJson;

  static JetRect _readBounds(Object? bounds) => bounds is Map
      ? JetRect.fromJson(bounds.cast<String, Object?>())
      : JetRect.zero;

  @override
  String toString() => 'UnknownElement($typeKey)';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test packages/jet_print/test/domain/unknown_element_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/unknown_element.dart packages/jet_print/test/domain/unknown_element_test.dart
git commit -m "feat(domain): add UnknownElement for lossless round-trip of unregistered types"
```

---

### Task 5: ReportFormatException

**Files:**
- Create: `packages/jet_print/lib/src/domain/serialization/report_format_exception.dart`
- Test: `packages/jet_print/test/domain/serialization/report_format_exception_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/serialization/report_format_exception_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';

void main() {
  test('ReportFormatException is an Exception that carries its message', () {
    const ReportFormatException exception = ReportFormatException('bad schema');
    expect(exception, isA<Exception>());
    expect(exception.message, 'bad schema');
    expect(exception.toString(), contains('bad schema'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test packages/jet_print/test/domain/serialization/report_format_exception_test.dart`
Expected: FAIL — `report_format_exception.dart` / `ReportFormatException` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/serialization/report_format_exception.dart`:

```dart
/// Thrown when a serialized report is structurally invalid.
library;

/// A structural fault encountered while decoding a report (missing
/// `schemaVersion`, a too-new schema, a malformed shape, …). Distinct from the
/// engine's non-fatal diagnostics: this is a fail-fast condition because the
/// input cannot be interpreted at all.
class ReportFormatException implements Exception {
  /// Creates the exception with a human-readable [message].
  const ReportFormatException(this.message);

  /// Describes what was wrong with the input.
  final String message;

  @override
  String toString() => 'ReportFormatException: $message';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test packages/jet_print/test/domain/serialization/report_format_exception_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/serialization/report_format_exception.dart packages/jet_print/test/domain/serialization/report_format_exception_test.dart
git commit -m "feat(domain): add ReportFormatException"
```

---

### Task 6: ElementCodec + ElementCodecRegistry + TextElementCodec

**Files:**
- Create: `packages/jet_print/lib/src/domain/serialization/element_codec.dart`
- Create: `packages/jet_print/lib/src/domain/serialization/text_element_codec.dart`
- Test: `packages/jet_print/test/domain/serialization/element_codec_test.dart`

> **Dart note (variance):** `ElementCodec.toJson` takes a `covariant ReportElement` parameter rather than the type variable `E`. This keeps `E` in a covariant (return-only) position, so `ElementCodec<TextElement>` is a subtype of `ElementCodec<ReportElement>` and can be stored in the registry's `Map<String, ElementCodec<ReportElement>>`. The registry only ever calls `toJson` after matching `element.typeKey`, so the runtime element is always the expected subtype.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/serialization/element_codec_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';
import 'package:jet_print/src/domain/unknown_element.dart';

ElementCodecRegistry _registryWithText() =>
    ElementCodecRegistry()..register('text', const TextElementCodec());

void main() {
  group('ElementCodecRegistry', () {
    test('encodes an element with its type key embedded', () {
      final ElementCodecRegistry registry = _registryWithText();
      const TextElement element = TextElement(
        id: 't1',
        bounds: JetRect(x: 1, y: 2, width: 3, height: 4),
        text: 'hi',
      );
      expect(registry.encode(element), <String, Object?>{
        'type': 'text',
        'id': 't1',
        'bounds': <String, Object?>{'x': 1.0, 'y': 2.0, 'w': 3.0, 'h': 4.0},
        'text': 'hi',
      });
    });

    test('round-trips a registered element', () {
      final ElementCodecRegistry registry = _registryWithText();
      const TextElement element = TextElement(
        id: 't1',
        bounds: JetRect(x: 1, y: 2, width: 3, height: 4),
        text: 'hi',
      );
      final ReportElement decoded = registry.decode(registry.encode(element));
      expect(decoded, element);
    });

    test('decodes an unregistered type to a lossless UnknownElement', () {
      final ElementCodecRegistry registry = _registryWithText();
      final Map<String, Object?> json = <String, Object?>{
        'type': 'sparkline',
        'id': 's1',
        'bounds': <String, Object?>{'x': 0, 'y': 0, 'w': 10, 'h': 5},
        'series': <Object?>[3, 1, 4],
      };
      final ReportElement decoded = registry.decode(json);
      expect(decoded, isA<UnknownElement>());
      // Byte-for-byte round-trip: re-encoding yields the original JSON.
      expect(registry.encode(decoded), equals(json));
    });

    test('throws when element JSON has no string "type"', () {
      final ElementCodecRegistry registry = _registryWithText();
      expect(
        () => registry.decode(<String, Object?>{'id': 'x'}),
        throwsA(isA<ReportFormatException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test packages/jet_print/test/domain/serialization/element_codec_test.dart`
Expected: FAIL — `element_codec.dart` / `ElementCodecRegistry` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/serialization/element_codec.dart`:

```dart
/// The element serialization extension point.
library;

import '../report_element.dart';
import '../unknown_element.dart';
import 'report_format_exception.dart';

/// Serializes a single element type [E] to/from JSON. Register one per element
/// type so custom types persist with zero core edits (Constitution II/V).
///
/// `toJson` takes a `covariant ReportElement` (not `E`) so that
/// `ElementCodec<E>` stays a subtype of `ElementCodec<ReportElement>` and can be
/// held in [ElementCodecRegistry]; the registry only calls it after matching the
/// element's `typeKey`, so the cast is always sound.
abstract class ElementCodec<E extends ReportElement> {
  /// Const base constructor.
  const ElementCodec();

  /// Builds an [E] from its field map (the same map [toJson] produced, plus the
  /// `type` key, which implementations may ignore).
  E fromJson(Map<String, Object?> json);

  /// Returns the element's fields as a JSON-safe map **without** the `type`
  /// key — the registry adds `type` from [ReportElement.typeKey].
  Map<String, Object?> toJson(covariant ReportElement element);
}

/// Maps element `type` keys to their [ElementCodec]s and performs dispatch.
class ElementCodecRegistry {
  final Map<String, ElementCodec<ReportElement>> _codecs =
      <String, ElementCodec<ReportElement>>{};

  /// Registers [codec] for elements whose `typeKey` equals [typeKey].
  void register(String typeKey, ElementCodec<ReportElement> codec) {
    _codecs[typeKey] = codec;
  }

  /// Encodes [element] to a JSON-safe map. [UnknownElement]s are emitted from
  /// their preserved raw JSON; all others are `{'type': typeKey, ...fields}`.
  Map<String, Object?> encode(ReportElement element) {
    if (element is UnknownElement) {
      return Map<String, Object?>.of(element.rawJson);
    }
    final ElementCodec<ReportElement>? codec = _codecs[element.typeKey];
    if (codec == null) {
      throw StateError(
        'No ElementCodec registered for type "${element.typeKey}".',
      );
    }
    return <String, Object?>{'type': element.typeKey, ...codec.toJson(element)};
  }

  /// Decodes a JSON [json] map into a [ReportElement]. Unknown `type`s decode to
  /// a lossless [UnknownElement]; a missing/non-string `type` is a hard error.
  ReportElement decode(Map<String, Object?> json) {
    final Object? typeKey = json['type'];
    if (typeKey is! String) {
      throw const ReportFormatException('Element JSON missing string "type".');
    }
    final ElementCodec<ReportElement>? codec = _codecs[typeKey];
    if (codec == null) {
      return UnknownElement(
        typeKey: typeKey,
        rawJson: Map<String, Object?>.of(json),
      );
    }
    return codec.fromJson(json);
  }
}
```

Create `packages/jet_print/lib/src/domain/serialization/text_element_codec.dart`:

```dart
/// JSON codec for [TextElement].
library;

import '../elements/text_element.dart';
import '../geometry.dart';
import 'element_codec.dart';

/// Serializes [TextElement] to/from its field map.
class TextElementCodec extends ElementCodec<TextElement> {
  /// Const constructor (the codec is stateless).
  const TextElementCodec();

  @override
  TextElement fromJson(Map<String, Object?> json) => TextElement(
        id: json['id']! as String,
        bounds: JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        text: json['text']! as String,
      );

  @override
  Map<String, Object?> toJson(TextElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'text': element.text,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test packages/jet_print/test/domain/serialization/element_codec_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/serialization/element_codec.dart packages/jet_print/lib/src/domain/serialization/text_element_codec.dart packages/jet_print/test/domain/serialization/element_codec_test.dart
git commit -m "feat(domain): add element codec registry with text codec and unknown fallback"
```

---

### Task 7: ReportBand + BandType + ReportTemplate

**Files:**
- Create: `packages/jet_print/lib/src/domain/report_band.dart`
- Create: `packages/jet_print/lib/src/domain/report_template.dart`
- Test: `packages/jet_print/test/domain/report_template_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/report_template_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_template.dart';

void main() {
  group('ReportBand', () {
    test('defaults to no elements', () {
      const ReportBand band = ReportBand(type: BandType.pageHeader, height: 40);
      expect(band.type, BandType.pageHeader);
      expect(band.height, 40);
      expect(band.elements, isEmpty);
    });
  });

  group('ReportTemplate', () {
    test('holds a name, page, and ordered bands', () {
      const ReportTemplate template = ReportTemplate(
        name: 'Invoice',
        page: PageFormat.a4Portrait,
        bands: <ReportBand>[
          ReportBand(
            type: BandType.detail,
            height: 18,
            elements: <TextElement>[
              TextElement(
                id: 'line',
                bounds: JetRect(x: 0, y: 0, width: 200, height: 18),
                text: r'$F{description}',
              ),
            ],
          ),
        ],
      );
      expect(template.name, 'Invoice');
      expect(template.page, PageFormat.a4Portrait);
      expect(template.bands.single.elements.single, isA<TextElement>());
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test packages/jet_print/test/domain/report_template_test.dart`
Expected: FAIL — `report_band.dart` / `report_template.dart` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/report_band.dart`:

```dart
/// Horizontal bands — the vertical structure of a banded report.
library;

import 'report_element.dart';

/// The role a band plays in the report's vertical flow. The renderer (spec 008)
/// decides repetition/placement per type; here it is pure structure.
enum BandType {
  /// Printed once at the very start of the report.
  title,

  /// Repeated at the top of every page.
  pageHeader,

  /// Repeated above the detail section on each page/column.
  columnHeader,

  /// Printed when a group's key changes (before its details).
  groupHeader,

  /// Repeated once per data row.
  detail,

  /// Printed when a group ends (after its details).
  groupFooter,

  /// Repeated below the detail section on each page/column.
  columnFooter,

  /// Repeated at the bottom of every page.
  pageFooter,

  /// Printed once at the very end of the report.
  summary,

  /// Drawn behind every page (watermarks, frames).
  background,

  /// Printed instead of details when the data set is empty.
  noData,
}

/// An ordered, fixed-height band holding absolutely-positioned [elements].
class ReportBand {
  /// Creates a band of [type] and [height] points containing [elements].
  const ReportBand({
    required this.type,
    required this.height,
    this.elements = const <ReportElement>[],
  });

  /// The band's role in the report flow.
  final BandType type;

  /// The band's designed height, in points (may grow at layout time later).
  final double height;

  /// Elements placed within the band, at absolute bounds.
  final List<ReportElement> elements;
}
```

Create `packages/jet_print/lib/src/domain/report_template.dart`:

```dart
/// The root of a report definition.
library;

import 'page_format.dart';
import 'report_band.dart';

/// An immutable report definition: a named [page] layout with ordered [bands].
/// This is the artifact that serializes to versioned JSON (Constitution V).
class ReportTemplate {
  /// Creates a report template.
  const ReportTemplate({
    required this.name,
    required this.page,
    this.bands = const <ReportBand>[],
  });

  /// Human-readable template name.
  final String name;

  /// The page the report is laid out onto.
  final PageFormat page;

  /// The report's bands, in vertical/role order.
  final List<ReportBand> bands;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test packages/jet_print/test/domain/report_template_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/report_band.dart packages/jet_print/lib/src/domain/report_template.dart packages/jet_print/test/domain/report_template_test.dart
git commit -m "feat(domain): add ReportBand, BandType, and ReportTemplate"
```

---

### Task 8: Migration framework

**Files:**
- Create: `packages/jet_print/lib/src/domain/serialization/migration.dart`
- Test: `packages/jet_print/test/domain/serialization/migration_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/serialization/migration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/serialization/migration.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';

/// Renames a top-level `title` key to `name` (a representative v0 -> v1 change).
class _RenameTitleToName extends SchemaMigration {
  @override
  int get fromVersion => 0;

  @override
  Map<String, Object?> upgrade(Map<String, Object?> json) {
    final Map<String, Object?> next = Map<String, Object?>.of(json)
      ..['name'] = json['title']
      ..remove('title');
    return next;
  }
}

void main() {
  group('runMigrations', () {
    test('returns the input unchanged when already current', () {
      final Map<String, Object?> json = <String, Object?>{'name': 'X'};
      expect(
        runMigrations(json, from: 1, to: 1, migrations: const <SchemaMigration>[]),
        same(json),
      );
    });

    test('applies ordered migrations from old version to current', () {
      final Map<String, Object?> upgraded = runMigrations(
        <String, Object?>{'title': 'Old'},
        from: 0,
        to: 1,
        migrations: <SchemaMigration>[_RenameTitleToName()],
      );
      expect(upgraded['name'], 'Old');
      expect(upgraded.containsKey('title'), isFalse);
    });

    test('throws when a version step has no migration', () {
      expect(
        () => runMigrations(
          <String, Object?>{},
          from: 0,
          to: 1,
          migrations: const <SchemaMigration>[],
        ),
        throwsA(isA<ReportFormatException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test packages/jet_print/test/domain/serialization/migration_test.dart`
Expected: FAIL — `migration.dart` / `SchemaMigration` / `runMigrations` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/serialization/migration.dart`:

```dart
/// Forward migration of older report JSON to the current schema (Constitution V).
library;

import 'report_format_exception.dart';

/// Upgrades a report JSON map from [fromVersion] to [fromVersion] + 1.
///
/// Implementations are pure map-to-map transforms; chain them with
/// [runMigrations]. Each schema bump ships exactly one migration for the
/// previous version so any older file can be walked forward to current.
abstract class SchemaMigration {
  /// The schema version this migration upgrades **from**.
  int get fromVersion;

  /// Returns a new map upgraded to `fromVersion + 1`. Must not mutate [json].
  Map<String, Object?> upgrade(Map<String, Object?> json);
}

/// Walks [json] forward from version [from] to version [to] by applying the
/// matching [migrations] one version at a time. Returns [json] unchanged when
/// `from == to`. Throws [ReportFormatException] if a step has no migration.
Map<String, Object?> runMigrations(
  Map<String, Object?> json, {
  required int from,
  required int to,
  required List<SchemaMigration> migrations,
}) {
  Map<String, Object?> current = json;
  int version = from;
  while (version < to) {
    final int step = version;
    final SchemaMigration migration = migrations.firstWhere(
      (SchemaMigration m) => m.fromVersion == step,
      orElse: () => throw ReportFormatException(
        'No migration registered from schemaVersion $step.',
      ),
    );
    current = migration.upgrade(current);
    version += 1;
  }
  return current;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test packages/jet_print/test/domain/serialization/migration_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/serialization/migration.dart packages/jet_print/test/domain/serialization/migration_test.dart
git commit -m "feat(domain): add schema migration framework"
```

---

### Task 9: Template serialization (encode/decode + schemaVersion)

**Files:**
- Create: `packages/jet_print/lib/src/domain/serialization/report_codec.dart`
- Test: `packages/jet_print/test/domain/serialization/report_codec_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/serialization/report_codec_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/migration.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';
import 'package:jet_print/src/domain/serialization/report_format_exception.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';

ElementCodecRegistry _registry() =>
    ElementCodecRegistry()..register('text', const TextElementCodec());

const ReportTemplate _sample = ReportTemplate(
  name: 'Invoice',
  page: PageFormat.a4Portrait,
  bands: <ReportBand>[
    ReportBand(
      type: BandType.pageHeader,
      height: 60,
      elements: <TextElement>[
        TextElement(
          id: 'title',
          bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
          text: 'INVOICE',
        ),
      ],
    ),
    ReportBand(type: BandType.detail, height: 18),
  ],
);

class _RenameTitleToName extends SchemaMigration {
  @override
  int get fromVersion => 0;

  @override
  Map<String, Object?> upgrade(Map<String, Object?> json) =>
      Map<String, Object?>.of(json)
        ..['name'] = json['title']
        ..remove('title');
}

void main() {
  group('encodeTemplate / decodeTemplate', () {
    test('stamps the current schema version', () {
      expect(encodeTemplate(_sample, _registry())['schemaVersion'],
          kReportSchemaVersion);
    });

    test('round-trips a template through a real JSON string', () {
      final ElementCodecRegistry registry = _registry();
      final String wire = jsonEncode(encodeTemplate(_sample, registry));
      final ReportTemplate decoded = decodeTemplate(
        (jsonDecode(wire) as Map).cast<String, Object?>(),
        registry,
      );
      // Stable: re-encoding the decoded template reproduces the same JSON.
      expect(encodeTemplate(decoded, registry),
          equals(encodeTemplate(_sample, registry)));
      expect(decoded.bands.first.elements.first, isA<TextElement>());
      expect((decoded.bands.first.elements.first as TextElement).text,
          'INVOICE');
    });

    test('throws when schemaVersion is missing', () {
      expect(
        () => decodeTemplate(<String, Object?>{'name': 'x'}, _registry()),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('throws when schemaVersion is newer than this build', () {
      expect(
        () => decodeTemplate(
          <String, Object?>{'schemaVersion': kReportSchemaVersion + 1},
          _registry(),
        ),
        throwsA(isA<ReportFormatException>()),
      );
    });

    test('migrates an older file forward before parsing', () {
      // A version-0 document used `title` instead of `name`.
      final Map<String, Object?> v0 = <String, Object?>{
        'schemaVersion': 0,
        'title': 'Legacy',
        'page': PageFormat.a4Portrait.toJson(),
        'bands': <Object?>[],
      };
      final ReportTemplate decoded = decodeTemplate(
        v0,
        _registry(),
        migrations: <SchemaMigration>[_RenameTitleToName()],
      );
      expect(decoded.name, 'Legacy');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test packages/jet_print/test/domain/serialization/report_codec_test.dart`
Expected: FAIL — `report_codec.dart` / `encodeTemplate` / `decodeTemplate` / `kReportSchemaVersion` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `packages/jet_print/lib/src/domain/serialization/report_codec.dart`:

```dart
/// Versioned JSON (de)serialization for [ReportTemplate] (Constitution V).
library;

import '../page_format.dart';
import '../report_band.dart';
import '../report_element.dart';
import '../report_template.dart';
import 'element_codec.dart';
import 'migration.dart';
import 'report_format_exception.dart';

/// The report-schema version this build writes. Bump on every schema change and
/// ship a [SchemaMigration] for the previous version.
const int kReportSchemaVersion = 1;

/// Encodes [template] to a JSON-safe map, stamping [kReportSchemaVersion] and
/// routing each element through [registry].
Map<String, Object?> encodeTemplate(
  ReportTemplate template,
  ElementCodecRegistry registry,
) {
  return <String, Object?>{
    'schemaVersion': kReportSchemaVersion,
    'name': template.name,
    'page': template.page.toJson(),
    'bands': <Object?>[
      for (final ReportBand band in template.bands) _encodeBand(band, registry),
    ],
  };
}

Map<String, Object?> _encodeBand(ReportBand band, ElementCodecRegistry registry) {
  return <String, Object?>{
    'type': band.type.name,
    'height': band.height,
    'elements': <Object?>[
      for (final ReportElement element in band.elements) registry.encode(element),
    ],
  };
}

/// Decodes a report [json] map. Validates `schemaVersion` (fail-fast if missing
/// or newer than this build), walks older documents forward via [migrations],
/// then parses bands/elements through [registry].
ReportTemplate decodeTemplate(
  Map<String, Object?> json,
  ElementCodecRegistry registry, {
  List<SchemaMigration> migrations = const <SchemaMigration>[],
}) {
  final Object? rawVersion = json['schemaVersion'];
  if (rawVersion is! int) {
    throw const ReportFormatException(
      'Missing or non-integer "schemaVersion".',
    );
  }
  if (rawVersion > kReportSchemaVersion) {
    throw ReportFormatException(
      'Report schemaVersion $rawVersion is newer than this build supports '
      '($kReportSchemaVersion).',
    );
  }
  final Map<String, Object?> upgraded = rawVersion < kReportSchemaVersion
      ? runMigrations(
          json,
          from: rawVersion,
          to: kReportSchemaVersion,
          migrations: migrations,
        )
      : json;

  final Object? bands = upgraded['bands'];
  if (bands is! List) {
    throw const ReportFormatException('"bands" must be a list.');
  }
  return ReportTemplate(
    name: upgraded['name']! as String,
    page: PageFormat.fromJson((upgraded['page']! as Map).cast<String, Object?>()),
    bands: <ReportBand>[
      for (final Object? band in bands)
        _decodeBand((band! as Map).cast<String, Object?>(), registry),
    ],
  );
}

ReportBand _decodeBand(Map<String, Object?> json, ElementCodecRegistry registry) {
  final Object? elements = json['elements'];
  if (elements is! List) {
    throw const ReportFormatException('Band "elements" must be a list.');
  }
  return ReportBand(
    type: BandType.values.byName(json['type']! as String),
    height: (json['height']! as num).toDouble(),
    elements: <ReportElement>[
      for (final Object? element in elements)
        registry.decode((element! as Map).cast<String, Object?>()),
    ],
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test packages/jet_print/test/domain/serialization/report_codec_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/domain/serialization/report_codec.dart packages/jet_print/test/domain/serialization/report_codec_test.dart
git commit -m "feat(domain): add versioned template serialization with migration"
```

---

### Task 10: Full-suite green, analyzer, format, CHANGELOG

**Files:**
- Modify: `packages/jet_print/CHANGELOG.md`

- [ ] **Step 1: Confirm the architecture/layer-boundary test still passes**

The existing test at `packages/jet_print/test/architecture/layer_boundaries_test.dart` auto-scans every file under `lib/src/domain/`, including the new ones. No edit is needed — just run it.

Run: `flutter test packages/jet_print/test/architecture/layer_boundaries_test.dart`
Expected: PASS — none of the new domain files import `dart:ui`, a Flutter UI library, or another seam.

- [ ] **Step 2: Run the formatter (must be clean)**

Run: `dart format --output=none --set-exit-if-changed .`
Expected: exit 0 ("Formatted N files (0 changed)"). If it reports changes, run `dart format .` then re-run the check and amend the relevant commit.

- [ ] **Step 3: Run the analyzer (zero warnings gate)**

Run: `flutter analyze`
Expected: "No issues found!" — strict-casts/inference and the promoted hygiene lints all clean.

- [ ] **Step 4: Run the full package test suite**

Run: `flutter test packages/jet_print`
Expected: PASS — all new domain tests plus the pre-existing suite (including `domain_test.dart` for the untouched `ReportDocument` stub) are green.

- [ ] **Step 5: Update the changelog**

Add an entry to the top of `packages/jet_print/CHANGELOG.md` (create the file with a `# Changelog` header first if it does not exist):

```markdown
## Unreleased

### Added
- Report model foundation (spec 003 Part 1): pure-Dart geometry value types
  (`JetSize`/`JetOffset`/`JetEdgeInsets`/`JetRect`), `PageFormat`, the element
  model (`ReportElement`, `TextElement`, `UnknownElement`), `ReportBand`/
  `BandType`/`ReportTemplate`, an `ElementCodecRegistry` extension point, and
  versioned JSON serialization with a forward-migration framework
  (`encodeTemplate`/`decodeTemplate`, `schemaVersion`, `SchemaMigration`).
```

- [ ] **Step 6: Commit**

```bash
git add packages/jet_print/CHANGELOG.md
git commit -m "docs(domain): changelog for report-model serialization foundation"
```

---

## Self-Review

**1. Spec coverage** (against spec 003 Part-1 scope in [the design doc](../specs/2026-06-07-report-engine-design.md)):
- Pure-Dart geometry value types → Task 1 ✓
- Page model → Task 2 ✓
- Element model + extension point → Tasks 3, 6 ✓
- `UnknownElement` lossless round-trip → Tasks 4, 6 ✓
- Bands + template → Task 7 ✓
- Versioned JSON + `schemaVersion` → Task 9 ✓
- Migration framework → Tasks 8, 9 ✓
- `ReportFormatException` (fail-fast structural) → Tasks 5, 9 ✓
- Layer-boundary purity (no `dart:ui`) → Task 10 Step 1 ✓ (auto-enforced)
- Deferred (image/line/rect/barcode, styles, params/vars/groups/bindings, real migrations) → explicitly out of scope; tracked for 003 Part 2.

**2. Placeholder scan:** No "TBD/TODO/handle errors appropriately"; every code step shows complete, compilable Dart and every run step gives an exact command + expected result.

**3. Type consistency:** Names are stable across tasks — `JetSize/JetOffset/JetEdgeInsets/JetRect`, `JetRect.zero`, `PageFormat.a4Portrait`, `ReportElement.typeKey`, `TextElement(id,bounds,text)`, `UnknownElement(typeKey,rawJson)`, `ElementCodec.toJson(covariant ReportElement)`/`fromJson`, `ElementCodecRegistry.register/encode/decode`, `TextElementCodec`, `BandType`, `ReportBand(type,height,elements)`, `ReportTemplate(name,page,bands)`, `ReportFormatException(message)`, `SchemaMigration.fromVersion/upgrade`, `runMigrations(json, from:, to:, migrations:)`, `kReportSchemaVersion`, `encodeTemplate(template, registry)`, `decodeTemplate(json, registry, {migrations})`. The JSON key sets used in codecs (`w/h`, `dx/dy`, `l/t/r/b`, `x/y/w/h`, `width/height/margins`, `type/id/bounds/text`, `schemaVersion/name/page/bands`, band `type/height/elements`) are consistent between every `toJson` and `fromJson`.
