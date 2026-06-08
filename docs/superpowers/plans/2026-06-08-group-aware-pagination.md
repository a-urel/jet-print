# Group-aware pagination — Spec 008b Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two opt-in `ReportGroup` flags — `reprintHeaderOnEachPage` (repeat a group's header at the top of a continuation page) and `keepTogether` (move a whole group to a fresh page rather than split it) — to the 008a layout engine.

**Architecture:** Carry group identity into the internal Fill→Layout IR via `FilledBand.group`. In the layouter, pre-measure every band once, maintain a header-driven open-group stack (open on header, close on enter-outer-footer / footer-run-end / summary-noData / next-instance), re-emit open flagged headers on every page break, and — for `keepTogether` groups — compute instance extents in one O(n) exit-driven pass and break *before* a group that won't fit the remainder but fits a fresh page (accounting for repeated outer headers).

**Tech Stack:** Dart (pub workspace monorepo), Flutter test harness. Domain (+2 flags) + `rendering/fill/` (+1 IR field) + `rendering/layout/` (the algorithm). Pure geometry — no expression engine enters layout. Value-type IR with deep equality; TDD with `flutter test`; `PageFrame` data goldens.

**Spec:** `docs/superpowers/specs/2026-06-08-group-aware-pagination-design.md`.

**Conventions for every task:**
- Run all commands from `packages/jet_print/`. Test form: `flutter test test/<path> -r expanded`.
- After each task `flutter analyze` must print `No issues found!` (analyzer promotes `unused_import`/`unused_local_variable`/`unused_element`/`unused_field`/`dead_code` to **errors**; explicit types are used throughout — keep them).
- `lib/` files use **relative** imports, ordered `dart:` → `package:` → relative, each group alphabetized by import string.
- Test files use white-box `package:jet_print/src/...` imports.
- New `src/` types are **not** exported from `jet_print.dart` (the public surface is the 011 facade).
- **Schema is NOT bumped** (`kReportSchemaVersion` stays `1`): the two flags are additive optional fields; the codec contract comment is amended to codify the pre-1.0 carve-out (spec §4). Constitution V is **not** amended by this plan.
- Commit messages end with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (omitted below for brevity).
- Branch is already `008b-group-aware-pagination`.

---

## File Structure

**Modify (domain + serialization):**
- `lib/src/domain/report_group.dart` — add `keepTogether`, `reprintHeaderOnEachPage`.
- `lib/src/domain/serialization/report_codec.dart` — amend the `kReportSchemaVersion` contract comment (comment only).

**Modify (`rendering/fill/`):**
- `lib/src/rendering/fill/filled_report.dart` — add `FilledBand.group`.
- `lib/src/rendering/fill/report_filler.dart` — `addBand` propagates `band.group` (one line).

**Modify (`rendering/layout/`):**
- `lib/src/rendering/layout/report_layouter.dart` — open-group lifetime stack + reprint (Task 3); keepTogether extent pre-pass + break (Task 4).

**Tests:**
- `test/domain/report_group_test.dart` (extend) — flag round-trip + equality.
- `test/rendering/fill/filled_report_test.dart` (extend) — `FilledBand.group` equality + toString.
- `test/rendering/fill/report_filler_test.dart` (extend) — group propagation.
- `test/rendering/layout/report_layouter_test.dart` (extend) — group-aware `PageFrame` goldens.
- `CHANGELOG.md`.

**No new layer-boundary test:** the existing `layout/` seam test already globs the directory and forbids `expression/`; 008b adds no expression import.

---

## Task 1: `ReportGroup` flags + codec contract comment

**Files:**
- Modify: `lib/src/domain/report_group.dart`
- Modify: `lib/src/domain/serialization/report_codec.dart`
- Test: `test/domain/report_group_test.dart`

- [ ] **Step 1: Write the failing tests**

In `test/domain/report_group_test.dart`, replace the file body with (keeps the two existing tests, adds the flag tests):

```dart
// ReportGroup value type + serialization (spec 005b; flags 008b). No Flutter UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/report_group.dart';

void main() {
  group('ReportGroup', () {
    test('round-trips through JSON', () {
      const ReportGroup g =
          ReportGroup(name: 'category', expression: r'$F{category}');
      expect(ReportGroup.fromJson(g.toJson()), g);
    });

    test('has value equality and a consistent hash code', () {
      expect(const ReportGroup(name: 'a', expression: 'x'),
          const ReportGroup(name: 'a', expression: 'x'));
      expect(const ReportGroup(name: 'a', expression: 'x').hashCode,
          const ReportGroup(name: 'a', expression: 'x').hashCode);
      expect(
          const ReportGroup(name: 'a', expression: 'x') ==
              const ReportGroup(name: 'a', expression: 'y'),
          isFalse);
    });

    test('flags default to false and are omitted from JSON', () {
      const ReportGroup g = ReportGroup(name: 'a', expression: 'x');
      expect(g.keepTogether, isFalse);
      expect(g.reprintHeaderOnEachPage, isFalse);
      expect(g.toJson().containsKey('keepTogether'), isFalse);
      expect(g.toJson().containsKey('reprintHeaderOnEachPage'), isFalse);
    });

    test('flags round-trip when true', () {
      const ReportGroup g = ReportGroup(
          name: 'a',
          expression: 'x',
          keepTogether: true,
          reprintHeaderOnEachPage: true);
      final ReportGroup decoded = ReportGroup.fromJson(g.toJson());
      expect(decoded.keepTogether, isTrue);
      expect(decoded.reprintHeaderOnEachPage, isTrue);
      expect(decoded, g);
    });

    test('absent flag keys decode to false (backward compatible)', () {
      final ReportGroup g = ReportGroup.fromJson(
          <String, Object?>{'name': 'a', 'expression': 'x'});
      expect(g.keepTogether, isFalse);
      expect(g.reprintHeaderOnEachPage, isFalse);
    });

    test('flags participate in equality', () {
      expect(
          const ReportGroup(name: 'a', expression: 'x', keepTogether: true) ==
              const ReportGroup(name: 'a', expression: 'x'),
          isFalse);
      expect(
          const ReportGroup(
                  name: 'a', expression: 'x', reprintHeaderOnEachPage: true) ==
              const ReportGroup(name: 'a', expression: 'x'),
          isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/domain/report_group_test.dart -r expanded`
Expected: FAIL — `ReportGroup` has no `keepTogether`/`reprintHeaderOnEachPage` parameter.

- [ ] **Step 3: Add the flags to `ReportGroup`**

In `lib/src/domain/report_group.dart`, update the class. Constructor:

```dart
  /// Creates a group keyed by [expression].
  const ReportGroup({
    required this.name,
    required this.expression,
    this.keepTogether = false,
    this.reprintHeaderOnEachPage = false,
  });
```

`fromJson` (tolerant of absent keys → false):

```dart
  /// Reads a [ReportGroup] from its [toJson] map.
  factory ReportGroup.fromJson(Map<String, Object?> json) => ReportGroup(
        name: json['name']! as String,
        expression: json['expression']! as String,
        keepTogether: json['keepTogether'] as bool? ?? false,
        reprintHeaderOnEachPage:
            json['reprintHeaderOnEachPage'] as bool? ?? false,
      );
```

Add the two fields after `expression` (preserve the existing doc-comment style):

```dart
  /// When true, the layout engine tries to keep this group's whole instance on
  /// one page — moving it to a fresh page if it does not fit the remainder but
  /// fits a fresh page (008b). Default false.
  final bool keepTogether;

  /// When true, this group's header band(s) are reprinted at the top of each
  /// continuation page the group spans (008b). Default false.
  final bool reprintHeaderOnEachPage;
```

`toJson` (omit when false, so existing JSON is unchanged):

```dart
  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'expression': expression,
        if (keepTogether) 'keepTogether': true,
        if (reprintHeaderOnEachPage) 'reprintHeaderOnEachPage': true,
      };
```

`==`/`hashCode`/`toString`:

```dart
  @override
  bool operator ==(Object other) =>
      other is ReportGroup &&
      other.name == name &&
      other.expression == expression &&
      other.keepTogether == keepTogether &&
      other.reprintHeaderOnEachPage == reprintHeaderOnEachPage;

  @override
  int get hashCode =>
      Object.hash(name, expression, keepTogether, reprintHeaderOnEachPage);

  @override
  String toString() => 'ReportGroup($name, "$expression"'
      '${keepTogether ? ', keepTogether' : ''}'
      '${reprintHeaderOnEachPage ? ', reprintHeader' : ''})';
```

- [ ] **Step 4: Amend the codec contract comment**

In `lib/src/domain/serialization/report_codec.dart`, replace the `kReportSchemaVersion` doc comment (currently "Bump on every schema change and ship a [SchemaMigration] for the previous version.") with:

```dart
/// The report-schema version this build writes. Bump on every schema change and
/// ship a [SchemaMigration] for the previous version.
///
/// Pre-1.0 carve-out (spec 008b §4): while the library is **not deployed**,
/// additive **optional** fields that load backward-compatibly (absent ⇒ default)
/// may be introduced at the current schema version without a bump or migration —
/// there is no on-disk data to migrate. The bump-and-migrate rule above applies
/// in full from 1.0 onward.
const int kReportSchemaVersion = 1;
```

- [ ] **Step 5: Run the tests + analyzer**

Run: `flutter test test/domain/ -r expanded && flutter analyze`
Expected: the new `report_group` tests PASS; all existing domain/serialization tests still PASS (the existing `report_codec` re-encode-equality holds because the flags are omitted when false); `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/domain/report_group.dart lib/src/domain/serialization/report_codec.dart \
  test/domain/report_group_test.dart
git commit -m "feat(domain): ReportGroup keepTogether + reprintHeaderOnEachPage flags (008b)"
```

---

## Task 2: `FilledBand.group` + Fill propagation

**Files:**
- Modify: `lib/src/rendering/fill/filled_report.dart`
- Modify: `lib/src/rendering/fill/report_filler.dart`
- Test: `test/rendering/fill/filled_report_test.dart`
- Test: `test/rendering/fill/report_filler_test.dart`

Context: `FilledBand` is the internal Fill→Layout IR (no `toJson`). Adding `group` (the `ReportGroup.name` for group bands, null otherwise) carries no schema impact. Fill's `addBand` already holds the source `ReportBand`, so propagation is one line.

- [ ] **Step 1: Write the failing tests**

In `test/rendering/fill/filled_report_test.dart`, add these tests inside `main()` (after the existing FilledBand tests). They need imports for `BandType`, `JetValue`, and the geometry/element types — add any missing import from this set at the top:

```dart
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/expression/value.dart';
```

Tests:

```dart
  test('FilledBand.group participates in equality and hashCode', () {
    FilledBand band(String? group) => FilledBand(
          type: BandType.groupHeader,
          height: 10,
          elements: const <ReportElement>[],
          variables: const <String, JetValue>{},
          group: group,
        );
    expect(band('region'), band('region'));
    expect(band('region').hashCode, band('region').hashCode);
    expect(band('region') == band('city'), isFalse);
    expect(band('region') == band(null), isFalse);
  });

  test('FilledBand.group defaults to null and appears in toString when set', () {
    final FilledBand plain = FilledBand(
        type: BandType.detail,
        height: 10,
        elements: const <ReportElement>[],
        variables: const <String, JetValue>{});
    expect(plain.group, isNull);
    final FilledBand grouped = FilledBand(
        type: BandType.groupHeader,
        height: 10,
        elements: const <ReportElement>[],
        variables: const <String, JetValue>{},
        group: 'region');
    expect(grouped.toString(), contains('region'));
  });
```

(If `filled_report_test.dart` does not already import `ReportElement`, add `import 'package:jet_print/src/domain/report_element.dart';` too.)

In `test/rendering/fill/report_filler_test.dart`, add this test inside `main()` (the file already has the `gh`/`gf`/`t` helpers and `JetInMemoryDataSource`/`ReportFiller` in scope from 007c):

```dart
  test('filled group bands carry their group name; plain bands carry null', () {
    final ReportTemplate tpl = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      groups: const <ReportGroup>[
        ReportGroup(name: 'region', expression: r'$F{region}'),
      ],
      bands: <ReportBand>[
        gh('region', text: 'H'),
        ReportBand(type: BandType.detail, height: 10,
            elements: <ReportElement>[t('d', text: '.')]),
        gf('region', text: 'F'),
      ],
    );
    final FillResult res = ReportFiller().fill(
      tpl,
      JetInMemoryDataSource(<Map<String, Object?>>[
        <String, Object?>{'region': 'West'},
      ]),
    );
    final List<FilledBand> b = res.report.bands;
    expect(b[0].type, BandType.groupHeader);
    expect(b[0].group, 'region');
    expect(b[1].type, BandType.detail);
    expect(b[1].group, isNull);
    expect(b.last.type, BandType.groupFooter);
    expect(b.last.group, 'region');
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/rendering/fill/filled_report_test.dart test/rendering/fill/report_filler_test.dart -r expanded`
Expected: FAIL — `FilledBand` has no `group` parameter.

- [ ] **Step 3: Add `FilledBand.group`**

In `lib/src/rendering/fill/filled_report.dart`, update `FilledBand`. Constructor (add `this.group` after `variables`):

```dart
  FilledBand({
    required this.type,
    required this.height,
    required List<ReportElement> elements,
    required Map<String, JetValue> variables,
    this.group,
  })  : elements = List<ReportElement>.unmodifiable(elements),
        variables = Map<String, JetValue>.unmodifiable(variables);
```

Add the field after `variables`:

```dart
  /// The [ReportGroup] name this band belongs to (008b); set for
  /// `groupHeader`/`groupFooter` bands, null otherwise. Lets the layout engine
  /// track open group instances. Not persisted — this is the internal IR.
  final String? group;
```

Update `==` (add the `group` comparison):

```dart
  @override
  bool operator ==(Object other) =>
      other is FilledBand &&
      other.type == type &&
      other.height == height &&
      other.group == group &&
      _listEquals(other.elements, elements) &&
      _mapEquals(other.variables, variables);
```

Update `hashCode` (add `group`):

```dart
  @override
  int get hashCode {
    final int varsHash = Object.hashAllUnordered(
      <int>[
        for (final MapEntry<String, JetValue> e in variables.entries)
          Object.hash(e.key, e.value),
      ],
    );
    return Object.hash(type, height, group, Object.hashAll(elements), varsHash);
  }
```

Update `toString` (include `group` when non-null):

```dart
  @override
  String toString() => 'FilledBand(${type.name}'
      '${group == null ? '' : ' [$group]'}, ${elements.length} elements)';
```

- [ ] **Step 4: Propagate `group` in Fill**

In `lib/src/rendering/fill/report_filler.dart`, in the nested `addBand` function, pass `band.group`:

```dart
    void addBand(ReportBand band, DataRow? row, Map<String, JetValue> vars) {
      bands.add(FilledBand(
        type: band.type,
        height: band.height,
        elements: <ReportElement>[
          for (final ReportElement e in band.elements)
            resolver.resolve(e, row: row, params: params, variables: vars),
        ],
        variables: vars,
        group: band.group,
      ));
    }
```

- [ ] **Step 5: Run the tests + analyzer**

Run: `flutter test test/rendering/fill/ -r expanded && flutter analyze`
Expected: the new tests PASS; all existing 007b/007c filler tests still PASS (the no-groups path is unchanged; group bands now additionally carry their name); `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/rendering/fill/filled_report.dart lib/src/rendering/fill/report_filler.dart \
  test/rendering/fill/filled_report_test.dart test/rendering/fill/report_filler_test.dart
git commit -m "feat(fill): FilledBand.group IR field + propagation (008b)"
```

---

## Task 3: `reprintHeaderOnEachPage` — open-group lifetime + header re-emit

**Files:**
- Modify: `lib/src/rendering/layout/report_layouter.dart`
- Test: `test/rendering/layout/report_layouter_test.dart`

Context: The layouter gains the header-driven open-group lifetime (spec §5) and re-emits open flagged headers on every page break (§7). A `groupHeader`/`groupFooter` with `null`/undeclared `group` is laid out as a plain body band (no lifetime effect, no diagnostic), keeping the 008a regression byte-identical. A flag set on a group with no header band emits one **info** advisory. `keepTogether` is added in Task 4 — this task leaves the break decision as 008a's single overflow break (now routed through `breakPage()`).

- [ ] **Step 1: Add the failing tests**

In `test/rendering/layout/report_layouter_test.dart`, add an import near the others:

```dart
import 'package:jet_print/src/domain/report_group.dart';
```

Add these helpers just below the existing `_filled` helper (top of file):

```dart
// A group-typed (or plain) body band carrying optional group identity.
FilledBand _gband(BandType type,
        {String? group, double height = 20, String id = 'x'}) =>
    FilledBand(
      type: type,
      height: height,
      group: group,
      elements: <ReportElement>[
        _rect(id, JetRect(x: 0, y: 0, width: 180, height: height)),
      ],
      variables: const <String, JetValue>{},
    );

ReportTemplate _tplWithGroups(List<ReportGroup> groups) =>
    ReportTemplate(name: 'demo', page: _smallPage, groups: groups);
```

Add these tests inside `main()` (after the existing 008a tests):

```dart
  test('a group header reprints at the top of a continuation page when flagged',
      () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(
          name: 'g', expression: r'$F{g}', reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
      _gband(BandType.detail, height: 30, id: 'd3'),
    ]);
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    final List<RectPrimitive> p2 =
        r.pages[1].primitives.whereType<RectPrimitive>().toList();
    expect(p2.first.elementId, 'GH'); // reprinted header is first on page 2
    expect(p2.first.bounds, const JetRect(x: 10, y: 10, width: 180, height: 20));
  });

  test('a group header does not reprint when the flag is off (default)', () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(name: 'g', expression: r'$F{g}'),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
      _gband(BandType.detail, height: 30, id: 'd3'),
    ]);
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    expect(
        r.pages[1].primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'GH'),
        isFalse);
  });

  test('nested group headers reprint outer-then-inner on a continuation page',
      () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(
          name: 'region', expression: r'$F{region}',
          reprintHeaderOnEachPage: true),
      ReportGroup(
          name: 'city', expression: r'$F{city}',
          reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'region', height: 20, id: 'RH'),
      _gband(BandType.groupHeader, group: 'city', height: 20, id: 'CH'),
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
    ]);
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    final List<String?> ids = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    expect(ids.take(2).toList(), <String>['RH', 'CH']); // outer then inner
  });

  test('a group with multiple header bands reprints all of them in order', () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(
          name: 'g', expression: r'$F{g}', reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 15, id: 'H1'),
      _gband(BandType.groupHeader, group: 'g', height: 15, id: 'H2'),
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
    ]);
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    final List<String?> ids = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    expect(ids.take(2).toList(), <String>['H1', 'H2']);
  });

  test('a break between an inner footer and an outer footer reprints only the '
      'outer header', () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(
          name: 'region', expression: r'$F{region}',
          reprintHeaderOnEachPage: true),
      ReportGroup(
          name: 'city', expression: r'$F{city}',
          reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'region', height: 10, id: 'RH'),
      _gband(BandType.groupHeader, group: 'city', height: 10, id: 'CH'),
      _gband(BandType.detail, height: 40, id: 'd1'),
      _gband(BandType.groupFooter, group: 'city', height: 15, id: 'CF'),
      _gband(BandType.groupFooter, group: 'region', height: 15, id: 'RF'),
    ]);
    // RH@10 CH@20 d1@30..70 CF@70..85; RF (85+15>90) -> page 2. City closed at
    // its footer-run end, so only region reprints.
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    final Set<String?> p2 = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toSet();
    expect(p2.contains('RH'), isTrue);
    expect(p2.contains('CH'), isFalse);
  });

  test('a break between the final group footer and summary reprints no header',
      () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(
          name: 'g', expression: r'$F{g}', reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH'),
      _gband(BandType.detail, height: 50, id: 'd1'),
      _gband(BandType.groupFooter, group: 'g', height: 15, id: 'GF'),
      _gband(BandType.summary, height: 20, id: 'S'),
    ]);
    // GH@10 d1@20..70 GF@70..85; S (85+20>90) -> page 2. Group closed before S.
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    final Set<String?> p2 = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toSet();
    expect(p2.contains('S'), isTrue);
    expect(p2.contains('GH'), isFalse);
  });

  test('a group-typed band with null group lays out as a plain band', () {
    final ReportTemplate tpl = _tplWithGroups(const <ReportGroup>[]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, height: 30, id: 'GH'), // group: null
      _gband(BandType.detail, height: 30, id: 'd1'),
      _gband(BandType.detail, height: 30, id: 'd2'),
    ]);
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2); // GH@10 d1@40 d2(70+30>90)->page2
    expect(
        r.pages[1].primitives
            .whereType<RectPrimitive>()
            .any((RectPrimitive p) => p.elementId == 'GH'),
        isFalse); // not reprinted
    expect(r.diagnostics.entries, isEmpty); // no diagnostic
  });

  test('a flag on a header-less group emits an info and changes nothing', () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(
          name: 'g', expression: r'$F{g}', reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.detail, height: 30, id: 'd1'),
    ]);
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(
        r.diagnostics.entries
            .where((Diagnostic d) => d.severity == DiagnosticSeverity.info)
            .length,
        1);
  });

  test('a header-only group is closed by summary (no reprint above summary)',
      () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(
          name: 'g', expression: r'$F{g}', reprintHeaderOnEachPage: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'g', height: 10, id: 'GH'),
      _gband(BandType.detail, height: 60, id: 'd1'),
      _gband(BandType.summary, height: 25, id: 'S'),
    ]);
    // GH@10..20 d1@20..80; S (80+25>90) -> page 2. The header-only group (no
    // footer) is closed by the summary rule, so no header reprints above S.
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    final Set<String?> p2 = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toSet();
    expect(p2.contains('S'), isTrue);
    expect(p2.contains('GH'), isFalse);
  });

  test('group-aware layout is deterministic', () {
    ReportTemplate tpl() => _tplWithGroups(<ReportGroup>[
          ReportGroup(
              name: 'g', expression: r'$F{g}', reprintHeaderOnEachPage: true),
        ]);
    FilledReport filled() => _filled(<FilledBand>[
          _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
          _gband(BandType.detail, height: 30, id: 'd1'),
          _gband(BandType.detail, height: 30, id: 'd2'),
          _gband(BandType.detail, height: 30, id: 'd3'),
        ]);
    final LayoutResult a = ReportLayouter().layout(tpl(), filled());
    final LayoutResult b = ReportLayouter().layout(tpl(), filled());
    expect(a.pages, b.pages); // PageFrame has value equality
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/rendering/layout/report_layouter_test.dart -r expanded`
Expected: FAIL — group headers are not reprinted yet; the header-less advisory is not emitted.

- [ ] **Step 3: Implement the open-group lifetime + reprint**

In `lib/src/rendering/layout/report_layouter.dart`, add the imports (alphabetized in the relative group — `report_group.dart` sorts after `report_element.dart`, before `report_template.dart`):

```dart
import '../../domain/report_group.dart';
```

Add this typedef just above `class LayoutResult`:

```dart
/// One open group instance during pagination: its [name], nesting [level]
/// (outermost = 0), the [headers] measured at its open (for reprint), and its
/// [reprint] flag (008b).
typedef _OpenGroup = ({
  String name,
  int level,
  List<MeasuredBand> headers,
  bool reprint,
});
```

Replace the `layout(...)` method body (everything inside the method) with this version. It keeps the 008a setup verbatim and adds the group lookup, the header-less advisory, the pre-measure, the open-group stack, and the per-band lifetime/reprint:

```dart
  LayoutResult layout(ReportTemplate template, FilledReport filled) {
    final ReportDiagnostics diagnostics = ReportDiagnostics();
    final RenderContext ctx = RenderContext(measurer: _measurer);
    final BandMeasurer bandMeasurer = BandMeasurer(_renderers, ctx);

    final PageFormat page = template.page;
    if (filled.page != page) {
      diagnostics.warning(
          'filled.page differs from template.page; using template.page');
    }

    final double left = page.margins.left;
    final double top = page.margins.top;
    final double bottom = page.height - page.margins.bottom;
    final double contentHeight = bottom - top;

    final List<ReportBand> headers = <ReportBand>[
      for (final ReportBand b in template.bands)
        if (b.type == BandType.pageHeader) b,
    ];
    final List<ReportBand> footers = <ReportBand>[
      for (final ReportBand b in template.bands)
        if (b.type == BandType.pageFooter) b,
    ];
    double sumHeight(List<ReportBand> bands) {
      double h = 0;
      for (final ReportBand b in bands) {
        h += b.height;
      }
      return h;
    }

    final double headerHeight = sumHeight(headers);
    final double footerHeight = sumHeight(footers);
    final double bodyTop = top + headerHeight;
    final double bodyBottom = bottom - footerHeight;
    final double bodyCapacity = bodyBottom - bodyTop;

    if (bodyCapacity <= 0) {
      diagnostics.warning(
          'page chrome (header $headerHeight + footer $footerHeight) leaves no '
          'room for body on a $contentHeight-pt printable height; chrome '
          'overlaps and body bands overflow');
    }

    for (final BandType ignored in const <BandType>[
      BandType.columnHeader,
      BandType.columnFooter,
      BandType.background,
    ]) {
      if (template.bands.any((ReportBand b) => b.type == ignored)) {
        diagnostics
            .info('${ignored.name} bands are not laid out in 008a; ignored');
      }
    }

    for (final ReportBand band in <ReportBand>[...headers, ...footers]) {
      for (final ReportElement el in band.elements) {
        if (el is TextElement && el.expression != null) {
          diagnostics.info(
              'chrome text expression on "${el.id}" was not evaluated in the '
              'static layout pass',
              elementId: el.id);
        } else if (el is ImageElement && el.source is! BytesImageSource) {
          diagnostics.info(
              'chrome image on "${el.id}" is not embedded; renders a placeholder',
              elementId: el.id);
        }
      }
    }

    // Group lookup: name -> nesting level (outermost = 0) and name -> definition.
    final Map<String, int> levelOf = <String, int>{
      for (int i = 0; i < template.groups.length; i++)
        template.groups[i].name: i,
    };
    final Map<String, ReportGroup> groupByName = <String, ReportGroup>{
      for (final ReportGroup g in template.groups) g.name: g,
    };

    // Advisory: a flag on a group that never opens a header band does nothing.
    final Set<String> groupsWithHeader = <String>{
      for (final FilledBand b in filled.bands)
        if (b.type == BandType.groupHeader && b.group != null) b.group!,
    };
    for (final ReportGroup g in template.groups) {
      if ((g.keepTogether || g.reprintHeaderOnEachPage) &&
          !groupsWithHeader.contains(g.name)) {
        diagnostics.info(
            'group "${g.name}" sets keepTogether/reprintHeaderOnEachPage but '
            'has no group-header band; the flag has no effect');
      }
    }

    void place(List<({ReportElement element, JetRect bounds})> boxes,
        double topY, FrameBuilder fb) {
      for (final ({ReportElement element, JetRect bounds}) e in boxes) {
        _renderers.rendererFor(e.element).emit(
              e.element,
              ctx,
              JetRect(
                x: left + e.bounds.x,
                y: topY + e.bounds.y,
                width: e.bounds.width,
                height: e.bounds.height,
              ),
              fb,
            );
      }
    }

    // Pre-measure every body band once (pure, position-independent).
    final List<MeasuredBand> measured = <MeasuredBand>[
      for (final FilledBand b in filled.bands) bandMeasurer.measure(b),
    ];

    final List<_OpenGroup> openStack = <_OpenGroup>[];
    final List<FrameBuilder> pages = <FrameBuilder>[FrameBuilder(page)];
    double cursorY = bodyTop;

    void reEmitHeaders() {
      for (final _OpenGroup g in openStack) {
        if (!g.reprint) continue;
        for (final MeasuredBand hmb in g.headers) {
          place(hmb.elements, cursorY, pages.last);
          cursorY += hmb.height;
        }
      }
    }

    void breakPage() {
      pages.add(FrameBuilder(page));
      cursorY = bodyTop;
      reEmitHeaders();
    }

    String? prevHeaderGroup;
    for (int i = 0; i < filled.bands.length; i++) {
      final FilledBand band = filled.bands[i];
      final MeasuredBand mb = measured[i];
      final bool isGroupBand = (band.type == BandType.groupHeader ||
              band.type == BandType.groupFooter) &&
          band.group != null &&
          levelOf.containsKey(band.group);
      final int level = isGroupBand ? levelOf[band.group]! : -1;

      // Pre-place closure (§5.2): an outer footer ends its inner groups (rule 1);
      // summary/noData end all groups (rule 3).
      if (band.type == BandType.groupFooter && isGroupBand) {
        while (openStack.isNotEmpty && openStack.last.level > level) {
          openStack.removeLast();
        }
      } else if (band.type == BandType.summary ||
          band.type == BandType.noData) {
        openStack.clear();
      }

      if (cursorY + mb.height > bodyBottom && cursorY > bodyTop) {
        breakPage();
      }
      if (bodyCapacity > 0 && mb.height > bodyCapacity) {
        diagnostics.warning('band height ${mb.height} exceeds body capacity '
            '$bodyCapacity; content overflows');
      }
      place(mb.elements, cursorY, pages.last);
      cursorY += mb.height;

      // Post-place lifetime (§5.1 open/append; §5.2 rule 2 footer-run end).
      if (band.type == BandType.groupHeader && isGroupBand) {
        if (prevHeaderGroup == band.group &&
            openStack.isNotEmpty &&
            openStack.last.name == band.group) {
          openStack.last.headers.add(mb); // continuation header
        } else {
          while (openStack.isNotEmpty && openStack.last.level >= level) {
            openStack.removeLast(); // new instance: close prior g + inner
          }
          openStack.add((
            name: band.group!,
            level: level,
            headers: <MeasuredBand>[mb],
            reprint: groupByName[band.group]!.reprintHeaderOnEachPage,
          ));
        }
      } else if (band.type == BandType.groupFooter && isGroupBand) {
        final bool runEnd = i + 1 >= filled.bands.length ||
            filled.bands[i + 1].type != BandType.groupFooter ||
            filled.bands[i + 1].group != band.group;
        if (runEnd) {
          while (openStack.isNotEmpty && openStack.last.level >= level) {
            openStack.removeLast();
          }
        }
      }
      prevHeaderGroup =
          (band.type == BandType.groupHeader && isGroupBand) ? band.group : null;
    }

    // Chrome post-pass (008a, unchanged).
    for (final FrameBuilder fb in pages) {
      double y = top;
      for (final ReportBand h in headers) {
        place(_authoredBoxes(h), y, fb);
        y += h.height;
      }
      y = bodyBottom;
      for (final ReportBand f in footers) {
        place(_authoredBoxes(f), y, fb);
        y += f.height;
      }
    }

    return LayoutResult(
      pages: <PageFrame>[for (final FrameBuilder fb in pages) fb.build()],
      diagnostics: diagnostics,
    );
  }
```

- [ ] **Step 4: Run the tests + analyzer**

Run: `flutter test test/rendering/layout/report_layouter_test.dart -r expanded && flutter analyze`
Expected: PASS — all existing 008a layout tests (their group-typed bands carry no `group` → laid out as plain bands, byte-identical) **plus** the 10 new reprint/lifetime tests; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/layout/report_layouter.dart test/rendering/layout/report_layouter_test.dart
git commit -m "feat(layout): reprintHeaderOnEachPage + open-group lifetime (008b)"
```

---

## Task 4: `keepTogether` — extent pre-pass + keep-together break

**Files:**
- Modify: `lib/src/rendering/layout/report_layouter.dart`
- Test: `test/rendering/layout/report_layouter_test.dart`

Context: Layers the O(n) extent pre-pass (spec §6.1) and the keep-together break decision (§6.2) onto Task 3's loop. The break decision subtracts the headers that will actually repeat on the fresh page (`bodyCapacity − repeatedOuter`), and is mutually exclusive with the overflow break via a `broke` flag (one break per band).

- [ ] **Step 1: Add the failing tests**

In `test/rendering/layout/report_layouter_test.dart`, add these tests inside `main()` (after the Task 3 tests):

```dart
  test('keepTogether moves a whole group to a fresh page when it does not fit '
      'the remainder', () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(name: 'g', expression: r'$F{g}', keepTogether: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.detail, height: 60, id: 'pre'),
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 30, id: 'gd1'),
    ]);
    // pre@10..70; group extent 50 doesn't fit remainder (70..90) but fits a
    // fresh page -> moved whole to page 2.
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    expect(
        r.pages[0].primitives
            .whereType<RectPrimitive>()
            .map((RectPrimitive p) => p.elementId)
            .toSet(),
        <String>{'pre'});
    expect(
        r.pages[1].primitives
            .whereType<RectPrimitive>()
            .map((RectPrimitive p) => p.elementId)
            .toSet()
            .containsAll(<String>{'GH', 'gd1'}),
        isTrue);
    // one break per band: GH lands at bodyTop on page 2 (no blank page).
    expect(
        r.pages[1].primitives
            .whereType<RectPrimitive>()
            .firstWhere((RectPrimitive p) => p.elementId == 'GH')
            .bounds
            .y,
        10);
  });

  test('keepTogether does not force-break a group taller than the page', () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(name: 'g', expression: r'$F{g}', keepTogether: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.detail, height: 40, id: 'pre'),
      _gband(BandType.groupHeader, group: 'g', height: 20, id: 'GH'),
      _gband(BandType.detail, height: 70, id: 'big'),
    ]);
    // group extent 90 > bodyCapacity 80 -> not force-broken; it splits.
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    expect(
        r.pages[0].primitives
            .whereType<RectPrimitive>()
            .map((RectPrimitive p) => p.elementId)
            .toSet(),
        <String>{'pre', 'GH'});
    expect(r.pages[1].primitives.whereType<RectPrimitive>().single.elementId,
        'big');
  });

  test('keepTogether accounts for repeated outer headers (splits, not moved)',
      () {
    final ReportTemplate tpl = _tplWithGroups(<ReportGroup>[
      ReportGroup(
          name: 'region', expression: r'$F{region}',
          reprintHeaderOnEachPage: true),
      ReportGroup(name: 'city', expression: r'$F{city}', keepTogether: true),
    ]);
    final FilledReport filled = _filled(<FilledBand>[
      _gband(BandType.groupHeader, group: 'region', height: 20, id: 'RH'),
      _gband(BandType.detail, height: 30, id: 'fill'),
      _gband(BandType.groupHeader, group: 'city', height: 20, id: 'CH'),
      _gband(BandType.detail, height: 50, id: 'cd1'),
    ]);
    // city extent 70 fits a raw page (80) but NOT after region's repeated header
    // (80-20=60), so it is NOT moved whole -> it splits: CH on page 1, cd1 on
    // page 2 below the reprinted RH.
    final LayoutResult r = ReportLayouter().layout(tpl, filled);
    expect(r.pages.length, 2);
    expect(
        r.pages[0].primitives
            .whereType<RectPrimitive>()
            .map((RectPrimitive p) => p.elementId)
            .toSet(),
        containsAll(<String>{'RH', 'fill', 'CH'}));
    final List<String?> p2 = r.pages[1].primitives
        .whereType<RectPrimitive>()
        .map((RectPrimitive p) => p.elementId)
        .toList();
    expect(p2, <String>['RH', 'cd1']); // region header reprinted, then cd1
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/rendering/layout/report_layouter_test.dart -r expanded`
Expected: FAIL — `keepTogether` does no breaking yet (the "moves a whole group" and "accounts for repeated outer headers" tests fail).

- [ ] **Step 3: Add the extent pre-pass**

In `lib/src/rendering/layout/report_layouter.dart`, add this typedef just below the `_OpenGroup` typedef:

```dart
/// One open group span during the extent pre-pass: its [name], [level], and the
/// stream index [openIndex] of its opening header (008b §6.1).
typedef _Span = ({String name, int level, int openIndex});
```

In `layout(...)`, immediately after the `final List<MeasuredBand> measured = [...]` line, insert the prefix-sum + extent pre-pass:

```dart
    // Prefix sums + single O(n) exit-driven extent pre-pass for keepTogether
    // groups (spec §6.1). keepExtent[openIndex] = the instance's total height.
    final List<double> cum = <double>[0];
    for (final MeasuredBand mb in measured) {
      cum.add(cum.last + mb.height);
    }
    final Map<int, double> keepExtent = <int, double>{};
    final List<_Span> spanStack = <_Span>[];
    void finalizeSpan(_Span s, int exitIndex) {
      if (groupByName[s.name]!.keepTogether) {
        keepExtent[s.openIndex] = cum[exitIndex] - cum[s.openIndex];
      }
    }

    String? spanPrevHeader;
    for (int k = 0; k < filled.bands.length; k++) {
      final FilledBand band = filled.bands[k];
      final bool isGroupBand = (band.type == BandType.groupHeader ||
              band.type == BandType.groupFooter) &&
          band.group != null &&
          levelOf.containsKey(band.group);
      final int level = isGroupBand ? levelOf[band.group]! : -1;
      final bool newHeader = band.type == BandType.groupHeader &&
          isGroupBand &&
          spanPrevHeader != band.group;
      if (newHeader) {
        while (spanStack.isNotEmpty && spanStack.last.level >= level) {
          finalizeSpan(spanStack.removeLast(), k);
        }
      } else if (band.type == BandType.groupFooter && isGroupBand) {
        while (spanStack.isNotEmpty && spanStack.last.level > level) {
          finalizeSpan(spanStack.removeLast(), k);
        }
      } else if (band.type == BandType.summary ||
          band.type == BandType.noData) {
        while (spanStack.isNotEmpty) {
          finalizeSpan(spanStack.removeLast(), k);
        }
      }
      if (newHeader) {
        spanStack.add((name: band.group!, level: level, openIndex: k));
      }
      spanPrevHeader =
          (band.type == BandType.groupHeader && isGroupBand) ? band.group : null;
    }
    while (spanStack.isNotEmpty) {
      finalizeSpan(spanStack.removeLast(), filled.bands.length);
    }
```

- [ ] **Step 4: Add the keep-together break to the loop**

In the same method, inside the `for (int i = ...)` loop, **replace** the existing overflow-break block:

```dart
      if (cursorY + mb.height > bodyBottom && cursorY > bodyTop) {
        breakPage();
      }
```

with the keep-together-then-overflow block (mutually exclusive via `broke`):

```dart
      bool broke = false;
      if (keepExtent.containsKey(i)) {
        final double extent = keepExtent[i]!;
        double repeatedOuter = 0;
        for (final _OpenGroup g in openStack) {
          if (!g.reprint) continue;
          for (final MeasuredBand hmb in g.headers) {
            repeatedOuter += hmb.height;
          }
        }
        final double fresh = bodyCapacity - repeatedOuter;
        if (extent <= fresh &&
            cursorY + extent > bodyBottom &&
            cursorY > bodyTop) {
          breakPage();
          broke = true;
        }
      }
      if (!broke && cursorY + mb.height > bodyBottom && cursorY > bodyTop) {
        breakPage();
      }
```

- [ ] **Step 5: Run the tests + analyzer**

Run: `flutter test test/rendering/layout/report_layouter_test.dart -r expanded && flutter analyze`
Expected: PASS — all Task 3 tests plus the 3 new keepTogether tests; `No issues found!`.

- [ ] **Step 6: Run the full suite (no regressions)**

Run: `flutter test -r expanded`
Expected: every test PASSES (007/008a unchanged; the new 008b tests added).

- [ ] **Step 7: Commit**

```bash
git add lib/src/rendering/layout/report_layouter.dart test/rendering/layout/report_layouter_test.dart
git commit -m "feat(layout): keepTogether group break with repeated-header accounting (008b)"
```

---

## Task 5: CHANGELOG + final verification

**Files:**
- Modify: `packages/jet_print/CHANGELOG.md`

- [ ] **Step 1: Update the CHANGELOG**

In `packages/jet_print/CHANGELOG.md`, under the current unreleased `### Added` section (after the 008a entry), add:

```markdown
- **Group-aware pagination (spec 008b).** Two opt-in `ReportGroup` flags: `reprintHeaderOnEachPage`
  repeats a group's header band(s) at the top of each continuation page it spans, and `keepTogether`
  moves a whole group instance to a fresh page rather than splitting it (when it fits a fresh page,
  accounting for any repeated outer headers). Group identity is carried into the internal Fill→Layout
  IR via `FilledBand.group`; the schema is unchanged (the codec contract comment now codifies the
  pre-1.0 additive-optional-fields carve-out). A flag on a header-less group is a no-op + info.
```

- [ ] **Step 2: Run the full suite + analyzer**

Run: `flutter test -r expanded && flutter analyze`
Expected: every test PASSES; `No issues found!`.

- [ ] **Step 3: Commit**

```bash
git add packages/jet_print/CHANGELOG.md
git commit -m "docs(layout): changelog for group-aware pagination (008b)"
```

---

## Done

All of spec 008b (group-aware pagination) is implemented: the two opt-in `ReportGroup` flags (+ codec carve-out comment), the `FilledBand.group` IR completion (+ one-line Fill propagation), the header-driven open-group lifetime with `reprintHeaderOnEachPage` re-emit, and `keepTogether` (O(n) extent pre-pass + repeated-outer-header-aware break, one break per band). Group bands without identity lay out as plain bands; flags on header-less groups are no-ops + info. After Task 5, dispatch a final holistic code review over the whole 008b change set, then use `superpowers:finishing-a-development-branch` to merge `008b-group-aware-pagination` into `main`.
