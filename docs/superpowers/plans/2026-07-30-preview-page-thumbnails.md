# Preview Page Thumbnails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a left page-thumbnail rail to `JetReportPreview`, with a toolbar button that shows/hides it.

**Architecture:** A new package-internal `PageThumbnailRail` widget renders a fixed-extent `ListView.builder` of page thumbnails, each painted from a `ui.Picture` recorded through the library's shared `paintFrame` → `CanvasPainter` pipeline and held in an LRU cache that disposes evicted pictures. `JetReportPreview` keeps only the toggle state, the toolbar button, and the `Row` that seats the rail beside the existing page area. The rail is shown by default and auto-hidden below a 700 px body width.

**Tech Stack:** Dart / Flutter, `shadcn_ui` (`ShadTheme`, `ShadIconButton`, `ShadSeparator`), `flutter_test` + `matchesGoldenFile`, `flutter gen-l10n` for localization.

**Design spec:** `docs/superpowers/specs/2026-07-30-preview-page-thumbnails-design.md`

## Global Constraints

- **Working directory:** all `flutter` commands run inside `packages/jet_print` unless a step says otherwise. Run all `git` commands from the repo root `/Users/ahmeturel/Projects/oss/jet-print` — `flutter` leaves the shell inside the package.
- **Constitution IV (NON-NEGOTIABLE):** thumbnails must paint through the shared `paintFrame` → `CanvasPainter` → `FrameCustomPainter` path. No thumbnail-specific element drawing code, no separate low-resolution render path.
- **Encapsulation (SC-007):** library tests are external consumers and may import only `package:jet_print/jet_print.dart`. Any test importing `package:jet_print/src/...` must be added to the white-box allowlist in `test/encapsulation_test.dart`, with a comment saying why.
- **Public API:** the only new public surface is `JetReportPreview.showThumbnails`. `PageThumbnailRail`, `LruCache`, and the sheet-colour helper stay unexported.
- **`ui.Picture` ownership:** every picture the rail records is owned by the rail and disposed exactly once (on eviction, on report change, or in `dispose`). Never blit a picture owned by another widget — undisposed pictures leak on web/CanvasKit.
- **Localization:** every new user-visible string exists in **all three** ARB files (`jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`) and is regenerated with `flutter gen-l10n`. Never hand-edit `jet_print_localizations*.dart`.
- **Golden files:** the four preview goldens (`rendered_invoice_light/dark/page2`, `chart_preview_light`) render at ≤ 600 px wide, below the 700 px breakpoint, so they are expected to stay unchanged. If one fails, STOP and inspect before regenerating.
- **Dart style:** the codebase uses explicit types on locals (`final ShadThemeData theme = ...`), doc comments on every public/library member, and `ValueKey<String>('jet_print.preview.*')` keys for testable widgets. Match it.

---

## File Structure

**Create:**
- `packages/jet_print/lib/src/designer/preview/lru_cache.dart` — a pure-Dart bounded LRU map with an eviction callback. No Flutter imports, so the eviction math is unit-testable in isolation.
- `packages/jet_print/lib/src/designer/preview/preview_sheet.dart` — the shared paper-sheet colour used by both the main preview page and the thumbnails.
- `packages/jet_print/lib/src/designer/preview/page_thumbnail_rail.dart` — the rail widget: list, tile, picture cache wiring, auto-scroll.
- `packages/jet_print/test/designer/preview/lru_cache_test.dart` — white-box unit test.
- `packages/jet_print/test/designer/preview/page_thumbnail_rail_test.dart` — white-box widget test of the rail in isolation.
- `packages/jet_print/test/designer/preview/preview_thumbnails_test.dart` — black-box test of the toggle, defaults and navigation through the public `JetReportPreview`.

**Modify:**
- `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart` — `showThumbnails` parameter, toggle toolbar action, `Row` layout, breakpoint default, sheet-colour reuse.
- `packages/jet_print/lib/src/designer/l10n/jet_print_{en,de,tr}.arb` — two new keys.
- `packages/jet_print/lib/src/designer/l10n/jet_print_localizations{,_en,_de,_tr}.dart` — regenerated, never hand-edited.
- `packages/jet_print/test/encapsulation_test.dart` — allowlist the two new white-box tests.
- `packages/jet_print/test/public_api_test.dart` — cover the new parameter.
- `packages/jet_print/test/designer/preview/preview_localization_{,de_,tr_}test.dart` + `preview_localization_support.dart` — fix-ups for the now-visible rail (800×600 surface).
- `apps/jet_print_playground/test/rendered_invoice_example_test.dart` — fix-ups (900×700 surface).

---

## Task 1: Bounded LRU cache

**Files:**
- Create: `packages/jet_print/lib/src/designer/preview/lru_cache.dart`
- Create: `packages/jet_print/test/designer/preview/lru_cache_test.dart`
- Modify: `packages/jet_print/test/encapsulation_test.dart` (white-box allowlist)

**Interfaces:**
- Consumes: nothing.
- Produces: `class LruCache<K, V>` with `LruCache({required int capacity, required void Function(V value) onEvict})`, `V? operator [](K key)`, `void operator []=(K key, V value)`, `void clear()`, `int get length`, `bool containsKey(K key)`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/preview/lru_cache_test.dart`:

```dart
// White-box unit test for the preview's bounded LRU cache (pure Dart, no
// Flutter): eviction order, access promotion, overwrite and clear all hand the
// dropped value to `onEvict` exactly once, which is what makes the thumbnail
// rail's `ui.Picture` disposal correct.
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/preview/lru_cache.dart';

void main() {
  late List<String> evicted;
  LruCache<int, String> cacheOf(int capacity) => LruCache<int, String>(
        capacity: capacity,
        onEvict: evicted.add,
      );

  setUp(() => evicted = <String>[]);

  test('evicts the least recently inserted entry past capacity', () {
    final LruCache<int, String> cache = cacheOf(2);
    cache[1] = 'a';
    cache[2] = 'b';
    cache[3] = 'c';

    expect(cache.length, 2);
    expect(cache.containsKey(1), isFalse);
    expect(cache[2], 'b');
    expect(cache[3], 'c');
    expect(evicted, <String>['a']);
  });

  test('reading an entry promotes it, so the other one is evicted next', () {
    final LruCache<int, String> cache = cacheOf(2);
    cache[1] = 'a';
    cache[2] = 'b';
    expect(cache[1], 'a'); // promotes 1; 2 is now least-recently used
    cache[3] = 'c';

    expect(cache.containsKey(1), isTrue);
    expect(cache.containsKey(2), isFalse);
    expect(evicted, <String>['b']);
  });

  test('overwriting a key evicts the replaced value', () {
    final LruCache<int, String> cache = cacheOf(2);
    cache[1] = 'a';
    cache[1] = 'a2';

    expect(cache.length, 1);
    expect(cache[1], 'a2');
    expect(evicted, <String>['a']);
  });

  test('a missing key reads null and evicts nothing', () {
    final LruCache<int, String> cache = cacheOf(2);
    expect(cache[7], isNull);
    expect(evicted, isEmpty);
  });

  test('clear evicts every entry and empties the cache', () {
    final LruCache<int, String> cache = cacheOf(3);
    cache[1] = 'a';
    cache[2] = 'b';
    cache.clear();

    expect(cache.length, 0);
    expect(evicted, <String>['a', 'b']);
  });
}
```

- [ ] **Step 2: Allowlist the white-box test**

In `packages/jet_print/test/encapsulation_test.dart`, inside `_isWhiteBoxSeamTest`, add another `||` clause at the end of the existing chain (keep the surrounding style — comment then predicate):

```dart
      // Preview thumbnails (044): the bounded LRU cache behind the thumbnail
      // rail's `ui.Picture` budget is an unexported `src/` pure helper kept
      // Flutter-free so the eviction math is unit-testable; its unit test is
      // white-box (Principle III).
      path.endsWith('/test/designer/preview/lru_cache_test.dart') ||
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/preview/lru_cache_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'jet_print' ... lru_cache.dart` / "Target of URI doesn't exist".

- [ ] **Step 4: Write the implementation**

Create `packages/jet_print/lib/src/designer/preview/lru_cache.dart`:

```dart
/// A bounded least-recently-used map with an eviction hook.
///
/// Kept deliberately Flutter-free (Principle III) so the eviction math is
/// unit-testable in isolation from the widget that owns it. The preview's
/// thumbnail rail uses it to bound how many recorded `ui.Picture`s it holds,
/// disposing whatever falls out.
library;

/// A map of at most [capacity] entries; inserting past that evicts the
/// least-recently-used entry through [onEvict].
///
/// "Used" means read via `[]` or written via `[]=`. [onEvict] is called for a
/// dropped value exactly once: on eviction, on overwrite of an existing key,
/// and for every remaining entry on [clear].
class LruCache<K, V extends Object> {
  /// Creates a cache holding at most [capacity] entries (must be positive),
  /// handing every dropped value to [onEvict].
  LruCache({required this.capacity, required this.onEvict})
      : assert(capacity > 0, 'capacity must be positive');

  /// The maximum number of live entries.
  final int capacity;

  /// Invoked with each value the cache drops, so the owner can release it.
  final void Function(V value) onEvict;

  /// Insertion-ordered: the first key is the least recently used, because both
  /// reads and writes re-insert their entry at the end.
  final Map<K, V> _entries = <K, V>{};

  /// The number of live entries (never above [capacity]).
  int get length => _entries.length;

  /// Whether [key] currently holds a value, without promoting it.
  bool containsKey(K key) => _entries.containsKey(key);

  /// The value for [key], promoting it to most-recently-used; null if absent.
  V? operator [](K key) {
    final V? value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  /// Stores [value] under [key] as most-recently-used, evicting the replaced
  /// value (if any) and then the least-recently-used entries past [capacity].
  void operator []=(K key, V value) {
    final V? replaced = _entries.remove(key);
    if (replaced != null) onEvict(replaced);
    _entries[key] = value;
    while (_entries.length > capacity) {
      final K oldest = _entries.keys.first;
      onEvict(_entries.remove(oldest)!);
    }
  }

  /// Drops every entry, evicting each one.
  void clear() {
    for (final V value in _entries.values) {
      onEvict(value);
    }
    _entries.clear();
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/preview/lru_cache_test.dart test/encapsulation_test.dart`
Expected: PASS (5 LRU cases + the encapsulation invariants).

- [ ] **Step 6: Analyze**

Run: `cd packages/jet_print && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/preview/lru_cache.dart \
        packages/jet_print/test/designer/preview/lru_cache_test.dart \
        packages/jet_print/test/encapsulation_test.dart
git commit -m "feat(preview): bounded LRU cache helper for thumbnail pictures"
```

---

## Task 2: Localization keys for the toggle

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_de.arb`
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_tr.arb`
- Regenerate: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations{,_en,_de,_tr}.dart`
- Test: `packages/jet_print/test/designer/preview/l10n_thumbnail_keys_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `JetPrintLocalizations.previewShowThumbnails` and `JetPrintLocalizations.previewHideThumbnails` (both `String get`), available in en/de/tr.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/preview/l10n_thumbnail_keys_test.dart`:

```dart
// The thumbnail-toggle strings exist in every supported locale (FR-016/FR-017).
// Black-box: reads the strings through the public localization delegate.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// Pumps a minimal localized host under [locale] and returns the resolved
/// strings.
Future<JetPrintLocalizations> _load(WidgetTester tester, Locale locale) async {
  late JetPrintLocalizations l10n;
  await tester.pumpWidget(WidgetsApp(
    color: const Color(0xFF000000),
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: Builder(
      builder: (BuildContext context) {
        l10n = JetPrintLocalizations.of(context);
        return const SizedBox.shrink();
      },
    ),
  ));
  await tester.pumpAndSettle();
  return l10n;
}

void main() {
  testWidgets('the thumbnail-toggle strings resolve in en/de/tr', (
    WidgetTester tester,
  ) async {
    for (final Locale locale in <Locale>[
      const Locale('en'),
      const Locale('de'),
      const Locale('tr'),
    ]) {
      final JetPrintLocalizations l10n = await _load(tester, locale);
      expect(l10n.previewShowThumbnails, isNotEmpty, reason: '$locale show');
      expect(l10n.previewHideThumbnails, isNotEmpty, reason: '$locale hide');
      expect(l10n.previewShowThumbnails, isNot(l10n.previewHideThumbnails),
          reason: '$locale show/hide must differ');
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/preview/l10n_thumbnail_keys_test.dart`
Expected: FAIL to compile — "The getter 'previewShowThumbnails' isn't defined for the class 'JetPrintLocalizations'".

- [ ] **Step 3: Add the keys to the three ARB files**

In `jet_print_en.arb`, immediately after the `previewPrint` block (and before the blank line preceding `"modeDesigner"`):

```json
  "previewShowThumbnails": "Show page thumbnails",
  "@previewShowThumbnails": {
    "description": "Tooltip + accessible name of the report preview's toolbar action that opens the page-thumbnail rail."
  },
  "previewHideThumbnails": "Hide page thumbnails",
  "@previewHideThumbnails": {
    "description": "Tooltip + accessible name of the report preview's toolbar action that closes the page-thumbnail rail."
  },
```

In `jet_print_de.arb`, at the matching position (the German ARB carries values only, no `@` metadata blocks — match whatever shape the neighbouring `previewPrint` entry has in that file):

```json
  "previewShowThumbnails": "Seitenminiaturen einblenden",
  "previewHideThumbnails": "Seitenminiaturen ausblenden",
```

In `jet_print_tr.arb`, at the matching position:

```json
  "previewShowThumbnails": "Sayfa küçük resimlerini göster",
  "previewHideThumbnails": "Sayfa küçük resimlerini gizle",
```

- [ ] **Step 4: Regenerate the localizations**

Run: `cd packages/jet_print && flutter gen-l10n`
Expected: exits 0; `git status` shows `jet_print_localizations.dart`, `_en.dart`, `_de.dart`, `_tr.dart` modified. Do **not** hand-edit those files — if a getter is missing, the ARB entry is wrong.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/preview/l10n_thumbnail_keys_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze**

Run: `cd packages/jet_print && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/l10n packages/jet_print/test/designer/preview/l10n_thumbnail_keys_test.dart
git commit -m "feat(l10n): show/hide page-thumbnail strings for en, de, tr"
```

---

## Task 3: Shared preview sheet colour

**Files:**
- Create: `packages/jet_print/lib/src/designer/preview/preview_sheet.dart`
- Modify: `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart:475-485` (the page `BoxDecoration` colour)

**Interfaces:**
- Consumes: nothing.
- Produces: `Color previewSheetColor(Brightness brightness)` — pure white in light mode, slate-200 (`0xFFE2E8F0`) in dark mode.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/preview/preview_sheet_test.dart`:

```dart
// White-box unit test for the shared preview paper-sheet colour: the main page
// surface and every thumbnail must agree, in both brightnesses.
@TestOn('vm')
library;

import 'dart:ui' show Brightness, Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/preview/preview_sheet.dart';

void main() {
  test('light mode sheets are pure white', () {
    expect(previewSheetColor(Brightness.light), const Color(0xFFFFFFFF));
  });

  test('dark mode sheets are slate-200, not white', () {
    expect(previewSheetColor(Brightness.dark), const Color(0xFFE2E8F0));
  });
}
```

- [ ] **Step 2: Allowlist the white-box test**

In `packages/jet_print/test/encapsulation_test.dart`, extend the clause added in Task 1 so both preview helpers are covered — replace the single `path.endsWith('/test/designer/preview/lru_cache_test.dart') ||` line with:

```dart
      path.endsWith('/test/designer/preview/lru_cache_test.dart') ||
      path.endsWith('/test/designer/preview/preview_sheet_test.dart') ||
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/preview/preview_sheet_test.dart`
Expected: FAIL — "Target of URI doesn't exist: 'package:jet_print/src/designer/preview/preview_sheet.dart'".

- [ ] **Step 4: Write the implementation**

Create `packages/jet_print/lib/src/designer/preview/preview_sheet.dart`:

```dart
/// The paper-sheet colour shared by the preview's page surface and its page
/// thumbnails, so the two can never drift apart.
library;

import 'dart:ui' show Brightness, Color;

/// The on-screen colour of a paper sheet under [brightness].
///
/// Pure white in light mode; a slight gray (slate-200) in dark mode so the
/// sheet does not glare against the dark surround. The exported/printed
/// artifact is always white — that is the render pipeline, not this view.
Color previewSheetColor(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFFFFFFFF);
```

- [ ] **Step 5: Use it from the preview page surface**

In `jet_report_preview.dart`, add the import beside the other relative imports:

```dart
import 'preview_sheet.dart';
```

and replace the page `Container`'s colour (the `decoration:` block around line 475) so the inline conditional and its comment become the shared call:

```dart
                                decoration: BoxDecoration(
                                  color: previewSheetColor(theme.brightness),
                                  border: Border.all(color: colors.border),
                                ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/preview test/encapsulation_test.dart test/goldens/rendered_invoice_test.dart`
Expected: PASS, goldens included — this is a pure extraction, so the painted colours are identical.

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/preview/preview_sheet.dart \
        packages/jet_print/lib/src/designer/preview/jet_report_preview.dart \
        packages/jet_print/test/designer/preview/preview_sheet_test.dart \
        packages/jet_print/test/encapsulation_test.dart
git commit -m "refactor(preview): share the paper-sheet colour helper"
```

---

## Task 4: The `PageThumbnailRail` widget

**Files:**
- Create: `packages/jet_print/lib/src/designer/preview/page_thumbnail_rail.dart`
- Create: `packages/jet_print/test/designer/preview/page_thumbnail_rail_test.dart`
- Modify: `packages/jet_print/test/encapsulation_test.dart` (allowlist)

**Interfaces:**
- Consumes: `LruCache<int, ui.Picture>` (Task 1), `previewSheetColor` (Task 3), `JetPrintLocalizations.previewPageIndicator(int, int)` (existing).
- Produces:
  - `const double kThumbnailRailWidth = 144;`
  - `class PageThumbnailRail extends StatefulWidget` with `PageThumbnailRail({Key? key, required RenderedReport report, required int currentIndex, required ValueChanged<int> onSelect})`.
  - Widget keys: the list is `ValueKey<String>('jet_print.preview.thumbnails.list')`; tile *i* is `ValueKey<String>('jet_print.preview.thumbnail.$i')`.
  - `@visibleForTesting int get debugCachedCount` on the rail's state class `PageThumbnailRailState` (public state class name so tests can reach it via `tester.state`).

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/preview/page_thumbnail_rail_test.dart`:

```dart
// White-box widget test for the preview's page-thumbnail rail (044): tile
// count, selection chrome, tap-to-select, and the bounded picture cache. The
// rail is an unexported `src/` designer-internal seam (the
// expression_editor_dialog precedent), so this test imports it directly.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/preview/page_thumbnail_rail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// 200x100 page, 10pt margins -> 80pt body; 30pt detail bands -> 2 rows/page.
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ReportDefinition _definition() => const ReportDefinition(
      name: 'Quarterly Report',
      page: _page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 30,
              elements: <ReportElement>[
                TextElement(
                  id: 'name',
                  bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
                  text: 'name',
                  expression: r'$F{name}',
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// A report of `rows / 2` pages (2 rows fit per page).
RenderedReport _report({int rows = 6}) =>
    const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < rows; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

Key _tileKey(int index) => ValueKey<String>('jet_print.preview.thumbnail.$index');

Future<void> _pumpRail(
  WidgetTester tester, {
  required RenderedReport report,
  int currentIndex = 0,
  Size size = const Size(400, 600),
  void Function(int)? onSelect,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: Align(
      alignment: Alignment.topLeft,
      child: PageThumbnailRail(
        report: report,
        currentIndex: currentIndex,
        onSelect: onSelect ?? (int _) {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders one tile per page, captioned with the page number', (
    WidgetTester tester,
  ) async {
    await _pumpRail(tester, report: _report()); // 3 pages

    expect(find.byKey(_tileKey(0)), findsOneWidget);
    expect(find.byKey(_tileKey(1)), findsOneWidget);
    expect(find.byKey(_tileKey(2)), findsOneWidget);
    expect(find.byKey(_tileKey(3)), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping a tile reports that page index', (
    WidgetTester tester,
  ) async {
    final List<int> selected = <int>[];
    await _pumpRail(tester, report: _report(), onSelect: selected.add);

    await tester.tap(find.byKey(_tileKey(2)));
    await tester.pumpAndSettle();

    expect(selected, <int>[2]);
  });

  testWidgets('the current page tile is marked selected for a11y', (
    WidgetTester tester,
  ) async {
    await _pumpRail(tester, report: _report(), currentIndex: 1);

    final SemanticsNode node = tester.getSemantics(find.byKey(_tileKey(1)));
    expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
    final SemanticsNode other = tester.getSemantics(find.byKey(_tileKey(0)));
    expect(other.hasFlag(SemanticsFlag.isSelected), isFalse);
  });

  testWidgets('records a picture for the visible tiles', (
    WidgetTester tester,
  ) async {
    await _pumpRail(tester, report: _report());

    final PageThumbnailRailState state =
        tester.state<PageThumbnailRailState>(find.byType(PageThumbnailRail));
    expect(state.debugCachedCount, greaterThan(0));
  });

  testWidgets('the picture cache stays within its cap while scrolling', (
    WidgetTester tester,
  ) async {
    // 120 rows -> 60 pages, far more than the 24-picture cap.
    await _pumpRail(tester, report: _report(rows: 120));
    final PageThumbnailRailState state =
        tester.state<PageThumbnailRailState>(find.byType(PageThumbnailRail));

    for (int i = 0; i < 10; i++) {
      await tester.drag(
        find.byKey(const ValueKey<String>('jet_print.preview.thumbnails.list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(state.debugCachedCount, lessThanOrEqualTo(24));
    }
  });
}
```

Add `import 'package:flutter/semantics.dart';` at the top if `SemanticsFlag`/`SemanticsNode` are not already resolved through `flutter/widgets.dart`.

- [ ] **Step 2: Allowlist the white-box test**

In `packages/jet_print/test/encapsulation_test.dart`, extend the preview clause from Tasks 1/3 with:

```dart
      path.endsWith('/test/designer/preview/page_thumbnail_rail_test.dart') ||
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/preview/page_thumbnail_rail_test.dart`
Expected: FAIL — "Target of URI doesn't exist: 'package:jet_print/src/designer/preview/page_thumbnail_rail.dart'".

- [ ] **Step 4: Write the implementation**

Create `packages/jet_print/lib/src/designer/preview/page_thumbnail_rail.dart`:

```dart
/// The report preview's page-thumbnail rail (044): a lazily-painted, scrollable
/// list of page thumbnails that selects the previewed page.
///
/// Constitution IV (NON-NEGOTIABLE): a thumbnail is the *same* picture the main
/// preview would record — recorded through the shared `paintFrame` →
/// `CanvasPainter` pipeline and blitted through `FrameCustomPainter` at a
/// smaller scale, since a `ui.Picture` is a resolution-independent display
/// list. There is no thumbnail-specific element drawing code.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../rendering/engine/rendered_report.dart';
import '../../rendering/frame/page_frame.dart';
import '../../rendering/paint/canvas_painter.dart';
import '../../rendering/paint/report_painter.dart';
import '../canvas/frame_custom_painter.dart';
import '../l10n/jet_print_localizations.dart';
import 'lru_cache.dart';
import 'preview_sheet.dart';

/// The rail's total width, including the sheet, its padding and the scrollbar
/// gutter. The preview reserves exactly this much when the rail is open.
const double kThumbnailRailWidth = 144;

/// The painted width of one thumbnail sheet.
const double _thumbWidth = 112;

/// The fixed height of the page-number caption under each sheet.
const double _captionHeight = 18;

/// Vertical breathing room below each tile, part of its fixed extent.
const double _tileGap = 10;

/// How many recorded pictures the rail keeps alive at once. Each one also
/// pins any images decoded for that page, so the cap stays modest.
const int _cacheCapacity = 24;

/// A scrollable list of page thumbnails for [report], highlighting
/// [currentIndex] and reporting taps through [onSelect].
///
/// Pages are recorded on demand as their tiles scroll into view and held in a
/// bounded LRU cache, so a long report neither builds every frame up front nor
/// grows an unbounded picture budget.
class PageThumbnailRail extends StatefulWidget {
  /// Creates a thumbnail rail over [report].
  const PageThumbnailRail({
    super.key,
    required this.report,
    required this.currentIndex,
    required this.onSelect,
  });

  /// The rendered report whose pages are listed.
  final RenderedReport report;

  /// The zero-based page currently shown in the preview; its tile is
  /// highlighted and scrolled into view.
  final int currentIndex;

  /// Invoked with the zero-based page index of a tapped thumbnail.
  final ValueChanged<int> onSelect;

  @override
  State<PageThumbnailRail> createState() => PageThumbnailRailState();
}

/// The rail's state. Public (unexported) so widget tests can read
/// [debugCachedCount]; it has no public API beyond that.
class PageThumbnailRailState extends State<PageThumbnailRail> {
  late final LruCache<int, ui.Picture> _pictures = LruCache<int, ui.Picture>(
    capacity: _cacheCapacity,
    onEvict: (ui.Picture picture) => picture.dispose(),
  );

  /// Indices whose record is in flight, so a fast scroll cannot request the
  /// same page twice before the first `await` returns.
  final Set<int> _inFlight = <int>{};

  final ScrollController _controller = ScrollController();

  /// The number of live cached pictures (test seam for the cache cap).
  @visibleForTesting
  int get debugCachedCount => _pictures.length;

  /// The fixed per-tile extent, derived from page 0's aspect ratio. A fixed
  /// extent keeps scrolling O(visible) on a many-page report and makes
  /// scroll-to-index pure arithmetic.
  double get _tileExtent {
    final PageFormat page = widget.report.pageAt(0).frame.page;
    return _thumbWidth * page.height / page.width + _captionHeight + _tileGap;
  }

  @override
  void didUpdateWidget(PageThumbnailRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.report, widget.report)) {
      _pictures.clear();
      _inFlight.clear();
    }
  }

  @override
  void dispose() {
    _pictures.clear();
    _controller.dispose();
    super.dispose();
  }

  /// Records page [index] into a picture through the shared paint pipeline,
  /// then caches it. No-ops while an identical request is in flight; drops the
  /// result if the widget unmounted or the report was swapped meanwhile.
  Future<void> _record(int index) async {
    if (_inFlight.contains(index) || _pictures.containsKey(index)) return;
    _inFlight.add(index);
    final RenderedReport report = widget.report;
    final PageFrame frame = report.pageAt(index).frame;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ReportPainter painter =
        CanvasPainter(ui.Canvas(recorder), report.fonts);
    await paintFrame(frame, painter);
    final ui.Picture picture = recorder.endRecording();
    _inFlight.remove(index);
    if (!mounted || !identical(report, widget.report)) {
      picture.dispose();
      return;
    }
    setState(() => _pictures[index] = picture);
  }

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    return SizedBox(
      width: kThumbnailRailWidth,
      child: ColoredBox(
        color: theme.colorScheme.muted,
        child: ListView.builder(
          key: const ValueKey<String>('jet_print.preview.thumbnails.list'),
          controller: _controller,
          // No list padding: the scroll offset of tile i must stay exactly
          // `i * _tileExtent` for the auto-scroll math.
          padding: EdgeInsets.zero,
          itemExtent: _tileExtent,
          itemCount: widget.report.pageCount,
          itemBuilder: (BuildContext context, int index) {
            final ui.Picture? picture = _pictures[index];
            if (picture == null) {
              // Recording is async and calls setState — schedule it off the
              // build path. `_record` de-duplicates repeated requests.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _record(index);
              });
            }
            return _ThumbnailTile(
              index: index,
              pageCount: widget.report.pageCount,
              page: widget.report.pageAt(index).frame.page,
              picture: picture,
              selected: index == widget.currentIndex,
              onTap: () => widget.onSelect(index),
            );
          },
        ),
      ),
    );
  }
}

/// One thumbnail: a paper sheet painted from [picture] (empty while the record
/// is in flight, matching the main preview), with a page-number caption.
class _ThumbnailTile extends StatelessWidget {
  const _ThumbnailTile({
    required this.index,
    required this.pageCount,
    required this.page,
    required this.picture,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final int pageCount;
  final PageFormat page;
  final ui.Picture? picture;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ShadThemeData theme = ShadTheme.of(context);
    final ShadColorScheme colors = theme.colorScheme;
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
    final double scale = _thumbWidth / page.width;

    return Semantics(
      button: true,
      selected: selected,
      label: l10n.previewPageIndicator(index + 1, pageCount),
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              key: ValueKey<String>('jet_print.preview.thumbnail.$index'),
              width: _thumbWidth,
              height: page.height * scale,
              decoration: BoxDecoration(
                color: previewSheetColor(theme.brightness),
                border: Border.all(
                  color: selected ? colors.primary : colors.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: CustomPaint(
                painter: FrameCustomPainter(
                  picture: picture,
                  scale: scale,
                  revision: index,
                ),
              ),
            ),
            SizedBox(
              height: _captionHeight,
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: selected
                      ? theme.textTheme.small
                      : theme.textTheme.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/preview/page_thumbnail_rail_test.dart test/encapsulation_test.dart`
Expected: PASS (5 rail cases + encapsulation).

If the tile overflows its `itemExtent`, the extent math and the tile's own heights disagree — fix the constants, do **not** wrap the tile in a scroll view.

- [ ] **Step 6: Analyze**

Run: `cd packages/jet_print && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/preview/page_thumbnail_rail.dart \
        packages/jet_print/test/designer/preview/page_thumbnail_rail_test.dart \
        packages/jet_print/test/encapsulation_test.dart
git commit -m "feat(preview): lazily painted page-thumbnail rail widget"
```

---

## Task 5: Wire the rail into the preview, with the toolbar toggle

**Files:**
- Modify: `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart`
- Create: `packages/jet_print/test/designer/preview/preview_thumbnails_test.dart`
- Modify: `packages/jet_print/test/public_api_test.dart`

**Interfaces:**
- Consumes: `PageThumbnailRail`, `kThumbnailRailWidth` (Task 4); `l10n.previewShowThumbnails` / `previewHideThumbnails` (Task 2).
- Produces: `JetReportPreview({..., bool showThumbnails = true})`; toggle button key `ValueKey<String>('jet_print.preview.thumbnails')`; breakpoint constant `const double kThumbnailAutoHideWidth = 700;` (private to the preview file is fine — no other file needs it).

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/preview/preview_thumbnails_test.dart`:

```dart
// The preview's thumbnail rail and its toolbar toggle (044). Black-box: this
// test stands in for an external consumer and imports only the public entry
// point.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

const Key _toggleKey = ValueKey<String>('jet_print.preview.thumbnails');
const Key _listKey = ValueKey<String>('jet_print.preview.thumbnails.list');
Key _tileKey(int index) => ValueKey<String>('jet_print.preview.thumbnail.$index');

ReportDefinition _definition() => const ReportDefinition(
      name: 'Quarterly Report',
      page: _page,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'root/c0',
              type: BandType.detail,
              height: 30,
              elements: <ReportElement>[
                TextElement(
                  id: 'name',
                  bounds: JetRect(x: 0, y: 0, width: 180, height: 16),
                  text: 'name',
                  expression: r'$F{name}',
                ),
              ],
            )),
          ],
        ),
      ),
    );

RenderedReport _report({int rows = 6}) =>
    const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 0; i < rows; i++) <String, Object?>{'name': 'row $i'},
      ]),
    );

Future<void> _pumpPreview(
  WidgetTester tester, {
  Size size = const Size(1000, 700),
  bool showThumbnails = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    home: JetReportPreview(
      report: _report(),
      showThumbnails: showThumbnails,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a wide preview opens with the rail shown', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester);
    expect(find.byKey(_listKey), findsOneWidget);
  });

  testWidgets('the toolbar toggle hides and re-shows the rail', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsNothing);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);
  });

  testWidgets('showThumbnails: false opens hidden, and the toggle still works',
      (WidgetTester tester) async {
    await _pumpPreview(tester, showThumbnails: false);
    expect(find.byKey(_listKey), findsNothing);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);
  });

  testWidgets('a narrow preview opens with the rail auto-hidden', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester, size: const Size(600, 700));
    expect(find.byKey(_listKey), findsNothing);

    // The breakpoint only picks the default; the user can still open it.
    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_listKey), findsOneWidget);
  });

  testWidgets('tapping a thumbnail navigates the preview to that page', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester);
    expect(find.text('Page 1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(_tileKey(2)));
    await tester.pumpAndSettle();

    expect(find.text('Page 3 of 3'), findsOneWidget);
  });

  testWidgets('the toggle carries a state-dependent accessible name', (
    WidgetTester tester,
  ) async {
    await _pumpPreview(tester);
    expect(find.bySemanticsLabel('Hide page thumbnails'), findsOneWidget);

    await tester.tap(find.byKey(_toggleKey));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Show page thumbnails'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Add the public-API test**

Append to `packages/jet_print/test/public_api_test.dart`, next to the existing `JetReportPreview` case:

```dart
  test('JetReportPreview exposes the additive showThumbnails flag (044)', () {
    final RenderedReport report = const JetReportEngine().renderDefinition(
      _flatTextDef(),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );
    expect(JetReportPreview(report: report).showThumbnails, isTrue);
    expect(
      JetReportPreview(report: report, showThumbnails: false).showThumbnails,
      isFalse,
    );
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd packages/jet_print && flutter test test/designer/preview/preview_thumbnails_test.dart test/public_api_test.dart`
Expected: FAIL to compile — "No named parameter with the name 'showThumbnails'".

- [ ] **Step 4: Add the parameter and the state**

In `jet_report_preview.dart`, add the imports:

```dart
import 'page_thumbnail_rail.dart';
```

Add the constructor parameter (after `initialPage`) and its field, documented as an initial value:

```dart
    this.showThumbnails = true,
```

```dart
  /// Whether the page-thumbnail rail is open when the preview first builds
  /// (044). Like [initialPage] this is an **initial value**: the user's later
  /// toggling wins, and a host rebuild never yanks the rail back.
  ///
  /// The rail is auto-hidden on first build when the body is narrower than
  /// 700 logical pixels, so a phone opens on the page itself; the toolbar
  /// toggle still opens it at any width.
  final bool showThumbnails;
```

In `_JetReportPreviewState`, add beside the other view-state fields:

```dart
  /// Whether the thumbnail rail is currently open. Seeded from
  /// [JetReportPreview.showThumbnails] and then owned by the user's toggling.
  late bool _showThumbnails = widget.showThumbnails;

  /// Guards the one-shot narrow-viewport decision, mirroring
  /// [_defaultZoomResolved]: the breakpoint may only *hide* the rail on first
  /// build, never open one the host asked to keep shut.
  bool _thumbnailDefaultResolved = false;

  /// Below this body width the rail is hidden on first build. Sits above the
  /// 600 px golden surfaces and below the toolbar's 880 px scroll breakpoint.
  static const double _thumbnailAutoHideWidth = 700;
```

- [ ] **Step 5: Add the toggle toolbar action**

Give `_ToolbarButton` an `active` flag so it can render pressed — replace its field list and `build` body:

```dart
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.active = false,
  });

  final Key? buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Whether the button's toggle is on; shadcn has no toggle icon button, so
  /// the on-state uses the filled `secondary` variant and the off-state the
  /// usual ghost.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Widget button = active
        ? ShadIconButton.secondary(
            key: buttonKey,
            icon: Icon(icon, size: 16),
            width: 32,
            height: 32,
            padding: EdgeInsets.zero,
            onPressed: onPressed,
          )
        : ShadIconButton.ghost(
            key: buttonKey,
            icon: Icon(icon, size: 16),
            width: 32,
            height: 32,
            padding: EdgeInsets.zero,
            onPressed: onPressed,
          );

    return ShadTooltip(
      builder: (BuildContext context) => Text(label),
      // The tooltip is hover-only; expose it as the button's accessible name
      // too (the glyph alone is not announced) — FR-018.
      child: MergeSemantics(
        child: Semantics(
          label: label,
          button: true,
          child: button,
        ),
      ),
    );
  }
}
```

Then, in `_toolbarActions`, make the toggle the **first** entry, before the page-navigation group:

```dart
    return <Widget>[
      // Thumbnail rail toggle (044) — leading, because it changes what the rest
      // of the page-navigation group operates on.
      _ToolbarButton(
        buttonKey: const ValueKey<String>('jet_print.preview.thumbnails'),
        icon: LucideIcons.panelLeft,
        label: _showThumbnails
            ? l10n.previewHideThumbnails
            : l10n.previewShowThumbnails,
        active: _showThumbnails,
        onPressed: () => setState(() => _showThumbnails = !_showThumbnails),
      ),
      const _Divider(),
      // Page-navigation group — prev / "page X of N" / next. ...
```

- [ ] **Step 6: Seat the rail beside the page area**

In `build`, wrap the existing `Expanded`'s child in an outer `LayoutBuilder` (which sees the **full** body width, before the rail takes its share) and a `Row`. The existing `Semantics` + inner `LayoutBuilder` page area moves under the trailing `Expanded` **unchanged**:

```dart
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints body) {
                  // One-shot narrow default, mirroring the zoom default just
                  // below: a plain field write (no setState), consumed by this
                  // same build.
                  if (!_thumbnailDefaultResolved) {
                    _thumbnailDefaultResolved = true;
                    if (body.maxWidth < _thumbnailAutoHideWidth) {
                      _showThumbnails = false;
                    }
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (_showThumbnails) ...<Widget>[
                        PageThumbnailRail(
                          report: widget.report,
                          currentIndex: _index,
                          onSelect: _goTo,
                        ),
                        const ShadSeparator.vertical(margin: EdgeInsets.zero),
                      ],
                      Expanded(
                        child: Semantics(
                          container: true,
                          label: l10n.previewFitToWidth,
                          child: LayoutBuilder(
                            // ...the existing page-area builder, unchanged...
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
```

`kThumbnailRailWidth` is applied by the rail itself, so nothing else needs to know it.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/preview/preview_thumbnails_test.dart test/public_api_test.dart`
Expected: PASS (6 preview cases + the public-API suite).

- [ ] **Step 8: Analyze**

Run: `cd packages/jet_print && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 9: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/preview/jet_report_preview.dart \
        packages/jet_print/test/designer/preview/preview_thumbnails_test.dart \
        packages/jet_print/test/public_api_test.dart
git commit -m "feat(preview): thumbnail rail with a toolbar show/hide toggle"
```

---

## Task 6: Auto-scroll the rail to the current page

**Files:**
- Modify: `packages/jet_print/lib/src/designer/preview/page_thumbnail_rail.dart`
- Modify: `packages/jet_print/test/designer/preview/preview_thumbnails_test.dart`

**Interfaces:**
- Consumes: `PageThumbnailRail.currentIndex`, `_tileExtent` (Task 4).
- Produces: no new API — behaviour only.

- [ ] **Step 1: Write the failing test**

Append to `packages/jet_print/test/designer/preview/preview_thumbnails_test.dart`. Add the next-button key beside the others at the top of the file:

```dart
const Key _nextKey = ValueKey<String>('jet_print.preview.next');
```

and add this case, plus a taller-report pump helper:

```dart
  testWidgets('navigating from the toolbar scrolls the rail to that page', (
    WidgetTester tester,
  ) async {
    // 60 rows -> 30 pages: far more tiles than fit in a 700pt-tall rail.
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ShadApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: JetReportPreview(report: _report(rows: 60), initialPage: 0),
    ));
    await tester.pumpAndSettle();

    final double before =
        tester.widget<ListView>(find.byKey(_listKey)).controller!.offset;
    expect(before, 0);

    // Walk far enough that the target tile is well below the fold.
    for (int i = 0; i < 20; i++) {
      await tester.tap(find.byKey(_nextKey));
      await tester.pumpAndSettle();
    }

    final double after =
        tester.widget<ListView>(find.byKey(_listKey)).controller!.offset;
    expect(after, greaterThan(before),
        reason: 'the rail should have scrolled to follow the current page');
    expect(find.byKey(_tileKey(20)), findsOneWidget,
        reason: 'the current page tile should be built and visible');
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/preview/preview_thumbnails_test.dart -n "scrolls the rail"`
Expected: FAIL — the offset stays 0 (the rail never follows the selection).

- [ ] **Step 3: Implement the reveal**

In `page_thumbnail_rail.dart`, extend `didUpdateWidget` and add `_revealCurrent`:

```dart
  @override
  void didUpdateWidget(PageThumbnailRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.report, widget.report)) {
      _pictures.clear();
      _inFlight.clear();
    }
    if (oldWidget.currentIndex != widget.currentIndex) {
      // Off the build path: scrolling drives layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealCurrent();
      });
    }
  }

  /// Scrolls the current page's tile into view — centred — unless it is
  /// already fully visible. The offset of tile *i* is exactly
  /// `i * _tileExtent` because the list carries no padding and a fixed extent.
  void _revealCurrent() {
    if (!_controller.hasClients) return;
    final double extent = _tileExtent;
    final double top = widget.currentIndex * extent;
    final ScrollPosition position = _controller.position;
    final double viewport = position.viewportDimension;
    if (top >= position.pixels && top + extent <= position.pixels + viewport) {
      return;
    }
    final double target = (top - (viewport - extent) / 2)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/jet_print && flutter test test/designer/preview`
Expected: PASS — the whole preview test directory, including the rail, toggle and localization files.

- [ ] **Step 5: Analyze**

Run: `cd packages/jet_print && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/preview/page_thumbnail_rail.dart \
        packages/jet_print/test/designer/preview/preview_thumbnails_test.dart
git commit -m "feat(preview): scroll the thumbnail rail to the current page"
```

---

## Task 7: Existing-test fix-ups and full verification

**Files:**
- Modify (as needed): `packages/jet_print/test/designer/preview/preview_localization_support.dart`, `preview_localization_test.dart`, `preview_localization_de_test.dart`, `preview_localization_tr_test.dart`
- Modify (as needed): `apps/jet_print_playground/test/rendered_invoice_example_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: a green repo.

- [ ] **Step 1: Run the full library suite and catalogue the failures**

Run: `cd packages/jet_print && flutter test`
Expected: the new tests pass; some pre-existing preview tests may fail because their 800×600 surface now shows the rail. Typical breakages and their fixes:

- **Ambiguous text finder** (e.g. `find.text('1')` now also matching a thumbnail caption): scope it, e.g.
  ```dart
  find.descendant(
    of: find.byKey(const ValueKey<String>('jet_print.preview.page')),
    matching: find.text('1'),
  )
  ```
  or, when the test is not about the rail at all, pump with `showThumbnails: false`.
- **Off-screen tap targets** on a narrower page area: `await tester.ensureVisible(finder)` before tapping, matching the existing `_openZoomMenu` helper.

Fix each failure at its call site. Do **not** weaken an assertion to make it pass — if a test genuinely covered something the rail changed, say so in the commit message.

- [ ] **Step 2: Verify the goldens did not move**

Run: `cd packages/jet_print && flutter test test/goldens test/rendering/chart_golden_test.dart`
Expected: PASS with **no** regenerated files — those surfaces are 600 px wide, below the 700 px breakpoint, so the rail is auto-hidden.

If a golden fails, STOP. Inspect the failure image under `test/failures/` before doing anything else: a diff confined to the toolbar means the new button shifted the Skia glyph cache (regenerate deliberately with `flutter test --update-goldens <file>` and eyeball the diff); a diff in the page area means the layout change leaked into the page surface, which is a bug in Task 5, not a golden to bless.

- [ ] **Step 3: Run the playground suite**

Run: `cd apps/jet_print_playground && flutter analyze && flutter test`
Expected: PASS. Its preview tests pump at 900×700, so the rail is visible there; apply the same finder-scoping fixes as Step 1 where needed.

- [ ] **Step 4: Run the whole library suite once more**

Run: `cd packages/jet_print && flutter analyze && flutter test`
Expected: "No issues found!" and every test passing. Record the final counts (e.g. "2274 passing") in the commit body.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add -A
git commit -m "test: scope preview finders around the new thumbnail rail"
```

- [ ] **Step 6: GUI walk (manual, by the user)**

Run: `cd apps/jet_print_playground && flutter run -d macos`

Check by hand, since no automated test covers the feel:
1. Open a multi-page demo's preview — the rail is there, thumbnails paint within a beat, page 1 is highlighted.
2. Click thumbnail 3 — the page area follows; the highlight moves.
3. Use the toolbar next/prev past the fold — the rail scrolls to keep the current tile visible.
4. Toggle the button — the rail disappears, the page re-fits to the wider area, the button looks pressed only while the rail is open.
5. Narrow the window under ~700 px — the rail stays as-is (the breakpoint is first-build only, by design); reopening the preview at that width opens without it.
6. Open the 20 000-row "Defter" demo and flick the rail hard — scrolling stays smooth and memory does not climb without bound.

---

## Self-Review Notes

Spec coverage check — every design section maps to a task:

| Spec section | Task |
|---|---|
| Left rail placement, `Row` layout | 5 |
| Rail widget + fixed-extent list + tiles | 4 |
| Shared paint pipeline, no reuse of the main picture | 4 |
| LRU cache with disposal, `_inFlight` coalescing, `debugCachedCount` | 1, 4 |
| Auto-scroll | 6 |
| Toolbar toggle, on-state variant | 5 |
| `showThumbnails` initial-value parameter | 5 |
| Narrow-viewport default (hide-only) | 5 |
| Two l10n keys × en/de/tr via ARB + gen-l10n | 2 |
| Sheet-colour parity between page and thumbnails | 3 |
| Test list (7 behaviours) | 4, 5, 6 |
| Existing-test fix-ups, golden verification | 7 |
| Out of scope (rail keyboard traversal, resizing, grid view, reordering) | not planned — correct |
