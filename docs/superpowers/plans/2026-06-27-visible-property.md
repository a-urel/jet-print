# `visible` Property Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every report element and band a `visible` property — a static bool or a boolean expression — that hides the object at fill time (invisible elements aren't painted; invisible bands collapse), fully back-compatible.

**Architecture:** A new pure serializable `BoolProperty {value, expression}` value type carries the flag; `expression` wins over `value` when set. The fill engine evaluates it once per object via a shared `resolveVisibility` helper (fail-safe to *visible* + a diagnostic on parse error / eval error / non-boolean). Invisible objects are filtered out of the `FilledReport` IR, so the layouter and painter are untouched.

**Tech Stack:** Dart / Flutter, `flutter_test`, `shadcn_ui` (designer). Domain + serialization + rendering/fill + designer layers.

## Global Constraints

- Run `flutter` / `dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` ([[git-cwd-drift-after-flutter]]).
- **Constitution II (layered architecture):** domain (`lib/src/domain`) MUST NOT import the expression engine (`lib/src/expression`). `BoolProperty` stays pure; evaluation is injected.
- **Constitution V (serialization):** additive, no `reportFormatVersion` bump. Default (`value==true && expression==null`) is omitted from JSON; old reports decode to the default → visible. Round-trip stays byte-identical for all-visible reports.
- **Constitution IV (WYSIWYG):** goldens unchanged for all-visible reports.
- **Default everywhere:** `const BoolProperty()` == `{value: true, expression: null}`.
- **Rebuilder-sweep discipline ([[spec-031-designer-total-resolution-status]], [[rename-report-objects-status]]):** a new base field is silently dropped by any rebuilder that constructs a subtype directly instead of via `copyWith`. Each task that adds the field must thread it through EVERY constructor/`copyWith`/`withBounds`/`withName`/`withVisible`/`==`/`hashCode` of the affected type.
- Run `dart format` and a clean `dart analyze` before each commit.

---

## File Map

**New**
- `lib/src/domain/bool_property.dart` — the `BoolProperty` value type.
- `lib/src/rendering/fill/visibility.dart` — the `resolveVisibility` fill-time helper.
- `lib/src/designer/controller/commands/set_visible_command.dart` — undoable element + band visibility commands.
- Tests: `test/domain/bool_property_test.dart`, `test/rendering/fill/visibility_test.dart`, plus extensions to existing element/band/codec/filler/designer tests.

**Modified**
- `lib/src/domain/report_element.dart` (base field + abstract `withVisible`)
- `lib/src/domain/elements/{text,shape,image,barcode}_element.dart`, `lib/src/domain/unknown_element.dart`
- `lib/src/domain/band.dart`
- `lib/src/domain/serialization/{text,shape,image,barcode}_element_codec.dart`
- `lib/src/domain/serialization/report_definition_codec.dart` (`_encodeBand`/`_decodeBand`)
- `lib/src/rendering/fill/element_resolver.dart` (`isVisible` method)
- `lib/src/rendering/fill/report_filler.dart` (`addBand` element filter + band skip)
- `lib/src/designer/controller/jet_report_designer_controller.dart` (`setElementVisible`/`setBandVisible`)
- `lib/src/designer/layout/panels/properties_panel.dart` (Visible section, element + band)

---

## Task 1: `BoolProperty` value type

**Files:**
- Create: `lib/src/domain/bool_property.dart`
- Test: `test/domain/bool_property_test.dart`

**Interfaces:**
- Produces:
  - `class BoolProperty` with `const BoolProperty({bool value = true, String? expression})`, fields `final bool value`, `final String? expression`, `bool get hasExpression`.
  - `bool getValue(bool Function(String expr) evaluate)` — returns `expression != null ? evaluate(expression!) : value`.
  - `BoolProperty copyWith({bool? value, String Function()? expression})` — `expression` is a thunk: omit = keep, `() => null` = clear, `() => x` = set (mirrors `barcode_element.dart`'s `dataField`).
  - `Map<String, Object?> toJson()` — `{ if (!value) 'value': false, if (expression != null) 'expression': expression }` (empty map for the default).
  - `factory BoolProperty.fromJson(Map<String, Object?> json)` — `value = json['value'] as bool? ?? true`, `expression = json['expression'] as String?`.
  - value `==` / `hashCode` over `(value, expression)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/bool_property_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';

void main() {
  group('BoolProperty', () {
    test('default is visible with no expression', () {
      const p = BoolProperty();
      expect(p.value, isTrue);
      expect(p.expression, isNull);
      expect(p.hasExpression, isFalse);
    });

    test('getValue: static value used when no expression', () {
      expect(const BoolProperty(value: false).getValue((_) => true), isFalse);
      expect(const BoolProperty(value: true).getValue((_) => false), isTrue);
    });

    test('getValue: expression wins when present (precedence)', () {
      const p = BoolProperty(value: true, expression: 'x');
      expect(p.getValue((e) {
        expect(e, 'x');
        return false;
      }), isFalse);
    });

    test('copyWith thunk: omit keeps, ()=>null clears, ()=>v sets', () {
      const p = BoolProperty(value: false, expression: 'a');
      expect(p.copyWith().expression, 'a');
      expect(p.copyWith(expression: () => null).expression, isNull);
      expect(p.copyWith(expression: () => 'b').expression, 'b');
      expect(p.copyWith(value: true).value, isTrue);
    });

    test('toJson omits defaults; round-trips', () {
      expect(const BoolProperty().toJson(), <String, Object?>{});
      expect(const BoolProperty(value: false).toJson(),
          <String, Object?>{'value': false});
      expect(const BoolProperty(expression: 'q').toJson(),
          <String, Object?>{'expression': 'q'});
      const both = BoolProperty(value: false, expression: 'q');
      expect(BoolProperty.fromJson(both.toJson()), both);
    });

    test('fromJson defaults a missing value to true', () {
      expect(BoolProperty.fromJson(<String, Object?>{}), const BoolProperty());
    });

    test('equality and hashCode', () {
      expect(const BoolProperty(value: false, expression: 'a'),
          const BoolProperty(value: false, expression: 'a'));
      expect(const BoolProperty(value: false, expression: 'a').hashCode,
          const BoolProperty(value: false, expression: 'a').hashCode);
      expect(const BoolProperty(value: false),
          isNot(const BoolProperty(value: true)));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/bool_property_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../bool_property.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/domain/bool_property.dart
/// A boolean property that is either a static [value] or, when [expression] is
/// non-null, a boolean expression that takes precedence over [value].
///
/// Pure and serializable: it stores the expression as a string and never
/// evaluates it itself (Constitution II — the domain layer must not depend on
/// the expression engine). Evaluation is injected via [getValue].
library;

class BoolProperty {
  /// Creates a property defaulting to visible/true with no expression.
  const BoolProperty({this.value = true, this.expression});

  /// The static fallback, used when [expression] is null.
  final bool value;

  /// When non-null, the boolean expression that governs the result (precedence
  /// over [value]). Null means use [value].
  final String? expression;

  /// Whether an [expression] governs this property.
  bool get hasExpression => expression != null;

  /// Resolves the effective boolean. [evaluate] is supplied by the caller (the
  /// fill layer) so this type stays free of the expression engine.
  bool getValue(bool Function(String expr) evaluate) =>
      expression != null ? evaluate(expression!) : value;

  /// Returns a copy with fields replaced. [expression] is a thunk so callers can
  /// distinguish keep (omit) from clear (`() => null`) and set (`() => v`).
  BoolProperty copyWith({bool? value, String Function()? expression}) =>
      BoolProperty(
        value: value ?? this.value,
        expression: expression == null ? this.expression : expression(),
      );

  /// Emits only non-default sub-keys; the default (`true`, no expression) is the
  /// empty map (callers omit the owning key entirely).
  Map<String, Object?> toJson() => <String, Object?>{
        if (!value) 'value': false,
        if (expression != null) 'expression': expression,
      };

  /// Reads a [BoolProperty]; a missing `value` defaults to true.
  factory BoolProperty.fromJson(Map<String, Object?> json) => BoolProperty(
        value: json['value'] as bool? ?? true,
        expression: json['expression'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is BoolProperty &&
      other.value == value &&
      other.expression == expression;

  @override
  int get hashCode => Object.hash(value, expression);

  @override
  String toString() => 'BoolProperty($value'
      '${expression == null ? '' : ', expr: "$expression"'})';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/bool_property_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/bool_property.dart packages/jet_print/test/domain/bool_property_test.dart
git commit -m "feat(domain): add BoolProperty value type for visible property"
```

---

## Task 2: `visible` on the element model

Add `BoolProperty visible` to `ReportElement` and thread it through every subtype. Add a polymorphic `withVisible` primitive (mirrors `withName`).

**Files:**
- Modify: `lib/src/domain/report_element.dart`
- Modify: `lib/src/domain/elements/text_element.dart`, `shape_element.dart`, `image_element.dart`, `barcode_element.dart`
- Modify: `lib/src/domain/unknown_element.dart`
- Test: `test/domain/element_visible_test.dart` (new)

**Interfaces:**
- Consumes: `BoolProperty` (Task 1).
- Produces:
  - `ReportElement` base: `final BoolProperty visible` (constructor `this.visible = const BoolProperty()`), abstract `ReportElement withVisible(BoolProperty visible)`.
  - Each subtype: `visible` passed via `super.visible`, threaded through its constructor / `copyWith` / `withBounds` / `withName` / `==` / `hashCode`, and a concrete `withVisible`.
  - `UnknownElement.withVisible` is a no-op returning `this` (its JSON is authoritative).

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/element_visible_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';

const _b = JetRect(x: 0, y: 0, width: 10, height: 10);
const _b2 = JetRect(x: 1, y: 1, width: 5, height: 5);
const _vis = BoolProperty(value: false, expression: 'show');

void main() {
  final List<ReportElement> samples = <ReportElement>[
    const TextElement(id: 't', bounds: _b, text: 'x', visible: _vis),
    const ShapeElement(id: 's', bounds: _b, visible: _vis),
    ImageElement(id: 'i', bounds: _b, visible: _vis),
    const BarcodeElement(id: 'c', bounds: _b, data: '1', visible: _vis),
  ];

  for (final ReportElement e in samples) {
    group('${e.runtimeType} preserves visible', () {
      test('default is visible', () {
        // A fresh element with no visible arg defaults to the visible default.
        expect(e.withVisible(const BoolProperty()).visible,
            const BoolProperty());
      });
      test('withBounds preserves visible', () {
        expect(e.withBounds(_b2).visible, _vis);
      });
      test('withName preserves visible', () {
        expect(e.withName('n').visible, _vis);
      });
      test('withVisible replaces only visible', () {
        final ReportElement r = e.withVisible(const BoolProperty(value: true));
        expect(r.visible, const BoolProperty(value: true));
        expect(r.id, e.id);
        expect(r.bounds, e.bounds);
      });
      test('equality distinguishes visible', () {
        expect(e, isNot(e.withVisible(const BoolProperty())));
      });
    });
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/element_visible_test.dart`
Expected: FAIL — `No named parameter with the name 'visible'`.

- [ ] **Step 3: Modify the base class**

In `lib/src/domain/report_element.dart`, add the import, the field, and the abstract primitive:

```dart
import 'bool_property.dart';
import 'geometry.dart';
```

```dart
  const ReportElement(
      {required this.id,
      required this.bounds,
      this.name,
      this.visible = const BoolProperty()});
```

```dart
  /// Whether this element renders. A static bool or a boolean expression
  /// (BoolProperty); when invisible the element is omitted at fill time and
  /// never painted. Defaults to always-visible.
  final BoolProperty visible;
```

After `withName`, add:

```dart
  /// Returns a copy of this element of the **same concrete type** with its
  /// [visible] property replaced, every other field preserved. The polymorphic
  /// visibility primitive (mirrors [withName]). An [UnknownElement] is a no-op
  /// passthrough (its preserved JSON is inert).
  ReportElement withVisible(BoolProperty visible);
```

- [ ] **Step 4: Thread through `TextElement`**

`lib/src/domain/elements/text_element.dart`: add `import '../bool_property.dart';`. Add `super.visible` to the constructor; add `BoolProperty? visible` to `copyWith` and pass `visible: visible ?? this.visible`; pass `visible: visible` in `withBounds` (it delegates to `copyWith`, already covered) and `withName`; add `withVisible`; add `visible` to `==` and `hashCode`.

```dart
  const TextElement({
    required super.id,
    required super.bounds,
    required this.text,
    this.style = JetTextStyle.fallback,
    this.expression,
    this.format,
    super.name,
    super.visible,
  });
```

```dart
  TextElement copyWith(
          {String? text,
          JetTextStyle? style,
          JetRect? bounds,
          String? name,
          BoolProperty? visible}) =>
      TextElement(
        id: id,
        bounds: bounds ?? this.bounds,
        text: text ?? this.text,
        style: style ?? this.style,
        expression: expression,
        format: format,
        name: name ?? this.name,
        visible: visible ?? this.visible,
      );

  @override
  TextElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  TextElement withName(String? name) => TextElement(
        id: id,
        bounds: bounds,
        text: text,
        style: style,
        expression: expression,
        format: format,
        name: name,
        visible: visible,
      );

  @override
  TextElement withVisible(BoolProperty visible) => TextElement(
        id: id,
        bounds: bounds,
        text: text,
        style: style,
        expression: expression,
        format: format,
        name: name,
        visible: visible,
      );
```

Add `&& other.visible == visible` to `operator ==`, and `visible` as the last arg to `Object.hash(...)`.

- [ ] **Step 5: Thread through `ShapeElement`**

`lib/src/domain/elements/shape_element.dart`: add `import '../bool_property.dart';`, `super.visible` to the constructor, `BoolProperty? visible` to `copyWith` (pass `visible: visible ?? this.visible`), `visible: visible` to the direct-constructor `withBounds` and `withName` bodies, a `withVisible` that rebuilds preserving every field (incl. `kind`/`style`/`unknownForm`), and `visible` in `==`/`hashCode`. Match the existing field set in this file exactly — read it first.

- [ ] **Step 6: Thread through `ImageElement`**

`lib/src/domain/elements/image_element.dart` (no `copyWith` — direct constructors): add `import '../bool_property.dart';`, `super.visible` to the constructor, `visible: visible` to the `withBounds` and `withName` direct constructors, add `withVisible`:

```dart
  @override
  ImageElement withBounds(JetRect bounds) =>
      ImageElement(id: id, bounds: bounds, source: source, fit: fit, name: name,
          visible: visible);

  @override
  ImageElement withName(String? name) =>
      ImageElement(id: id, bounds: bounds, source: source, fit: fit, name: name,
          visible: visible);

  @override
  ImageElement withVisible(BoolProperty visible) =>
      ImageElement(id: id, bounds: bounds, source: source, fit: fit, name: name,
          visible: visible);
```

Add `visible` to `==`/`hashCode` (read the file; match the existing equality field set).

- [ ] **Step 7: Thread through `BarcodeElement`**

`lib/src/domain/elements/barcode_element.dart`: add `import '../bool_property.dart';`, `super.visible` to the constructor, `BoolProperty? visible` to `copyWith` (pass `visible: visible ?? this.visible`; `withBounds` delegates to `copyWith`), `visible: visible` to the direct-constructor `withName` body, add `withVisible` rebuilding directly and preserving every field (`symbology`/`data`/`dataField`/`showText`/`quietZone`/`eccLevel`/`color`/… — read the file), and `visible` in `==`/`hashCode`.

- [ ] **Step 8: Add the `UnknownElement` no-op**

`lib/src/domain/unknown_element.dart`:

```dart
  /// A no-op: an unknown element's preserved JSON is never rewritten, so it
  /// round-trips byte-for-byte (Constitution V). Setting visibility on an
  /// unrecognized element is intentionally inert rather than lossy.
  @override
  UnknownElement withVisible(BoolProperty visible) => this;
```

Add `import 'bool_property.dart';`.

- [ ] **Step 9: Run the test to verify it passes**

Run: `flutter test test/domain/element_visible_test.dart`
Expected: PASS.

- [ ] **Step 10: Guard against the rebuilder sweep**

Run from `packages/jet_print`:
```bash
grep -rn "TextElement(\|ShapeElement(\|ImageElement(\|BarcodeElement(" lib | grep -v "_test\|copyWith\|class \|//"
```
For each hit that constructs an element and is NOT a `withVisible`/`copyWith` already covered, confirm whether it should carry `visible` forward. **Known intentional exception:** `element_resolver.dart` builds fresh `TextElement(...)` copies on parse-error / unresolved-field / page-ref branches — those are post-fill resolved copies whose visibility was already applied by the filter (Task 7), so they need not carry `visible`. Document any other rebuilder you touch in the commit message.

- [ ] **Step 11: Run the domain test suite + analyze**

Run: `flutter test test/domain && dart analyze lib/src/domain`
Expected: PASS, no analyzer issues.

- [ ] **Step 12: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain packages/jet_print/test/domain/element_visible_test.dart
git commit -m "feat(domain): add visible BoolProperty + withVisible to all elements"
```

---

## Task 3: Element codec serialization

**Files:**
- Modify: `lib/src/domain/serialization/text_element_codec.dart`, `shape_element_codec.dart`, `image_element_codec.dart`, `barcode_element_codec.dart`
- Test: `test/domain/serialization/element_visible_codec_test.dart` (new)

**Interfaces:**
- Consumes: `BoolProperty.toJson` / `BoolProperty.fromJson` (Task 1); `visible` on each element (Task 2).
- Produces: each codec writes `if (element.visible != const BoolProperty()) 'visible': element.visible.toJson()` and reads `visible: json['visible'] is Map ? BoolProperty.fromJson((json['visible']! as Map).cast<String, Object?>()) : const BoolProperty()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/serialization/element_visible_codec_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';

void main() {
  const codec = TextElementCodec();
  const b = JetRect(x: 0, y: 0, width: 10, height: 10);

  test('default visible is omitted from JSON (back-compat)', () {
    const el = TextElement(id: 't', bounds: b, text: 'x');
    expect(codec.toJson(el).containsKey('visible'), isFalse);
  });

  test('non-default visible round-trips', () {
    const el = TextElement(
        id: 't', bounds: b, text: 'x',
        visible: BoolProperty(value: false, expression: r'$F{ok}'));
    final json = codec.toJson(el);
    expect(json['visible'],
        <String, Object?>{'value': false, 'expression': r'$F{ok}'});
    expect(codec.fromJson(json).visible,
        const BoolProperty(value: false, expression: r'$F{ok}'));
  });

  test('legacy JSON without visible decodes to default', () {
    final el = codec.fromJson(<String, Object?>{
      'id': 't',
      'bounds': b.toJson(),
      'text': 'x',
    });
    expect(el.visible, const BoolProperty());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/serialization/element_visible_codec_test.dart`
Expected: FAIL — `visible` key absent / not read.

- [ ] **Step 3: Update each codec**

In each of the four codecs add `import '../bool_property.dart';`. In `fromJson`, add the named arg:
```dart
        visible: json['visible'] is Map
            ? BoolProperty.fromJson((json['visible']! as Map).cast<String, Object?>())
            : const BoolProperty(),
```
In `toJson`, append (keep it after the existing optional keys, e.g. after `name`):
```dart
        if (element.visible != const BoolProperty())
          'visible': element.visible.toJson(),
```

- [ ] **Step 4: Run the test + the existing codec suite**

Run: `flutter test test/domain/serialization`
Expected: PASS (new test + all existing round-trip tests green — back-compat).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/serialization packages/jet_print/test/domain/serialization/element_visible_codec_test.dart
git commit -m "feat(serialization): persist element visible (omit-when-default)"
```

---

## Task 4: `visible` on `Band`

**Files:**
- Modify: `lib/src/domain/band.dart`
- Test: `test/domain/band_visible_test.dart` (new)

**Interfaces:**
- Consumes: `BoolProperty` (Task 1).
- Produces: `Band` gains `final BoolProperty visible` (constructor `this.visible = const BoolProperty()`), `BoolProperty? visible` in `copyWith`, and `visible` in `==`/`hashCode`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/band_visible_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;

void main() {
  const band = Band(id: 'b', type: BandType.detail, height: 20);

  test('default band is visible', () {
    expect(band.visible, const BoolProperty());
  });

  test('copyWith sets visible, preserves others', () {
    final r = band.copyWith(visible: const BoolProperty(value: false));
    expect(r.visible, const BoolProperty(value: false));
    expect(r.id, 'b');
    expect(r.height, 20);
  });

  test('copyWith without visible preserves it', () {
    final hidden = band.copyWith(visible: const BoolProperty(expression: 'e'));
    expect(hidden.copyWith(height: 30).visible,
        const BoolProperty(expression: 'e'));
  });

  test('equality distinguishes visible', () {
    expect(band, isNot(band.copyWith(visible: const BoolProperty(value: false))));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/band_visible_test.dart`
Expected: FAIL — `No named parameter with the name 'visible'`.

- [ ] **Step 3: Modify `Band`**

Add `import 'bool_property.dart';`. Add `this.visible = const BoolProperty()` to the constructor; the field with dartdoc; `BoolProperty? visible` to `copyWith` passing `visible: visible ?? this.visible`; `&& other.visible == visible` to `==`; and `visible` to `Object.hash(...)`.

- [ ] **Step 4: Run the test + domain suite to verify pass**

Run: `flutter test test/domain/band_visible_test.dart test/domain`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/band.dart packages/jet_print/test/domain/band_visible_test.dart
git commit -m "feat(domain): add visible BoolProperty to Band"
```

---

## Task 5: Band codec serialization

**Files:**
- Modify: `lib/src/domain/serialization/report_definition_codec.dart` (`_encodeBand` ~line 128, `_decodeBand` ~line 306)
- Test: `test/domain/serialization/band_visible_codec_test.dart` (new)

**Interfaces:**
- Consumes: `Band.visible` (Task 4), `BoolProperty` JSON (Task 1).
- Produces: `_encodeBand` writes `if (band.visible != const BoolProperty()) 'visible': band.visible.toJson()`; `_decodeBand` reads `visible: json['visible'] is Map ? BoolProperty.fromJson(...) : const BoolProperty()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/domain/serialization/band_visible_codec_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/serialization/report_definition_codec.dart';
import 'package:jet_print/src/domain/serialization/report_format.dart';

// Build the smallest definition with one band carrying a non-default visible,
// encode then decode, and assert the band's visible survives. Read an existing
// report_definition_codec round-trip test first to copy the construction helper
// for a minimal ReportDefinition with a single detail band.
void main() {
  test('band visible round-trips; default omitted', () {
    // ... construct def with detailBand.copyWith(
    //        visible: const BoolProperty(expression: r'$F{show}')) ...
    // final json = encodeReportDefinition(def);   // match the real API name
    // final back = decodeReportDefinition(json);
    // expect(<the band>.visible, const BoolProperty(expression: r'$F{show}'));
  });
}
```
Replace the comments with the concrete construction/round-trip, copying the helper and the exact public encode/decode function names from an existing test in `test/domain/serialization/`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/serialization/band_visible_codec_test.dart`
Expected: FAIL — band visible not preserved.

- [ ] **Step 3: Update `_encodeBand` / `_decodeBand`**

Add `import '../bool_property.dart';` (if not already present). In `_encodeBand`, after the `name` key:
```dart
    if (band.visible != const BoolProperty()) 'visible': band.visible.toJson(),
```
In `_decodeBand`, add to the `Band(...)` construction:
```dart
    visible: json['visible'] is Map
        ? BoolProperty.fromJson((json['visible']! as Map).cast<String, Object?>())
        : const BoolProperty(),
```

- [ ] **Step 4: Run the test + full serialization suite**

Run: `flutter test test/domain/serialization`
Expected: PASS (back-compat: existing definition round-trips unchanged).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart packages/jet_print/test/domain/serialization/band_visible_codec_test.dart
git commit -m "feat(serialization): persist band visible (omit-when-default)"
```

---

## Task 6: `resolveVisibility` fill-time helper

A pure helper that evaluates a `BoolProperty` against a `FillEvalContext`, fail-safe to *visible* with a diagnostic on any problem.

**Files:**
- Create: `lib/src/rendering/fill/visibility.dart`
- Test: `test/rendering/fill/visibility_test.dart` (new)

**Interfaces:**
- Consumes: `BoolProperty.getValue` (Task 1); `FillEvalContext` (`fill_eval_context.dart`); `ReportDiagnostics` (`report_diagnostics.dart`); `Expression` / `JetValue` / `JetBool` / `JetError` (`lib/src/expression`).
- Produces:
  ```dart
  bool resolveVisibility(
      BoolProperty prop, FillEvalContext ctx, ReportDiagnostics diagnostics,
      {required String id, required Set<String> pageRefs});
  ```
  Returns the effective visibility. On parse error, eval error (`JetError`), page-scoped-var use, or a non-`JetBool` result → returns `true` and records a diagnostic. `pageRefs` is the set `FillEvalContext` populates when a `$V{}` page var is touched (caller passes the same set it gave the context).

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/fill/visibility_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/rendering/fill/fill_eval_context.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';
import 'package:jet_print/src/rendering/fill/visibility.dart';

bool _run(BoolProperty p, ReportDiagnostics d) {
  final refs = <String>{};
  final ctx = FillEvalContext(
    functions: JetFunctionRegistry.standard(), // use the real factory name
    diagnostics: d,
    warnedFields: <String>{},
    pageRefs: refs,
    elementId: 'x',
  );
  return resolveVisibility(p, ctx, d, id: 'x', pageRefs: refs);
}

void main() {
  test('static true / false', () {
    expect(_run(const BoolProperty(), ReportDiagnostics()), isTrue);
    expect(_run(const BoolProperty(value: false), ReportDiagnostics()), isFalse);
  });

  test('boolean expression true / false', () {
    expect(_run(const BoolProperty(expression: '1 == 1'), ReportDiagnostics()),
        isTrue);
    expect(_run(const BoolProperty(expression: '1 == 2'), ReportDiagnostics()),
        isFalse);
  });

  test('parse error -> visible + diagnostic', () {
    final d = ReportDiagnostics();
    expect(_run(const BoolProperty(expression: '1 +'), d), isTrue);
    expect(d.messages, isNotEmpty);
  });

  test('non-boolean result -> visible + diagnostic', () {
    final d = ReportDiagnostics();
    expect(_run(const BoolProperty(expression: '1 + 1'), d), isTrue);
    expect(d.messages, isNotEmpty);
  });
}
```
Confirm the real `JetFunctionRegistry` factory name and `ReportDiagnostics` accessor (`.messages` / `.diagnostics`) from `function_registry.dart` and `report_diagnostics.dart`; adjust the helper/assertions to match.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/rendering/fill/visibility_test.dart`
Expected: FAIL — `visibility.dart` missing.

- [ ] **Step 3: Write the helper**

```dart
// lib/src/rendering/fill/visibility.dart
/// Fill-time evaluation of an object's [BoolProperty] visibility (elements and
/// bands share this). Fail-safe: any parse error, evaluation error, page-scoped
/// variable use, or non-boolean result keeps the object VISIBLE and records a
/// diagnostic, so a broken expression never silently drops content.
library;

import '../../domain/bool_property.dart';
import '../../expression/expression.dart';
import '../../expression/expression_exception.dart';
import '../../expression/value.dart';
import 'fill_eval_context.dart';
import 'report_diagnostics.dart';

/// Returns whether the object is visible. [pageRefs] is the set the [ctx] fills
/// when a page-scoped variable is referenced (illegal here → diagnostic).
bool resolveVisibility(
  BoolProperty prop,
  FillEvalContext ctx,
  ReportDiagnostics diagnostics, {
  required String id,
  required Set<String> pageRefs,
}) {
  return prop.getValue((String exprText) {
    final Expression parsed;
    try {
      parsed = Expression.parse(exprText);
    } on ExpressionException catch (e) {
      diagnostics.error('Visibility expression parse failed: ${e.message}',
          elementId: id);
      return true;
    }
    final JetValue value = parsed.evaluate(ctx);
    if (pageRefs.isNotEmpty) {
      diagnostics.error(
          'Page-scoped variable(s) ${pageRefs.join(', ')} are not allowed in a '
          'visibility expression',
          elementId: id);
      return true;
    }
    if (value is JetError) {
      diagnostics.error('Visibility expression error: ${value.message}',
          elementId: id);
      return true;
    }
    if (value is JetBool) return value.value;
    diagnostics.warning(
        'Visibility expression did not evaluate to a boolean; element shown',
        elementId: id);
    return true;
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/rendering/fill/visibility_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill/visibility.dart packages/jet_print/test/rendering/fill/visibility_test.dart
git commit -m "feat(fill): add resolveVisibility helper (fail-safe to visible)"
```

---

## Task 7: Wire visibility into the filler

Filter invisible elements out of each filled band; skip invisible bands entirely (collapse).

**Files:**
- Modify: `lib/src/rendering/fill/element_resolver.dart` (add `isVisible`)
- Modify: `lib/src/rendering/fill/report_filler.dart` (`addBand` element filter + band skip)
- Test: `test/rendering/fill/fill_visibility_test.dart` (new)

**Interfaces:**
- Consumes: `resolveVisibility` (Task 6); `ReportElement.visible` / `Band.visible`; `FillEvalContext`.
- Produces:
  - `ElementResolver.isVisible(ReportElement el, {DataRow? row, Map<String, Object?> params, Map<String, JetValue> variables}) -> bool` — builds a `FillEvalContext` (as `_resolveText` does) and calls `resolveVisibility(el.visible, ctx, diagnostics, id: el.id, pageRefs: pageRefs)`.
  - `report_filler.dart`: a `bandVisible(Band, DataRow?, vars)` local that resolves `band.visible`; `addBand` filters elements via `resolver.isVisible(...)`; `emitOnce`/`addBand` callers skip emitting when the band is invisible.

- [ ] **Step 1: Write the failing test**

```dart
// test/rendering/fill/fill_visibility_test.dart
// Fill a report with: (a) an element whose visible.value == false,
// (b) an element with a per-row visible expression, (c) a band with
// visible.value == false. Assert (a)/(c) are absent from FilledReport,
// (b) appears only on matching rows. Copy the fill harness (data source +
// fillReport call) from an existing test in test/rendering/fill/.
import 'package:flutter_test/flutter_test.dart';
// imports + harness per existing fill tests

void main() {
  test('invisible element is omitted from the filled band', () {
    // build def with a detail band containing one visible + one hidden element
    // fill, then assert the hidden element id is not in any FilledBand.elements
  });

  test('invisible band is omitted from the band stream (collapse)', () {
    // band.copyWith(visible: const BoolProperty(value: false))
    // assert no FilledBand of that band's identity/role appears
  });

  test('per-row visible expression hides on non-matching rows', () {
    // visible: BoolProperty(expression: r'$F{flag} == true')
    // assert element present on flag==true rows, absent on flag==false rows
  });

  test('all-visible report is unchanged (regression)', () {
    // fill a normal def, assert element/band counts match the pre-change baseline
  });
}
```
Fill in using the existing fill-test harness (find the `fillReport`/`ReportFiller` entry point and a sample `JetDataSource` in `test/rendering/fill/`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/rendering/fill/fill_visibility_test.dart`
Expected: FAIL — hidden element/band still present.

- [ ] **Step 3: Add `ElementResolver.isVisible`**

In `element_resolver.dart`, add `import '../../domain/bool_property.dart';` and `import 'visibility.dart';`, then:

```dart
  /// Whether [element] is visible for this row (FR — visible property). Builds
  /// the same evaluation context a text expression sees; fail-safe to visible.
  bool isVisible(
    ReportElement element, {
    DataRow? row,
    Map<String, Object?> params = const <String, Object?>{},
    Map<String, JetValue> variables = const <String, JetValue>{},
  }) {
    if (element.visible == const BoolProperty()) return true; // fast path
    final Set<String> pageRefs = <String>{};
    final FillEvalContext ctx = FillEvalContext(
      row: row,
      params: params,
      variables: variables,
      functions: functions,
      diagnostics: diagnostics,
      warnedFields: warnedFields,
      pageRefs: pageRefs,
      elementId: element.id,
      budget: budget,
    );
    return resolveVisibility(element.visible, ctx, diagnostics,
        id: element.id, pageRefs: pageRefs);
  }
```

- [ ] **Step 4: Filter elements in `addBand`**

In `report_filler.dart` `addBand` (~line 235), guard each resolved element:
```dart
        elements: <ReportElement>[
          for (final ReportElement e in band.elements)
            if (resolver.isVisible(e, row: row, params: params, variables: vars))
              resolver.resolve(e, row: row, params: params, variables: vars),
        ],
```

- [ ] **Step 5: Skip invisible bands**

Still in `report_filler.dart`, add a band-visibility gate at the top of `addBand` so an invisible band never enters the stream:
```dart
    void addBand(Band band, DataRow? row, Map<String, JetValue> vars,
        {String? group}) {
      if (band.visible != const BoolProperty()) {
        final Set<String> pageRefs = <String>{};
        final ctx = FillEvalContext(
          row: row, params: params, variables: vars,
          functions: functions, diagnostics: diagnostics,
          warnedFields: warnedFields, pageRefs: pageRefs, elementId: band.id,
        );
        if (!resolveVisibility(band.visible, ctx, diagnostics,
            id: band.id, pageRefs: pageRefs)) {
          return; // collapse: omit the band entirely
        }
      }
      bands.add(FilledBand( /* unchanged */ ));
    }
```
Add `import 'visibility.dart';` and (if not present) the `bool_property`/`FillEvalContext`/`function_registry` imports to `report_filler.dart`. Confirm `functions`, `diagnostics`, `warnedFields`, `params` are in scope at `addBand` (they are used to build `resolver` earlier — reuse the same locals).

- [ ] **Step 6: Run the test + full fill suite**

Run: `flutter test test/rendering/fill`
Expected: PASS — new visibility tests + all existing fill tests green (all-visible unchanged).

- [ ] **Step 7: Run golden tests (no regression)**

Run: `flutter test` (or the golden subset, e.g. `flutter test --tags golden` if tagged)
Expected: PASS — goldens byte-identical (no report under test uses `visible`).

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill packages/jet_print/test/rendering/fill/fill_visibility_test.dart
git commit -m "feat(fill): omit invisible elements; collapse invisible bands"
```

---

## Task 8: `SetVisibleCommand` + controller methods

**Files:**
- Create: `lib/src/designer/controller/commands/set_visible_command.dart`
- Modify: `lib/src/designer/controller/jet_report_designer_controller.dart`
- Test: `test/designer/controller/set_visible_command_test.dart` (new)

**Interfaces:**
- Consumes: `EditCommand` / `DesignerDocument` (`edit_command.dart`, `designer_document.dart`); `updateElement` / `updateBand` (`band_walker.dart`); `ReportElement.withVisible` (Task 2); `Band.copyWith` (Task 4); `_commit` (private controller method).
- Produces:
  - `class SetElementVisibleCommand extends EditCommand { const SetElementVisibleCommand({required String id, required BoolProperty visible}); }`
  - `class SetBandVisibleCommand extends EditCommand { const SetBandVisibleCommand({required String bandId, required BoolProperty visible}); }`
  - Controller: `void setElementVisible(String id, BoolProperty visible)`, `void setBandVisible(String bandId, BoolProperty visible)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/designer/controller/set_visible_command_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/bool_property.dart';
// import controller + a builder for a minimal definition with one element + band
// (copy the setup from an existing controller test, e.g. set_binding_command_test).

void main() {
  test('setElementVisible sets and is undoable', () {
    // final c = <controller with a text element 't'>;
    // c.setElementVisible('t', const BoolProperty(value: false));
    // expect(<element 't'>.visible, const BoolProperty(value: false));
    // c.undo();
    // expect(<element 't'>.visible, const BoolProperty());
  });

  test('setBandVisible sets and is undoable', () {
    // c.setBandVisible('<bandId>', const BoolProperty(expression: r'$F{x}'));
    // expect(<band>.visible.expression, r'$F{x}');
    // c.undo(); expect(<band>.visible, const BoolProperty());
  });

  test('setElementVisible on equal value is a no-op (no history entry)', () {
    // c.setElementVisible('t', const BoolProperty()); // already default
    // expect(c.canUndo, isFalse);  // match the real undo-availability getter
  });
}
```
Copy the controller construction + the undo/lookup getters from an existing controller test (e.g. `test/designer/controller/set_binding_command_test.dart` if present, else the nearest command test).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/designer/controller/set_visible_command_test.dart`
Expected: FAIL — methods/commands missing.

- [ ] **Step 3: Write the commands**

```dart
// lib/src/designer/controller/commands/set_visible_command.dart
/// Commands that set an object's [visible] BoolProperty (visible property).
library;

import '../../../domain/bool_property.dart';
import '../../../domain/band.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the [visible] property of the element with [id]. No-op for an absent id
/// or an already-equal value.
class SetElementVisibleCommand extends EditCommand {
  const SetElementVisibleCommand({required this.id, required this.visible});

  final String id;
  final BoolProperty visible;

  @override
  String get label => 'Set visibility';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(before.definition, id,
            (ReportElement e) => e.withVisible(visible)),
      );
}

/// Sets the [visible] property of the band with [bandId].
class SetBandVisibleCommand extends EditCommand {
  const SetBandVisibleCommand({required this.bandId, required this.visible});

  final String bandId;
  final BoolProperty visible;

  @override
  String get label => 'Set band visibility';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateBand(before.definition, bandId,
            (Band b) => b.copyWith(visible: visible)),
      );
}
```

- [ ] **Step 4: Add the controller methods**

In `jet_report_designer_controller.dart`, add the import and (near `setBinding`, ~line 748):
```dart
  /// Sets the [visible] property of element [id] (undoable). No-op when equal.
  void setElementVisible(String id, BoolProperty visible) =>
      _commit(SetElementVisibleCommand(id: id, visible: visible));

  /// Sets the [visible] property of band [bandId] (undoable). No-op when equal.
  void setBandVisible(String bandId, BoolProperty visible) =>
      _commit(SetBandVisibleCommand(bandId: bandId, visible: visible));
```
Add `import '../../domain/bool_property.dart';` and `import 'commands/set_visible_command.dart';` (match the existing import grouping).

- [ ] **Step 5: Run the test to verify pass**

Run: `flutter test test/designer/controller/set_visible_command_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/controller packages/jet_print/test/designer/controller/set_visible_command_test.dart
git commit -m "feat(designer): SetVisibleCommand + controller setElement/BandVisible"
```

---

## Task 9: Properties panel Visible section (element + band)

A "Visible" toggle + an optional expression field (fx editor) for the selected element and for the selected band.

**Files:**
- Modify: `lib/src/designer/layout/panels/properties_panel.dart`
- Test: `test/designer/properties_visible_test.dart` (new, widget test)

**Interfaces:**
- Consumes: `controller.setElementVisible` / `controller.setBandVisible` (Task 8); `showExpressionEditor(context, ...)` (`expression_editor_dialog.dart`, returns `Future<String?>`); `ShadSwitch`; the `_LabeledRow` helper already in this file; `element.visible` / `band.visible`.
- Produces: a private `_visibleSection({required BoolProperty visible, required ValueChanged<BoolProperty> onChanged})` widget reused by the element inspector and `_bandInspector`.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/designer/properties_visible_test.dart
// Pump the designer with one text element selected; find the "Visible" switch,
// toggle it off, assert controller.setElementVisible was called with
// BoolProperty(value:false) (or assert the element's visible became value:false).
// Copy the pump/setup harness from an existing properties_panel widget test.
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toggling Visible off hides the selected element', (t) async {
    // pump designer, select element, tap the Visible ShadSwitch,
    // expect <element>.visible == const BoolProperty(value: false)
  });
}
```
Copy the pump harness + finders from the nearest existing `test/designer/*properties*` widget test.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/designer/properties_visible_test.dart`
Expected: FAIL — no "Visible" control.

- [ ] **Step 3: Add the shared section widget**

In `properties_panel.dart`, add a helper on `_PropertiesPanelState`:
```dart
  Widget _visibleSection({
    required BoolProperty visible,
    required ValueChanged<BoolProperty> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _LabeledRow(
          label: l10n.visibleLabel, // add to l10n; fallback literal 'Visible' ok for first cut
          child: ShadSwitch(
            value: visible.value,
            onChanged: (bool v) => onChanged(visible.copyWith(value: v)),
          ),
        ),
        _LabeledRow(
          label: l10n.visibleWhenLabel, // 'Visible when'
          child: _ExpressionButton(
            expression: visible.expression,
            onEdit: () async {
              final String? next = await showExpressionEditor(
                  context, /* match the real positional/named params */
                  initial: visible.expression);
              if (next == null) return; // dialog cancelled
              onChanged(visible.copyWith(
                  expression: () => next.isEmpty ? null : next));
            },
          ),
        ),
      ],
    );
  }
```
`_ExpressionButton` may already exist for the text-element expression UI — reuse it; if not, render a simple button showing `visible.expression ?? '—'` that opens the editor. Match `showExpressionEditor`'s real signature (read `expression_editor_dialog.dart` lines 26–40).

- [ ] **Step 4: Wire it into the element inspector**

In the element inspector body (after the geometry block, before the per-type sections ~line 329), insert:
```dart
        _visibleSection(
          visible: element.visible,
          onChanged: (BoolProperty v) =>
              controller.setElementVisible(element.id, v),
        ),
```

- [ ] **Step 5: Wire it into the band inspector**

In `_bandInspector`, after the band name/height controls, insert:
```dart
        _visibleSection(
          visible: band.visible,
          onChanged: (BoolProperty v) => controller.setBandVisible(band.id, v),
        ),
```
(Read `_bandInspector` to get the local `band` variable name; if it only has `bandId`, look the band up via `findBand(controller.definition, bandId)`.)

- [ ] **Step 6: Add l10n strings (or inline literals)**

If the designer uses generated l10n, add `visibleLabel` ("Visible") and `visibleWhenLabel` ("Visible when") to the ARB and regenerate; otherwise use string literals for the first cut. Match the existing l10n pattern in this file (it imports an `l10n` object).

- [ ] **Step 7: Run the test + designer suite + analyze**

Run: `flutter test test/designer && dart analyze lib`
Expected: PASS, no analyzer issues.

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/test/designer/properties_visible_test.dart packages/jet_print/lib/src/designer/l10n
git commit -m "feat(designer): Visible toggle + expression in Properties panel"
```

---

## Final verification

- [ ] Run the full suite: `cd packages/jet_print && flutter test`. Expected: all green (lib + playground if applicable).
- [ ] `dart analyze` clean; `dart format --set-exit-if-changed lib test` clean.
- [ ] Confirm goldens byte-identical (no baseline regenerated).
- [ ] **Opus final review** specifically auditing the rebuilder sweep (Task 2 Step 10): grep every `TextElement(`/`ShapeElement(`/`ImageElement(`/`BarcodeElement(`/`Band(` direct constructor in `lib/` and confirm none silently drops `visible` (the [[spec-031-designer-total-resolution-status]] failure mode).
- [ ] Manual GUI walk: toggle an element/band visible off; set a `$F{}` boolean expression; verify hide + collapse in preview.

## Self-review notes (coverage check)

- Spec §1 BoolProperty → Task 1. §2 model fields (element+band) → Tasks 2, 4. §3 fill (element omit + band collapse + helper) → Tasks 6, 7. §4 serialization → Tasks 3, 5. §5 designer UI → Tasks 8, 9. §6 testing → every task is TDD + final golden check.
- Precedence (expression wins) lives only in `BoolProperty.getValue` (Task 1) — single source.
- Fail-safe-to-visible + diagnostic lives only in `resolveVisibility` (Task 6) — single source.
- Back-compat: omit-when-default in Tasks 3 & 5; legacy-decode tests in both.
- Type consistency: `withVisible(BoolProperty)`, `copyWith({..., BoolProperty? visible})`, `copyWith({..., String Function()? expression})` (thunk) used identically across tasks.
