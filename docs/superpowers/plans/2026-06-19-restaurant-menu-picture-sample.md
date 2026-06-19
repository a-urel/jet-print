# Restaurant Menu Picture-Sample Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Menu" playground tab — a restaurant menu grouped by category, where each item shows a data-bound food picture — the first sample to exercise the engine's `ImageElement`.

**Architecture:** Pure consumer-side sample, mirroring the existing payroll/packing-slip samples. A flat menu-item list is grouped by `category` (single `GroupLevel`, the payroll department pattern). Each master row renders a `detail` band whose left cell is an `ImageElement` bound via `FieldImageSource('photo')`; the page header carries a fixed `BytesImageSource` logo. Photos are synthesized in-code as uncompressed 24-bit BMP swatches (no binary assets, no async, license-clean) and carried as base64 in each data row — the fill resolver decodes base64 → bytes.

**Tech Stack:** Dart/Flutter, `package:jet_print/jet_print.dart` (public API only), `flutter_test`, ARB/`gen-l10n` localization.

## Global Constraints

- Consume the library through `package:jet_print/jet_print.dart` only — **no changes to the `jet_print` library source**. (Test-only reach-ins to `package:jet_print/src/rendering/frame/primitive.dart` are allowed, matching `rendered_payroll_example_test.dart`.)
- All work is under `apps/jet_print_playground/`.
- Sample field/label *data* is illustrative and intentionally **not** localized; only tab chrome (`tabMenu`) is localized, across **all three** ARBs: `app_en.arb` (with `@`-metadata), `app_tr.arb`, `app_de.arb`.
- Money format string is `#,##0.00` (the repo-proven pattern; no embedded currency glyph). A footer note states the currency.
- A4 portrait content width is `538` logical units (as in `payroll_sample.dart`).
- **No golden image changes** — this is a new, isolated sample + tab.
- Photos are **generated in-code** (BMP), never bundled as assets; `photo` is declared `JetFieldType.string` and carries base64.
- Run all commands from `apps/jet_print_playground/` unless stated otherwise. Run `git` from the repo root (`/Users/ahmeturel/Projects/oss/jet-print`) — `flutter` leaves the cwd inside the package.
- Work on branch `restaurant-menu-picture-sample` (already created and holding the design doc).

---

### Task 1: In-code BMP swatch generator

A focused, independently-testable pure-Dart unit that produces real encoded image bytes (so `ui.instantiateImageCodec` in `canvas_painter.dart` can decode them at paint time). Uncompressed 24-bit BMP, bottom-up rows, 4-byte row padding.

**Files:**
- Create: `apps/jet_print_playground/lib/menu_photo.dart`
- Test: `apps/jet_print_playground/test/menu_photo_test.dart`

**Interfaces:**
- Produces:
  - `Uint8List gradientBmp({required int width, required int height, required int topRgb, required int bottomRgb})` — a 24-bit BMP with a vertical gradient from `topRgb` (top row) to `bottomRgb` (bottom row); colors are `0xRRGGBB` ints.
  - `String gradientBmpBase64({required int width, required int height, required int topRgb, required int bottomRgb})` — `base64Encode` of the above.

- [ ] **Step 1: Write the failing test**

Create `apps/jet_print_playground/test/menu_photo_test.dart`:

```dart
// Confirms the in-code BMP generator emits real, decodable image bytes — the
// thing the engine's painter (ui.instantiateImageCodec) needs at paint time.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print_playground/menu_photo.dart';

void main() {
  group('gradientBmp', () {
    test('has a well-formed BMP header and exact size', () {
      final Uint8List b =
          gradientBmp(width: 8, height: 6, topRgb: 0xFF0000, bottomRgb: 0x0000FF);
      // 'BM' magic.
      expect(b[0], 0x42);
      expect(b[1], 0x4D);
      final ByteData bd = ByteData.sublistView(b);
      // Pixel-data offset is right after the 14+40 byte headers.
      expect(bd.getUint32(10, Endian.little), 54);
      // 24bpp, BI_RGB, declared width/height.
      expect(bd.getInt32(18, Endian.little), 8);
      expect(bd.getInt32(22, Endian.little), 6);
      expect(bd.getUint16(28, Endian.little), 24);
      expect(bd.getUint32(30, Endian.little), 0);
      // Row stride for width 8 = 24 bytes (already 4-aligned); 6 rows + 54 header.
      expect(b.length, 54 + 24 * 6);
    });

    testWidgets('decodes through the Flutter codec to the requested size',
        (WidgetTester tester) async {
      final Uint8List b =
          gradientBmp(width: 12, height: 9, topRgb: 0xE8B04B, bottomRgb: 0x7A3B12);
      final ui.Codec codec = await ui.instantiateImageCodec(b);
      final ui.FrameInfo frame = await codec.getNextFrame();
      expect(frame.image.width, 12);
      expect(frame.image.height, 9);
    });

    test('base64 variant round-trips to the same bytes', () {
      final Uint8List raw =
          gradientBmp(width: 4, height: 4, topRgb: 0x112233, bottomRgb: 0x445566);
      final String b64 = gradientBmpBase64(
          width: 4, height: 4, topRgb: 0x112233, bottomRgb: 0x445566);
      expect(base64Decode(b64), raw);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/menu_photo_test.dart`
Expected: FAIL — `menu_photo.dart` / `gradientBmp` does not exist (compile error).

- [ ] **Step 3: Write minimal implementation**

Create `apps/jet_print_playground/lib/menu_photo.dart`:

```dart
/// In-code image generation for the restaurant-menu sample.
///
/// Produces uncompressed 24-bit BMP swatches as raw bytes — a vertical gradient
/// between two colors. BMP is chosen because it is trivial to synthesize
/// byte-by-byte in pure synchronous Dart (no compression, no Flutter binding to
/// *build*) and is accepted by `ui.instantiateImageCodec`, which the engine's
/// painter uses to decode `ImagePrimitive` bytes at paint time. Keeps the sample
/// asset-free and license-clean.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Builds a 24-bit BMP of [width]×[height] with a vertical gradient from
/// [topRgb] (top row) to [bottomRgb] (bottom row). Colors are `0xRRGGBB`.
Uint8List gradientBmp({
  required int width,
  required int height,
  required int topRgb,
  required int bottomRgb,
}) {
  const int headerSize = 54; // 14-byte file header + 40-byte info header.
  // Each pixel is 3 bytes (BGR); rows are padded to a 4-byte boundary.
  final int rowStride = ((width * 3 + 3) ~/ 4) * 4;
  final int pixelBytes = rowStride * height;
  final int fileSize = headerSize + pixelBytes;

  final Uint8List bytes = Uint8List(fileSize);
  final ByteData bd = ByteData.sublistView(bytes);

  // BITMAPFILEHEADER.
  bytes[0] = 0x42; // 'B'
  bytes[1] = 0x4D; // 'M'
  bd.setUint32(2, fileSize, Endian.little);
  bd.setUint32(10, headerSize, Endian.little); // pixel-data offset

  // BITMAPINFOHEADER.
  bd.setUint32(14, 40, Endian.little); // this header's size
  bd.setInt32(18, width, Endian.little);
  bd.setInt32(22, height, Endian.little); // positive => bottom-up rows
  bd.setUint16(26, 1, Endian.little); // color planes
  bd.setUint16(28, 24, Endian.little); // bits per pixel
  bd.setUint32(30, 0, Endian.little); // BI_RGB (no compression)
  bd.setUint32(34, pixelBytes, Endian.little); // raw image size

  final int tr = (topRgb >> 16) & 0xFF;
  final int tg = (topRgb >> 8) & 0xFF;
  final int tb = topRgb & 0xFF;
  final int br = (bottomRgb >> 16) & 0xFF;
  final int bg = (bottomRgb >> 8) & 0xFF;
  final int bb = bottomRgb & 0xFF;

  for (int y = 0; y < height; y++) {
    // BMP rows are stored bottom-up: file row 0 is the image's bottom row.
    final int imageRow = height - 1 - y;
    final double t = height == 1 ? 0 : imageRow / (height - 1);
    final int r = (tr + (br - tr) * t).round();
    final int g = (tg + (bg - tg) * t).round();
    final int b = (tb + (bb - tb) * t).round();
    int o = headerSize + y * rowStride;
    for (int x = 0; x < width; x++) {
      bytes[o++] = b; // BMP pixels are stored BGR.
      bytes[o++] = g;
      bytes[o++] = r;
    }
    // Trailing row-padding bytes are already zero.
  }
  return bytes;
}

/// [gradientBmp] base64-encoded — the form carried in a data row's image field.
String gradientBmpBase64({
  required int width,
  required int height,
  required int topRgb,
  required int bottomRgb,
}) =>
    base64Encode(gradientBmp(
      width: width,
      height: height,
      topRgb: topRgb,
      bottomRgb: bottomRgb,
    ));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/menu_photo_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/menu_photo.dart apps/jet_print_playground/test/menu_photo_test.dart
git commit -m "feat(playground): in-code BMP swatch generator for menu photos"
```

---

### Task 2: Menu schema + report definition

The authored report: page header with an embedded `BytesImageSource` logo, a `category` group, one `detail` band per menu item (thumbnail + name/description/price), and a page footer.

**Files:**
- Create: `apps/jet_print_playground/lib/menu_sample.dart`
- Test: `apps/jet_print_playground/test/menu_definition_test.dart`

**Interfaces:**
- Consumes: `gradientBmp(...)` from Task 1 (for the logo bytes).
- Produces:
  - `const JetDataSchema menuSchema` — fields `category`, `name`, `description` (`string`), `price` (`double`), `photo` (`string`, base64 image).
  - `ReportDefinition menuSampleDefinition()` — non-const (embeds generated logo bytes). Element IDs relied on downstream: page-header logo `brandLogo`; category group key `$F{category}`; item detail band id `item` with children `itemPhoto` (image, `FieldImageSource('photo')`), `itemName`, `itemDesc`, `itemPrice`.

- [ ] **Step 1: Write the failing test**

Create `apps/jet_print_playground/test/menu_definition_test.dart`:

```dart
// Confirms the menu sample is a category-grouped flat list whose detail band
// carries a data-bound food picture, and whose page header carries an embedded
// logo — pristine under the validator. Public API only.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_playground/menu_sample.dart';

void main() {
  group('menu sample', () {
    test('schema is a flat menu item with a string photo field', () {
      FieldDef f(String name) =>
          menuSchema.fields.firstWhere((FieldDef e) => e.name == name);
      expect(f('category').type, JetFieldType.string);
      expect(f('name').type, JetFieldType.string);
      expect(f('description').type, JetFieldType.string);
      expect(f('price').type, JetFieldType.double);
      // No image/bytes field type exists; the photo is base64 in a string.
      expect(f('photo').type, JetFieldType.string);
      // Flat: no nested collections.
      expect(menuSchema.fields.any((FieldDef e) => e.type == JetFieldType.collection),
          isFalse);
    });

    test('master rows are grouped by category with one detail band', () {
      final DetailScope root = menuSampleDefinition().body.root;
      // Master scope iterates menu items (no collectionField on root).
      expect(root.collectionField, isNull);
      // One group level, keyed on category.
      expect(root.groups, hasLength(1));
      expect(root.groups.single.key, r'$F{category}');
      expect(root.groups.single.header?.type, BandType.groupHeader);
      // Exactly one per-row detail band (the item card), no nested scopes.
      expect(root.children.whereType<NestedScope>(), isEmpty);
      final List<BandNode> bands = root.children.whereType<BandNode>().toList();
      expect(bands, hasLength(1));
      expect(bands.single.band.type, BandType.detail);
      expect(bands.single.band.id, 'item');
    });

    test('the item photo is an image bound to the photo field', () {
      final Band item = menuSampleDefinition()
          .body
          .root
          .children
          .whereType<BandNode>()
          .single
          .band;
      final ImageElement photo = item.elements
          .firstWhere((ReportElement e) => e.id == 'itemPhoto') as ImageElement;
      expect(photo.source, isA<FieldImageSource>());
      expect((photo.source as FieldImageSource).field, 'photo');
    });

    test('the page header logo is an embedded bytes image', () {
      final Band header = menuSampleDefinition().furniture!.pageHeader!;
      final ImageElement logo = header.elements
          .firstWhere((ReportElement e) => e.id == 'brandLogo') as ImageElement;
      expect(logo.source, isA<BytesImageSource>());
      expect((logo.source as BytesImageSource).bytes, isNotEmpty);
    });

    test('is pristine under the library validator (no diagnostics)', () {
      expect(validate(menuSampleDefinition()), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/menu_definition_test.dart`
Expected: FAIL — `menu_sample.dart` / `menuSchema` / `menuSampleDefinition` do not exist.

- [ ] **Step 3: Write minimal implementation**

Create `apps/jet_print_playground/lib/menu_sample.dart`:

```dart
/// The playground's restaurant-menu sample — a category-grouped list of dishes,
/// each with a data-bound food picture — authored entirely through the library's
/// public API (`package:jet_print/jet_print.dart`).
///
/// It is the first sample to use the engine's `ImageElement`, demonstrating both
/// no-I/O image paths: per-row photos via `FieldImageSource('photo')` (the data
/// carries base64 bytes the fill resolver decodes), and a fixed page-header logo
/// via an embedded `BytesImageSource`. Photos are synthesized in-code as BMP
/// swatches (see `menu_photo.dart`) — abstract gradients, but proof that
/// distinct per-row images bind and paint.
///
/// Field/label names are illustrative sample data and intentionally not
/// localized; only the designer's own chrome is.
library;

import 'package:jet_print/jet_print.dart';

import 'menu_photo.dart';

/// The menu data structure: a flat dish row. `photo` holds base64 image bytes
/// (declared `string`, since there is no image/bytes field type); the fill
/// resolver turns it into image bytes. Attach it via `dataSchema:`.
const JetDataSchema menuSchema = JetDataSchema(
  name: 'MenuItem',
  fields: <FieldDef>[
    FieldDef('category', type: JetFieldType.string),
    FieldDef('name', type: JetFieldType.string),
    FieldDef('description', type: JetFieldType.string),
    FieldDef('price', type: JetFieldType.double),
    FieldDef('photo', type: JetFieldType.string),
  ],
);

/// A muted grey used for captions and secondary text.
const JetColor _grey = JetColor(0xFF888888);

/// A warm rule color under category headings.
const JetColor _rule = JetColor(0xFFBFA15A);

const String _money = '#,##0.00';

/// The brand-mark bytes embedded in the page header (a small generated swatch
/// standing in for a real logo). Computed once at first use.
final BytesImageSource _logo = BytesImageSource(
  gradientBmp(width: 44, height: 44, topRgb: 0xC9762B, bottomRgb: 0x7A3B12),
);

/// The restaurant-menu report authored in the reified band model (spec 024).
/// Non-const because it embeds generated logo bytes.
ReportDefinition menuSampleDefinition() => ReportDefinition(
      name: 'Menu',
      page: PageFormat.a4Portrait,
      furniture: PageFurniture(
        pageHeader: Band(
          id: 'pageHeader',
          type: BandType.pageHeader,
          height: 56,
          elements: <ReportElement>[
            ImageElement(
              id: 'brandLogo',
              bounds: const JetRect(x: 0, y: 4, width: 44, height: 44),
              source: _logo,
              fit: JetBoxFit.contain,
            ),
            const TextElement(
              id: 'brandName',
              bounds: JetRect(x: 56, y: 6, width: 420, height: 24),
              text: 'The Copper Kettle',
              style: JetTextStyle(fontSize: 18, weight: JetFontWeight.bold),
            ),
            const TextElement(
              id: 'brandTag',
              bounds: JetRect(x: 56, y: 32, width: 420, height: 16),
              text: 'Seasonal kitchen · est. 2014',
              style: JetTextStyle(fontSize: 10, color: _grey),
            ),
            const ShapeElement(
              id: 'headerRule',
              bounds: JetRect(x: 0, y: 53, width: 538, height: 1),
              kind: ShapeKind.rectangle,
              style: JetBoxStyle(fill: _rule),
            ),
          ],
        ),
        pageFooter: Band(
          id: 'pageFooter',
          type: BandType.pageFooter,
          height: 20,
          elements: const <ReportElement>[
            TextElement(
              id: 'footerNote',
              bounds: JetRect(x: 0, y: 2, width: 538, height: 14),
              text: 'Prices in USD',
              style: JetTextStyle(fontSize: 8, color: _grey),
              expression:
                  r'"Prices in USD  ·  Dishes may contain allergens  ·  Page " + $V{PAGE_NUMBER} + " of " + $V{PAGE_COUNT}',
            ),
          ],
        ),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          groups: <GroupLevel>[
            GroupLevel(
              id: 'category',
              name: 'category',
              key: r'$F{category}',
              header: Band(
                id: 'catHeader',
                type: BandType.groupHeader,
                height: 28,
                elements: const <ReportElement>[
                  TextElement(
                    id: 'catName',
                    bounds: JetRect(x: 0, y: 4, width: 538, height: 18),
                    text: 'category',
                    style: JetTextStyle(
                        fontSize: 13, weight: JetFontWeight.bold),
                    expression: r'$F{category}',
                  ),
                  ShapeElement(
                    id: 'catRule',
                    bounds: JetRect(x: 0, y: 24, width: 538, height: 1),
                    kind: ShapeKind.rectangle,
                    style: JetBoxStyle(fill: _rule),
                  ),
                ],
              ),
            ),
          ],
          children: const <ScopeNode>[
            BandNode(Band(
              id: 'item',
              type: BandType.detail,
              height: 64,
              elements: <ReportElement>[
                // Per-row food picture: resolved from the row's base64 `photo`.
                ImageElement(
                  id: 'itemPhoto',
                  bounds: JetRect(x: 0, y: 6, width: 52, height: 52),
                  source: FieldImageSource('photo'),
                  fit: JetBoxFit.cover,
                ),
                TextElement(
                  id: 'itemName',
                  bounds: JetRect(x: 64, y: 6, width: 380, height: 18),
                  text: 'name',
                  style: JetTextStyle(
                      fontSize: 12, weight: JetFontWeight.bold),
                  expression: r'$F{name}',
                ),
                TextElement(
                  id: 'itemDesc',
                  bounds: JetRect(x: 64, y: 26, width: 380, height: 28),
                  text: 'description',
                  style: JetTextStyle(fontSize: 9, color: _grey),
                  expression: r'$F{description}',
                ),
                TextElement(
                  id: 'itemPrice',
                  bounds: JetRect(x: 448, y: 8, width: 90, height: 18),
                  text: 'price',
                  style: JetTextStyle(
                      fontSize: 12,
                      align: JetTextAlign.right,
                      weight: JetFontWeight.bold),
                  expression: r'$F{price}',
                  format: _money,
                ),
              ],
            )),
          ],
        ),
      ),
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/menu_definition_test.dart`
Expected: PASS (5 tests).

If `validate(...)` reports a diagnostic, read its message: the menu tree (one `category` group + one direct `detail` band under root, no nested scopes) is the canonical grouped-list shape (cf. the empty seed in `main.dart` and the invoice sample). Do not add nested scopes or extra per-row bands to satisfy it; fix the actual reported issue.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/menu_sample.dart apps/jet_print_playground/test/menu_definition_test.dart
git commit -m "feat(playground): menu schema + report definition with bound photos"
```

---

### Task 3: Sample data + render entry

The real menu data (with generated per-row photos) and the one-call render through the public engine — the consumer side, and what the preview/export uses.

**Files:**
- Create: `apps/jet_print_playground/lib/rendered_menu_example.dart`
- Test: `apps/jet_print_playground/test/rendered_menu_example_test.dart`

**Interfaces:**
- Consumes: `gradientBmpBase64(...)` (Task 1); `menuSchema`, `menuSampleDefinition()` (Task 2).
- Produces:
  - `final List<Map<String, Object?>> kSampleMenu` — dishes ordered so equal categories are contiguous; each row has `category`, `name`, `description`, `price`, `photo` (base64 BMP). **Not `const`** (photos are computed).
  - `JetDataSource menuDataSource()` — `JetInMemoryDataSource(kSampleMenu, fields: menuSchema.fields)`.
  - `RenderedReport renderMenuDefinition({ReportDefinition? definition, JetDataSource? source, List<JetFontFamily> fonts})`.

- [ ] **Step 1: Write the failing test**

Create `apps/jet_print_playground/test/rendered_menu_example_test.dart`:

```dart
// Rendered menu example: data source + render through
// `package:jet_print/jet_print.dart` only. Confirms the run fills cleanly, that
// every item's data-bound photo resolves to real image bytes, that the embedded
// header logo paints, and that the prices match the SAME sample data.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jet_print/jet_print.dart';
// Implementation import for the rendered-run proof — the same reach-in the
// engine's own tests use (cf. rendered_payroll_example_test.dart).
import 'package:jet_print/src/rendering/frame/primitive.dart'
    show ImagePrimitive, TextRunPrimitive;
import 'package:jet_print/src/rendering/text/text_measurer.dart' show TextLine;
import 'package:jet_print_playground/rendered_menu_example.dart';

final NumberFormat _money = NumberFormat('#,##0.00');

void main() {
  group('rendered menu example', () {
    test('items are ordered so equal categories are contiguous', () {
      final List<String> cats = <String>[
        for (final Map<String, Object?> m in kSampleMenu) m['category']! as String,
      ];
      final List<String> contiguous = cats
          .toSet()
          .expand((String c) => cats.where((String x) => x == c))
          .toList();
      expect(cats, contiguous);
      expect(cats.toSet().length, greaterThanOrEqualTo(2));
    });

    test('every item carries a non-empty base64 photo', () {
      for (final Map<String, Object?> m in kSampleMenu) {
        expect(m['photo'], isA<String>());
        expect((m['photo']! as String), isNotEmpty);
      }
    });

    test('renders cleanly (no error diagnostics)', () {
      final RenderedReport report = renderMenuDefinition();
      expect(report.pageCount, greaterThan(0));
      expect(
        report.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });

    test('each item resolves its bound photo to real image bytes', () {
      final RenderedReport report = renderMenuDefinition();
      final List<ImagePrimitive> photos =
          _imagesForId(report, 'itemPhoto').toList();
      // One painted photo per menu item, each with decoded bytes.
      expect(photos, hasLength(kSampleMenu.length));
      for (final ImagePrimitive p in photos) {
        expect(p.bytes, isNotEmpty);
      }
    });

    test('the embedded header logo paints at least once', () {
      final RenderedReport report = renderMenuDefinition();
      final List<ImagePrimitive> logos =
          _imagesForId(report, 'brandLogo').toList();
      expect(logos, isNotEmpty);
      expect(logos.first.bytes, isNotEmpty);
    });

    test('prices render the formatted sample values in order', () {
      final RenderedReport report = renderMenuDefinition();
      final List<String> expected = <String>[
        for (final Map<String, Object?> m in kSampleMenu)
          _money.format(m['price']! as num),
      ];
      expect(_runsForId(report, 'itemPrice'), expected);
    });
  });
}

/// The painted image primitives for [elementId], in paint order across pages.
Iterable<ImagePrimitive> _imagesForId(RenderedReport report, String elementId) =>
    <ImagePrimitive>[
      for (int i = 0; i < report.pageCount; i++)
        for (final ImagePrimitive p
            in report.pageAt(i).frame.primitives.whereType<ImagePrimitive>())
          if (p.elementId == elementId) p,
    ];

/// The rendered text runs of [elementId], in paint order across pages.
List<String> _runsForId(RenderedReport report, String elementId) => <String>[
      for (int i = 0; i < report.pageCount; i++)
        for (final TextRunPrimitive p
            in report.pageAt(i).frame.primitives.whereType<TextRunPrimitive>())
          if (p.elementId == elementId)
            p.lines.map((TextLine l) => l.text).join(),
    ];
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/rendered_menu_example_test.dart`
Expected: FAIL — `rendered_menu_example.dart` / `kSampleMenu` do not exist.

- [ ] **Step 3: Write minimal implementation**

Create `apps/jet_print_playground/lib/rendered_menu_example.dart`:

```dart
/// Real data for the restaurant-menu sample, plus the one-call render through
/// the public engine — the consumer side of the category-grouped picture menu,
/// all through `package:jet_print/jet_print.dart` only.
///
/// Seven dishes across three categories, ordered by category so the group breaks
/// resolve. Each row carries a generated BMP swatch (base64) as its `photo`;
/// the declared schema (`menuSchema.fields`) is passed to the data source so
/// `$F{...}` bindings resolve. The list is `final`, not `const`, because the
/// photo bytes are computed.
library;

import 'package:flutter/widgets.dart' show Locale;
import 'package:jet_print/jet_print.dart';

import 'menu_photo.dart';
import 'menu_sample.dart';

/// A 64×64 generated food swatch (vertical gradient) as base64 — stands in for
/// a real photo while keeping the sample asset-free.
String _photo(int topRgb, int bottomRgb) =>
    gradientBmpBase64(width: 64, height: 64, topRgb: topRgb, bottomRgb: bottomRgb);

/// The sample menu — the source of truth the data source and the tests both
/// read, so the rendered prices and the expected values can never drift.
final List<Map<String, Object?>> kSampleMenu = <Map<String, Object?>>[
  // --- Appetizers ---
  <String, Object?>{
    'category': 'Appetizers',
    'name': 'Bruschetta',
    'description': 'Grilled sourdough, vine tomato, basil, olive oil.',
    'price': 8.00,
    'photo': _photo(0xE8C07A, 0xB6772E),
  },
  <String, Object?>{
    'category': 'Appetizers',
    'name': 'Crispy Calamari',
    'description': 'Lightly fried, lemon aioli, sea salt.',
    'price': 11.00,
    'photo': _photo(0xF0D9A8, 0xC79A4B),
  },
  // --- Mains ---
  <String, Object?>{
    'category': 'Mains',
    'name': 'Margherita Pizza',
    'description': 'San Marzano tomato, fior di latte, basil.',
    'price': 14.00,
    'photo': _photo(0xE7553B, 0x7E1F12),
  },
  <String, Object?>{
    'category': 'Mains',
    'name': 'Spaghetti Carbonara',
    'description': 'Guanciale, pecorino, egg yolk, black pepper.',
    'price': 13.00,
    'photo': _photo(0xF2E2B0, 0xC9A24A),
  },
  <String, Object?>{
    'category': 'Mains',
    'name': 'Grilled Salmon',
    'description': 'Seasonal greens, lemon-dill butter.',
    'price': 19.00,
    'photo': _photo(0xF1A07A, 0xB24A36),
  },
  // --- Desserts ---
  <String, Object?>{
    'category': 'Desserts',
    'name': 'Tiramisu',
    'description': 'Espresso-soaked savoiardi, mascarpone, cocoa.',
    'price': 7.00,
    'photo': _photo(0xC9A07A, 0x5E3B22),
  },
  <String, Object?>{
    'category': 'Desserts',
    'name': 'Pistachio Gelato',
    'description': 'House-churned, Sicilian pistachio.',
    'price': 6.00,
    'photo': _photo(0xCFE0A0, 0x6F8E3C),
  },
];

/// The sample menu as an in-memory data source, matching [menuSchema]. The
/// declared `fields:` is passed so `$F{...}` bindings (incl. the photo) resolve.
JetDataSource menuDataSource() =>
    JetInMemoryDataSource(kSampleMenu, fields: menuSchema.fields);

/// Renders [menuSampleDefinition] over [menuDataSource] through the native
/// [JetReportEngine.renderDefinition] path — the same single call the designer
/// tab's preview uses. [definition] defaults to the bundled sample so the
/// designer can pass its LIVE edits; [source] defaults to the sample data.
RenderedReport renderMenuDefinition({
  ReportDefinition? definition,
  JetDataSource? source,
  List<JetFontFamily> fonts = const <JetFontFamily>[],
}) =>
    JetReportEngine().renderDefinition(
      definition ?? menuSampleDefinition(),
      source ?? menuDataSource(),
      options: RenderOptions(
        locale: const Locale('en'),
        knownFields: _schemaFieldNames(menuSchema.fields),
        fonts: fonts,
      ),
    );

/// Every field name the schema declares (top-level and nested), so all `$F{...}`
/// bindings are recognized.
Set<String> _schemaFieldNames(List<FieldDef> fields) => <String>{
      for (final FieldDef f in fields) ...<String>{
        f.name,
        ..._schemaFieldNames(f.fields),
      },
    };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/rendered_menu_example_test.dart`
Expected: PASS (6 tests). In particular `each item resolves its bound photo to real image bytes` proves the `FieldImageSource('photo')` → bytes path works for every row.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/rendered_menu_example.dart apps/jet_print_playground/test/rendered_menu_example_test.dart
git commit -m "feat(playground): menu sample data + render entry"
```

---

### Task 4: Wire the Menu tab + localization

Add the tab to the shell, localize its label in all three ARBs, regenerate the localizations, and update the consumer smoke test (six → seven tabs).

**Files:**
- Modify: `apps/jet_print_playground/lib/l10n/app_en.arb` (add `tabMenu` + `@tabMenu`)
- Modify: `apps/jet_print_playground/lib/l10n/app_tr.arb` (add `tabMenu`)
- Modify: `apps/jet_print_playground/lib/l10n/app_de.arb` (add `tabMenu`)
- Modify: `apps/jet_print_playground/lib/l10n/app_localizations*.dart` (regenerated via `flutter gen-l10n`)
- Modify: `apps/jet_print_playground/lib/main.dart` (imports + new `ShadTab`)
- Modify: `apps/jet_print_playground/test/app_consumes_library_test.dart` (six → seven; add `'Menu'`)

**Interfaces:**
- Consumes: `menuSampleDefinition()`, `menuSchema` (Task 2); `renderMenuDefinition(...)` (Task 3); generated `AppLocalizations.tabMenu`.

- [ ] **Step 1: Write the failing test**

Edit `apps/jet_print_playground/test/app_consumes_library_test.dart`.

Change the test name and label list in the second `testWidgets` block. Replace:

```dart
  testWidgets(
    'the shell shows six live designer tabs and no placeholder',
```

with:

```dart
  testWidgets(
    'the shell shows seven live designer tabs and no placeholder',
```

and replace the label list:

```dart
      for (final String label in const <String>[
        'Empty',
        'Invoice',
        'Label',
        'Barcode',
        'Packing slip',
        'List',
      ]) {
```

with:

```dart
      for (final String label in const <String>[
        'Empty',
        'Invoice',
        'Label',
        'Barcode',
        'Packing slip',
        'Payroll',
        'List',
        'Menu',
      ]) {
```

(The original list omitted `Payroll`; including it here keeps the smoke test honest about every tab.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app_consumes_library_test.dart`
Expected: FAIL — no `ShadTab` with label `Menu` (and the `Payroll` assertion now also runs); `AppLocalizations.tabMenu` may not yet exist (compile error) until Steps 3–4.

- [ ] **Step 3: Add the localized labels**

In `apps/jet_print_playground/lib/l10n/app_en.arb`, immediately before the `"comingSoon"` entry, add:

```json
  "tabMenu": "Menu",
  "@tabMenu": {
    "description": "Tab label for the restaurant-menu picture demo."
  },

```

In `apps/jet_print_playground/lib/l10n/app_tr.arb`, change the `"tabPayroll"` line to add a following `tabMenu` line (keep the trailing `comingSoon` last):

```json
  "tabPayroll": "Bordro",
  "tabMenu": "Menü",
  "comingSoon": "Yakında"
```

In `apps/jet_print_playground/lib/l10n/app_de.arb`, likewise:

```json
  "tabPayroll": "Gehaltsabrechnung",
  "tabMenu": "Speisekarte",
  "comingSoon": "Demnächst"
```

- [ ] **Step 4: Regenerate the localizations**

Run: `flutter gen-l10n`
Expected: updates `lib/l10n/app_localizations.dart` and the `_en/_tr/_de` files with a `tabMenu` getter. (If `flutter gen-l10n` reports no config, run `flutter pub get` first — it triggers the same gen-l10n pipeline.)

Verify the getter exists:
Run: `grep -n "tabMenu" lib/l10n/app_localizations.dart`
Expected: a `String get tabMenu;` declaration.

- [ ] **Step 5: Wire the tab in main.dart**

In `apps/jet_print_playground/lib/main.dart`, add the two imports (alphabetically among the existing sample imports):

```dart
import 'menu_sample.dart';
```
```dart
import 'rendered_menu_example.dart';
```

Then add a new `ShadTab` immediately after the `'nested-lists'` tab's closing `),` (the last tab in the `tabs:` list, ending with `child: Text(l10n.tabList),`). Insert:

```dart
                ShadTab<String>(
                  value: 'menu',
                  leading: const Icon(LucideIcons.image, size: 16),
                  expandContent: true,
                  // A live designer over a restaurant menu — dishes grouped by
                  // category, each row a data-bound food picture, with an
                  // embedded header logo (menu_sample.dart). The first sample to
                  // use ImageElement.
                  content: _FillTabHeight(
                    child: _DesignerTab(
                      fonts: fonts,
                      seed: menuSampleDefinition(),
                      dataSchema: menuSchema,
                      renderReport: (ReportDefinition def) =>
                          renderMenuDefinition(definition: def, fonts: fonts),
                    ),
                  ),
                  child: Text(l10n.tabMenu),
                ),
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/app_consumes_library_test.dart`
Expected: PASS — all tab labels (including `Payroll` and `Menu`) are found and no `Coming soon` placeholder remains.

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart \
        apps/jet_print_playground/lib/l10n/ \
        apps/jet_print_playground/test/app_consumes_library_test.dart
git commit -m "feat(playground): wire the Menu picture tab + localization"
```

---

### Task 5: Full-suite verification

Confirm the new sample integrates cleanly with zero analyzer issues and no golden regressions.

**Files:** none (verification only).

- [ ] **Step 1: Analyze the playground**

Run (from `apps/jet_print_playground/`): `flutter analyze`
Expected: "No issues found!" (or no new issues attributable to the added files).

- [ ] **Step 2: Run the full playground test suite**

Run (from `apps/jet_print_playground/`): `flutter test`
Expected: all tests pass, including the four new test files and the updated consumer smoke test. No golden failures (this sample adds no goldens and changes none).

- [ ] **Step 3: (If the repo has root-level arch/golden tests) run them**

Run (from repo root `/Users/ahmeturel/Projects/oss/jet-print`): `flutter test` in any package whose goldens could be affected — here only `apps/jet_print_playground` is touched, so Step 2 covers it. Confirm `git status` shows no unexpected modified golden files.

Expected: clean. If any golden changed, stop and investigate — the design forbids golden changes.

- [ ] **Step 4: Final commit (only if Steps 1–3 produced fixes)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add -A
git commit -m "chore(playground): analyzer/verification fixups for the menu sample"
```

(If Steps 1–3 were already clean, skip this commit.)

---

## Self-Review

**Spec coverage:**
- "First sample to exercise `ImageElement`" → Tasks 2–3 (image element in the detail band + header).
- "Demonstrate both `FieldImageSource` and `BytesImageSource`" → Task 2 (`itemPhoto` field-bound; `brandLogo` embedded bytes); proven in Task 3's render test.
- "Flat data grouped by category" → Task 2 schema + single `GroupLevel` on `$F{category}`; Task 3 contiguous-category data.
- "Photo declared `string`, base64" → Task 2 schema test; Task 3 data.
- "Generated in-code, BMP, no assets, synchronous" → Task 1 generator + tests.
- "New tab + l10n in en/tr/de" → Task 4.
- "Definition test + render test" → Tasks 2 and 3.
- "`flutter analyze` clean, suite green, no golden diffs, public-API only" → Task 5 + Global Constraints.

**Placeholder scan:** No TBD/TODO; every code step contains full content; no "similar to Task N" stand-ins.

**Type consistency:** `gradientBmp`/`gradientBmpBase64` signatures identical across Tasks 1/2/3. Element IDs (`brandLogo`, `itemPhoto`, `itemName`, `itemDesc`, `itemPrice`, `catName`, `item`) match between the definition (Task 2) and the tests (Tasks 2/3). `menuSchema`, `menuSampleDefinition`, `kSampleMenu`, `menuDataSource`, `renderMenuDefinition` referenced consistently. `FieldImageSource.field`, `BytesImageSource.bytes`, `ImagePrimitive{bytes, elementId}`, `JetBoxFit`, `validate(...)` all match the verified public/test-reach-in API.
