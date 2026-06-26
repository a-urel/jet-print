# Rename Report Objects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let designer users give any element or band a friendly, optional display name (editable in the Properties header and the Outline tree), falling back to the element's text or its type label when blank.

**Architecture:** Add an optional `String? name` to the `ReportElement` base and `Band`, threaded through every subtype, `copyWith`, and JSON codec (written only when non-null → backward-compatible, goldens byte-identical). A `displayLabel` resolver computes what Properties/Outline show. Two new undoable commands (`RenameElementCommand`, `RenameBandCommand`) reuse the existing `updateElement`/`updateBand` walkers and the value-equality no-op in `_commit`. A single reusable `EditableLabel` widget powers both edit surfaces.

**Tech Stack:** Dart / Flutter, `shadcn_ui` (ShadTheme), the package's hand-written localizations (`JetPrintLocalizations`), the existing `EditCommand` + `DesignerDocument` undo model.

## Global Constraints

- **No schema-version bump.** `name` is an additive optional field; codecs read a missing `name` as `null`. Existing serialized reports must round-trip byte-identically (matches the spec 036 barcode precedent).
- **`id` is never changed.** It stays the unique identity key (selection, hit-test, copy/paste, undo, validator I1). `name` is unconstrained (may be empty/blank, may duplicate).
- **Empty name = use default.** Trimmed-empty/whitespace `name` is stored as `null`; the UI shows the fallback label.
- **Goldens unaffected.** `name` is never painted onto the canvas.
- **Locales.** The package ships `en`, `de`, `tr`. No new localized strings are required (fallbacks reuse existing `elementTypeLabel`/`bandTypeLabel`).
- **Immutability + value equality.** Every domain type is `const`-friendly and implements `==`/`hashCode` over all fields — `name` must be added to both.

---

### Task 1: Domain — add optional `name` to elements and bands

**Files:**
- Modify: `packages/jet_print/lib/src/domain/report_element.dart` (base class: add `name` field + abstract `withName`)
- Modify: `packages/jet_print/lib/src/domain/elements/text_element.dart`
- Modify: `packages/jet_print/lib/src/domain/elements/shape_element.dart`
- Modify: `packages/jet_print/lib/src/domain/elements/image_element.dart`
- Modify: `packages/jet_print/lib/src/domain/elements/barcode_element.dart`
- Modify: `packages/jet_print/lib/src/domain/unknown_element.dart`
- Modify: `packages/jet_print/lib/src/domain/band.dart` (add `name` to ctor + `copyWith` + `==`/`hashCode`)
- Test: `packages/jet_print/test/domain/elements/element_name_test.dart` (new)
- Test: `packages/jet_print/test/domain/band_test.dart` (extend)

**Interfaces:**
- Produces:
  - `ReportElement.name` → `String?` (default `null`), on the base.
  - `ReportElement.withName(String? name)` → `ReportElement` (abstract; returns a copy of the same concrete type with `name` replaced — the polymorphic rename primitive, mirroring `withBounds`).
  - Each subtype's `copyWith` gains a `String? name` parameter that **replaces** the field (so `copyWith(name: null)` cannot clear — clearing goes through `withName`; see note below).
  - `Band.copyWith({String? name})` replaces the band name.
- Consumes: nothing from other tasks.

> **`copyWith` vs `withName` for clearing:** Dart's positional-default `copyWith` cannot distinguish "leave" from "set null". So for elements, `copyWith({String? name})` only *sets* a non-null name; **clearing to null is done exclusively via `withName(null)`**, which reconstructs the element. `withName(value)` is the single primitive the rename command uses (it handles both set and clear). `Band` is simpler — its rename command builds the band explicitly (Task 4), so `Band.copyWith` does not need a clear path either; the command passes the full reconstruction.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/elements/element_name_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/report_element.dart';

void main() {
  const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 10);

  test('name defaults to null on every element type', () {
    expect(const TextElement(id: 't', bounds: r, text: 'x').name, isNull);
    expect(
        const ShapeElement(id: 's', bounds: r, kind: ShapeKind.rectangle).name,
        isNull);
    expect(
        const BarcodeElement(
                id: 'b',
                bounds: r,
                symbology: BarcodeSymbology.auto,
                data: 'x')
            .name,
        isNull);
  });

  test('withName sets and clears name, preserving type and other fields', () {
    const TextElement t = TextElement(id: 't', bounds: r, text: 'hi');
    final ReportElement named = t.withName('Greeting');
    expect(named, isA<TextElement>());
    expect(named.name, 'Greeting');
    expect((named as TextElement).text, 'hi');
    expect(named.id, 't');
    expect(named.withName(null).name, isNull);
  });

  test('name participates in equality', () {
    const TextElement a = TextElement(id: 't', bounds: r, text: 'hi');
    final ReportElement b = a.withName('Greeting');
    expect(a == b, isFalse);
    expect(a.withName('Greeting') == b, isTrue);
  });

  test('constructor accepts name', () {
    const ShapeElement s =
        ShapeElement(id: 's', bounds: r, kind: ShapeKind.rectangle, name: 'Line');
    expect(s.name, 'Line');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/domain/elements/element_name_test.dart`
Expected: FAIL — `name` getter and `withName`/`name:` parameter don't exist (compile errors).

- [ ] **Step 3: Implement — base class**

In `report_element.dart`, extend the base constructor and add the field + abstract primitive:

```dart
abstract class ReportElement {
  /// Creates an element with a unique [id] and absolute [bounds], and an
  /// optional human-facing [name].
  const ReportElement({required this.id, required this.bounds, this.name});

  /// Stable, unique identifier within a template (used for selection/binding).
  final String id;

  /// Absolute position and size within the owning band, in points.
  final JetRect bounds;

  /// Optional human-facing display name. When null/blank the UI shows a
  /// fallback (the element's text, or its type label). Never referenced by
  /// expressions; purely a label. Unconstrained — may be empty or duplicated.
  final String? name;

  String get typeKey;

  ReportElement withBounds(JetRect bounds);

  /// Returns a copy of this element of the **same concrete type** with its
  /// display [name] replaced (pass `null` to clear), every other field
  /// preserved. The polymorphic rename primitive (mirrors [withBounds]). An
  /// [UnknownElement] is a no-op passthrough (its preserved JSON is inert).
  ReportElement withName(String? name);
}
```

- [ ] **Step 4: Implement — TextElement**

Thread `super.name`, add `name` to `copyWith`, add `withName`, include in `==`/`hashCode`:

```dart
  const TextElement({
    required super.id,
    required super.bounds,
    required this.text,
    this.style = JetTextStyle.fallback,
    this.expression,
    this.format,
    super.name,
  });

  // ... fields unchanged ...

  TextElement copyWith({String? text, JetTextStyle? style, JetRect? bounds, String? name}) =>
      TextElement(
        id: id,
        bounds: bounds ?? this.bounds,
        text: text ?? this.text,
        style: style ?? this.style,
        expression: expression,
        format: format,
        name: name ?? this.name,
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
      );

  @override
  bool operator ==(Object other) =>
      other is TextElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.text == text &&
      other.style == style &&
      other.expression == expression &&
      other.format == format &&
      other.name == name;

  @override
  int get hashCode =>
      Object.hash(id, bounds, text, style, expression, format, name);
```

> Note: `withName` reconstructs explicitly (does not call `copyWith`) so passing `null` truly clears the name.

- [ ] **Step 5: Implement — ShapeElement**

```dart
  const ShapeElement({
    required super.id,
    required super.bounds,
    required this.kind,
    this.style = JetBoxStyle.none,
    this.flipDiagonal = false,
    this.unknownForm,
    super.name,
  });

  ShapeElement copyWith({
    JetRect? bounds,
    ShapeKind? kind,
    JetBoxStyle? style,
    bool? flipDiagonal,
    bool clearUnknownForm = false,
    String? name,
  }) =>
      ShapeElement(
        id: id,
        bounds: bounds ?? this.bounds,
        kind: kind ?? this.kind,
        style: style ?? this.style,
        flipDiagonal: flipDiagonal ?? this.flipDiagonal,
        unknownForm: clearUnknownForm ? null : unknownForm,
        name: name ?? this.name,
      );

  @override
  ShapeElement withBounds(JetRect bounds) => ShapeElement(
        id: id,
        bounds: bounds,
        kind: kind,
        style: style,
        flipDiagonal: flipDiagonal,
        unknownForm: unknownForm,
        name: name,
      );

  @override
  ShapeElement withName(String? name) => ShapeElement(
        id: id,
        bounds: bounds,
        kind: kind,
        style: style,
        flipDiagonal: flipDiagonal,
        unknownForm: unknownForm,
        name: name,
      );
```

Add `&& other.name == name` to `==` and `name` as the final arg of `Object.hash(...)`.

- [ ] **Step 6: Implement — ImageElement**

```dart
  const ImageElement({
    required super.id,
    required super.bounds,
    required this.source,
    this.fit = JetBoxFit.contain,
    super.name,
  });

  @override
  ImageElement withBounds(JetRect bounds) =>
      ImageElement(id: id, bounds: bounds, source: source, fit: fit, name: name);

  @override
  ImageElement withName(String? name) =>
      ImageElement(id: id, bounds: bounds, source: source, fit: fit, name: name);
```

Add `&& other.name == name` to `==` and `name` to `Object.hash(id, bounds, source, fit, name)`.

- [ ] **Step 7: Implement — BarcodeElement**

```dart
  const BarcodeElement({
    required super.id,
    required super.bounds,
    required this.symbology,
    required this.data,
    this.dataField,
    this.color = JetColor.black,
    this.showText = true,
    this.quietZone = true,
    this.eccLevel = QrErrorCorrectionLevel.m,
    super.name,
  });

  BarcodeElement copyWith({
    JetRect? bounds,
    BarcodeSymbology? symbology,
    String? data,
    String? Function()? dataField,
    JetColor? color,
    bool? showText,
    bool? quietZone,
    QrErrorCorrectionLevel? eccLevel,
    String? name,
  }) =>
      BarcodeElement(
        id: id,
        bounds: bounds ?? this.bounds,
        symbology: symbology ?? this.symbology,
        data: data ?? this.data,
        dataField: dataField != null ? dataField() : this.dataField,
        color: color ?? this.color,
        showText: showText ?? this.showText,
        quietZone: quietZone ?? this.quietZone,
        eccLevel: eccLevel ?? this.eccLevel,
        name: name ?? this.name,
      );

  @override
  BarcodeElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  BarcodeElement withName(String? name) => BarcodeElement(
        id: id,
        bounds: bounds,
        symbology: symbology,
        data: data,
        dataField: dataField,
        color: color,
        showText: showText,
        quietZone: quietZone,
        eccLevel: eccLevel,
        name: name,
      );
```

Add `&& other.name == name` to `==` and `name` as the final arg of `Object.hash(...)` (Object.hash supports up to 20 args — currently 9, fine).

- [ ] **Step 8: Implement — UnknownElement**

Preserve any `name` already present in its raw JSON, keep `withName` a no-op passthrough (consistent with `withBounds`):

```dart
  UnknownElement({required this.typeKey, required this.rawJson})
      : super(
          id: rawJson['id'] is String ? rawJson['id']! as String : '',
          bounds: _readBounds(rawJson['bounds']),
          name: rawJson['name'] is String ? rawJson['name']! as String : null,
        );

  @override
  UnknownElement withBounds(JetRect bounds) => this;

  /// A no-op: an unknown element's preserved JSON is never rewritten, so it
  /// round-trips byte-for-byte (Constitution V). Renaming an unrecognized
  /// element is intentionally inert rather than lossy.
  @override
  UnknownElement withName(String? name) => this;
```

- [ ] **Step 9: Implement — Band**

Add `name` to the constructor, `copyWith`, `==`, `hashCode`:

```dart
  const Band({
    required this.id,
    required this.type,
    required this.height,
    this.elements = const <ReportElement>[],
    this.columnLayout,
    this.name,
  });

  /// Optional human-facing display name; when null/blank the Outline and
  /// Properties show the localized [bandTypeLabel]. Unconstrained.
  final String? name;

  Band copyWith({
    String? id,
    BandType? type,
    double? height,
    List<ReportElement>? elements,
    ColumnLayout? columnLayout,
    String? name,
  }) =>
      Band(
        id: id ?? this.id,
        type: type ?? this.type,
        height: height ?? this.height,
        elements: elements ?? this.elements,
        columnLayout: columnLayout ?? this.columnLayout,
        name: name ?? this.name,
      );
```

Add `&& other.name == name` to `==` and `name` to `Object.hash(id, type, height, Object.hashAll(elements), columnLayout, name)`.

> **Band clearing caveat:** like elements, `Band.copyWith(name: null)` won't clear. The rename command (Task 4) reconstructs the band explicitly to support clearing. Add a one-line `band_test.dart` case (Step 10) asserting `copyWith(name: 'X')` sets the name.

- [ ] **Step 10: Extend band_test.dart**

Add to `packages/jet_print/test/domain/band_test.dart`:

```dart
  test('Band carries an optional name (default null)', () {
    const Band b = Band(id: 'b1', type: BandType.detail, height: 20);
    expect(b.name, isNull);
    expect(b.copyWith(name: 'Lines').name, 'Lines');
    expect(b.copyWith(name: 'Lines') == b, isFalse);
  });
```

(Reuse the file's existing imports for `Band`/`BandType`.)

- [ ] **Step 11: Run tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/domain/elements/element_name_test.dart test/domain/band_test.dart`
Expected: PASS.

- [ ] **Step 12: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain packages/jet_print/test/domain
git commit -m "feat(domain): add optional display name to elements and bands"
```

---

### Task 2: Serialization — round-trip `name`

**Files:**
- Modify: `packages/jet_print/lib/src/domain/serialization/text_element_codec.dart`
- Modify: `packages/jet_print/lib/src/domain/serialization/shape_element_codec.dart`
- Modify: `packages/jet_print/lib/src/domain/serialization/image_element_codec.dart`
- Modify: `packages/jet_print/lib/src/domain/serialization/barcode_element_codec.dart`
- Modify: `packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart` (`_encodeBand` + `_decodeBand`)
- Test: `packages/jet_print/test/domain/serialization/name_roundtrip_test.dart` (new)

**Interfaces:**
- Consumes: `ReportElement.name`, `Band.name` (Task 1).
- Produces: each codec's `toJson` writes `'name'` only when non-null; `fromJson` reads `json['name'] as String?`. Legacy JSON (no `name` key) decodes to `null`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/domain/serialization/name_roundtrip_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;

void main() {
  const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 10);
  const TextElementCodec codec = TextElementCodec();

  test('text element name round-trips when set', () {
    const TextElement t =
        TextElement(id: 't', bounds: r, text: 'hi', name: 'Greeting');
    final Map<String, Object?> json = codec.toJson(t);
    expect(json['name'], 'Greeting');
    expect(codec.fromJson(json).name, 'Greeting');
  });

  test('text element omits name key when null (byte-compatible legacy)', () {
    const TextElement t = TextElement(id: 't', bounds: r, text: 'hi');
    final Map<String, Object?> json = codec.toJson(t);
    expect(json.containsKey('name'), isFalse);
  });

  test('legacy JSON without name decodes to null', () {
    final TextElement decoded = codec.fromJson(<String, Object?>{
      'id': 't',
      'bounds': r.toJson(),
      'text': 'hi',
    });
    expect(decoded.name, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/domain/serialization/name_roundtrip_test.dart`
Expected: FAIL — `toJson` does not emit `name`, `fromJson` ignores it.

- [ ] **Step 3: Implement — every element codec**

In `text_element_codec.dart` `fromJson`, add after `format:`:

```dart
        name: json['name'] as String?,
```

In `toJson`, add as the last map entry:

```dart
        if (element.name != null) 'name': element.name,
```

Apply the identical two edits to `shape_element_codec.dart`, `image_element_codec.dart`, and `barcode_element_codec.dart` (add `name: json['name'] as String?` to each `fromJson` constructor call, and `if (element.name != null) 'name': element.name` as the final entry of each `toJson` map).

- [ ] **Step 4: Implement — band codec**

In `report_definition_codec.dart`, `_encodeBand` — add as the final entry before the closing brace:

```dart
    if (band.name != null) 'name': band.name,
```

In `_decodeBand`, add to the `Band(...)` constructor (after `columnLayout:`):

```dart
    name: json['name'] as String?,
```

- [ ] **Step 5: Run the new test + the existing round-trip suite**

Run: `cd packages/jet_print && flutter test test/domain/serialization/`
Expected: PASS — including `built_in_round_trip_test.dart` and `styled_elements_roundtrip_test.dart` (unchanged, since `name` is omitted when null).

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/serialization packages/jet_print/test/domain/serialization
git commit -m "feat(serialization): round-trip element and band display name"
```

---

### Task 3: Display-label resolver

**Files:**
- Create: `packages/jet_print/lib/src/designer/l10n/object_display_label.dart`
- Test: `packages/jet_print/test/designer/l10n/object_display_label_test.dart` (new)

**Interfaces:**
- Consumes: `ReportElement.name`, `Band.name` (Task 1); existing `elementTypeLabel(element, l10n)` and `bandTypeLabel(type, l10n)`.
- Produces:
  - `String elementDisplayLabel(ReportElement element, JetPrintLocalizations l10n)` — `name` if non-blank; else a `TextElement`'s `text` if non-blank; else `elementTypeLabel(element, l10n)`.
  - `String bandDisplayLabel(Band band, JetPrintLocalizations l10n)` — `name` if non-blank; else `bandTypeLabel(band.type, l10n)`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/l10n/object_display_label_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/designer/l10n/jet_print_localizations_en.dart';
import 'package:jet_print/src/designer/l10n/object_display_label.dart';

void main() {
  final l10n = JetPrintLocalizationsEn();
  const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 10);

  test('explicit name wins', () {
    const t = TextElement(id: 't', bounds: r, text: 'hi', name: 'Greeting');
    expect(elementDisplayLabel(t, l10n), 'Greeting');
  });

  test('blank name on text falls back to its text', () {
    const t = TextElement(id: 't', bounds: r, text: 'Subtotal');
    expect(elementDisplayLabel(t, l10n), 'Subtotal');
  });

  test('whitespace-only name is treated as blank', () {
    const t = TextElement(id: 't', bounds: r, text: 'Subtotal', name: '   ');
    expect(elementDisplayLabel(t, l10n), 'Subtotal');
  });

  test('blank text falls back to the type label', () {
    const t = TextElement(id: 't', bounds: r, text: '');
    expect(elementDisplayLabel(t, l10n), l10n.elementTypeText);
  });

  test('non-text element falls back to its type label', () {
    const s = ShapeElement(id: 's', bounds: r, kind: ShapeKind.rectangle);
    expect(elementDisplayLabel(s, l10n), l10n.elementTypeShape);
  });

  test('band name wins, else type label', () {
    const named = Band(id: 'b', type: BandType.detail, height: 20, name: 'Lines');
    const plain = Band(id: 'b', type: BandType.groupFooter, height: 20);
    expect(bandDisplayLabel(named, l10n), 'Lines');
    expect(bandDisplayLabel(plain, l10n), l10n.bandTypeGroupFooter);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/l10n/object_display_label_test.dart`
Expected: FAIL — `object_display_label.dart` does not exist.

- [ ] **Step 3: Implement the resolver**

Create `packages/jet_print/lib/src/designer/l10n/object_display_label.dart`:

```dart
/// Resolves the label shown for a report object in the Properties header and
/// the Outline tree. A single source of truth so both surfaces agree (and a
/// rename is reflected identically in each).
library;

import '../../domain/band.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/report_element.dart';
import 'band_type_label.dart';
import 'element_type_label.dart';
import 'jet_print_localizations.dart';

bool _blank(String? s) => s == null || s.trim().isEmpty;

/// The label for [element]: its display [ReportElement.name] when set; else a
/// [TextElement]'s literal text when non-blank; else the localized type label.
String elementDisplayLabel(
    ReportElement element, JetPrintLocalizations l10n) {
  if (!_blank(element.name)) return element.name!.trim();
  if (element is TextElement && !_blank(element.text)) return element.text;
  return elementTypeLabel(element, l10n);
}

/// The label for [band]: its display [Band.name] when set; else the localized
/// band-type label.
String bandDisplayLabel(Band band, JetPrintLocalizations l10n) {
  if (!_blank(band.name)) return band.name!.trim();
  return bandTypeLabel(band.type, l10n);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/l10n/object_display_label_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/l10n/object_display_label.dart packages/jet_print/test/designer/l10n/object_display_label_test.dart
git commit -m "feat(designer): add object display-label resolver"
```

---

### Task 4: Rename commands

**Files:**
- Create: `packages/jet_print/lib/src/designer/controller/commands/rename_element_command.dart`
- Create: `packages/jet_print/lib/src/designer/controller/commands/rename_band_command.dart`
- Test: `packages/jet_print/test/designer/controller/rename_command_test.dart` (new)

**Interfaces:**
- Consumes: `ReportElement.withName` (Task 1), `Band.copyWith`/reconstruction (Task 1), `updateElement`/`updateBand` (`band_walker.dart`), `EditCommand`, `DesignerDocument`.
- Produces:
  - `RenameElementCommand({required String id, required String? name})` — sets the element's display name (`null` clears).
  - `RenameBandCommand({required String bandId, required String? name})` — sets the band's display name (`null` clears).
  - Both are value-equal no-ops when the name is unchanged (handled by `_commit`).

> The caller normalizes blank→null (Task 5); commands store whatever they're given.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/controller/rename_command_test.dart`. Build a minimal document via the existing test fixtures — mirror an existing command test (e.g. `binding_command_test.dart`) for `DesignerDocument` construction. Skeleton:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/designer/controller/designer_document.dart';
import 'package:jet_print/src/designer/controller/commands/rename_element_command.dart';
import 'package:jet_print/src/designer/controller/commands/rename_band_command.dart';
import 'package:jet_print/src/designer/controller/band_walker.dart';

// Helper: smallest definition holding one detail band with one text element.
// Reuse the construction pattern from binding_command_test.dart.
void main() {
  const JetRect r = JetRect(x: 0, y: 0, width: 10, height: 10);

  test('RenameElementCommand sets the element name', () {
    final DesignerDocument doc = _docWith(
      const TextElement(id: 't1', bounds: r, text: 'hi'),
    );
    final DesignerDocument after =
        const RenameElementCommand(id: 't1', name: 'Greeting').apply(doc);
    final ReportElement? e = _findElement(after, 't1');
    expect(e?.name, 'Greeting');
  });

  test('RenameElementCommand clears the name with null', () {
    final DesignerDocument doc = _docWith(
      const TextElement(id: 't1', bounds: r, text: 'hi', name: 'Old'),
    );
    final DesignerDocument after =
        const RenameElementCommand(id: 't1', name: null).apply(doc);
    expect(_findElement(after, 't1')?.name, isNull);
  });

  test('RenameBandCommand sets the band name', () {
    final DesignerDocument doc = _docWith(
      const TextElement(id: 't1', bounds: r, text: 'hi'),
    );
    final DesignerDocument after =
        const RenameBandCommand(bandId: 'detail', name: 'Lines').apply(doc);
    // assert the band named 'detail' now has name 'Lines' (walk via band_walker)
  });
}
```

(The implementer fills `_docWith`/`_findElement` by copying the fixture helpers from `binding_command_test.dart`; the band id in that fixture is the detail band's id.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/controller/rename_command_test.dart`
Expected: FAIL — command classes don't exist.

- [ ] **Step 3: Implement RenameElementCommand**

Create `rename_element_command.dart`:

```dart
/// The command that sets a report element's display name.
library;

import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the display [name] of the element with [id] (via `withName`; `null`
/// clears it back to the fallback label). Preserves every other field.
/// Renaming to the current name yields a value-equal document, so the
/// controller's commit records no history entry (a no-op). A no-op for an
/// absent id (the transform returns the element unchanged for non-matches).
class RenameElementCommand extends EditCommand {
  /// Creates a rename of element [id] to [name] (`null` clears).
  const RenameElementCommand({required this.id, required this.name});

  /// The target element id.
  final String id;

  /// The new display name, or `null` to clear.
  final String? name;

  @override
  String get label => 'Rename';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
            before.definition, id, (ReportElement e) => e.withName(name)),
      );
}
```

- [ ] **Step 4: Implement RenameBandCommand**

Create `rename_band_command.dart`. `Band.copyWith(name: null)` cannot clear, so reconstruct via `copyWith` for set and an explicit `Band(...)` for clear:

```dart
/// The command that sets a band's display name.
library;

import '../../../domain/band.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the display [name] of the band with [bandId] (`null` clears it back to
/// the localized type label). Renaming to the current name is a value-equal
/// no-op; a no-op for an absent id.
class RenameBandCommand extends EditCommand {
  /// Creates a rename of band [bandId] to [name] (`null` clears).
  const RenameBandCommand({required this.bandId, required this.name});

  /// The target band id.
  final String bandId;

  /// The new display name, or `null` to clear.
  final String? name;

  @override
  String get label => 'Rename';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateBand(before.definition, bandId, (Band b) => Band(
              id: b.id,
              type: b.type,
              height: b.height,
              elements: b.elements,
              columnLayout: b.columnLayout,
              name: name,
            )),
      );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/controller/rename_command_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/controller/commands packages/jet_print/test/designer/controller/rename_command_test.dart
git commit -m "feat(designer): add rename-element and rename-band commands"
```

---

### Task 5: Controller API — `renameElement` / `renameBand`

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (add imports + two methods)
- Test: `packages/jet_print/test/designer/controller/rename_controller_test.dart` (new)

**Interfaces:**
- Consumes: `RenameElementCommand`, `RenameBandCommand` (Task 4); existing `_commit`.
- Produces:
  - `void renameElement(String id, String? name)` — normalizes blank→null, commits one undoable step; no-op when unchanged.
  - `void renameBand(String bandId, String? name)` — same for bands.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/controller/rename_controller_test.dart`. Construct a controller from a fixture definition the way existing controller tests do (mirror `properties_editor_test.dart` or `band_lifecycle_test.dart` for controller setup):

```dart
// imports as in existing controller tests + the controller
void main() {
  test('renameElement sets name and is undoable', () {
    final controller = /* build from fixture with text element 't1' */;
    controller.renameElement('t1', 'Greeting');
    expect(/* element t1 */ .name, 'Greeting');
    controller.undo();
    expect(/* element t1 */ .name, isNull);
  });

  test('renameElement normalizes blank to null', () {
    final controller = /* fixture, t1 already named 'Old' */;
    controller.renameElement('t1', '   ');
    expect(/* element t1 */ .name, isNull);
  });

  test('renameElement to the same value records no history', () {
    final controller = /* fixture, t1 unnamed */;
    final bool before = controller.canUndo; // false
    controller.renameElement('t1', null); // unchanged
    expect(controller.canUndo, before);
  });

  test('renameBand sets the band name', () {
    final controller = /* fixture */;
    controller.renameBand('detail', 'Lines');
    expect(/* band detail */ .name, 'Lines');
  });
}
```

(Use the controller's existing read accessors — e.g. `controller.definition` walked via `band_walker` — and `canUndo`/`undo` exactly as other controller tests reference them. The implementer copies those helpers from a neighboring test.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/controller/rename_controller_test.dart`
Expected: FAIL — `renameElement`/`renameBand` not defined.

- [ ] **Step 3: Add the imports**

In `jet_report_designer_controller.dart`, alongside the other `commands/` imports (near lines 47–52):

```dart
import 'commands/rename_band_command.dart';
import 'commands/rename_element_command.dart';
```

- [ ] **Step 4: Implement the methods**

Add next to `setText`/`rename` (after the `rename` method, ~line 723):

```dart
  /// Sets the display [name] of the element [id] as one undoable step.
  ///
  /// A blank or whitespace-only [name] is normalized to `null` (clearing the
  /// override so the fallback label shows). Renaming to the current value is a
  /// no-op (no history, no notify). Mirrors the report-level [rename].
  void renameElement(String id, String? name) =>
      _commit(RenameElementCommand(id: id, name: _normalizeName(name)));

  /// Sets the display [name] of the band [bandId] as one undoable step; blank
  /// normalizes to `null` (falling back to the band-type label). No-op when
  /// unchanged.
  void renameBand(String bandId, String? name) =>
      _commit(RenameBandCommand(bandId: bandId, name: _normalizeName(name)));

  static String? _normalizeName(String? name) =>
      (name == null || name.trim().isEmpty) ? null : name.trim();
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/controller/rename_controller_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart packages/jet_print/test/designer/controller/rename_controller_test.dart
git commit -m "feat(designer): controller renameElement/renameBand with blank normalization"
```

---

### Task 6: `EditableLabel` widget

**Files:**
- Create: `packages/jet_print/lib/src/designer/layout/widgets/editable_label.dart`
- Test: `packages/jet_print/test/designer/widgets/editable_label_test.dart` (new)

**Interfaces:**
- Produces a reusable widget:
  ```dart
  EditableLabel({
    Key? key,
    required String display,        // what shows when not editing (the resolved label)
    required String? value,         // the raw stored name to prefill (null/blank → empty field)
    required String placeholder,    // shown in the empty field (the fallback label)
    required ValueChanged<String?> onCommit, // trimmed text, or null when cleared
    bool editing,                   // controlled: is the field shown?
    VoidCallback? onEditingStart,   // request to enter edit mode (e.g. tap)
    VoidCallback? onEditingEnd,     // edit dismissed (commit or cancel)
    TextStyle? textStyle,
  })
  ```
- Behavior: when `editing` is false shows `display` text; when true shows a `TextField` autofocused, prefilled with `value ?? ''`, `placeholder` as hint. **Enter** or **focus-loss** commits `onCommit(normalized)` (trim; empty→null) then `onEditingEnd()`. **Esc** calls `onEditingEnd()` without committing.
- Consumes: nothing from earlier tasks (pure widget).

> Controlled `editing` keeps state in the parent (the panel), so the Outline knows which row is being renamed and the Properties header can reset on selection change.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/widgets/editable_label_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/layout/widgets/editable_label.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('shows display text when not editing', (tester) async {
    await tester.pumpWidget(host(EditableLabel(
      display: 'Greeting',
      value: 'Greeting',
      placeholder: 'Text',
      editing: false,
      onCommit: (_) {},
    )));
    expect(find.text('Greeting'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Enter commits trimmed text', (tester) async {
    String? committed = 'unset';
    await tester.pumpWidget(host(EditableLabel(
      display: 'Greeting',
      value: 'Greeting',
      placeholder: 'Text',
      editing: true,
      onCommit: (v) => committed = v,
    )));
    await tester.enterText(find.byType(TextField), '  Total  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(committed, 'Total');
  });

  testWidgets('empty commit yields null', (tester) async {
    String? committed = 'unset';
    await tester.pumpWidget(host(EditableLabel(
      display: 'Greeting',
      value: 'Greeting',
      placeholder: 'Text',
      editing: true,
      onCommit: (v) => committed = v,
    )));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(committed, isNull);
  });

  testWidgets('Esc cancels without committing', (tester) async {
    String? committed = 'unset';
    await tester.pumpWidget(host(EditableLabel(
      display: 'Greeting',
      value: 'Greeting',
      placeholder: 'Text',
      editing: true,
      onCommit: (v) => committed = v,
    )));
    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(committed, 'unset');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/widgets/editable_label_test.dart`
Expected: FAIL — widget doesn't exist.

- [ ] **Step 3: Implement the widget**

Create `packages/jet_print/lib/src/designer/layout/widgets/editable_label.dart`:

```dart
/// A label that swaps to an inline text field for renaming a report object.
///
/// Used by the Properties header and the Outline rows so rename behaves
/// identically in both. `editing` is controlled by the parent (which tracks
/// which object is being renamed). Commit trims the input and maps an empty
/// result to `null` (clearing the name → fallback label).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// See library doc. [onCommit] receives the trimmed name, or `null` when empty.
class EditableLabel extends StatefulWidget {
  /// Creates an editable label.
  const EditableLabel({
    super.key,
    required this.display,
    required this.value,
    required this.placeholder,
    required this.onCommit,
    this.editing = false,
    this.onEditingEnd,
    this.textStyle,
  });

  /// The text shown when not editing (the resolved display label).
  final String display;

  /// The raw stored name used to prefill the field (null/blank → empty).
  final String? value;

  /// The hint shown in the empty field (the fallback label).
  final String placeholder;

  /// Called with the trimmed new name, or `null` when the field is left empty.
  final ValueChanged<String?> onCommit;

  /// Whether the inline field is shown (controlled by the parent).
  final bool editing;

  /// Called when the edit ends (after commit, or on Esc cancel).
  final VoidCallback? onEditingEnd;

  /// The text style for the static label.
  final TextStyle? textStyle;

  @override
  State<EditableLabel> createState() => _EditableLabelState();
}

class _EditableLabelState extends State<EditableLabel> {
  late final TextEditingController _text =
      TextEditingController(text: widget.value ?? '');
  final FocusNode _focus = FocusNode();
  bool _committing = false;

  @override
  void didUpdateWidget(EditableLabel old) {
    super.didUpdateWidget(old);
    if (widget.editing && !old.editing) {
      _text.text = widget.value ?? '';
      _committing = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focus.requestFocus();
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      });
    }
  }

  void _commit() {
    if (_committing) return;
    _committing = true;
    final String trimmed = _text.text.trim();
    widget.onCommit(trimmed.isEmpty ? null : trimmed);
    widget.onEditingEnd?.call();
  }

  void _cancel() {
    _committing = true; // suppress the focus-loss commit that Esc triggers
    widget.onEditingEnd?.call();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.editing) {
      return Text(
        widget.display,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.textStyle,
      );
    }
    return Focus(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.placeholder,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        ),
        style: widget.textStyle,
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _commit(),
      ),
    );
  }
}
```

> Note on focus-loss vs Esc: `_cancel` sets `_committing = true` first so the `onTapOutside`/blur that Esc may provoke is suppressed — Esc never commits.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/widgets/editable_label_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/widgets/editable_label.dart packages/jet_print/test/designer/widgets/editable_label_test.dart
git commit -m "feat(designer): add reusable EditableLabel widget"
```

---

### Task 7: Wire rename into the Properties header

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (`_Header`, `_elementInspector`, `_bandInspector`, and the panel's `State` to hold an `_editingHeader` flag)
- Test: `packages/jet_print/test/designer/properties_rename_test.dart` (new)

**Interfaces:**
- Consumes: `EditableLabel` (Task 6); `elementDisplayLabel`/`bandDisplayLabel` (Task 3); `elementTypeLabel`/`bandTypeLabel` (existing); `controller.renameElement`/`renameBand` (Task 5).
- Produces: clicking the Properties header name turns it into an `EditableLabel`; commit calls the matching controller rename. The flag resets when the selection changes.

- [ ] **Step 1: Write the failing widget test**

Create `packages/jet_print/test/designer/properties_rename_test.dart`. Mirror `properties_editor_test.dart` for harness setup (it already pumps the Properties panel against a controller). Assert:

```dart
// 1. Pump designer with a TextElement selected whose text is 'Subtotal', no name.
// 2. Expect the header shows 'Subtotal' (the fallback) via find.text('Subtotal').
// 3. Tap the header label; enter 'Totals row'; submit.
// 4. Expect controller's element now has name 'Totals row'
//    (walk controller.definition) and find.text('Totals row') in the header.
```

(The implementer copies the exact pump/harness helpers from `properties_editor_test.dart`; use the same key conventions. Add a `ValueKey('jet_print.designer.properties.header')` to the header in Step 3 to target the tap.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/properties_rename_test.dart`
Expected: FAIL — header is static text, no rename.

- [ ] **Step 3: Make `_Header` editable**

Convert the `_Header` usages so the title is rendered through `EditableLabel`. Since the Properties panel is already a `StatefulWidget` (it holds focus nodes like `_xFocus`), add a field to its state:

```dart
  bool _editingHeader = false;
```

Reset it whenever the inspected object changes — in the build path that computes the selected id/band, compare against a stored `_lastInspectedKey` and set `_editingHeader = false` when it differs (follow the same reset idiom the panel already uses for its number-field focus, if any; otherwise reset in `didUpdateWidget`/at the top of the inspector build when the target key changes).

Give `_Header` an editing-capable variant. Replace its `Text(title, …)` with:

```dart
        Expanded(
          child: EditableLabel(
            key: const ValueKey<String>('jet_print.designer.properties.header'),
            display: title,
            value: rawName,
            placeholder: fallback,
            editing: editing,
            onEditingEnd: onEditingEnd,
            onCommit: onCommit,
            textStyle:
                theme.textTheme.small.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
```

Add `rawName`, `fallback`, `editing`, `onEditingEnd`, `onCommit` as `_Header` constructor params, and wrap the glyph+label row in a `GestureDetector(onTap: onEditingStart)` (a new param) so clicking the header begins editing.

- [ ] **Step 4: Pass the wiring from the element inspector**

In `_elementInspector`, replace the header line:

```dart
      _Header(
        icon: _elementGlyph(element),
        title: elementDisplayLabel(element, l10n),
        rawName: element.name,
        fallback: elementTypeLabel(element, l10n),
        editing: _editingHeader,
        onEditingStart: () => setState(() => _editingHeader = true),
        onEditingEnd: () => setState(() => _editingHeader = false),
        onCommit: (String? name) {
          controller.renameElement(element.id, name);
          setState(() => _editingHeader = false);
        },
        theme: theme,
      ),
```

Add the import:

```dart
import '../../l10n/object_display_label.dart';
```

(and `element_type_label.dart` if not already imported).

- [ ] **Step 5: Pass the wiring from the band inspector**

In `_bandInspector` (around line 843), wire the band's `_Header` the same way:

```dart
      _Header(
        icon: _bandGlyph(band.type),
        title: bandDisplayLabel(band, l10n),
        rawName: band.name,
        fallback: bandTypeLabel(band.type, l10n),
        editing: _editingHeader,
        onEditingStart: () => setState(() => _editingHeader = true),
        onEditingEnd: () => setState(() => _editingHeader = false),
        onCommit: (String? name) {
          controller.renameBand(band.id, name);
          setState(() => _editingHeader = false);
        },
        theme: theme,
      ),
```

Leave the group header (`group.name`, line ~901) untouched (out of scope). For any *other* `_Header` callers (e.g. line ~874), pass `editing: false`, `onEditingStart: null`, and a no-op `onCommit` so they stay read-only — or give `_Header` sensible defaults (`editing = false`, `onEditingStart`/`onCommit` optional) so existing call sites compile unchanged.

- [ ] **Step 6: Run the test + the existing Properties tests**

Run: `cd packages/jet_print && flutter test test/designer/properties_rename_test.dart test/designer/properties_editor_test.dart test/designer/properties_focus_test.dart`
Expected: PASS (no regressions in the existing Properties tests).

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/test/designer/properties_rename_test.dart
git commit -m "feat(designer): rename objects from the Properties header"
```

---

### Task 8: Wire rename into the Outline tree (double-click)

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart` (track an `_editingId`; render the band/element label through `EditableLabel`; double-tap to start)
- Test: `packages/jet_print/test/designer/outline_rename_test.dart` (new)

**Interfaces:**
- Consumes: `EditableLabel` (Task 6); `elementDisplayLabel`/`bandDisplayLabel` (Task 3); `controller.renameElement`/`renameBand` (Task 5).
- Produces: double-tapping an element or band row in the Outline replaces its label with an inline editor; commit calls the matching controller rename. Single tap still selects.

> The panel must be (or become) a `StatefulWidget` to hold `String? _editingId`. Check the current declaration first — if it's `StatelessWidget`, convert it, moving the existing `_collapsed`/`_toggle` state in with it (they look like instance state already, so it is almost certainly already stateful).

- [ ] **Step 1: Write the failing widget test**

Create `packages/jet_print/test/designer/outline_rename_test.dart`. Mirror `outline_tree_test.dart` for harness setup. Assert:

```dart
// 1. Pump the Outline against a controller whose detail band holds a text
//    element 't1' (text 'Subtotal', no name).
// 2. find.text('Subtotal') shows in the element row.
// 3. Double-tap that row (gesture on its row key); enter 'Totals'; submit.
// 4. Expect the element 't1' now has name 'Totals' on controller.definition,
//    and find.text('Totals') appears.
// 5. Double-tap the detail band row; enter 'Line items'; submit; expect the
//    band's name is 'Line items'.
```

(Copy the pump helper and the row/key conventions from `outline_tree_test.dart`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/outline_rename_test.dart`
Expected: FAIL — rows are static, no inline edit.

- [ ] **Step 3: Add editing state + reset on selection change**

In the Outline panel state, add:

```dart
  String? _editingId; // the band or element id currently being renamed
```

When the panel rebuilds for a different selection, clear `_editingId` if the edited node is no longer present/selected (follow the `_collapsed` handling idiom).

- [ ] **Step 4: Render the element leaf label through EditableLabel**

In the element loop (around line 318), pass the resolved label and an editing flag into `_leafRow`. Extend `_leafRow` to accept:

```dart
    required String? rawName,
    required String fallback,
    required bool editing,
    required VoidCallback onEditingStart,   // double-tap
    required VoidCallback onEditingEnd,
    required ValueChanged<String?> onCommit,
```

and render its label as:

```dart
        editing
            ? EditableLabel(
                display: label,
                value: rawName,
                placeholder: fallback,
                editing: true,
                onEditingEnd: onEditingEnd,
                onCommit: onCommit,
              )
            : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, …),
```

Wrap the row's existing `GestureDetector` with `onDoubleTap: onEditingStart` (keep `onTap: onSelect`). Call site:

```dart
      rows.add(_leafRow(
        rowKey: ValueKey<String>('jet_print.designer.outline.element.${element.id}'),
        depth: depth + 1,
        icon: _elementGlyph(element),
        label: elementDisplayLabel(element, l10n),
        rawName: element.name,
        fallback: elementTypeLabel(element, l10n),
        editing: _editingId == element.id,
        onEditingStart: () => setState(() => _editingId = element.id),
        onEditingEnd: () => setState(() => _editingId = null),
        onCommit: (String? name) {
          controller.renameElement(element.id, name);
          setState(() => _editingId = null);
        },
        selected: selection.contains(element.id),
        onSelect: () => controller.select(element.id),
        theme: theme,
      ));
```

Add imports for `object_display_label.dart` and `element_type_label.dart`.

- [ ] **Step 5: Render the band branch label through EditableLabel**

`_branchRow` is shared by report/scope/group/band rows, so do **not** make every branch editable. Instead, in the band `_branchRow` call (line ~297), pass `label: bandDisplayLabel(band, l10n)` and add optional editing params to `_branchRow` (defaulting to non-editable so the report/scope/group callers are unchanged):

```dart
    String? rawName,
    String? fallback,
    bool editing = false,
    VoidCallback? onEditingStart,
    VoidCallback? onEditingEnd,
    ValueChanged<String?>? onCommit,
```

In `_branchRow`, when `editing` is true render `EditableLabel` in place of the label `Text`; wrap its `GestureDetector` with `onDoubleTap: onEditingStart` (only attaches behavior when non-null). Band call site adds:

```dart
      label: bandDisplayLabel(band, l10n),
      rawName: band.name,
      fallback: bandTypeLabel(band.type, l10n),
      editing: _editingId == band.id,
      onEditingStart: () => setState(() => _editingId = band.id),
      onEditingEnd: () => setState(() => _editingId = null),
      onCommit: (String? name) {
        controller.renameBand(band.id, name);
        setState(() => _editingId = null);
      },
```

- [ ] **Step 6: Run the test + the existing Outline tests**

Run: `cd packages/jet_print && flutter test test/designer/outline_tree_test.dart test/designer/outline_add_list_group_test.dart test/designer/outline_list_label_test.dart test/designer/outline_rename_test.dart`
Expected: PASS (no regressions).

- [ ] **Step 7: Full suite + analyzer**

Run:
```bash
cd packages/jet_print && flutter analyze && flutter test
```
Expected: analyzer clean; full lib suite green (goldens unchanged, since `name` is never painted and is omitted from JSON when null).

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart packages/jet_print/test/designer/outline_rename_test.dart
git commit -m "feat(designer): rename objects from the Outline tree (double-click)"
```

---

## Self-Review

**Spec coverage:**
- Optional `name` on element + band → Task 1. ✅
- `id` stays machine key, never changed → no task touches `id`; rename writes `name` only. ✅
- Fallback chain (name → text → type label; bands → type label) → Task 3 (`object_display_label.dart`), reusing existing `elementTypeLabel`/`bandTypeLabel`. ✅ (Simplification vs spec: non-text fallback uses the existing generic `elementTypeLabel` — "Shape"/"Image"/"Barcode" — not per-`ShapeKind` names, avoiding new locale strings. Captured in Task 3 + Global Constraints.)
- Two entry points, same command → Properties (Task 7) + Outline (Task 8), both call `renameElement`/`renameBand` (Task 5). ✅
- Editors prefill current name, placeholder shows fallback → `EditableLabel` (Task 6) `value`/`placeholder`. ✅
- Empty valid → clears to null (fallback); no uniqueness/error → Task 5 `_normalizeName`, no validation added. ✅
- Codecs omit `name` when null, backward-compatible, goldens byte-identical → Task 2 + Global Constraints + Task 8 Step 7. ✅
- Undo/redo, same-value no-op, selection unaffected → Task 4/5 (value-equality in `_commit`; `id` unchanged so selection holds). ✅
- Testing (domain, codec incl legacy, label helper, command, controller, both widgets) → Tasks 1–8. ✅

**Placeholder scan:** Test scaffolds in Tasks 4, 5, 7, 8 reference "copy the fixture/harness helpers from `<neighbor test>`" rather than inlining a full fixture. This is deliberate (the neighboring tests are the canonical fixtures and inlining would risk drift), and each names the exact file to copy from and the exact assertions — not a "TODO". All production-code steps show complete code.

**Type consistency:** `withName(String?)` is defined on the base (Task 1) and used by `RenameElementCommand` (Task 4). `renameElement(String, String?)`/`renameBand(String, String?)` defined in Task 5, called in Tasks 7–8. `elementDisplayLabel`/`bandDisplayLabel` defined Task 3, used Tasks 7–8. `EditableLabel` constructor params (`display`/`value`/`placeholder`/`editing`/`onEditingEnd`/`onCommit`) are consistent across Tasks 6–8. `Band.copyWith(name:)` (set) vs explicit `Band(...)` reconstruction for clearing (Task 4) — consistent and documented.
