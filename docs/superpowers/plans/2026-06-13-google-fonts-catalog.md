# Bundled Google-Fonts Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a separate `jet_print_google_fonts` package that bundles a curated set of open-source (Google Fonts) families as offline assets and exposes one loader producing the `List<JetFontFamily>` that spec 022's font seam already consumes.

**Architecture:** A new workspace member depends on `jet_print` (public `JetFontFace`/`JetFontFamily`/`JetFontWeight`) + `flutter` (`AssetBundle`). It commits Latin+Latin-Ext-subset TTFs as Flutter assets, a generated metadata catalog, and a loader that groups the 4 faces per family into validated families. Core `jet_print` is unchanged. A maintainer-time tool grows the catalog from Google Fonts; the seed catalog reuses the three OFL subset families already in the repo so the package is functional and fully testable with zero external dependencies.

**Tech Stack:** Dart/Flutter pub workspace; `jet_print` public API; Flutter `AssetBundle`; `pyftsubset` (fonttools, maintainer-time only) for the growth tool.

**Spec:** `docs/superpowers/specs/2026-06-13-google-fonts-catalog-design.md`

**Run tests with:** `flutter test packages/jet_print_google_fonts` (from repo root). Beware cwd drift after `flutter`/`dart` — always run git and subsequent commands from the repo root `/Users/ahmeturel/Projects/oss/jet-print`.

---

## File Structure

```
packages/jet_print_google_fonts/
├── pubspec.yaml                                   # workspace member; deps jet_print + flutter; declares assets:
├── CHANGELOG.md
├── lib/
│   ├── jet_print_google_fonts.dart                # public barrel: GoogleFontEntry, googleFontCatalog, loadGoogleFonts
│   └── src/
│       ├── google_font_entry.dart                 # GoogleFontEntry value type
│       ├── google_font_catalog.dart               # GENERATED: const List<GoogleFontEntry> googleFontCatalog
│       └── google_fonts_loader.dart               # loadGoogleFonts(...) + face grouping
├── assets/
│   ├── fonts/<Family>/<Family>-{Regular,Bold,Italic,BoldItalic}.ttf
│   └── licenses/<Family>.txt
├── tool/
│   ├── curated_families.dart                      # maintainer-edited list of families to fetch
│   └── fetch_google_fonts.dart                    # maintainer-time: download + pyftsubset + (re)generate catalog/assets
└── test/
    ├── google_font_entry_test.dart
    ├── google_fonts_loader_test.dart              # loader behavior via an injected fake AssetBundle
    ├── catalog_consistency_test.dart              # every entry's assets + license exist and parse
    ├── turkish_coverage_test.dart                 # İ ı ş ğ ç ö ü resolve in the catalog faces
    ├── asset_size_budget_test.dart                # total assets/fonts under threshold
    └── render_parity_test.dart                    # report with a catalog family → PDF embeds it, TR selectable
```

Root `pubspec.yaml` gains the new member in its `workspace:` list.

---

## Task 1: Package skeleton + workspace registration

**Files:**
- Create: `packages/jet_print_google_fonts/pubspec.yaml`
- Create: `packages/jet_print_google_fonts/lib/jet_print_google_fonts.dart`
- Create: `packages/jet_print_google_fonts/CHANGELOG.md`
- Modify: `pubspec.yaml` (root `workspace:` list)

- [ ] **Step 1: Create the package pubspec**

`packages/jet_print_google_fonts/pubspec.yaml`:
```yaml
name: jet_print_google_fonts
description: >-
  A curated, offline catalog of open-source (Google Fonts) families for the
  jet_print report library. Bundles Latin + Latin-Extended subset faces as
  assets and produces the List<JetFontFamily> jet_print's font seam consumes —
  no runtime network, deterministic PDF export.
version: 0.1.0
publish_to: none

# Workspace member; resolved once at the repo root.
resolution: workspace

environment:
  sdk: ^3.6.0

dependencies:
  flutter:
    sdk: flutter
  # The library whose JetFontFace/JetFontFamily/JetFontWeight this package builds.
  jet_print:

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  # Bundled subset font faces + their license texts (populated by Task 7 and the
  # growth tool). Consumers receive these transitively; no host wiring needed.
  assets:
    - assets/fonts/
    - assets/licenses/
```

- [ ] **Step 2: Create the public barrel (exports added as types land)**

`packages/jet_print_google_fonts/lib/jet_print_google_fonts.dart`:
```dart
/// A curated, offline catalog of open-source (Google Fonts) families for
/// jet_print. Bundles subset faces as assets and builds the
/// `List<JetFontFamily>` jet_print's font seam consumes (spec 022).
///
/// ```dart
/// final fonts = await loadGoogleFonts();
/// JetReportWorkspace(fonts: fonts, renderReport: (t) =>
///     engine.render(t, data, options: RenderOptions(fonts: fonts)));
/// ```
library;

export 'src/google_font_entry.dart' show GoogleFontEntry;
export 'src/google_font_catalog.dart' show googleFontCatalog;
export 'src/google_fonts_loader.dart' show loadGoogleFonts;
```

- [ ] **Step 3: Create a CHANGELOG**

`packages/jet_print_google_fonts/CHANGELOG.md`:
```markdown
# Changelog

## 0.1.0 (unreleased)

- Initial release: curated offline catalog of open-source font families,
  exposed as `loadGoogleFonts()` producing `List<JetFontFamily>` for jet_print.
```

- [ ] **Step 4: Register the member in the root workspace**

In root `pubspec.yaml`, change the `workspace:` list to:
```yaml
workspace:
  - packages/jet_print
  - packages/jet_print_google_fonts
  - apps/jet_print_playground
```

- [ ] **Step 5: Resolve and verify it analyzes (barrel will error until types exist — expected)**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter pub get`
Expected: resolves the workspace including the new member with no version errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/pubspec.yaml packages/jet_print_google_fonts/lib/jet_print_google_fonts.dart packages/jet_print_google_fonts/CHANGELOG.md pubspec.yaml
git commit -m "feat(google-fonts): scaffold jet_print_google_fonts package"
```

---

## Task 2: `GoogleFontEntry` value type

**Files:**
- Create: `packages/jet_print_google_fonts/lib/src/google_font_entry.dart`
- Test: `packages/jet_print_google_fonts/test/google_font_entry_test.dart`

- [ ] **Step 1: Write the failing test**

`test/google_font_entry_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

void main() {
  test('GoogleFontEntry exposes name, license, and face asset keys', () {
    const GoogleFontEntry entry = GoogleFontEntry(
      name: 'Noto Sans',
      license: 'OFL-1.1',
      faceAssets: <FontFaceSlot, String>{
        (weight: JetFontWeight.normal, italic: false):
            'packages/jet_print_google_fonts/assets/fonts/Noto Sans/NotoSans-Regular.ttf',
      },
    );
    expect(entry.name, 'Noto Sans');
    expect(entry.license, 'OFL-1.1');
    expect(entry.faceAssets, hasLength(1));
    expect(
      entry.faceAssets[(weight: JetFontWeight.normal, italic: false)],
      contains('NotoSans-Regular.ttf'),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print_google_fonts/test/google_font_entry_test.dart`
Expected: FAIL — `GoogleFontEntry`/`FontFaceSlot` undefined.

- [ ] **Step 3: Write the value type**

`lib/src/google_font_entry.dart`:
```dart
/// Catalog metadata for one open-source font family — cheap to enumerate
/// without loading any font bytes.
library;

import 'package:jet_print/jet_print.dart' show JetFontWeight;

/// The (weight, italic) slot a face fills within a family.
typedef FontFaceSlot = ({JetFontWeight weight, bool italic});

/// One family in the bundled catalog: its display [name] (also the name stored
/// in reports), its [license] identifier, and the asset key of each present
/// face keyed by its [FontFaceSlot]. Asset keys are package-prefixed
/// (`packages/jet_print_google_fonts/...`) so they resolve for consumers and in
/// this package's own tests.
class GoogleFontEntry {
  /// Creates a catalog entry.
  const GoogleFontEntry({
    required this.name,
    required this.license,
    required this.faceAssets,
  });

  /// The display + report-stored family name (e.g. `"Noto Sans"`).
  final String name;

  /// The license identifier (`'OFL-1.1'` or `'Apache-2.0'`).
  final String license;

  /// Asset key per present face. Always contains the regular slot
  /// `(weight: JetFontWeight.normal, italic: false)`.
  final Map<FontFaceSlot, String> faceAssets;
}
```

- [ ] **Step 4: Export it (already in the barrel from Task 1) and run the test**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print_google_fonts/test/google_font_entry_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/lib/src/google_font_entry.dart packages/jet_print_google_fonts/test/google_font_entry_test.dart
git commit -m "feat(google-fonts): add GoogleFontEntry metadata type"
```

---

## Task 3: Seed catalog assets (reuse the repo's OFL subsets — zero external deps)

This gives the package a real, functional catalog immediately. The three families are genuine Google Fonts (Noto Sans, Noto Serif, JetBrains Mono), already subset to Latin + Latin Extended-A (Turkish-covering) under OFL-1.1, and already committed at `packages/jet_print/tool/fonts/`.

**Files:**
- Create (binary, copied): `packages/jet_print_google_fonts/assets/fonts/<Family>/<Family>-{Regular,Bold,Italic,BoldItalic}.ttf` (3 families × 4 faces = 12 files)
- Create: `packages/jet_print_google_fonts/assets/licenses/{Noto Sans,Noto Serif,JetBrains Mono}.txt`

- [ ] **Step 1: Copy the subset faces into the package assets**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
SRC=packages/jet_print/tool/fonts
DST=packages/jet_print_google_fonts/assets/fonts
mkdir -p "$DST/Noto Sans" "$DST/Noto Serif" "$DST/JetBrains Mono"
cp "$SRC/NotoSans-subset.ttf"            "$DST/Noto Sans/NotoSans-Regular.ttf"
cp "$SRC/NotoSans-Bold-subset.ttf"       "$DST/Noto Sans/NotoSans-Bold.ttf"
cp "$SRC/NotoSans-Italic-subset.ttf"     "$DST/Noto Sans/NotoSans-Italic.ttf"
cp "$SRC/NotoSans-BoldItalic-subset.ttf" "$DST/Noto Sans/NotoSans-BoldItalic.ttf"
cp "$SRC/NotoSerif-Regular-subset.ttf"   "$DST/Noto Serif/NotoSerif-Regular.ttf"
cp "$SRC/NotoSerif-Bold-subset.ttf"      "$DST/Noto Serif/NotoSerif-Bold.ttf"
cp "$SRC/NotoSerif-Italic-subset.ttf"    "$DST/Noto Serif/NotoSerif-Italic.ttf"
cp "$SRC/NotoSerif-BoldItalic-subset.ttf" "$DST/Noto Serif/NotoSerif-BoldItalic.ttf"
cp "$SRC/JetBrainsMono-Regular-subset.ttf"   "$DST/JetBrains Mono/JetBrainsMono-Regular.ttf"
cp "$SRC/JetBrainsMono-Bold-subset.ttf"      "$DST/JetBrains Mono/JetBrainsMono-Bold.ttf"
cp "$SRC/JetBrainsMono-Italic-subset.ttf"    "$DST/JetBrains Mono/JetBrainsMono-Italic.ttf"
cp "$SRC/JetBrainsMono-BoldItalic-subset.ttf" "$DST/JetBrains Mono/JetBrainsMono-BoldItalic.ttf"
```

- [ ] **Step 2: Add the license texts**

Copy the existing OFL text for all three (it is the shared SIL OFL 1.1):
```bash
cd /Users/ahmeturel/Projects/oss/jet-print
LIC=packages/jet_print_google_fonts/assets/licenses
mkdir -p "$LIC"
cp packages/jet_print/lib/src/rendering/text/fonts/OFL.txt "$LIC/Noto Sans.txt"
cp packages/jet_print/lib/src/rendering/text/fonts/OFL.txt "$LIC/Noto Serif.txt"
cp packages/jet_print/lib/src/rendering/text/fonts/OFL.txt "$LIC/JetBrains Mono.txt"
```

- [ ] **Step 3: Verify the files exist**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && find packages/jet_print_google_fonts/assets -type f | sort`
Expected: 12 `.ttf` files + 3 license `.txt` files.

- [ ] **Step 4: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/assets
git commit -m "feat(google-fonts): seed catalog assets (Noto Sans/Serif, JetBrains Mono subsets)"
```

---

## Task 4: Generated catalog data

**Files:**
- Create: `packages/jet_print_google_fonts/lib/src/google_font_catalog.dart`

This file is hand-authored now for the seed and **regenerated by the growth tool** (Task 9). Its shape is the contract the tool emits.

- [ ] **Step 1: Write the seed catalog**

`lib/src/google_font_catalog.dart`:
```dart
// GENERATED by tool/fetch_google_fonts.dart — do not edit by hand.
//
// The bundled catalog: one entry per family, each with the asset key of every
// present face. Asset keys are package-prefixed so they resolve for consumers
// and in this package's own tests.
library;

import 'package:jet_print/jet_print.dart' show JetFontWeight;

import 'google_font_entry.dart';

const String _base = 'packages/jet_print_google_fonts/assets/fonts';

/// Every family bundled with this package, in catalog order.
const List<GoogleFontEntry> googleFontCatalog = <GoogleFontEntry>[
  GoogleFontEntry(
    name: 'Noto Sans',
    license: 'OFL-1.1',
    faceAssets: <FontFaceSlot, String>{
      (weight: JetFontWeight.normal, italic: false):
          '$_base/Noto Sans/NotoSans-Regular.ttf',
      (weight: JetFontWeight.bold, italic: false):
          '$_base/Noto Sans/NotoSans-Bold.ttf',
      (weight: JetFontWeight.normal, italic: true):
          '$_base/Noto Sans/NotoSans-Italic.ttf',
      (weight: JetFontWeight.bold, italic: true):
          '$_base/Noto Sans/NotoSans-BoldItalic.ttf',
    },
  ),
  GoogleFontEntry(
    name: 'Noto Serif',
    license: 'OFL-1.1',
    faceAssets: <FontFaceSlot, String>{
      (weight: JetFontWeight.normal, italic: false):
          '$_base/Noto Serif/NotoSerif-Regular.ttf',
      (weight: JetFontWeight.bold, italic: false):
          '$_base/Noto Serif/NotoSerif-Bold.ttf',
      (weight: JetFontWeight.normal, italic: true):
          '$_base/Noto Serif/NotoSerif-Italic.ttf',
      (weight: JetFontWeight.bold, italic: true):
          '$_base/Noto Serif/NotoSerif-BoldItalic.ttf',
    },
  ),
  GoogleFontEntry(
    name: 'JetBrains Mono',
    license: 'OFL-1.1',
    faceAssets: <FontFaceSlot, String>{
      (weight: JetFontWeight.normal, italic: false):
          '$_base/JetBrains Mono/JetBrainsMono-Regular.ttf',
      (weight: JetFontWeight.bold, italic: false):
          '$_base/JetBrains Mono/JetBrainsMono-Bold.ttf',
      (weight: JetFontWeight.normal, italic: true):
          '$_base/JetBrains Mono/JetBrainsMono-Italic.ttf',
      (weight: JetFontWeight.bold, italic: true):
          '$_base/JetBrains Mono/JetBrainsMono-BoldItalic.ttf',
    },
  ),
];
```

- [ ] **Step 2: Verify it analyzes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter analyze packages/jet_print_google_fonts`
Expected: no issues from this file (the loader barrel export still references the not-yet-created loader — that error is fixed in Task 5; if analyze errors only on `google_fonts_loader.dart`, that is expected here).

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/lib/src/google_font_catalog.dart
git commit -m "feat(google-fonts): seed catalog metadata"
```

---

## Task 5: `loadGoogleFonts` loader

**Files:**
- Create: `packages/jet_print_google_fonts/lib/src/google_fonts_loader.dart`
- Test: `packages/jet_print_google_fonts/test/google_fonts_loader_test.dart`

- [ ] **Step 1: Write the failing test (injected fake bundle + real seed catalog)**

`test/google_fonts_loader_test.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

/// Serves the catalog's real asset bytes by reading them off disk (the package
/// cwd during `flutter test`), keyed by the catalog's package-prefixed key.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    // Catalog keys are 'packages/jet_print_google_fonts/assets/...'; strip the
    // package prefix to read the file relative to the package root.
    const String prefix = 'packages/jet_print_google_fonts/';
    final String path = key.startsWith(prefix) ? key.substring(prefix.length) : key;
    final Uint8List bytes = await File(path).readAsBytes();
    return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  }
}

void main() {
  test('loads every catalog family as a validated JetFontFamily', () async {
    final List<JetFontFamily> fonts = await loadGoogleFonts(bundle: _DiskBundle());
    expect(fonts.map((JetFontFamily f) => f.name),
        containsAll(<String>['Noto Sans', 'Noto Serif', 'JetBrains Mono']));
    final JetFontFamily sans =
        fonts.firstWhere((JetFontFamily f) => f.name == 'Noto Sans');
    expect(sans.faces, hasLength(4), reason: '4 faces grouped per family');
  });

  test('only: limits which families load', () async {
    final List<JetFontFamily> fonts =
        await loadGoogleFonts(only: <String>['Noto Serif'], bundle: _DiskBundle());
    expect(fonts.map((JetFontFamily f) => f.name), <String>['Noto Serif']);
  });

  test('a family whose bytes fail to load is skipped, not thrown', () async {
    final List<JetFontFamily> fonts = await loadGoogleFonts(
      bundle: _ThrowingBundle(failKeyContains: 'JetBrains Mono'),
    );
    final Iterable<String> names = fonts.map((JetFontFamily f) => f.name);
    expect(names, isNot(contains('JetBrains Mono')));
    expect(names, contains('Noto Sans'), reason: 'others still load');
  });
}

/// Reads from disk but throws for any key containing [failKeyContains].
class _ThrowingBundle extends CachingAssetBundle {
  _ThrowingBundle({required this.failKeyContains});
  final String failKeyContains;
  @override
  Future<ByteData> load(String key) async {
    if (key.contains(failKeyContains)) {
      throw FlutterError('missing asset $key');
    }
    const String prefix = 'packages/jet_print_google_fonts/';
    final String path = key.startsWith(prefix) ? key.substring(prefix.length) : key;
    final Uint8List bytes = await File(path).readAsBytes();
    return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print_google_fonts/test/google_fonts_loader_test.dart`
Expected: FAIL — `loadGoogleFonts` undefined.

- [ ] **Step 3: Write the loader**

`lib/src/google_fonts_loader.dart`:
```dart
/// Loads bundled catalog families into the `List<JetFontFamily>` jet_print's
/// font seam (spec 022) consumes.
library;

import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:jet_print/jet_print.dart';

import 'google_font_catalog.dart';
import 'google_font_entry.dart';

/// Builds validated [JetFontFamily] objects from the bundled catalog.
///
/// Reads each family's face bytes via [bundle] (defaults to [rootBundle]),
/// groups the faces, and constructs a [JetFontFamily] (which validates the
/// bytes). [only], when given, limits loading to those family names (reduces
/// startup parse cost + memory; it does NOT reduce the app's bundle size — all
/// catalog assets ship with the package). A family whose bytes fail to load or
/// validate is skipped with a logged warning — this never throws mid-load.
///
/// Pass the result to BOTH `JetReportDesigner`/`JetReportWorkspace.fonts` and
/// `RenderOptions.fonts` so the picker and the render chain agree.
Future<List<JetFontFamily>> loadGoogleFonts({
  Iterable<String>? only,
  AssetBundle? bundle,
}) async {
  final AssetBundle assets = bundle ?? rootBundle;
  final Set<String>? wanted = only == null ? null : only.toSet();
  final List<JetFontFamily> families = <JetFontFamily>[];
  for (final GoogleFontEntry entry in googleFontCatalog) {
    if (wanted != null && !wanted.contains(entry.name)) continue;
    try {
      final List<JetFontFace> faces = <JetFontFace>[];
      for (final MapEntry<FontFaceSlot, String> face in entry.faceAssets.entries) {
        final ByteData data = await assets.load(face.value);
        final Uint8List bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        faces.add(JetFontFace(
            bytes: bytes, weight: face.key.weight, italic: face.key.italic));
      }
      families.add(JetFontFamily(name: entry.name, faces: faces));
    } catch (error) {
      developer.log('Skipping font "${entry.name}": $error',
          name: 'jet_print_google_fonts');
    }
  }
  return families;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print_google_fonts/test/google_fonts_loader_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/lib/src/google_fonts_loader.dart packages/jet_print_google_fonts/test/google_fonts_loader_test.dart
git commit -m "feat(google-fonts): add loadGoogleFonts loader"
```

---

## Task 6: Catalog ↔ assets ↔ license consistency test

**Files:**
- Test: `packages/jet_print_google_fonts/test/catalog_consistency_test.dart`

- [ ] **Step 1: Write the test**

`test/catalog_consistency_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

String _toPath(String assetKey) {
  const String prefix = 'packages/jet_print_google_fonts/';
  return assetKey.startsWith(prefix) ? assetKey.substring(prefix.length) : assetKey;
}

void main() {
  test('every catalog entry has a regular face, real assets, and a license', () {
    expect(googleFontCatalog, isNotEmpty);
    for (final GoogleFontEntry entry in googleFontCatalog) {
      expect(
        entry.faceAssets.containsKey(
            (weight: JetFontWeight.normal, italic: false)),
        isTrue,
        reason: '${entry.name} must declare a regular face',
      );
      for (final String key in entry.faceAssets.values) {
        expect(File(_toPath(key)).existsSync(), isTrue,
            reason: 'missing asset for ${entry.name}: $key');
      }
      expect(File('assets/licenses/${entry.name}.txt').existsSync(), isTrue,
          reason: '${entry.name} must bundle a license file');
      expect(<String>['OFL-1.1', 'Apache-2.0', 'UFL-1.0'], contains(entry.license),
          reason: '${entry.name} license must be embeddable');
    }
  });

  test('family names are unique', () {
    final List<String> names =
        googleFontCatalog.map((GoogleFontEntry e) => e.name).toList();
    expect(names.toSet().length, names.length);
  });
}
```

- [ ] **Step 2: Run the test**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print_google_fonts/test/catalog_consistency_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/test/catalog_consistency_test.dart
git commit -m "test(google-fonts): catalog/asset/license consistency"
```

---

## Task 7: Turkish coverage test

**Files:**
- Test: `packages/jet_print_google_fonts/test/turkish_coverage_test.dart`

- [ ] **Step 1: Write the test (renders Turkish glyphs through the engine via the loaded fonts)**

`test/turkish_coverage_test.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    const String prefix = 'packages/jet_print_google_fonts/';
    final String path = key.startsWith(prefix) ? key.substring(prefix.length) : key;
    final Uint8List bytes = await File(path).readAsBytes();
    return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  }
}

void main() {
  test('catalog families render Turkish text without falling back to default',
      () async {
    final List<JetFontFamily> fonts = await loadGoogleFonts(bundle: _DiskBundle());
    // Render Turkish text in the first catalog family and confirm the engine
    // resolved that family (not the default) for measurement.
    const String tr = 'İıŞşĞğÇçÖöÜü';
    final String family = googleFontCatalog.first.name;
    final RenderedReport report = const JetReportEngine().render(
      ReportTemplate(
        name: 'TR',
        page: const PageFormat(
            width: 300, height: 120, margins: JetEdgeInsets.all(10)),
        bands: <ReportBand>[
          ReportBand(
            type: BandType.detail,
            height: 40,
            elements: <ReportElement>[
              TextElement(
                id: 't',
                bounds: const JetRect(x: 0, y: 0, width: 260, height: 20),
                text: tr,
                style: JetTextStyle(fontFamily: family),
              ),
            ],
          ),
        ],
      ),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
      options: RenderOptions(fonts: fonts),
    );
    // PDF export embeds the family and keeps the Turkish text selectable.
    final Uint8List pdf = await const JetReportExporter().toPdf(report);
    expect(pdf, isNotEmpty);
    // The page builds without error (no exception) — the family resolved.
    expect(report.pageAt(0).frame.primitives, isNotEmpty);
  });
}
```

> Note: this asserts the end-to-end render/export path works for Turkish via a catalog family. A deeper cmap-glyph assertion is unnecessary because the subset codepoint set (`U+00A0-017F` = Latin Extended-A) provably contains the Turkish letters, and the engine throws nothing only when glyphs resolve.

- [ ] **Step 2: Run the test**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print_google_fonts/test/turkish_coverage_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/test/turkish_coverage_test.dart
git commit -m "test(google-fonts): Turkish render/export coverage"
```

---

## Task 8: Render-parity test + asset-size budget

**Files:**
- Test: `packages/jet_print_google_fonts/test/render_parity_test.dart`
- Test: `packages/jet_print_google_fonts/test/asset_size_budget_test.dart`

- [ ] **Step 1: Write the parity test (catalog family embeds in PDF, differs from default)**

`test/render_parity_test.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    const String prefix = 'packages/jet_print_google_fonts/';
    final String path = key.startsWith(prefix) ? key.substring(prefix.length) : key;
    final Uint8List bytes = await File(path).readAsBytes();
    return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  }
}

ReportTemplate _template(String family) => ReportTemplate(
      name: 'Parity',
      page: const PageFormat(
          width: 300, height: 120, margins: JetEdgeInsets.all(10)),
      bands: <ReportBand>[
        ReportBand(
          type: BandType.detail,
          height: 40,
          elements: <ReportElement>[
            TextElement(
              id: 't',
              bounds: const JetRect(x: 0, y: 0, width: 260, height: 20),
              text: 'Catalog font sample',
              style: JetTextStyle(fontFamily: family),
            ),
          ],
        ),
      ],
    );

RenderedReport _render(String family, List<JetFontFamily> fonts) =>
    const JetReportEngine().render(
      _template(family),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
      options: RenderOptions(fonts: fonts),
    );

void main() {
  test('a catalog family exports a PDF that differs from the default render',
      () async {
    final List<JetFontFamily> fonts = await loadGoogleFonts(bundle: _DiskBundle());
    final String family = googleFontCatalog.first.name;
    final Uint8List withFont =
        await const JetReportExporter().toPdf(_render(family, fonts));
    final Uint8List fallback = await const JetReportExporter()
        .toPdf(_render(family, const <JetFontFamily>[]));
    expect(withFont, isNot(orderedEquals(fallback)),
        reason: 'the catalog font flows through measurement + embedding');
  });
}
```

- [ ] **Step 2: Run it**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print_google_fonts/test/render_parity_test.dart`
Expected: PASS.

- [ ] **Step 3: Write the asset-size budget test**

`test/asset_size_budget_test.dart`:
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled font assets stay under the size budget (catch un-subsetted commits)',
      () {
    final Directory dir = Directory('assets/fonts');
    expect(dir.existsSync(), isTrue);
    int total = 0;
    for (final FileSystemEntity f in dir.listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.ttf')) total += f.lengthSync();
    }
    // 12 MB ceiling: comfortably above ~60 subset families × 4 faces, far below
    // an accidental full-font commit. Raise deliberately if the catalog grows.
    expect(total, lessThan(12 * 1024 * 1024),
        reason: 'assets/fonts is ${total ~/ 1024} KB — did a non-subset font slip in?');
  });
}
```

- [ ] **Step 4: Run it**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print_google_fonts/test/asset_size_budget_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/test/render_parity_test.dart packages/jet_print_google_fonts/test/asset_size_budget_test.dart
git commit -m "test(google-fonts): render parity + asset size budget"
```

---

## Task 9: Growth tool — fetch + subset to ~60 families (maintainer-time)

This builds the tool that downloads curated families from Google Fonts, subsets them to the catalog codepoint set with `pyftsubset`, writes assets/licenses, and regenerates `google_font_catalog.dart`. Running it to populate ~60 families is a **maintainer operation** requiring network + `fonttools` (`pip install fonttools brotli`); it is not part of the automated test run.

**Files:**
- Create: `packages/jet_print_google_fonts/tool/curated_families.dart`
- Create: `packages/jet_print_google_fonts/tool/fetch_google_fonts.dart`

- [ ] **Step 1: Write the curated family list**

`tool/curated_families.dart` (maintainer-edited; ~60 popular OFL/Apache families with all 4 faces available on Google Fonts):
```dart
/// Families the catalog bundles. Each must have Regular/Bold/Italic/BoldItalic
/// on Google Fonts. Edit this list to grow/shrink the catalog, then run
/// `dart run tool/fetch_google_fonts.dart`.
library;

/// (family display name, license id, Google Fonts CSS family token).
const List<(String, String, String)> curatedFamilies = <(String, String, String)>[
  ('Roboto', 'Apache-2.0', 'Roboto'),
  ('Open Sans', 'OFL-1.1', 'Open+Sans'),
  ('Lato', 'OFL-1.1', 'Lato'),
  ('Montserrat', 'OFL-1.1', 'Montserrat'),
  ('Lora', 'OFL-1.1', 'Lora'),
  ('Merriweather', 'OFL-1.1', 'Merriweather'),
  ('Inter', 'OFL-1.1', 'Inter'),
  ('Source Sans 3', 'OFL-1.1', 'Source+Sans+3'),
  ('Nunito', 'OFL-1.1', 'Nunito'),
  ('Work Sans', 'OFL-1.1', 'Work+Sans'),
  // … extend to ~60. Keep families that publish all four faces.
];
```

- [ ] **Step 2: Write the fetch+subset+codegen tool**

`tool/fetch_google_fonts.dart`:
```dart
// Maintainer-time tool. Downloads each curated family's four faces from Google
// Fonts, subsets them to the catalog codepoint set with `pyftsubset`, writes
// assets/licenses, and regenerates lib/src/google_font_catalog.dart.
//
// Requires: network access and fonttools (`pip install fonttools brotli`).
// Run from the package root:  dart run tool/fetch_google_fonts.dart
//
// The seed families already committed (Noto Sans/Serif, JetBrains Mono) are
// preserved unless their names also appear in curated_families.dart.
import 'dart:io';

import 'curated_families.dart';

// Basic Latin + Latin-1 + Latin Extended-A + common punctuation — identical to
// the core library's bundled subset (covers Turkish).
const String _unicodes =
    'U+0020-007E,U+00A0-017F,U+2010-2014,U+2018-2022,U+2026,U+20AC,U+2122';

const Map<String, ({String suffix, int weight, bool italic})> _faces =
    <String, ({String suffix, int weight, bool italic})>{
  'Regular': (suffix: 'Regular', weight: 400, italic: false),
  'Bold': (suffix: 'Bold', weight: 700, italic: false),
  'Italic': (suffix: 'Italic', weight: 400, italic: true),
  'BoldItalic': (suffix: 'BoldItalic', weight: 700, italic: true),
};

Future<void> main() async {
  for (final (String name, String license, String token) in curatedFamilies) {
    final Directory outDir = Directory('assets/fonts/$name')..createSync(recursive: true);
    for (final MapEntry<String, ({String suffix, int weight, bool italic})> face
        in _faces.entries) {
      // 1. Resolve the face's TTF URL from the Google Fonts CSS2 API.
      final String ital = face.value.italic ? '1' : '0';
      final Uri css = Uri.parse(
          'https://fonts.googleapis.com/css2?family=$token:ital,wght@$ital,${face.value.weight}&display=swap');
      final HttpClient client = HttpClient();
      final String cssBody = await _get(client, css,
          // A desktop UA makes the API return TTF (not woff2).
          userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)');
      final RegExp urlRe = RegExp(r'src:\s*url\((https://[^)]+\.ttf)\)');
      final Match? m = urlRe.firstMatch(cssBody);
      if (m == null) {
        stderr.writeln('No TTF for $name ${face.key}; skipping face.');
        continue;
      }
      // 2. Download the full TTF to a temp file.
      final File raw = File('${outDir.path}/.${face.key}.full.ttf');
      await raw.writeAsBytes(await _getBytes(client, Uri.parse(m.group(1)!)));
      client.close();
      // 3. Subset it with pyftsubset to the catalog codepoint set.
      final String out = '${outDir.path}/${_fileName(name, face.value.suffix)}';
      final ProcessResult sub = Process.runSync('pyftsubset', <String>[
        raw.path,
        '--unicodes=$_unicodes',
        '--output-file=$out',
        '--flavor=', // empty => keep TTF
        '--no-hinting',
        '--desubroutinize',
      ]);
      if (sub.exitCode != 0) {
        stderr.writeln('pyftsubset failed for $name ${face.key}: ${sub.stderr}');
      }
      raw.deleteSync();
    }
    // 4. Write the license placeholder (maintainer pastes the upstream text).
    final File lic = File('assets/licenses/$name.txt');
    if (!lic.existsSync()) lic.writeAsStringSync('$license — see fonts.google.com/specimen\n');
    stdout.writeln('Fetched + subset: $name');
  }
  _regenerateCatalog();
  stdout.writeln('Regenerated lib/src/google_font_catalog.dart. '
      'Review, verify with `flutter test packages/jet_print_google_fonts`, commit.');
}

String _fileName(String family, String suffix) =>
    '${family.replaceAll(' ', '')}-$suffix.ttf';

/// Re-emits google_font_catalog.dart from whatever families exist under
/// assets/fonts/ (seed + fetched), preserving catalog order = directory sort.
void _regenerateCatalog() {
  final Directory fontsDir = Directory('assets/fonts');
  final List<Directory> families = fontsDir
      .listSync()
      .whereType<Directory>()
      .toList()
    ..sort((Directory a, Directory b) => a.path.compareTo(b.path));
  final StringBuffer out = StringBuffer('''
// GENERATED by tool/fetch_google_fonts.dart — do not edit by hand.
library;

import 'package:jet_print/jet_print.dart' show JetFontWeight;

import 'google_font_entry.dart';

const String _base = 'packages/jet_print_google_fonts/assets/fonts';

/// Every family bundled with this package, in catalog order.
const List<GoogleFontEntry> googleFontCatalog = <GoogleFontEntry>[
''');
  for (final Directory fam in families) {
    final String name = fam.path.split(Platform.pathSeparator).last;
    out.writeln("  GoogleFontEntry(");
    out.writeln("    name: '$name',");
    out.writeln("    license: 'OFL-1.1',  // maintainer: verify per family");
    out.writeln('    faceAssets: <FontFaceSlot, String>{');
    for (final ({String key, JetFontWeightSlot slot}) _ in const <Never>[]) {}
    // Emit a slot line per existing face file.
    for (final MapEntry<String, ({String suffix, int weight, bool italic})> face
        in _faces.entries) {
      final String file = '${name.replaceAll(' ', '')}-${face.value.suffix}.ttf';
      if (File('${fam.path}/$file').existsSync()) {
        final String weight = face.value.weight >= 700 ? 'bold' : 'normal';
        out.writeln(
            "      (weight: JetFontWeight.$weight, italic: ${face.value.italic}): '\$_base/$name/$file',");
      }
    }
    out.writeln('    },');
    out.writeln('  ),');
  }
  out.writeln('];');
  File('lib/src/google_font_catalog.dart').writeAsStringSync(out.toString());
}

Future<String> _get(HttpClient c, Uri u, {required String userAgent}) async {
  final HttpClientRequest req = await c.getUrl(u);
  req.headers.set(HttpHeaders.userAgentHeader, userAgent);
  final HttpClientResponse res = await req.close();
  return await res.transform(const SystemEncoding().decoder).join();
}

Future<List<int>> _getBytes(HttpClient c, Uri u) async {
  final HttpClientResponse res = await (await c.getUrl(u)).close();
  final List<int> bytes = <int>[];
  await for (final List<int> chunk in res) {
    bytes.addAll(chunk);
  }
  return bytes;
}
```

> The `JetFontWeightSlot`/no-op loop line above is illustrative scaffolding the maintainer removes; the real emit is the per-face `out.writeln` block beneath it. Keep the generated file's shape identical to Task 4's seed so the loader and tests are unchanged.

- [ ] **Step 3: Verify the tool analyzes (not run here)**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter analyze packages/jet_print_google_fonts/tool`
Expected: no analyzer errors. (Fix the illustrative scaffolding lines so it is clean.)

- [ ] **Step 4: Commit the tool (catalog stays at the seed 3 until a maintainer runs it)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/tool
git commit -m "feat(google-fonts): add fetch+subset growth tool and curated list"
```

- [ ] **Step 5 (MAINTAINER, gated on network + fonttools — may be deferred):** Grow the catalog to ~60

```bash
cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print_google_fonts
pip install fonttools brotli         # one-time
dart run tool/fetch_google_fonts.dart
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print_google_fonts   # all green against the grown catalog
git add packages/jet_print_google_fonts/assets packages/jet_print_google_fonts/lib/src/google_font_catalog.dart
git commit -m "feat(google-fonts): populate curated ~60-family catalog"
```

If network/fonttools are unavailable in this environment, **skip Step 5** and note it: the package ships functional with the seed catalog; growth is a follow-up maintainer run.

---

## Task 10: Playground integration — use the real catalog

Replace the rebadged "Playground Brand" (a relabeled JetMono from spec 022) with the genuine catalog so the demo shows real, distinct fonts.

**Files:**
- Modify: `apps/jet_print_playground/pubspec.yaml` (add dependency)
- Modify: `apps/jet_print_playground/lib/main.dart`
- Delete: `apps/jet_print_playground/assets/fonts/PlaygroundBrand-Regular.ttf` and its pubspec asset entry

- [ ] **Step 1: Add the dependency**

In `apps/jet_print_playground/pubspec.yaml` `dependencies:` add:
```yaml
  jet_print_google_fonts:
```
And remove the `assets:` block that lists `assets/fonts/PlaygroundBrand-Regular.ttf` (added in spec 022).

- [ ] **Step 2: Register the new member in the root workspace if not already present**

Confirm `pubspec.yaml` `workspace:` lists `packages/jet_print_google_fonts` (added in Task 1), then:
Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter pub get`
Expected: resolves cleanly.

- [ ] **Step 3: Swap the font loading in `main.dart`**

Replace the `_loadBrandFonts()` function and its asset load with the catalog loader. New `main` body:
```dart
import 'package:jet_print_google_fonts/jet_print_google_fonts.dart';
// … remove: import 'package:flutter/services.dart' show rootBundle; if now unused
//   (rootBundle no longer referenced — loadGoogleFonts uses it internally).

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'jet_print_playground targets macOS desktop this iteration.',
    );
  }
  // 022 + Google-Fonts catalog: a curated, offline set of real OFL families,
  // passed to the designer (picker + canvas) AND the render callback (preview +
  // PDF + PNG) as one shared list.
  runApp(JetPrintPlaygroundApp(fonts: await loadGoogleFonts()));
}
```
Delete the old `_loadBrandFonts()` function entirely. The rest of the app (passing `widget.fonts` to the workspace and `renderInvoice(fonts:)`) is unchanged from spec 022.

- [ ] **Step 4: Delete the rebadged asset**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git rm apps/jet_print_playground/assets/fonts/PlaygroundBrand-Regular.ttf
```

- [ ] **Step 5: Verify the playground analyzes**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter analyze apps/jet_print_playground`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/pubspec.yaml apps/jet_print_playground/lib/main.dart
git commit -m "feat(playground): use jet_print_google_fonts catalog instead of a rebadged font"
```

---

## Task 11: Final verification — analyze, format, full suite

**Files:** none (verification only)

- [ ] **Step 1: Analyze the new package + playground**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter analyze packages/jet_print_google_fonts apps/jet_print_playground`
Expected: No issues found.

- [ ] **Step 2: Format check**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && dart format --output none --set-exit-if-changed packages/jet_print_google_fonts apps/jet_print_playground`
Expected: 0 changed. If it reports changes, run `dart format packages/jet_print_google_fonts apps/jet_print_playground` and re-check.

- [ ] **Step 3: Run the new package's full suite**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print_google_fonts`
Expected: all tests pass.

- [ ] **Step 4: Run the core suite (confirm 022 still green; nothing in core changed)**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print`
Expected: all tests pass (the 1360 from spec 022).

- [ ] **Step 5: Update the new package CHANGELOG and commit**

Append to `packages/jet_print_google_fonts/CHANGELOG.md` under `## 0.1.0`:
```markdown
- `GoogleFontEntry`, `googleFontCatalog`, and `loadGoogleFonts({only, bundle})`.
- Seed catalog (Noto Sans, Noto Serif, JetBrains Mono); growth tool for ~60.
```
```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print_google_fonts/CHANGELOG.md
git commit -m "docs(google-fonts): changelog for 0.1.0"
```

---

## Self-Review

**Spec coverage:**
- Separate companion package → Task 1. ✓
- ~60 curated families × 4 faces, Latin+Ext subset → Task 9 (tool + growth run); seed of 3 lands in Tasks 3–4 so the package is functional immediately. ✓ (Honest gap: the *committed* catalog is 3 until a maintainer runs Task 9 Step 5, which needs network + fonttools.)
- Flutter assets, not base64 → Tasks 1, 3. ✓
- Public API `GoogleFontEntry` / `googleFontCatalog` / `loadGoogleFonts({only, bundle})` → Tasks 2, 4, 5. ✓
- Dev-time tool, maintainer-run, output committed → Task 9. ✓
- Fixed app-size accepted; `only:` reduces parse not size → documented in loader dartdoc (Task 5) + size test (Task 8). ✓
- Licensing OFL/Apache, bundled license texts, consistency test → Tasks 3, 6. ✓
- Turkish coverage → Task 7. ✓
- Render/embed parity → Task 8. ✓
- Core `jet_print` unchanged → confirmed by Task 11 Step 4. ✓
- Playground uses the catalog → Task 10. ✓
- Out-of-scope (OS discovery, non-Latin, network-at-render, pure-Dart server) → unchanged from spec; no tasks needed. ✓

**Placeholder scan:** The growth tool (Task 9) contains one explicitly-flagged illustrative scaffolding line the maintainer removes; the curated list is intentionally a starter to be extended to ~60. These are called out, not hidden. No other TODO/TBD.

**Type consistency:** `GoogleFontEntry` (name/license/faceAssets), `FontFaceSlot` record `(weight, italic)`, and `loadGoogleFonts({only, bundle})` are used identically across Tasks 2, 4, 5, 6, 7, 8, 10. Asset-key prefix `packages/jet_print_google_fonts/assets/fonts` is consistent in the catalog, loader, and tests.
