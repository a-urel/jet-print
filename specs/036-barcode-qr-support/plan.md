# Industry-Grade Barcode / QR Code Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is Red→Green TDD (Constitution III).

**Goal:** Replace the placeholder barcode renderer with real, scannable symbology rendering (QR, Data Matrix, PDF417, Aztec, Code 128/39, EAN-13/8, UPC-A, ITF-14), with field-or-literal data binding, `Auto` symbology + override, HRI text, quiet zones, QR ECC, crisp/square modules, and auto-fix-else-placeholder error handling.

**Architecture:** A first-party `BarcodeEncoder` seam wraps the pure-Dart `barcode` package (already transitive via `pdf`); only one adapter file imports it. The encoder yields first-party geometry (`BarcodeSymbol` = positioned bar/module rects + HRI text runs) that the renderer translates into the existing `RectPrimitive`/`TextRunPrimitive` display list — so canvas, preview, and PDF render identically. Symbology inference and check-digit auto-fix are pure helpers. Data binding (`dataField`) is flattened at fill time exactly like text `expression` → resolved `text`. The codec change is additive (no migration).

**Tech Stack:** Dart / Flutter, `flutter_test`, `shadcn_ui` (designer widgets), `barcode` 2.2.9 (encoding), gen-l10n (en/de/tr). Spec: `specs/036-barcode-qr-support/spec.md`.

## Global Constraints

- **Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print`** (the `flutter` tool leaves cwd inside the package; always `cd` back to the repo root before `git`).
- **Branch `036-barcode-qr-support` is already checked out.** Do not create another.
- **Test-First is NON-NEGOTIABLE** (Constitution III): every code change is Red→Green.
- **Domain stays Flutter-free** (Constitution II): nothing under `lib/src/domain/` may import Flutter, rendering, designer, or the `barcode` package.
- **Only one file may import `package:barcode`**: `lib/src/rendering/elements/barcode/package_barcode_encoder.dart`. The third-party `BarcodeException` type must never escape the seam (catch → first-party `BarcodeInvalid`). Enforced by an architecture test in Task 11.
- **Serialization is additive** (Constitution V): write new fields only when non-default; existing documents round-trip byte-identically; **no new migration**; **pre-existing goldens MUST NOT change** — only new barcode goldens are added. If an existing golden changes, STOP and inspect.
- **WYSIWYG** (Constitution IV): bars/modules are existing primitives consumed identically by canvas and export.
- After every task: `flutter analyze` clean and `dart format --output=none --set-exit-if-changed lib test` a no-op before committing.
- Commit message footer on every commit:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File Map

**Domain (Flutter-free):**
- `lib/src/domain/elements/barcode_element.dart` — **modify**: expand `BarcodeSymbology`; add `QrErrorCorrectionLevel`; add `dataField`, `showText`, `quietZone`, `eccLevel`.
- `lib/src/domain/serialization/barcode_element_codec.dart` — **modify**: additive read/write.

**Encoder seam (pure Dart; `package_barcode_encoder.dart` is the only third-party import):**
- `lib/src/rendering/elements/barcode/barcode_symbol.dart` — **new**: `BarcodeModule`, `BarcodeHriText`, `BarcodeHriAlign`, `BarcodeSymbol`.
- `lib/src/rendering/elements/barcode/barcode_encoder.dart` — **new**: `BarcodeEncoder` interface, `BarcodeEncodeResult` (`BarcodeEncoded` / `BarcodeInvalid`).
- `lib/src/rendering/elements/barcode/symbology_inference.dart` — **new**: `inferSymbology`, `resolveConcreteSymbology`, `isTwoDSymbology`.
- `lib/src/rendering/elements/barcode/barcode_autofix.dart` — **new**: `mod10CheckDigit`, `barcodeAutoFix`.
- `lib/src/rendering/elements/barcode/package_barcode_encoder.dart` — **new**: `PackageBarcodeEncoder` (imports `package:barcode`).

**Rendering / fill:**
- `lib/src/rendering/elements/renderers/barcode_element_renderer.dart` — **modify**: real emission.
- `lib/src/rendering/fill/element_resolver.dart` — **modify**: barcode binding + diagnostics.

**Designer:**
- `lib/src/designer/controller/commands/set_barcode_symbology_command.dart` — **new**.
- `lib/src/designer/controller/commands/set_barcode_data_command.dart` — **new** (literal + field, two methods or one with nullable).
- `lib/src/designer/controller/commands/set_barcode_flag_command.dart` — **new** (showText / quietZone / eccLevel).
- `lib/src/designer/controller/jet_report_designer_controller.dart` — **modify**: dispatch methods.
- `lib/src/designer/controller/commands/create_element_command.dart` — **modify**: default `symbology: auto`.
- `lib/src/designer/layout/panels/properties_panel.dart` — **modify**: barcode section.
- `lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb` — **modify**: new keys.

**Public API:**
- `lib/jet_print.dart` — **modify**: export `QrErrorCorrectionLevel` (and confirm `BarcodeSymbology`).

**Tests:** one alongside each (paths given per task).

---

## Task 1: Domain model — symbology enum, ECC enum, element fields

**Files:**
- Modify: `lib/src/domain/elements/barcode_element.dart`
- Test (modify): `test/domain/elements/barcode_element_test.dart`

**Interfaces:**
- Produces:
  - `enum BarcodeSymbology { auto, qrCode, code128, ean13, ean8, upcA, code39, itf14, dataMatrix, pdf417, aztec }`
  - `enum QrErrorCorrectionLevel { l, m, q, h }`
  - `class BarcodeElement` with `final String? dataField; final bool showText; final bool quietZone; final QrErrorCorrectionLevel eccLevel;` plus existing `symbology`, `data`, `color`. `copyWith({JetRect? bounds, BarcodeSymbology? symbology, String? data, String? Function()? dataField, JetColor? color, bool? showText, bool? quietZone, QrErrorCorrectionLevel? eccLevel})`.

> **Note on `dataField` in `copyWith`:** because `dataField` is nullable and "set to null" is a real edit (switch from field to literal), use the **wrapped-callback** idiom (`String? Function()? dataField`) so callers can distinguish "leave unchanged" (omit) from "clear" (`dataField: () => null`). See Step 3.

- [ ] **Step 1: Read the existing test file and element** to match style: `test/domain/elements/barcode_element_test.dart` and `lib/src/domain/elements/barcode_element.dart`.

- [ ] **Step 2: Write failing tests.** Append to `test/domain/elements/barcode_element_test.dart`:

```dart
  test('defaults: auto symbology fields are off-by-default sensible', () {
    const el = BarcodeElement(
      id: 'b1',
      bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
      symbology: BarcodeSymbology.auto,
      data: 'X',
    );
    expect(el.dataField, isNull);
    expect(el.showText, isTrue);
    expect(el.quietZone, isTrue);
    expect(el.eccLevel, QrErrorCorrectionLevel.m);
  });

  test('copyWith replaces named fields and preserves the rest', () {
    const el = BarcodeElement(
      id: 'b1',
      bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
      symbology: BarcodeSymbology.auto,
      data: 'X',
    );
    final next = el.copyWith(
      symbology: BarcodeSymbology.ean13,
      dataField: () => 'sku',
      showText: false,
      quietZone: false,
      eccLevel: QrErrorCorrectionLevel.h,
    );
    expect(next.symbology, BarcodeSymbology.ean13);
    expect(next.dataField, 'sku');
    expect(next.showText, isFalse);
    expect(next.quietZone, isFalse);
    expect(next.eccLevel, QrErrorCorrectionLevel.h);
    expect(next.id, 'b1');
    expect(next.data, 'X');
  });

  test('copyWith can clear dataField back to null', () {
    const el = BarcodeElement(
      id: 'b1',
      bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
      symbology: BarcodeSymbology.auto,
      data: 'X',
      dataField: 'sku',
    );
    expect(el.copyWith(dataField: () => null).dataField, isNull);
    expect(el.copyWith().dataField, 'sku'); // omitted → unchanged
  });

  test('equality accounts for the new fields', () {
    const a = BarcodeElement(
      id: 'b1', bounds: JetRect(x: 0, y: 0, width: 1, height: 1),
      symbology: BarcodeSymbology.auto, data: 'X');
    const b = BarcodeElement(
      id: 'b1', bounds: JetRect(x: 0, y: 0, width: 1, height: 1),
      symbology: BarcodeSymbology.auto, data: 'X', showText: false);
    expect(a == b, isFalse);
  });
```

- [ ] **Step 3: Run → FAIL.** Run: `cd packages/jet_print && flutter test test/domain/elements/barcode_element_test.dart` — expect compile/assert failures (new fields/enum values missing).

- [ ] **Step 4: Implement.** Rewrite `lib/src/domain/elements/barcode_element.dart`:

```dart
/// A 1D/2D barcode element.
library;

import '../geometry.dart';
import '../report_element.dart';
import '../styles/color.dart';

/// The barcode symbology (encoding) to render. [auto] infers the concrete
/// symbology from the encoded value at fill time (see `symbology_inference`).
enum BarcodeSymbology {
  /// Infer the concrete symbology from the value (default for new elements).
  auto,

  /// 2D QR code.
  qrCode,

  /// 1D Code 128 (alphanumeric).
  code128,

  /// 1D EAN-13 / UPC retail code.
  ean13,

  /// 1D EAN-8 retail code.
  ean8,

  /// 1D UPC-A retail code.
  upcA,

  /// 1D Code 39.
  code39,

  /// 1D ITF-14 (interleaved 2-of-5, shipping containers).
  itf14,

  /// 2D Data Matrix.
  dataMatrix,

  /// 2D PDF417 (stacked linear).
  pdf417,

  /// 2D Aztec.
  aztec,
}

/// QR error-correction level (higher survives more damage, holds less data).
enum QrErrorCorrectionLevel { l, m, q, h }

/// Encodes [data] (or, when [dataField] is set, the value of that data-source
/// field resolved at fill time) as a [symbology] barcode drawn in [color]
/// within [bounds].
class BarcodeElement extends ReportElement {
  /// Creates a barcode element.
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
  });

  /// The barcode encoding (or [BarcodeSymbology.auto]).
  final BarcodeSymbology symbology;

  /// The literal data to encode when [dataField] is null.
  final String data;

  /// When non-null, the encoded value comes from this data-source field at
  /// fill time (and wins over [data]); otherwise [data] is used.
  final String? dataField;

  /// Foreground (bar/module) color.
  final JetColor color;

  /// Whether to draw human-readable text under 1D symbols (ignored by 2D).
  final bool showText;

  /// Whether to reserve the mandatory quiet-zone margin inside [bounds].
  final bool quietZone;

  /// QR error-correction level (ignored by non-QR symbologies).
  final QrErrorCorrectionLevel eccLevel;

  @override
  String get typeKey => 'barcode';

  /// Returns a copy with the named fields replaced and the rest preserved.
  ///
  /// [dataField] uses a wrapped callback so callers can clear it to null
  /// (`dataField: () => null`) distinctly from leaving it unchanged (omit).
  BarcodeElement copyWith({
    JetRect? bounds,
    BarcodeSymbology? symbology,
    String? data,
    String? Function()? dataField,
    JetColor? color,
    bool? showText,
    bool? quietZone,
    QrErrorCorrectionLevel? eccLevel,
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
      );

  @override
  BarcodeElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  bool operator ==(Object other) =>
      other is BarcodeElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.symbology == symbology &&
      other.data == data &&
      other.dataField == dataField &&
      other.color == color &&
      other.showText == showText &&
      other.quietZone == quietZone &&
      other.eccLevel == eccLevel;

  @override
  int get hashCode => Object.hash(id, bounds, symbology, data, dataField, color,
      showText, quietZone, eccLevel);

  @override
  String toString() => 'BarcodeElement($id, ${symbology.name})';
}
```

- [ ] **Step 5: Run → PASS.** Run: `cd packages/jet_print && flutter test test/domain/elements/barcode_element_test.dart`.

- [ ] **Step 6: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze lib/src/domain/elements/barcode_element.dart && dart format lib/src/domain/elements/barcode_element.dart test/domain/elements/barcode_element_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/elements/barcode_element.dart packages/jet_print/test/domain/elements/barcode_element_test.dart
git commit -m "feat(036): expand BarcodeElement (symbologies, dataField, HRI/quietZone/ecc)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Serialization — additive codec

**Files:**
- Modify: `lib/src/domain/serialization/barcode_element_codec.dart`
- Test (modify): `test/domain/serialization/element_codec_test.dart` (barcode section) — read it first to match harness.

**Interfaces:**
- Consumes: `BarcodeElement` (Task 1), `BarcodeSymbology`, `QrErrorCorrectionLevel`.
- Produces: JSON keys `symbology`, `data`, optional `dataField`, optional `color`, optional `showText`, optional `quietZone`, optional `ecc` — optional keys written **only when non-default**.

- [ ] **Step 1: Read** `test/domain/serialization/element_codec_test.dart` and `lib/src/domain/serialization/barcode_element_codec.dart`.

- [ ] **Step 2: Write failing tests.** Add to the barcode group in `element_codec_test.dart`:

```dart
  test('round-trips new fields', () {
    const el = BarcodeElement(
      id: 'b1',
      bounds: JetRect(x: 1, y: 2, width: 80, height: 40),
      symbology: BarcodeSymbology.ean13,
      data: '590123412345',
      dataField: 'sku',
      showText: false,
      quietZone: false,
      eccLevel: QrErrorCorrectionLevel.h,
    );
    const codec = BarcodeElementCodec();
    expect(codec.fromJson(codec.toJson(el)), el);
  });

  test('omits default fields (stable JSON)', () {
    const el = BarcodeElement(
      id: 'b1',
      bounds: JetRect(x: 0, y: 0, width: 1, height: 1),
      symbology: BarcodeSymbology.auto,
      data: 'X',
    );
    final json = const BarcodeElementCodec().toJson(el);
    expect(json.containsKey('dataField'), isFalse);
    expect(json.containsKey('showText'), isFalse);
    expect(json.containsKey('quietZone'), isFalse);
    expect(json.containsKey('ecc'), isFalse);
    expect(json.containsKey('color'), isFalse);
  });

  test('back-compat: legacy JSON (no new keys) loads with defaults', () {
    final el = const BarcodeElementCodec().fromJson(<String, Object?>{
      'id': 'b1',
      'bounds': <String, Object?>{'x': 0, 'y': 0, 'w': 10, 'h': 10},
      'symbology': 'qrCode',
      'data': 'hello',
    });
    expect(el.dataField, isNull);
    expect(el.showText, isTrue);
    expect(el.quietZone, isTrue);
    expect(el.eccLevel, QrErrorCorrectionLevel.m);
  });
```

- [ ] **Step 3: Run → FAIL.** Run: `cd packages/jet_print && flutter test test/domain/serialization/element_codec_test.dart`.

- [ ] **Step 4: Implement.** Rewrite `lib/src/domain/serialization/barcode_element_codec.dart`:

```dart
/// JSON codec for [BarcodeElement].
library;

import '../elements/barcode_element.dart';
import '../geometry.dart';
import '../styles/color.dart';
import 'element_codec.dart';

/// Serializes [BarcodeElement] to/from its field map. New fields (036) are
/// additive: written only when non-default, defaulted when absent, so legacy
/// documents round-trip byte-identically.
class BarcodeElementCodec extends ElementCodec<BarcodeElement> {
  /// Const constructor (the codec is stateless).
  const BarcodeElementCodec();

  @override
  BarcodeElement fromJson(Map<String, Object?> json) => BarcodeElement(
        id: json['id']! as String,
        bounds:
            JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        symbology: BarcodeSymbology.values.byName(json['symbology']! as String),
        data: json['data']! as String,
        dataField: json['dataField'] as String?,
        color: json['color'] is String
            ? JetColor.fromJson(json['color']! as String)
            : JetColor.black,
        showText: json['showText'] as bool? ?? true,
        quietZone: json['quietZone'] as bool? ?? true,
        eccLevel: json['ecc'] is String
            ? QrErrorCorrectionLevel.values.byName(json['ecc']! as String)
            : QrErrorCorrectionLevel.m,
      );

  @override
  Map<String, Object?> toJson(BarcodeElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'symbology': element.symbology.name,
        'data': element.data,
        if (element.dataField != null) 'dataField': element.dataField,
        if (element.color != JetColor.black) 'color': element.color.toJson(),
        if (!element.showText) 'showText': false,
        if (!element.quietZone) 'quietZone': false,
        if (element.eccLevel != QrErrorCorrectionLevel.m)
          'ecc': element.eccLevel.name,
      };
}
```

- [ ] **Step 5: Run → PASS** (the file's test + the broader round-trip): `cd packages/jet_print && flutter test test/domain/serialization/`.

- [ ] **Step 6: Analyzer + format + commit.**

```bash
cd packages/jet_print && flutter analyze lib/src/domain/serialization/barcode_element_codec.dart && dart format lib/src/domain/serialization/barcode_element_codec.dart test/domain/serialization/element_codec_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/serialization/barcode_element_codec.dart packages/jet_print/test/domain/serialization/element_codec_test.dart
git commit -m "feat(036): additive barcode codec (dataField/showText/quietZone/ecc)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Symbology inference + classification (pure)

**Files:**
- Create: `lib/src/rendering/elements/barcode/symbology_inference.dart`
- Test: `test/rendering/elements/barcode/symbology_inference_test.dart`

**Interfaces:**
- Consumes: `BarcodeSymbology` (Task 1).
- Produces:
  - `BarcodeSymbology inferSymbology(String value)` — never returns `auto`.
  - `BarcodeSymbology resolveConcreteSymbology(BarcodeSymbology symbology, String value)` — `symbology == auto ? inferSymbology(value) : symbology`; for an empty value returns `qrCode` (the design-time preview default, FR-004).
  - `bool isTwoDSymbology(BarcodeSymbology s)` — true for `qrCode`, `dataMatrix`, `pdf417`, `aztec`.

- [ ] **Step 1: Write failing tests.** Create `test/rendering/elements/barcode/symbology_inference_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/rendering/elements/barcode/symbology_inference.dart';

void main() {
  group('inferSymbology', () {
    test('URL → QR', () {
      expect(inferSymbology('https://x.example/a'), BarcodeSymbology.qrCode);
    });
    test('multiline / non-ascii / long → QR', () {
      expect(inferSymbology('a\nb'), BarcodeSymbology.qrCode);
      expect(inferSymbology('café'), BarcodeSymbology.qrCode);
      expect(inferSymbology('x' * 41), BarcodeSymbology.qrCode);
    });
    test('retail digit lengths', () {
      expect(inferSymbology('5901234123457'), BarcodeSymbology.ean13); // 13
      expect(inferSymbology('012345678905'), BarcodeSymbology.upcA);   // 12
      expect(inferSymbology('96385074'), BarcodeSymbology.ean8);       // 8
      expect(inferSymbology('00012345678905'), BarcodeSymbology.itf14);// 14
    });
    test('other all-digits → Code128', () {
      expect(inferSymbology('12345'), BarcodeSymbology.code128);
    });
    test('alphanumeric → Code128', () {
      expect(inferSymbology('ABC-123'), BarcodeSymbology.code128);
    });
    test('never returns auto', () {
      for (final s in <String>['', 'x', '12', 'http://a']) {
        expect(inferSymbology(s), isNot(BarcodeSymbology.auto));
      }
    });
  });

  group('resolveConcreteSymbology', () {
    test('explicit wins', () {
      expect(resolveConcreteSymbology(BarcodeSymbology.code39, '5901234123457'),
          BarcodeSymbology.code39);
    });
    test('auto infers', () {
      expect(resolveConcreteSymbology(BarcodeSymbology.auto, '5901234123457'),
          BarcodeSymbology.ean13);
    });
    test('auto + empty → QR preview default', () {
      expect(resolveConcreteSymbology(BarcodeSymbology.auto, ''),
          BarcodeSymbology.qrCode);
    });
  });

  group('isTwoDSymbology', () {
    test('classifies', () {
      expect(isTwoDSymbology(BarcodeSymbology.qrCode), isTrue);
      expect(isTwoDSymbology(BarcodeSymbology.dataMatrix), isTrue);
      expect(isTwoDSymbology(BarcodeSymbology.pdf417), isTrue);
      expect(isTwoDSymbology(BarcodeSymbology.aztec), isTrue);
      expect(isTwoDSymbology(BarcodeSymbology.code128), isFalse);
      expect(isTwoDSymbology(BarcodeSymbology.ean13), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run → FAIL.** Run: `cd packages/jet_print && flutter test test/rendering/elements/barcode/symbology_inference_test.dart` — expect "uri ... not found" / missing file.

- [ ] **Step 3: Implement.** Create `lib/src/rendering/elements/barcode/symbology_inference.dart`:

```dart
/// Pure symbology inference for [BarcodeSymbology.auto] and 1D/2D classification
/// (spec 036, FR-004). No Flutter, no third-party dependency.
library;

import '../../../domain/elements/barcode_element.dart';

/// The longest value still inferred as a 1D code; longer → QR.
const int _maxLinearLength = 40;

/// Infers a concrete symbology from [value] by the documented priority
/// (FR-004). Never returns [BarcodeSymbology.auto].
BarcodeSymbology inferSymbology(String value) {
  final String v = value.trim();
  // URL / multiline / non-ASCII / over-length → 2D QR.
  final bool nonAscii = v.runes.any((int r) => r < 0x20 || r > 0x7e);
  final bool looksUrl =
      v.startsWith('http://') || v.startsWith('https://') || v.contains('://');
  if (looksUrl || nonAscii || v.length > _maxLinearLength) {
    return BarcodeSymbology.qrCode;
  }
  final bool allDigits = v.isNotEmpty && RegExp(r'^\d+$').hasMatch(v);
  if (allDigits) {
    switch (v.length) {
      case 13:
        return BarcodeSymbology.ean13;
      case 12:
        return BarcodeSymbology.upcA;
      case 8:
        return BarcodeSymbology.ean8;
      case 14:
        return BarcodeSymbology.itf14;
      default:
        return BarcodeSymbology.code128;
    }
  }
  // Any remaining (alphanumeric or empty) → Code 128.
  return BarcodeSymbology.code128;
}

/// Resolves [symbology] to a concrete value: [inferSymbology] for `auto`, the
/// value itself otherwise. An empty value with `auto` previews as QR (FR-004).
BarcodeSymbology resolveConcreteSymbology(
    BarcodeSymbology symbology, String value) {
  if (symbology != BarcodeSymbology.auto) return symbology;
  if (value.trim().isEmpty) return BarcodeSymbology.qrCode;
  return inferSymbology(value);
}

/// Whether [s] is a 2D matrix symbology (square modules, no HRI text).
bool isTwoDSymbology(BarcodeSymbology s) =>
    s == BarcodeSymbology.qrCode ||
    s == BarcodeSymbology.dataMatrix ||
    s == BarcodeSymbology.pdf417 ||
    s == BarcodeSymbology.aztec;
```

- [ ] **Step 4: Run → PASS.** Run the test from Step 2.

- [ ] **Step 5: Format + commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/elements/barcode/symbology_inference.dart test/rendering/elements/barcode/symbology_inference_test.dart && flutter analyze lib/src/rendering/elements/barcode/symbology_inference.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/elements/barcode/symbology_inference.dart packages/jet_print/test/rendering/elements/barcode/symbology_inference_test.dart
git commit -m "feat(036): pure symbology inference + 1D/2D classification

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Check-digit auto-fix (pure)

**Files:**
- Create: `lib/src/rendering/elements/barcode/barcode_autofix.dart`
- Test: `test/rendering/elements/barcode/barcode_autofix_test.dart`

**Interfaces:**
- Consumes: `BarcodeSymbology` (Task 1).
- Produces:
  - `int mod10CheckDigit(String digits)` — UPC/EAN mod-10 check digit (weights 3,1 from the right).
  - `String barcodeAutoFix(BarcodeSymbology concrete, String value)` — returns a possibly-repaired value (append computed check digit for EAN-13 from 12 digits, EAN-8 from 7, UPC-A from 11, ITF-14 from 13; left-pad ITF-14 odd length with `0`); any other symbology or shape returns [value] unchanged. Validity is decided later by the encoder.

- [ ] **Step 1: Write failing tests.** Create `test/rendering/elements/barcode/barcode_autofix_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/rendering/elements/barcode/barcode_autofix.dart';

void main() {
  test('mod10 check digit (known EAN-13 vectors)', () {
    expect(mod10CheckDigit('590123412345'), 7); // 5901234123457
    expect(mod10CheckDigit('01234567890'), 5);   // UPC-A 012345678905
  });

  group('barcodeAutoFix', () {
    test('EAN-13: 12 digits → append check digit', () {
      expect(barcodeAutoFix(BarcodeSymbology.ean13, '590123412345'),
          '5901234123457');
    });
    test('EAN-13: 13 digits left unchanged', () {
      expect(barcodeAutoFix(BarcodeSymbology.ean13, '5901234123457'),
          '5901234123457');
    });
    test('EAN-8: 7 digits → append', () {
      expect(barcodeAutoFix(BarcodeSymbology.ean8, '9638507').length, 8);
    });
    test('UPC-A: 11 digits → append', () {
      expect(barcodeAutoFix(BarcodeSymbology.upcA, '01234567890'),
          '012345678905');
    });
    test('ITF-14: 13 digits → append check digit (14 total)', () {
      expect(barcodeAutoFix(BarcodeSymbology.itf14, '0001234567890').length, 14);
    });
    test('non-numeric EAN-13 returned unchanged (encoder will reject)', () {
      expect(barcodeAutoFix(BarcodeSymbology.ean13, 'ABC'), 'ABC');
    });
    test('Code128 / QR unchanged', () {
      expect(barcodeAutoFix(BarcodeSymbology.code128, 'ABC-1'), 'ABC-1');
      expect(barcodeAutoFix(BarcodeSymbology.qrCode, 'x'), 'x');
    });
  });
}
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement.** Create `lib/src/rendering/elements/barcode/barcode_autofix.dart`:

```dart
/// Pure check-digit / length auto-fix for retail symbologies (spec 036, FR-005).
/// Repairs what the spec allows; the encoder still validates the result.
library;

import '../../../domain/elements/barcode_element.dart';

bool _isDigits(String s) => s.isNotEmpty && RegExp(r'^\d+$').hasMatch(s);

/// The UPC/EAN mod-10 check digit for the [digits] *without* its check digit.
/// Weights alternate 3,1 starting from the rightmost given digit.
int mod10CheckDigit(String digits) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    final int d = digits.codeUnitAt(digits.length - 1 - i) - 0x30;
    sum += (i.isEven) ? d * 3 : d;
  }
  return (10 - (sum % 10)) % 10;
}

String _appendCheck(String digits) =>
    '$digits${mod10CheckDigit(digits)}';

/// Repairs [value] for [concrete] where the symbology spec allows; otherwise
/// returns [value] unchanged.
String barcodeAutoFix(BarcodeSymbology concrete, String value) {
  switch (concrete) {
    case BarcodeSymbology.ean13:
      return (_isDigits(value) && value.length == 12) ? _appendCheck(value) : value;
    case BarcodeSymbology.ean8:
      return (_isDigits(value) && value.length == 7) ? _appendCheck(value) : value;
    case BarcodeSymbology.upcA:
      return (_isDigits(value) && value.length == 11) ? _appendCheck(value) : value;
    case BarcodeSymbology.itf14:
      var v = value;
      if (_isDigits(v) && v.length == 13) v = _appendCheck(v);
      // ITF requires an even number of digits; left-pad if odd.
      if (_isDigits(v) && v.length.isOdd) v = '0$v';
      return v;
    case BarcodeSymbology.auto:
    case BarcodeSymbology.qrCode:
    case BarcodeSymbology.code128:
    case BarcodeSymbology.code39:
    case BarcodeSymbology.dataMatrix:
    case BarcodeSymbology.pdf417:
    case BarcodeSymbology.aztec:
      return value;
  }
}
```

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Format + commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/elements/barcode/barcode_autofix.dart test/rendering/elements/barcode/barcode_autofix_test.dart && flutter analyze lib/src/rendering/elements/barcode/barcode_autofix.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/elements/barcode/barcode_autofix.dart packages/jet_print/test/rendering/elements/barcode/barcode_autofix_test.dart
git commit -m "feat(036): retail check-digit / length auto-fix

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Encoder seam — geometry types + interface

**Files:**
- Create: `lib/src/rendering/elements/barcode/barcode_symbol.dart`
- Create: `lib/src/rendering/elements/barcode/barcode_encoder.dart`
- Test: `test/rendering/elements/barcode/barcode_symbol_test.dart`

**Interfaces:**
- Produces:
  - `enum BarcodeHriAlign { left, center, right }`
  - `class BarcodeModule { final double left, top, width, height; const BarcodeModule(this.left, this.top, this.width, this.height); }` (value equality).
  - `class BarcodeHriText { final double left, top, width, height; final String text; final BarcodeHriAlign align; const BarcodeHriText({...}); }` (value equality).
  - `class BarcodeSymbol { final List<BarcodeModule> modules; final List<BarcodeHriText> texts; final double spaceWidth, spaceHeight; final bool isTwoD; const BarcodeSymbol({...}); }`
  - `sealed class BarcodeEncodeResult {}` with `final class BarcodeEncoded extends BarcodeEncodeResult { final BarcodeSymbol symbol; final BarcodeSymbology resolvedSymbology; }` and `final class BarcodeInvalid extends BarcodeEncodeResult { final String reason; }`.
  - `abstract interface class BarcodeEncoder { BarcodeEncodeResult encode(BarcodeSymbology symbology, String value, {required double width, required double height, bool showText = true, QrErrorCorrectionLevel eccLevel = QrErrorCorrectionLevel.m}); }`

- [ ] **Step 1: Write failing test.** Create `test/rendering/elements/barcode/barcode_symbol_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/rendering/elements/barcode/barcode_symbol.dart';

void main() {
  test('BarcodeModule value equality', () {
    expect(const BarcodeModule(0, 0, 1, 2), const BarcodeModule(0, 0, 1, 2));
    expect(const BarcodeModule(0, 0, 1, 2) == const BarcodeModule(0, 0, 1, 3),
        isFalse);
  });

  test('BarcodeSymbol holds geometry', () {
    const sym = BarcodeSymbol(
      modules: <BarcodeModule>[BarcodeModule(0, 0, 1, 10)],
      texts: <BarcodeHriText>[],
      spaceWidth: 20,
      spaceHeight: 10,
      isTwoD: false,
    );
    expect(sym.modules, hasLength(1));
    expect(sym.isTwoD, isFalse);
  });
}
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement `barcode_symbol.dart`.**

```dart
/// First-party, package-agnostic barcode geometry (spec 036). The encoder seam
/// returns these; the renderer translates them into frame primitives. Pure Dart.
library;

/// Horizontal alignment of an HRI text run.
enum BarcodeHriAlign { left, center, right }

/// A single filled bar (1D) or module (2D) rectangle, in the symbol's own
/// coordinate space `[0..spaceWidth] x [0..spaceHeight]`.
class BarcodeModule {
  /// Creates a module rect.
  const BarcodeModule(this.left, this.top, this.width, this.height);

  /// Left/top/width/height, in symbol-space units.
  final double left, top, width, height;

  @override
  bool operator ==(Object other) =>
      other is BarcodeModule &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'BarcodeModule($left, $top, $width, $height)';
}

/// A human-readable text run beneath a 1D symbol, in symbol-space units.
class BarcodeHriText {
  /// Creates an HRI text run.
  const BarcodeHriText({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.text,
    required this.align,
  });

  /// Bounds in symbol-space units.
  final double left, top, width, height;

  /// The displayed text.
  final String text;

  /// Horizontal alignment within [left]..[left]+[width].
  final BarcodeHriAlign align;

  @override
  bool operator ==(Object other) =>
      other is BarcodeHriText &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height &&
      other.text == text &&
      other.align == align;

  @override
  int get hashCode => Object.hash(left, top, width, height, text, align);

  @override
  String toString() => 'BarcodeHriText("$text" @ $left,$top)';
}

/// The positioned geometry of an encoded symbol, in a coordinate space of
/// [spaceWidth] x [spaceHeight]. [isTwoD] symbols have square modules.
class BarcodeSymbol {
  /// Creates a symbol geometry.
  const BarcodeSymbol({
    required this.modules,
    required this.texts,
    required this.spaceWidth,
    required this.spaceHeight,
    required this.isTwoD,
  });

  /// Filled bar/module rectangles.
  final List<BarcodeModule> modules;

  /// HRI text runs (empty for 2D or when text is disabled).
  final List<BarcodeHriText> texts;

  /// The coordinate-space extents the geometry was laid out in.
  final double spaceWidth, spaceHeight;

  /// Whether this is a 2D matrix symbology.
  final bool isTwoD;
}
```

- [ ] **Step 4: Implement `barcode_encoder.dart`.**

```dart
/// The first-party barcode encoder seam (spec 036, FR-011). Implementations map
/// a symbology + value to [BarcodeSymbol] geometry or a [BarcodeInvalid] reason;
/// only the package adapter imports the third-party encoder.
library;

import '../../../domain/elements/barcode_element.dart';
import 'barcode_symbol.dart';

/// The outcome of an encode attempt.
sealed class BarcodeEncodeResult {
  /// Const base constructor.
  const BarcodeEncodeResult();
}

/// A successful encode: the [symbol] geometry and the [resolvedSymbology]
/// (the concrete symbology used, after `auto` inference).
final class BarcodeEncoded extends BarcodeEncodeResult {
  /// Creates a success result.
  const BarcodeEncoded(this.symbol, this.resolvedSymbology);

  /// The positioned geometry.
  final BarcodeSymbol symbol;

  /// The concrete symbology actually encoded.
  final BarcodeSymbology resolvedSymbology;
}

/// A failed encode (invalid data for the symbology, after auto-fix).
final class BarcodeInvalid extends BarcodeEncodeResult {
  /// Creates an invalid result with a human-readable [reason].
  const BarcodeInvalid(this.reason);

  /// Why the value could not be encoded.
  final String reason;
}

/// Encodes a barcode value into [BarcodeSymbol] geometry within a [width] x
/// [height] coordinate space.
abstract interface class BarcodeEncoder {
  /// Encodes [value] as [symbology] (resolving `auto`), laying out into a
  /// [width] x [height] space. Draws HRI text when [showText] and the symbology
  /// is 1D. [eccLevel] applies only to QR.
  BarcodeEncodeResult encode(
    BarcodeSymbology symbology,
    String value, {
    required double width,
    required double height,
    bool showText = true,
    QrErrorCorrectionLevel eccLevel = QrErrorCorrectionLevel.m,
  });
}
```

- [ ] **Step 5: Run → PASS.** Run the Step-1 test.

- [ ] **Step 6: Format + commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/elements/barcode/barcode_symbol.dart lib/src/rendering/elements/barcode/barcode_encoder.dart test/rendering/elements/barcode/barcode_symbol_test.dart && flutter analyze lib/src/rendering/elements/barcode/
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/elements/barcode/barcode_symbol.dart packages/jet_print/lib/src/rendering/elements/barcode/barcode_encoder.dart packages/jet_print/test/rendering/elements/barcode/barcode_symbol_test.dart
git commit -m "feat(036): first-party barcode geometry types + encoder seam

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Package adapter — `PackageBarcodeEncoder` (the only third-party import)

**Files:**
- Modify: `packages/jet_print/pubspec.yaml` (promote `barcode` to a direct dependency)
- Create: `lib/src/rendering/elements/barcode/package_barcode_encoder.dart`
- Test: `test/rendering/elements/barcode/package_barcode_encoder_test.dart`

**Interfaces:**
- Consumes: `BarcodeEncoder`, `BarcodeEncodeResult`/`BarcodeEncoded`/`BarcodeInvalid` (Task 5); `BarcodeSymbol`/`BarcodeModule`/`BarcodeHriText`/`BarcodeHriAlign` (Task 5); `resolveConcreteSymbology`/`isTwoDSymbology` (Task 3); `barcodeAutoFix` (Task 4); `BarcodeSymbology`/`QrErrorCorrectionLevel` (Task 1).
- Produces: `class PackageBarcodeEncoder implements BarcodeEncoder { const PackageBarcodeEncoder(); }`.

**`barcode` 2.2.9 API used (verified):** `Barcode.code128()/.code39()/.ean13()/.ean8()/.upcA()/.itf14()/.dataMatrix()/.pdf417()/.aztec()/.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel)`; `Iterable<BarcodeElement> bc.make(String data, {required double width, required double height, bool drawText, double? fontHeight})`; elements are `BarcodeBar(left, top, width, height, bool black)` and `BarcodeText(left, top, width, height, String text, BarcodeTextAlign align)`; `bool bc.isValid(String)`; `bc.verify(String)` throws `BarcodeException`. `BarcodeQRCorrectionLevel { low, medium, quartile, high }`, `BarcodeTextAlign { left, center, right }`.

- [ ] **Step 1: Promote `barcode` to a direct dependency.** In `packages/jet_print/pubspec.yaml`, under `dependencies:` (after `image: ^4.3.0`), add:

```yaml
  # Barcode/QR encoding (spec 036). Pure Dart, Apache-2.0, by the same author as
  # `pdf` (already a transitive dep via pdf). Isolated to package_barcode_encoder.dart.
  barcode: ^2.2.9
```

Run: `cd packages/jet_print && flutter pub get` — expect success, no version change (already resolved at 2.2.9).

- [ ] **Step 2: Write failing tests.** Create `test/rendering/elements/barcode/package_barcode_encoder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/rendering/elements/barcode/barcode_encoder.dart';
import 'package:jet_print/src/rendering/elements/barcode/package_barcode_encoder.dart';

void main() {
  const enc = PackageBarcodeEncoder();

  BarcodeEncoded ok(BarcodeEncodeResult r) {
    expect(r, isA<BarcodeEncoded>());
    return r as BarcodeEncoded;
  }

  test('Code128 produces bars within the space', () {
    final r = ok(enc.encode(BarcodeSymbology.code128, 'ABC-123',
        width: 200, height: 80));
    expect(r.resolvedSymbology, BarcodeSymbology.code128);
    expect(r.symbol.modules, isNotEmpty);
    expect(r.symbol.isTwoD, isFalse);
    for (final m in r.symbol.modules) {
      expect(m.left >= 0 && m.left + m.width <= 200.0001, isTrue);
    }
  });

  test('EAN-13 with 12 digits auto-fixes and encodes', () {
    final r = ok(enc.encode(BarcodeSymbology.ean13, '590123412345',
        width: 200, height: 80, showText: true));
    expect(r.resolvedSymbology, BarcodeSymbology.ean13);
    expect(r.symbol.texts, isNotEmpty); // HRI text present
  });

  test('EAN-13 with letters is invalid', () {
    expect(enc.encode(BarcodeSymbology.ean13, 'ABC', width: 200, height: 80),
        isA<BarcodeInvalid>());
  });

  test('auto infers QR for a URL; 2D has square modules', () {
    final r = ok(enc.encode(BarcodeSymbology.auto, 'https://x.example',
        width: 120, height: 120));
    expect(r.resolvedSymbology, BarcodeSymbology.qrCode);
    expect(r.symbol.isTwoD, isTrue);
    // 2D modules are square (within float tolerance).
    final m = r.symbol.modules.first;
    expect((m.width - m.height).abs() < 0.001, isTrue);
    expect(r.symbol.texts, isEmpty); // no HRI for 2D
  });

  test('QR ecc level changes the module count', () {
    final low = ok(enc.encode(BarcodeSymbology.qrCode, 'PAYLOAD-PAYLOAD',
        width: 120, height: 120, eccLevel: QrErrorCorrectionLevel.l));
    final high = ok(enc.encode(BarcodeSymbology.qrCode, 'PAYLOAD-PAYLOAD',
        width: 120, height: 120, eccLevel: QrErrorCorrectionLevel.h));
    expect(high.symbol.modules.length, greaterThanOrEqualTo(low.symbol.modules.length));
  });

  test('DataMatrix / PDF417 / Aztec encode', () {
    for (final s in <BarcodeSymbology>[
      BarcodeSymbology.dataMatrix,
      BarcodeSymbology.pdf417,
      BarcodeSymbology.aztec,
    ]) {
      expect(enc.encode(s, 'HELLO-036', width: 150, height: 150),
          isA<BarcodeEncoded>(), reason: '$s');
    }
  });
}
```

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Implement.** Create `lib/src/rendering/elements/barcode/package_barcode_encoder.dart`:

```dart
/// The sole adapter onto the third-party `barcode` package (spec 036, FR-011).
/// THIS IS THE ONLY FILE IN THE LIBRARY THAT MAY IMPORT `package:barcode`.
/// `BarcodeException` is caught here and never escapes the seam.
library;

import 'package:barcode/barcode.dart' as bc;

import '../../../domain/elements/barcode_element.dart';
import 'barcode_autofix.dart';
import 'barcode_encoder.dart';
import 'barcode_symbol.dart';
import 'symbology_inference.dart';

/// Encodes barcodes via the `barcode` package, translating its positioned
/// elements into first-party [BarcodeSymbol] geometry.
class PackageBarcodeEncoder implements BarcodeEncoder {
  /// Const constructor (stateless).
  const PackageBarcodeEncoder();

  @override
  BarcodeEncodeResult encode(
    BarcodeSymbology symbology,
    String value, {
    required double width,
    required double height,
    bool showText = true,
    QrErrorCorrectionLevel eccLevel = QrErrorCorrectionLevel.m,
  }) {
    final BarcodeSymbology concrete = resolveConcreteSymbology(symbology, value);
    final bool twoD = isTwoDSymbology(concrete);
    final String fixed = barcodeAutoFix(concrete, value);
    final bc.Barcode encoder = _encoderFor(concrete, eccLevel);

    if (!encoder.isValid(fixed)) {
      return BarcodeInvalid('Value "$value" is not valid for ${concrete.name}');
    }

    // 2D codes are laid out in a square so modules stay square; 1D uses the
    // full space and draws HRI text when requested.
    final double w = twoD ? (width < height ? width : height) : width;
    final double h = twoD ? w : height;
    final bool drawText = showText && !twoD;

    final List<BarcodeModule> modules = <BarcodeModule>[];
    final List<BarcodeHriText> texts = <BarcodeHriText>[];
    try {
      for (final bc.BarcodeElement e
          in encoder.make(fixed, width: w, height: h, drawText: drawText)) {
        if (e is bc.BarcodeBar) {
          if (e.black) {
            modules.add(BarcodeModule(e.left, e.top, e.width, e.height));
          }
        } else if (e is bc.BarcodeText) {
          texts.add(BarcodeHriText(
            left: e.left,
            top: e.top,
            width: e.width,
            height: e.height,
            text: e.text,
            align: _align(e.align),
          ));
        }
      }
    } on bc.BarcodeException catch (ex) {
      return BarcodeInvalid('${concrete.name}: ${ex.message}');
    }

    return BarcodeEncoded(
      BarcodeSymbol(
        modules: modules,
        texts: texts,
        spaceWidth: w,
        spaceHeight: h,
        isTwoD: twoD,
      ),
      concrete,
    );
  }

  bc.Barcode _encoderFor(BarcodeSymbology s, QrErrorCorrectionLevel ecc) {
    switch (s) {
      case BarcodeSymbology.qrCode:
        return bc.Barcode.qrCode(errorCorrectLevel: _ecc(ecc));
      case BarcodeSymbology.code128:
        return bc.Barcode.code128();
      case BarcodeSymbology.code39:
        return bc.Barcode.code39();
      case BarcodeSymbology.ean13:
        return bc.Barcode.ean13();
      case BarcodeSymbology.ean8:
        return bc.Barcode.ean8();
      case BarcodeSymbology.upcA:
        return bc.Barcode.upcA();
      case BarcodeSymbology.itf14:
        return bc.Barcode.itf14();
      case BarcodeSymbology.dataMatrix:
        return bc.Barcode.dataMatrix();
      case BarcodeSymbology.pdf417:
        return bc.Barcode.pdf417();
      case BarcodeSymbology.aztec:
        return bc.Barcode.aztec();
      case BarcodeSymbology.auto:
        // resolveConcreteSymbology never returns auto; defensive fallback.
        return bc.Barcode.qrCode(errorCorrectLevel: _ecc(ecc));
    }
  }

  bc.BarcodeQRCorrectionLevel _ecc(QrErrorCorrectionLevel l) {
    switch (l) {
      case QrErrorCorrectionLevel.l:
        return bc.BarcodeQRCorrectionLevel.low;
      case QrErrorCorrectionLevel.m:
        return bc.BarcodeQRCorrectionLevel.medium;
      case QrErrorCorrectionLevel.q:
        return bc.BarcodeQRCorrectionLevel.quartile;
      case QrErrorCorrectionLevel.h:
        return bc.BarcodeQRCorrectionLevel.high;
    }
  }

  BarcodeHriAlign _align(bc.BarcodeTextAlign a) {
    switch (a) {
      case bc.BarcodeTextAlign.left:
        return BarcodeHriAlign.left;
      case bc.BarcodeTextAlign.center:
        return BarcodeHriAlign.center;
      case bc.BarcodeTextAlign.right:
        return BarcodeHriAlign.right;
    }
  }
}
```

> **If the API differs** (e.g. `BarcodeBar`/`BarcodeText`/`BarcodeTextAlign` names or `make` params changed between versions): the cache copy is at `~/.pub-cache/hosted/pub.dev/barcode-2.2.9/lib/src/barcode_operations.dart` (element types) and `lib/src/barcode.dart` (factories + `make`). Adapt only this file — the seam confines the change.

- [ ] **Step 5: Run → PASS.** Run the Step-2 test.

- [ ] **Step 6: Analyzer + format + commit.**

```bash
cd packages/jet_print && flutter analyze lib/src/rendering/elements/barcode/package_barcode_encoder.dart && dart format lib/src/rendering/elements/barcode/package_barcode_encoder.dart test/rendering/elements/barcode/package_barcode_encoder_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/pubspec.yaml packages/jet_print/pubspec.lock packages/jet_print/lib/src/rendering/elements/barcode/package_barcode_encoder.dart packages/jet_print/test/rendering/elements/barcode/package_barcode_encoder_test.dart
git commit -m "feat(036): PackageBarcodeEncoder adapter over the barcode package

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Renderer — real bars/modules + HRI + quiet zone + placeholder

**Files:**
- Modify: `lib/src/rendering/elements/renderers/barcode_element_renderer.dart`
- Test (modify): `test/rendering/elements/barcode_element_renderer_test.dart` — read it first.

**Interfaces:**
- Consumes: `PackageBarcodeEncoder` (Task 6), `BarcodeEncoder`/`BarcodeEncoded`/`BarcodeInvalid` (Task 5), `resolveConcreteSymbology`/`isTwoDSymbology` (Task 3), `BarcodeElement` (Task 1), `RenderContext`/`FrameBuilder`/`RectPrimitive`/`TextRunPrimitive` (existing), `emitPlaceholder` (existing), `JetRect`/`JetTextStyle`.
- Produces: a `BarcodeElementRenderer` that emits a filled `RectPrimitive` per module (in `el.color`), a `TextRunPrimitive` per HRI run, or the existing placeholder on invalid data.

**Behavior contract:**
1. Value to encode = `el.data`. Quiet-zone inset of `bounds` by a margin when `el.quietZone` (margin = `0.1 * min(width, height)`, capped so it never exceeds 25% per side).
2. 2D symbols (per `resolveConcreteSymbology`+`isTwoDSymbology`) fit a centered **square** = `min(contentW, contentH)`.
3. Encode within the content box; translate each `BarcodeModule` → `RectPrimitive(fill: el.color)` offset by the content-box origin; each `BarcodeHriText` → a measured `TextRunPrimitive` (style: small, `el.color`).
4. `BarcodeInvalid` (or empty data with no bound preview) → `emitPlaceholder(...)` (unchanged behavior).
5. **Design-time bound-field preview:** if `el.data` is empty and `el.dataField != null`, encode `el.dataField!` as a QR preview (so the canvas shows a 2D symbol, FR-004). The renderer holds an injected `BarcodeEncoder` defaulting to `const PackageBarcodeEncoder()` (so tests can substitute a fake).

- [ ] **Step 1: Read** `test/rendering/elements/barcode_element_renderer_test.dart` and the current renderer.

- [ ] **Step 2: Write failing tests.** Replace/extend the renderer test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/barcode_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

void main() {
  const renderer = BarcodeElementRenderer();
  // Use the package-default encoder via the renderer's default.
  final ctx = RenderContext(measurer: const SimpleTextMeasurer()); // see note
  const bounds = JetRect(x: 10, y: 10, width: 160, height: 80);

  FrameBuilder freshBuilder() => FrameBuilder(const PageFormat.a4());

  test('valid Code128 emits filled rects in the bar color', () {
    const el = BarcodeElement(
      id: 'b1', bounds: bounds,
      symbology: BarcodeSymbology.code128, data: 'ABC-123',
      color: JetColor(0xFF000080));
    final out = freshBuilder();
    renderer.emit(el, ctx, bounds, out);
    final frame = out.build();
    final rects = frame.primitives.whereType<RectPrimitive>().toList();
    expect(rects, isNotEmpty);
    expect(rects.every((r) => r.fill == const JetColor(0xFF000080)), isTrue);
    // bars stay within bounds
    for (final r in rects) {
      expect(r.bounds.x >= bounds.x - 0.001, isTrue);
      expect(r.bounds.x + r.bounds.width <= bounds.x + bounds.width + 0.001, isTrue);
    }
  });

  test('showText emits an HRI TextRunPrimitive; disabling it omits text', () {
    const withText = BarcodeElement(
      id: 'b1', bounds: bounds, symbology: BarcodeSymbology.ean13,
      data: '590123412345', showText: true);
    const noText = BarcodeElement(
      id: 'b2', bounds: bounds, symbology: BarcodeSymbology.ean13,
      data: '590123412345', showText: false);
    final a = freshBuilder()..let((b) => renderer.emit(withText, ctx, bounds, b));
    // (use explicit builders; see note below — `let` is illustrative)
  });

  test('invalid data falls back to the placeholder (outline + label)', () {
    const el = BarcodeElement(
      id: 'b1', bounds: bounds, symbology: BarcodeSymbology.ean13, data: 'ABC');
    final out = freshBuilder();
    renderer.emit(el, ctx, bounds, out);
    final frame = out.build();
    // placeholder = one stroked rect + one text label
    expect(frame.primitives.whereType<RectPrimitive>().length, 1);
    expect(frame.primitives.whereType<TextRunPrimitive>().length, 1);
  });

  test('bound field with empty data previews as a 2D QR (no placeholder)', () {
    const el = BarcodeElement(
      id: 'b1', bounds: JetRect(x: 0, y: 0, width: 80, height: 80),
      symbology: BarcodeSymbology.auto, data: '', dataField: 'sku');
    final out = freshBuilder();
    renderer.emit(el, ctx, const JetRect(x: 0, y: 0, width: 80, height: 80), out);
    final rects = out.build().primitives.whereType<RectPrimitive>().toList();
    expect(rects.length, greaterThan(1)); // many modules, not a single outline
  });
}
```

> **Test harness note:** match the existing renderer test's `RenderContext`/measurer construction (read it in Step 1 — it already builds a context and a `FrameBuilder`). Drop the illustrative `let` helper; write each sub-case with an explicit `freshBuilder()` and compare HRI counts (`whereType<TextRunPrimitive>().length`) between `withText` and `noText`. Reuse whatever `TextMeasurer` the existing test uses (likely a fake or the built-in).

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Implement.** Rewrite `lib/src/rendering/elements/renderers/barcode_element_renderer.dart`:

```dart
/// Renders a [BarcodeElement] as real symbology (spec 036): filled module rects
/// plus HRI text, or the shared placeholder when the data cannot be encoded.
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/styles/text_style.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../../text/text_measurer.dart';
import '../barcode/barcode_encoder.dart';
import '../barcode/barcode_symbol.dart';
import '../barcode/package_barcode_encoder.dart';
import '../element_renderer.dart';
import '../placeholder.dart';
import '../render_context.dart';

/// The built-in renderer for `barcode` elements.
class BarcodeElementRenderer extends ElementRenderer<BarcodeElement> {
  /// Creates a renderer; [encoder] defaults to the package adapter.
  const BarcodeElementRenderer(
      {this.encoder = const PackageBarcodeEncoder()});

  /// The encoder seam (injectable for tests).
  final BarcodeEncoder encoder;

  @override
  JetSize measure(
          BarcodeElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(
      BarcodeElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    // Value: the resolved literal. An empty bound field previews as QR.
    final bool previewBoundField = el.data.isEmpty && el.dataField != null;
    final String value = previewBoundField ? el.dataField! : el.data;
    final BarcodeSymbology symbology =
        previewBoundField ? BarcodeSymbology.qrCode : el.symbology;

    // Quiet-zone inset (FR-007).
    final double margin = el.quietZone
        ? (0.1 * (bounds.width < bounds.height ? bounds.width : bounds.height))
            .clamp(0, 0.25 * bounds.width)
            .toDouble()
        : 0;
    final double cx = bounds.x + margin;
    final double cy = bounds.y + margin;
    final double cw = bounds.width - 2 * margin;
    final double ch = bounds.height - 2 * margin;
    if (cw <= 0 || ch <= 0) {
      emitPlaceholder(out, bounds, el.symbology.name, ctx,
          elementId: el.id, color: el.color);
      return;
    }

    final BarcodeEncodeResult result = encoder.encode(
      symbology,
      value,
      width: cw,
      height: ch,
      showText: el.showText,
      eccLevel: el.eccLevel,
    );

    if (result is! BarcodeEncoded) {
      emitPlaceholder(out, bounds, el.symbology.name, ctx,
          elementId: el.id, color: el.color);
      return;
    }

    final BarcodeSymbol sym = result.symbol;
    // Center the (possibly square) symbol within the content box.
    final double ox = cx + (cw - sym.spaceWidth) / 2;
    final double oy = cy + (ch - sym.spaceHeight) / 2;

    for (final BarcodeModule m in sym.modules) {
      out.add(RectPrimitive(
        bounds: JetRect(
            x: ox + m.left, y: oy + m.top, width: m.width, height: m.height),
        fill: el.color,
        elementId: el.id,
      ));
    }
    for (final BarcodeHriText t in sym.texts) {
      final JetTextStyle style =
          JetTextStyle(fontSize: t.height * 0.9, color: el.color);
      final JetRect tb = JetRect(
          x: ox + t.left, y: oy + t.top, width: t.width, height: t.height);
      final MeasuredText measured =
          ctx.measurer.measure(t.text, style, maxWidth: t.width);
      out.add(TextRunPrimitive(
        bounds: tb,
        lines: measured.lines,
        style: style,
        fontFamily: measured.fontFamily,
        elementId: el.id,
      ));
    }
  }
}
```

> **Verify in Step 1:** the exact `JetTextStyle` constructor params (the placeholder uses `JetTextStyle(fontSize:, color:)`), and `MeasuredText`'s `lines`/`fontFamily`/`size` shape (the text renderer reads `m.lines`/`m.fontFamily`). Match those.

- [ ] **Step 5: Run → PASS.** Run: `cd packages/jet_print && flutter test test/rendering/elements/barcode_element_renderer_test.dart`.

- [ ] **Step 6: Full rendering-suite regression.** Run: `cd packages/jet_print && flutter test test/rendering` — confirm nothing else regresses (the element-type registry test, etc.). **No golden should change here** (goldens for a barcode sample are added in Task 11). If a golden changes, STOP and inspect.

- [ ] **Step 7: Analyzer + format + commit.**

```bash
cd packages/jet_print && flutter analyze lib/src/rendering/elements/renderers/barcode_element_renderer.dart && dart format lib/src/rendering/elements/renderers/barcode_element_renderer.dart test/rendering/elements/barcode_element_renderer_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/elements/renderers/barcode_element_renderer.dart packages/jet_print/test/rendering/elements/barcode_element_renderer_test.dart
git commit -m "feat(036): render real barcode symbology (modules + HRI + quiet zone)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Fill-time data binding + diagnostics

**Files:**
- Modify: `lib/src/rendering/fill/element_resolver.dart`
- Test (modify): `test/rendering/fill/element_resolver_test.dart` — read it first to match harness (it constructs `ElementResolver`, `ReportDiagnostics`, `DataRow`).

**Interfaces:**
- Consumes: `BarcodeElement`/`BarcodeSymbology` (Task 1), `resolveConcreteSymbology` + `PackageBarcodeEncoder` + `BarcodeInvalid` (Tasks 3/5/6), existing `DataRow`/`ReportDiagnostics`/`knownFields`/`warnedFields`.
- Produces: `ElementResolver.resolve` handles `BarcodeElement`:
  - `dataField != null` → resolve to a `BarcodeElement` with `data = <stringified field value>`, `dataField: () => null`.
  - `dataField` not in `knownFields` (when schema-aware) → emit the existing unresolved warning (deduped), resolve `data = ''`, `dataField: () => null`.
  - After the value is known and non-empty, run `PackageBarcodeEncoder().encode(...)`; on `BarcodeInvalid`, emit a `warning` with its reason (deduped per element id).

- [ ] **Step 1: Read** `test/rendering/fill/element_resolver_test.dart` and the resolver.

- [ ] **Step 2: Write failing tests.** Add to the resolver test (use the file's existing helpers for building a `DataRow`, diagnostics, and resolver):

```dart
  test('barcode dataField resolves to the row value (flattened)', () {
    final resolver = makeResolver(); // existing helper or inline construction
    const el = BarcodeElement(
      id: 'b1', bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
      symbology: BarcodeSymbology.code128, data: '', dataField: 'sku');
    final resolved = resolver.resolve(el, row: rowWith({'sku': 'ABC-123'}))
        as BarcodeElement;
    expect(resolved.data, 'ABC-123');
    expect(resolved.dataField, isNull);
  });

  test('unknown dataField warns once and resolves empty', () {
    final diags = ReportDiagnostics();
    final resolver = ElementResolver(
      functions: defaultFunctions(),
      diagnostics: diags,
      knownFields: <String>{'sku'},
    );
    const el = BarcodeElement(
      id: 'b1', bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
      symbology: BarcodeSymbology.code128, data: '', dataField: 'bogus');
    final resolved = resolver.resolve(el, row: rowWith({'sku': 'x'}))
        as BarcodeElement;
    expect(resolved.data, '');
    expect(diags.messages.where((m) => m.elementId == 'b1'), isNotEmpty);
  });

  test('invalid value for a pinned symbology emits a diagnostic', () {
    final diags = ReportDiagnostics();
    final resolver = ElementResolver(
        functions: defaultFunctions(), diagnostics: diags);
    const el = BarcodeElement(
      id: 'b1', bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
      symbology: BarcodeSymbology.ean13, data: 'ABC');
    resolver.resolve(el);
    expect(diags.messages.where((m) => m.elementId == 'b1'), isNotEmpty);
  });

  test('literal data passes through (no dataField)', () {
    final resolver = ElementResolver(
        functions: defaultFunctions(), diagnostics: ReportDiagnostics());
    const el = BarcodeElement(
      id: 'b1', bounds: JetRect(x: 0, y: 0, width: 80, height: 40),
      symbology: BarcodeSymbology.code128, data: 'HELLO');
    expect((resolver.resolve(el) as BarcodeElement).data, 'HELLO');
  });
```

> Match the test file's actual helper names (`makeResolver`, `rowWith`, `defaultFunctions`, `ReportDiagnostics().messages`) — read Step 1 and adapt. If there is no `messages` getter, assert via whatever the file uses (e.g. `diags.warnings` / a collected list).

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Implement.** In `lib/src/rendering/fill/element_resolver.dart`:

Add imports near the top (with the other element imports):

```dart
import '../../domain/elements/barcode_element.dart';
import '../elements/barcode/barcode_encoder.dart';
import '../elements/barcode/package_barcode_encoder.dart';
import '../elements/barcode/symbology_inference.dart';
```

Add a field for the dedup set (next to `_warnedUrlImages`):

```dart
  /// Barcode elements already diagnosed for an invalid/unresolved value.
  final Set<String> _warnedBarcodes = <String>{};

  /// The encoder used to validate barcode data for diagnostics.
  static const BarcodeEncoder _barcodeEncoder = PackageBarcodeEncoder();
```

In `resolve(...)`, before the final `return element;`, add:

```dart
    if (element is BarcodeElement) {
      return _resolveBarcode(element, row);
    }
```

Add the method:

```dart
  BarcodeElement _resolveBarcode(BarcodeElement el, DataRow? row) {
    String value = el.data;
    final String? field = el.dataField;
    if (field != null) {
      final Set<String>? known = knownFields;
      if (known != null && !known.contains(field)) {
        if (warnedFields.add(field)) {
          diagnostics.warning(
              'Field "$field" is not in the data source',
              elementId: el.id);
        }
        value = '';
      } else if (row != null && row.hasField(field)) {
        final Object? v = row.field(field);
        value = v?.toString() ?? '';
      } else {
        value = '';
      }
    }

    // Validity diagnostic (FR-005/FR-016): warn once per element when a
    // non-empty value cannot be encoded for its (resolved) symbology.
    if (value.isNotEmpty) {
      final BarcodeEncodeResult r = _barcodeEncoder.encode(
        el.symbology,
        value,
        width: el.bounds.width,
        height: el.bounds.height,
        showText: el.showText,
        eccLevel: el.eccLevel,
      );
      if (r is BarcodeInvalid && _warnedBarcodes.add(el.id)) {
        diagnostics.warning(r.reason, elementId: el.id);
      }
    }

    // Flatten the binding so the renderer sees a literal.
    return field == null ? el : el.copyWith(data: value, dataField: () => null);
  }
```

> **Verify:** `diagnostics.warning(String, {elementId})` signature (used elsewhere in this file — match it). `row.hasField`/`row.field` exist (confirmed). The `symbology_inference` import is only needed if you call `resolveConcreteSymbology` directly; the encoder already resolves `auto` internally, so it may be unused — remove the import if the analyzer flags it.

- [ ] **Step 5: Run → PASS.** Run: `cd packages/jet_print && flutter test test/rendering/fill/element_resolver_test.dart`.

- [ ] **Step 6: Analyzer + format + commit.**

```bash
cd packages/jet_print && flutter analyze lib/src/rendering/fill/element_resolver.dart && dart format lib/src/rendering/fill/element_resolver.dart test/rendering/fill/element_resolver_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill/element_resolver.dart packages/jet_print/test/rendering/fill/element_resolver_test.dart
git commit -m "feat(036): resolve barcode dataField + emit validity diagnostics

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Designer commands + controller dispatch

**Files:**
- Create: `lib/src/designer/controller/commands/set_barcode_symbology_command.dart`
- Create: `lib/src/designer/controller/commands/set_barcode_data_command.dart`
- Create: `lib/src/designer/controller/commands/set_barcode_options_command.dart`
- Modify: `lib/src/designer/controller/jet_report_designer_controller.dart`
- Test: `test/designer/controller/set_barcode_commands_test.dart` (model on existing `set_barcode_color_command_test.dart` — read it first)

**Interfaces:**
- Consumes: `updateElement`, `DesignerDocument`, `EditCommand`, `BarcodeElement`, `BarcodeSymbology`, `QrErrorCorrectionLevel`, controller `_commit`.
- Produces controller methods:
  - `void setBarcodeSymbology(String id, BarcodeSymbology symbology)`
  - `void setBarcodeData(String id, String data)` (literal; also clears `dataField`)
  - `void setBarcodeDataField(String id, String? field)` (sets/clears the bound field)
  - `void setBarcodeShowText(String id, bool value)`
  - `void setBarcodeQuietZone(String id, bool value)`
  - `void setBarcodeEccLevel(String id, QrErrorCorrectionLevel level)`

- [ ] **Step 1: Read** `lib/src/designer/controller/commands/set_barcode_color_command.dart` (done above — replicate its shape) and `test/designer/controller/set_barcode_color_command_test.dart`.

- [ ] **Step 2: Write failing tests.** Create `test/designer/controller/set_barcode_commands_test.dart` mirroring the color-command test harness (build a document with a barcode, apply, assert). Cover one assertion per command, e.g.:

```dart
  test('setBarcodeSymbology updates symbology only', () {
    final doc = docWithBarcode(id: 'b1'); // helper mirrored from color test
    final next = SetBarcodeSymbologyCommand(
            id: 'b1', symbology: BarcodeSymbology.ean13)
        .apply(doc);
    final el = findBarcode(next, 'b1');
    expect(el.symbology, BarcodeSymbology.ean13);
  });

  test('setBarcodeData sets literal and clears dataField', () {
    final doc = docWithBarcode(id: 'b1', dataField: 'sku');
    final next =
        SetBarcodeDataCommand(id: 'b1', data: 'LITERAL').apply(doc);
    final el = findBarcode(next, 'b1');
    expect(el.data, 'LITERAL');
    expect(el.dataField, isNull);
  });

  test('setBarcodeDataField sets the bound field', () {
    final doc = docWithBarcode(id: 'b1');
    final el = findBarcode(
        SetBarcodeDataFieldCommand(id: 'b1', field: 'sku').apply(doc), 'b1');
    expect(el.dataField, 'sku');
  });

  test('options command toggles showText / quietZone / ecc', () {
    final doc = docWithBarcode(id: 'b1');
    final el = findBarcode(
        SetBarcodeOptionsCommand(id: 'b1', showText: false).apply(doc), 'b1');
    expect(el.showText, isFalse);
  });
```

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Implement the commands.** Each mirrors `SetBarcodeColorCommand`.

`set_barcode_symbology_command.dart`:

```dart
/// Command: change a barcode element's symbology (spec 036).
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Replaces the [BarcodeElement] [id]'s [symbology] in one undoable step.
class SetBarcodeSymbologyCommand extends EditCommand {
  /// Creates the command.
  const SetBarcodeSymbologyCommand({required this.id, required this.symbology});

  /// Target element id.
  final String id;

  /// New symbology.
  final BarcodeSymbology symbology;

  @override
  String get label => 'Edit barcode symbology';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(before.definition, id,
            (ReportElement e) =>
                e is BarcodeElement ? e.copyWith(symbology: symbology) : e),
      );
}
```

`set_barcode_data_command.dart` (two commands in one file — literal + field):

```dart
/// Commands: set a barcode element's data source (literal or bound field).
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the literal [data] and clears any bound field.
class SetBarcodeDataCommand extends EditCommand {
  /// Creates the command.
  const SetBarcodeDataCommand({required this.id, required this.data});

  /// Target element id.
  final String id;

  /// Literal value to encode.
  final String data;

  @override
  String get label => 'Edit barcode data';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(before.definition, id,
            (ReportElement e) => e is BarcodeElement
                ? e.copyWith(data: data, dataField: () => null)
                : e),
      );
}

/// Binds the barcode value to [field] (or clears it to null → literal).
class SetBarcodeDataFieldCommand extends EditCommand {
  /// Creates the command.
  const SetBarcodeDataFieldCommand({required this.id, required this.field});

  /// Target element id.
  final String id;

  /// Field name, or null to clear the binding.
  final String? field;

  @override
  String get label => 'Edit barcode field';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(before.definition, id,
            (ReportElement e) => e is BarcodeElement
                ? e.copyWith(dataField: () => field)
                : e),
      );
}
```

`set_barcode_options_command.dart` (showText / quietZone / ecc in one):

```dart
/// Command: toggle a barcode element's rendering options (spec 036).
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Updates any of [showText]/[quietZone]/[eccLevel] (omitted = unchanged).
class SetBarcodeOptionsCommand extends EditCommand {
  /// Creates the command.
  const SetBarcodeOptionsCommand({
    required this.id,
    this.showText,
    this.quietZone,
    this.eccLevel,
  });

  /// Target element id.
  final String id;

  /// New HRI-text flag, or null.
  final bool? showText;

  /// New quiet-zone flag, or null.
  final bool? quietZone;

  /// New QR ECC level, or null.
  final QrErrorCorrectionLevel? eccLevel;

  @override
  String get label => 'Edit barcode options';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(before.definition, id,
            (ReportElement e) => e is BarcodeElement
                ? e.copyWith(
                    showText: showText,
                    quietZone: quietZone,
                    eccLevel: eccLevel)
                : e),
      );
}
```

- [ ] **Step 5: Wire controller methods.** In `jet_report_designer_controller.dart`, next to `setBarcodeColor` (~L770), add the imports for the three new command files and:

```dart
  /// Changes the barcode [id]'s symbology.
  void setBarcodeSymbology(String id, BarcodeSymbology symbology) =>
      _commit(SetBarcodeSymbologyCommand(id: id, symbology: symbology));

  /// Sets the barcode [id]'s literal data (clears any bound field).
  void setBarcodeData(String id, String data) =>
      _commit(SetBarcodeDataCommand(id: id, data: data));

  /// Binds the barcode [id]'s value to [field] (null clears the binding).
  void setBarcodeDataField(String id, String? field) =>
      _commit(SetBarcodeDataFieldCommand(id: id, field: field));

  /// Toggles HRI text under the barcode [id].
  void setBarcodeShowText(String id, bool value) =>
      _commit(SetBarcodeOptionsCommand(id: id, showText: value));

  /// Toggles the quiet zone of the barcode [id].
  void setBarcodeQuietZone(String id, bool value) =>
      _commit(SetBarcodeOptionsCommand(id: id, quietZone: value));

  /// Sets the QR error-correction level of the barcode [id].
  void setBarcodeEccLevel(String id, QrErrorCorrectionLevel level) =>
      _commit(SetBarcodeOptionsCommand(id: id, eccLevel: level));
```

Confirm `BarcodeSymbology`/`QrErrorCorrectionLevel` are imported in the controller (the barcode_element import likely already exists for `setBarcodeColor`).

- [ ] **Step 6: Run → PASS** (commands test + a quick controller smoke if one exists). Run: `cd packages/jet_print && flutter test test/designer/controller/`.

- [ ] **Step 7: Analyzer + format + commit.**

```bash
cd packages/jet_print && flutter analyze lib/src/designer/controller && dart format lib/src/designer/controller/commands/set_barcode_symbology_command.dart lib/src/designer/controller/commands/set_barcode_data_command.dart lib/src/designer/controller/commands/set_barcode_options_command.dart lib/src/designer/controller/jet_report_designer_controller.dart test/designer/controller/set_barcode_commands_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/controller packages/jet_print/test/designer/controller/set_barcode_commands_test.dart
git commit -m "feat(036): designer commands for barcode symbology/data/options

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Properties panel UI + l10n + create default

**Files:**
- Modify: `lib/src/designer/layout/panels/properties_panel.dart`
- Modify: `lib/src/designer/controller/commands/create_element_command.dart`
- Modify: `lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`
- Test (modify): `test/designer/properties_editor_test.dart` — read it first.

**Interfaces:**
- Consumes: controller methods (Task 9), `BarcodeElement`/`BarcodeSymbology`/`QrErrorCorrectionLevel`, existing `SectionLabel`/`_LabeledRow`/`_ColorField`/`_BindingField`/`_UnresolvedHint`/`ShadSwitch`/`ShadSelect`, `JetPrintLocalizations`, `_unresolved` helper, `resolveConcreteSymbology`/`isTwoDSymbology` (Task 3).
- Produces: the barcode inspector section replacing the color-only block.

- [ ] **Step 1: Add ARB keys** to all three locale files (mirror an existing entry's `@key` metadata block). English (`jet_print_en.arb`) values; translate for de/tr (or copy English as a stopgap and mark `@needsReview` — but prefer real translations matching the existing tone). Keys:

```json
  "propertiesSymbology": "Symbology",
  "@propertiesSymbology": { "description": "Barcode symbology picker label" },
  "barcodeSymbologyAuto": "Auto",
  "@barcodeSymbologyAuto": { "description": "Auto-detect symbology option" },
  "propertiesBarcodeData": "Data",
  "@propertiesBarcodeData": { "description": "Barcode literal/field data label" },
  "barcodeDataLiteral": "Literal",
  "@barcodeDataLiteral": { "description": "Use a literal barcode value" },
  "barcodeDataField": "Field",
  "@barcodeDataField": { "description": "Bind the barcode value to a field" },
  "barcodeShowText": "Show text",
  "@barcodeShowText": { "description": "Toggle human-readable text under 1D barcodes" },
  "barcodeQuietZone": "Quiet zone",
  "@barcodeQuietZone": { "description": "Toggle the barcode quiet-zone margin" },
  "barcodeEccLevel": "Error correction",
  "@barcodeEccLevel": { "description": "QR error-correction level label" },
  "barcodeInvalidValue": "Value is not valid for this symbology",
  "@barcodeInvalidValue": { "description": "Inline hint: data invalid for the chosen symbology" },
  "barcodeAutoInferred": "Auto → {symbology}",
  "@barcodeAutoInferred": {
    "description": "Inline hint showing the inferred symbology",
    "placeholders": { "symbology": { "type": "String" } }
  }
```

Run gen-l10n: `cd packages/jet_print && flutter gen-l10n` (or `flutter pub get` if the project regenerates on get — check `l10n.yaml`). Confirm `JetPrintLocalizations` now exposes the new getters.

- [ ] **Step 2: Write failing widget test.** In `test/designer/properties_editor_test.dart` (match its harness — it pumps the panel with a controller + selected element), add:

```dart
  testWidgets('barcode inspector shows symbology + data + options', (t) async {
    // select a barcode element, pump the properties panel (mirror existing tests)
    await pumpPropertiesForBarcode(t, id: 'b1'); // adapt to the file's helpers
    expect(find.text('Symbology'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);
    expect(find.text('Show text'), findsOneWidget);
    expect(find.text('Quiet zone'), findsOneWidget);
  });

  testWidgets('ECC row only appears for QR', (t) async {
    await pumpPropertiesForBarcode(t, id: 'b1',
        symbology: BarcodeSymbology.qrCode);
    expect(find.text('Error correction'), findsOneWidget);
    await pumpPropertiesForBarcode(t, id: 'b2',
        symbology: BarcodeSymbology.code128);
    expect(find.text('Error correction'), findsNothing);
  });
```

> Adapt to the actual harness (the file already pumps the panel for text/image/shape elements — copy that scaffold and select a `BarcodeElement`).

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Implement the panel section.** Replace the existing `if (element is BarcodeElement) ...<Widget>[ ...color only... ]` block with the full section. Use `ShadSelect<BarcodeSymbology>` for the picker, the existing `_BindingField` for the field option and a `ShadInput`/text field for the literal (mirror how text `propertiesValue` / image `propertiesBinding` are built), and `ShadSwitch` for the toggles (as used at L802). Compute the inferred-symbology hint via `resolveConcreteSymbology(element.symbology, element.data)`. Gate the ECC row on `element.symbology == BarcodeSymbology.qrCode || (element.symbology == auto && resolveConcreteSymbology(...) == qrCode)`. Gate `showText` on a 1D resolved symbology (`!isTwoDSymbology(resolveConcreteSymbology(...))`).

Concrete skeleton (adapt widget names to the panel's helpers verified in Step 1 of Task 10):

```dart
      if (element is BarcodeElement) ...<Widget>[
        const SizedBox(height: 12),
        SectionLabel(l10n.propertiesSymbology),
        _LabeledRow(
          label: l10n.propertiesSymbology,
          child: ShadSelect<BarcodeSymbology>(
            initialValue: element.symbology,
            options: <Widget>[
              for (final BarcodeSymbology s in BarcodeSymbology.values)
                ShadOption<BarcodeSymbology>(
                  value: s,
                  child: Text(s == BarcodeSymbology.auto
                      ? l10n.barcodeSymbologyAuto
                      : s.name),
                ),
            ],
            selectedOptionBuilder: (context, value) => Text(
                value == BarcodeSymbology.auto
                    ? l10n.barcodeSymbologyAuto
                    : value.name),
            onChanged: (BarcodeSymbology? v) {
              if (v != null) controller.setBarcodeSymbology(id, v);
            },
          ),
        ),
        // Data: field-or-literal. Reuse _BindingField for the field case and a
        // text input for the literal; a small toggle switches mode.
        const SizedBox(height: 12),
        SectionLabel(l10n.propertiesBarcodeData),
        if (element.dataField != null)
          _BindingField(
            fieldKey: ValueKey<String>('$_p.field.barcodeField.$id'),
            value: element.dataField!,
            placeholder: l10n.bindingImageFieldHint,
            clearTooltip: l10n.bindingClearTooltip,
            onSet: (String v) => controller.setBarcodeDataField(id, v),
            onClear: () => controller.setBarcodeDataField(id, null),
          )
        else
          _BindingField(
            fieldKey: ValueKey<String>('$_p.field.barcodeData.$id'),
            value: element.data,
            placeholder: l10n.valueFieldHint,
            clearTooltip: l10n.bindingClearTooltip,
            onSet: (String v) => controller.setBarcodeData(id, v),
            onClear: () => controller.setBarcodeData(id, ''),
          ),
        // Mode toggle (literal ↔ field):
        _LabeledRow(
          label: l10n.barcodeDataField,
          child: ShadSwitch(
            value: element.dataField != null,
            onChanged: (bool bound) => bound
                ? controller.setBarcodeDataField(id, element.data)
                : controller.setBarcodeData(id, element.dataField ?? ''),
          ),
        ),
        // Inline hints
        if (element.dataField != null &&
            _unresolved(schema, controller, id, imageField: element.dataField))
          _UnresolvedHint(message: l10n.bindingUnresolved),
        if (element.symbology == BarcodeSymbology.auto && element.data.isNotEmpty)
          _InfoHint(message: l10n.barcodeAutoInferred(
              resolveConcreteSymbology(element.symbology, element.data).name)),
        // showText (1D only)
        if (!isTwoDSymbology(resolveConcreteSymbology(element.symbology, element.data)))
          _LabeledRow(
            label: l10n.barcodeShowText,
            child: ShadSwitch(
              value: element.showText,
              onChanged: (bool v) => controller.setBarcodeShowText(id, v),
            ),
          ),
        _LabeledRow(
          label: l10n.barcodeQuietZone,
          child: ShadSwitch(
            value: element.quietZone,
            onChanged: (bool v) => controller.setBarcodeQuietZone(id, v),
          ),
        ),
        // ECC (QR only)
        if (resolveConcreteSymbology(element.symbology, element.data) ==
            BarcodeSymbology.qrCode)
          _LabeledRow(
            label: l10n.barcodeEccLevel,
            child: ShadSelect<QrErrorCorrectionLevel>(
              initialValue: element.eccLevel,
              options: <Widget>[
                for (final QrErrorCorrectionLevel e
                    in QrErrorCorrectionLevel.values)
                  ShadOption<QrErrorCorrectionLevel>(
                      value: e, child: Text(e.name.toUpperCase())),
              ],
              selectedOptionBuilder: (context, v) => Text(v.name.toUpperCase()),
              onChanged: (QrErrorCorrectionLevel? v) {
                if (v != null) controller.setBarcodeEccLevel(id, v);
              },
            ),
          ),
        // Color (unchanged)
        const SizedBox(height: 12),
        _LabeledRow(
          label: l10n.propertiesColor,
          child: _ColorField(
            keyBase: '$_p.field.barcodeColor',
            value: element.color,
            onCommit: (JetColor? c) => controller.setBarcodeColor(id, c!),
          ),
        ),
      ],
```

> **Verify against the panel in Step 1 of this task:** the real `ShadSelect`/`ShadOption` API in the installed `shadcn_ui` (check `~/.pub-cache/hosted/pub.dev/shadcn_ui-*/lib` or an existing use), the `_BindingField`/`_InfoHint` constructors (there may be no `_InfoHint` — if not, render the hint with the same widget `_UnresolvedHint` uses but a neutral style, or add a tiny `_InfoHint`), and the `_unresolved(...)` signature (it takes `imageField:` today — generalize or add a `barcodeField:` param). Keep edits minimal and local.

- [ ] **Step 5: Update the create default.** In `create_element_command.dart`, change the barcode case:

```dart
    case DesignerToolType.barcode:
      return BarcodeElement(
        id: id,
        bounds: bounds,
        symbology: BarcodeSymbology.auto,
        data: '1234567890',
      );
```

- [ ] **Step 6: Run → PASS.** Run: `cd packages/jet_print && flutter test test/designer/properties_editor_test.dart`.

- [ ] **Step 7: Analyzer + format + commit.**

```bash
cd packages/jet_print && flutter analyze lib/src/designer && dart format lib/src/designer/layout/panels/properties_panel.dart lib/src/designer/controller/commands/create_element_command.dart test/designer/properties_editor_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer packages/jet_print/test/designer/properties_editor_test.dart
git commit -m "feat(036): barcode properties (symbology/data/options) + l10n + auto default

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Public API export, architecture test, goldens, full verification

**Files:**
- Modify: `lib/jet_print.dart` (export `QrErrorCorrectionLevel`)
- Test (modify): `test/public_api_test.dart`
- Test (new): `test/architecture/barcode_dependency_isolation_test.dart`
- Test (new): `test/designer/goldens/barcode_symbologies_golden_test.dart` (+ generated golden) and/or extend an export golden.

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Export the new public enum.** In `lib/jet_print.dart`, extend the barcode export:

```dart
export 'src/domain/elements/barcode_element.dart'
    show BarcodeElement, BarcodeSymbology, QrErrorCorrectionLevel;
```

Update `test/public_api_test.dart` if it asserts the exact exported symbol set (add `QrErrorCorrectionLevel`; the new `BarcodeSymbology` values need no change there).

- [ ] **Step 2: Architecture test — only one file imports `package:barcode`.** Create `test/architecture/barcode_dependency_isolation_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only package_barcode_encoder.dart imports package:barcode', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('package_barcode_encoder.dart')) continue;
      if (f.readAsStringSync().contains("package:barcode/")) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: 'barcode pkg leaked: $offenders');
  });

  test('domain does not import the encoder seam or barcode pkg', () {
    final offenders = <String>[];
    for (final f in Directory('lib/src/domain').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      if (s.contains('rendering/elements/barcode') ||
          s.contains('package:barcode/')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: 'domain leaked: $offenders');
  });
}
```

Run → PASS (if the first test fails, a stray import exists — fix it). Run: `cd packages/jet_print && flutter test test/architecture/barcode_dependency_isolation_test.dart`.

- [ ] **Step 3: Golden — multi-symbology sample.** Read an existing golden test (`test/rendering/.../*_golden_test.dart` or `test/designer/goldens/design_surface_test.dart`) to match the harness (`matchesGoldenFile`, the render/paint path). Create `test/designer/goldens/barcode_symbologies_golden_test.dart` that lays out a small report with one band containing: a Code 128 (`showText: true`), an EAN-13 (`590123412345`, auto-fixed), a QR (`https://x.example`, ecc `h`), and a Data Matrix — renders to the frame/canvas the same way existing goldens do, and asserts `matchesGoldenFile('goldens/barcode_symbologies.png')`. Generate the golden:

```bash
cd packages/jet_print && flutter test --update-goldens test/designer/goldens/barcode_symbologies_golden_test.dart
```

Then run without `--update-goldens` → PASS. Visually inspect the generated PNG: bars present, HRI digits under EAN-13/Code128, QR is a square module grid, quiet-zone margins visible.

- [ ] **Step 4: Full verification sweep (SC-008).**

```bash
cd packages/jet_print
flutter analyze                                              # clean
dart format --output=none --set-exit-if-changed lib test     # no-op
flutter test                                                  # ALL GREEN
```

**Pre-existing goldens MUST be unchanged** (only `barcode_symbologies.png` is new). If any other golden differs, STOP and inspect — a non-additive change leaked in.

- [ ] **Step 5: Playground sanity.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print/apps/jet_print_playground && flutter analyze && flutter test
```

Both green (the playground consumes the library through its public API; confirms `QrErrorCorrectionLevel` export + no break).

- [ ] **Step 6: Confirm Success Criteria.** SC-001 → Task 6 per-symbology + Task 11 golden. SC-002 → Task 8 dataField/literal. SC-003 → Task 3 inference table. SC-004 → Task 4 + Task 6 invalid + Task 8 diagnostic. SC-005 → Task 6 HRI/ecc + Task 7 quiet zone. SC-006 → Task 11 golden (shared primitives) + (optional) an export golden. SC-007 → Task 2 back-compat + Step 4 goldens-unchanged. SC-008 → Step 4. SC-009 → Step 2 architecture test.

- [ ] **Step 7: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/jet_print.dart packages/jet_print/test/public_api_test.dart packages/jet_print/test/architecture packages/jet_print/test/designer/goldens/barcode_symbologies_golden_test.dart packages/jet_print/test/designer/goldens/goldens/barcode_symbologies.png
git commit -m "feat(036): export QrErrorCorrectionLevel + dependency-isolation & golden tests

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 8 (optional): Manual GUI smoke.** `cd apps/jet_print_playground && flutter run -d macos`; drop a barcode, leave `Auto`, type `https://x.example` → QR renders; switch to `EAN-13`, type `590123412345` → bars + digits; bind to a field with a sample data source → preview renders per row; type letters into EAN-13 → placeholder + inline hint.

---

## Self-Review

**Spec coverage:**
- FR-001 (ten symbologies) → Tasks 1 (enum), 6 (adapter), 11 (golden).
- FR-002 (element fields) → Task 1.
- FR-003 (dataField at fill) → Task 8.
- FR-004 (auto inference + QR preview) → Task 3 (+ Task 7 preview).
- FR-005 (auto-fix else placeholder) → Tasks 4, 6, 7, 8.
- FR-006 (HRI 1D, ignored 2D) → Tasks 6, 7.
- FR-007 (quiet zone) → Task 7.
- FR-008 (QR ecc) → Tasks 1, 6, 10.
- FR-009 (crisp/square) → Tasks 6 (square 2D), 7 (centered fit). *Note:* "crisp" is delivered as equal-width modules from `make()` + square 2D fit; sub-pixel snapping is not separately implemented (vector output stays sharp). Acceptable per spec intent.
- FR-010 (color) → Task 7.
- FR-011 (seam, single import) → Tasks 5, 6, 11 (architecture test).
- FR-012 (unresolved field diagnostic) → Task 8.
- FR-013 (additive codec) → Task 2.
- FR-014 (designer edits, undoable) → Tasks 9, 10.
- FR-015 (inline hint, localized) → Task 10.
- FR-016 (diagnostics not in renderer) → Tasks 7 (renderer renders only), 8 (fill emits).
- SC-001..009 → Task 11 Step 6 mapping.

**Placeholder scan:** No TBD/TODO. The two `> Verify` notes (Task 6 API, Task 10 widget API) point at exact cache paths / existing-pattern files because those third-party/widget APIs must be confirmed against the installed versions — they are verification instructions with concrete fallbacks, not deferred work. Test-harness adaptation notes (Tasks 7/8/10) name the helpers to mirror.

**Type consistency:** `BarcodeSymbology`, `QrErrorCorrectionLevel`, `BarcodeElement.copyWith(dataField: () => …)`, `BarcodeEncoder.encode(...)` signature, `BarcodeEncoded.resolvedSymbology`, `BarcodeInvalid.reason`, `BarcodeModule`/`BarcodeHriText`/`BarcodeHriAlign`, `resolveConcreteSymbology`/`isTwoDSymbology`, `barcodeAutoFix`, `PackageBarcodeEncoder()` — names are used identically across Tasks 1→11. Controller methods in Task 9 match the calls in Task 10. `SetBarcodeOptionsCommand` carries all three optional flags, consistent with Task 9 tests and Task 10 calls.

**Risks:** (1) `barcode` API names — confined to Task 6, cache path given. (2) `shadcn_ui` `ShadSelect` API — confined to Task 10, verify against installed version. (3) Existing test harness helper names (resolver/panel/golden) — each task says "read first, match." (4) Goldens — additive only; Step 4 guards.
