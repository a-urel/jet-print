# Multi-Column Label Sheets — Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add built-in multi-column label-sheet layout — a detail band repeated across a uniform grid in horizontal print order — driven by an optional `ColumnLayout` property on the detail `Band`.

**Architecture:** `ColumnLayout` is a new immutable value type carried as an optional property of `Band`. The grid activates only when the lone detail band of a *pure single-detail body* carries a non-null `columnLayout`. A dedicated grid-placement branch in `ReportLayouter.layoutLazyDefinition` places each filled detail band into a uniform cell (arithmetic, horizontal order, count-driven page breaks); the existing linear pagination path is otherwise untouched. Filling, band measurement, and element rendering are unchanged. The reserved `columnHeader`/`columnFooter` bands stay reserved.

**Tech Stack:** Dart / Flutter, package `packages/jet_print`. Tests via `flutter test` (run from `packages/jet_print`). Goldens via `flutter test --update-goldens`.

## Global Constraints

- Pure domain layer imports only the domain tree + `package:flutter/foundation.dart` (for `listEquals`) — never rendering/designer/Flutter UI. (`column_layout.dart`, `band.dart`, `report_definition.dart`, `report_validation.dart`.)
- Serialization is **additive** and versioned (Constitution V): `schemaVersion` stays `2`; a new key is emitted **only when non-null** so every existing document round-trips byte-identically.
- Existing goldens MUST stay byte-identical (Constitution IV). A null `columnLayout` must drive the identical linear code path.
- The full existing suite (1568+ jet_print tests + playground) MUST stay green; `flutter analyze` MUST be clean.
- All commands run from `packages/jet_print` (the `flutter` CLI leaves cwd inside the package — always pass explicit paths; run `git` from the repo root).
- Each `_PlacedBand` now carries an `x`; the linear path records `x: left` so its output is unchanged.

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `lib/src/domain/column_layout.dart` | The `ColumnLayout` value type (geometry + JSON) | Create |
| `lib/src/domain/band.dart` | Add optional `columnLayout` property to `Band` | Modify |
| `lib/src/domain/report_definition.dart` | `isPureSingleDetailBody` + `soleDetailBand` gate helpers | Modify |
| `lib/src/domain/serialization/report_definition_codec.dart` | Encode/decode `Band.columnLayout` | Modify |
| `lib/src/domain/report_validation.dart` | Grid validation (FR-007/008/009) | Modify |
| `lib/src/rendering/layout/report_layouter.dart` | Grid-placement branch + `_PlacedBand.x` plumbing | Modify |
| `lib/jet_print.dart` | Export `ColumnLayout` | Modify |
| `test/domain/column_layout_test.dart` | `ColumnLayout` unit tests | Create |
| `test/domain/band_column_layout_test.dart` | `Band.columnLayout` unit tests | Create |
| `test/domain/sole_detail_band_test.dart` | Gate-helper unit tests | Create |
| `test/domain/serialization/report_codec_v2_test.dart` | Round-trip of `columnLayout` (SC-005) | Modify |
| `test/domain/column_layout_validation_test.dart` | Validation rule tests (SC-003) | Create |
| `test/rendering/layout/multi_column_layout_test.dart` | Grid placement + page-count + regression (SC-002/004) | Create |
| `test/goldens/label_sheet_test.dart` + PNG | Rendered label-sheet golden (SC-001) | Create |

---

### Task 1: `ColumnLayout` value type

**Files:**
- Create: `lib/src/domain/column_layout.dart`
- Modify: `lib/jet_print.dart`
- Test: `test/domain/column_layout_test.dart`

**Interfaces:**
- Produces: `class ColumnLayout` with `const ColumnLayout({required int columnCount, required double columnWidth, required double columnSpacing, required double rowSpacing})`; `ColumnLayout copyWith({int? columnCount, double? columnWidth, double? columnSpacing, double? rowSpacing})`; `Map<String, Object?> toJson()`; `factory ColumnLayout.fromJson(Map<String, Object?> json)`; value `==`/`hashCode`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/column_layout_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/column_layout.dart';

void main() {
  const ColumnLayout a = ColumnLayout(
      columnCount: 3, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);

  test('value equality and hashCode', () {
    const ColumnLayout b = ColumnLayout(
        columnCount: 3, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);
    const ColumnLayout c = ColumnLayout(
        columnCount: 2, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('copyWith replaces only the given field', () {
    expect(a.copyWith(columnCount: 4),
        const ColumnLayout(
            columnCount: 4, columnWidth: 180, columnSpacing: 12, rowSpacing: 8));
  });

  test('toJson / fromJson round-trips value-equal', () {
    final Map<String, Object?> json = a.toJson();
    expect(json, <String, Object?>{
      'columnCount': 3,
      'columnWidth': 180.0,
      'columnSpacing': 12.0,
      'rowSpacing': 8.0,
    });
    expect(ColumnLayout.fromJson(json), a);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/column_layout_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:jet_print/src/domain/column_layout.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/src/domain/column_layout.dart`:

```dart
/// The geometry of a multi-column label grid (spec 034) — an optional property
/// of the detail [Band] that serves as the label template.
///
/// Pure domain layer (no rendering/designer/Flutter UI). `columnWidth` is, in
/// effect, the detail band's render width; `columnSpacing` is the horizontal
/// gutter between columns and `rowSpacing` the vertical gap between label rows.
library;

/// An immutable label-grid spec: [columnCount] columns of [columnWidth] points,
/// separated by [columnSpacing] horizontally and [rowSpacing] vertically.
class ColumnLayout {
  /// Creates a column layout. All distances are in points.
  const ColumnLayout({
    required this.columnCount,
    required this.columnWidth,
    required this.columnSpacing,
    required this.rowSpacing,
  });

  /// Reads a [ColumnLayout] from its [toJson] map.
  factory ColumnLayout.fromJson(Map<String, Object?> json) => ColumnLayout(
        columnCount: (json['columnCount']! as num).toInt(),
        columnWidth: (json['columnWidth']! as num).toDouble(),
        columnSpacing: (json['columnSpacing']! as num).toDouble(),
        rowSpacing: (json['rowSpacing']! as num).toDouble(),
      );

  /// Number of columns across the page body.
  final int columnCount;

  /// Width of each column (cell), in points.
  final double columnWidth;

  /// Horizontal gutter between columns, in points.
  final double columnSpacing;

  /// Vertical gap between label rows, in points.
  final double rowSpacing;

  /// Returns a copy with the given fields replaced.
  ColumnLayout copyWith({
    int? columnCount,
    double? columnWidth,
    double? columnSpacing,
    double? rowSpacing,
  }) =>
      ColumnLayout(
        columnCount: columnCount ?? this.columnCount,
        columnWidth: columnWidth ?? this.columnWidth,
        columnSpacing: columnSpacing ?? this.columnSpacing,
        rowSpacing: rowSpacing ?? this.rowSpacing,
      );

  /// Serializes to a JSON-safe map.
  Map<String, Object?> toJson() => <String, Object?>{
        'columnCount': columnCount,
        'columnWidth': columnWidth,
        'columnSpacing': columnSpacing,
        'rowSpacing': rowSpacing,
      };

  @override
  bool operator ==(Object other) =>
      other is ColumnLayout &&
      other.columnCount == columnCount &&
      other.columnWidth == columnWidth &&
      other.columnSpacing == columnSpacing &&
      other.rowSpacing == rowSpacing;

  @override
  int get hashCode =>
      Object.hash(columnCount, columnWidth, columnSpacing, rowSpacing);

  @override
  String toString() => 'ColumnLayout($columnCount x ${columnWidth}pt, '
      'gap $columnSpacing/$rowSpacing)';
}
```

Then export it from `lib/jet_print.dart` — add directly after the existing `export 'src/domain/band.dart' show Band;` line (around line 63):

```dart
export 'src/domain/column_layout.dart' show ColumnLayout;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/column_layout_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/column_layout.dart packages/jet_print/lib/jet_print.dart packages/jet_print/test/domain/column_layout_test.dart
git commit -m "feat(034): add ColumnLayout value type"
```

---

### Task 2: Add `columnLayout` to `Band`

**Files:**
- Modify: `lib/src/domain/band.dart`
- Test: `test/domain/band_column_layout_test.dart`

**Interfaces:**
- Consumes: `ColumnLayout` (Task 1).
- Produces: `Band` gains `final ColumnLayout? columnLayout;`, an optional constructor named parameter `this.columnLayout`, a `copyWith({..., ColumnLayout? columnLayout})` carry-through, and `==`/`hashCode` participation.

- [ ] **Step 1: Write the failing test**

Create `test/domain/band_column_layout_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/column_layout.dart';
import 'package:jet_print/src/domain/report_band.dart';

void main() {
  const ColumnLayout grid = ColumnLayout(
      columnCount: 3, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);

  test('columnLayout defaults to null and is value-equal when absent', () {
    const Band a = Band(id: 'd', type: BandType.detail, height: 80);
    const Band b = Band(id: 'd', type: BandType.detail, height: 80);
    expect(a.columnLayout, isNull);
    expect(a, b);
  });

  test('a band carrying columnLayout differs from one without', () {
    const Band withGrid =
        Band(id: 'd', type: BandType.detail, height: 80, columnLayout: grid);
    const Band withoutGrid = Band(id: 'd', type: BandType.detail, height: 80);
    expect(withGrid, isNot(withoutGrid));
    expect(withGrid.columnLayout, grid);
  });

  test('copyWith preserves columnLayout when not overridden', () {
    const Band withGrid =
        Band(id: 'd', type: BandType.detail, height: 80, columnLayout: grid);
    expect(withGrid.copyWith(height: 90).columnLayout, grid);
    expect(withGrid.copyWith(columnLayout: grid.copyWith(columnCount: 2))
        .columnLayout!.columnCount, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/band_column_layout_test.dart`
Expected: FAIL — `No named parameter with the name 'columnLayout'`.

- [ ] **Step 3: Write minimal implementation**

In `lib/src/domain/band.dart`, add the import after the existing `report_band.dart` import:

```dart
import 'column_layout.dart';
```

Add the constructor parameter (after `this.elements`):

```dart
  const Band({
    required this.id,
    required this.type,
    required this.height,
    this.elements = const <ReportElement>[],
    this.columnLayout,
  });
```

Add the field (after the `elements` field):

```dart
  /// When non-null on the lone detail band of a pure single-detail body, lays
  /// the band out as a multi-column label grid (spec 034). Null elsewhere.
  final ColumnLayout? columnLayout;
```

Extend `copyWith`:

```dart
  Band copyWith({
    String? id,
    BandType? type,
    double? height,
    List<ReportElement>? elements,
    ColumnLayout? columnLayout,
  }) =>
      Band(
        id: id ?? this.id,
        type: type ?? this.type,
        height: height ?? this.height,
        elements: elements ?? this.elements,
        columnLayout: columnLayout ?? this.columnLayout,
      );
```

Extend `==` (add the final clause) and `hashCode`:

```dart
  @override
  bool operator ==(Object other) =>
      other is Band &&
      other.id == id &&
      other.type == type &&
      other.height == height &&
      listEquals(other.elements, elements) &&
      other.columnLayout == columnLayout;

  @override
  int get hashCode =>
      Object.hash(id, type, height, Object.hashAll(elements), columnLayout);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/band_column_layout_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify no existing Band consumer broke**

Run: `flutter test test/domain/`
Expected: PASS (all domain tests; the new optional field is additive).

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/band.dart packages/jet_print/test/domain/band_column_layout_test.dart
git commit -m "feat(034): carry optional columnLayout on Band"
```

---

### Task 3: `ReportDefinition` gate helpers

**Files:**
- Modify: `lib/src/domain/report_definition.dart`
- Test: `test/domain/sole_detail_band_test.dart`

**Interfaces:**
- Consumes: `Band.columnLayout` (Task 2); `DetailScope`, `ScopeNode`, `BandNode` (already imported via `detail_scope.dart`).
- Produces: on `ReportDefinition` — `bool get isPureSingleDetailBody` and `Band? get soleDetailBand`. `soleDetailBand` returns the single detail band when the body is a pure single-detail flow, else `null`. Both the validator (Task 5) and layouter (Task 6) consume `soleDetailBand`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/sole_detail_band_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/group_level.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';

const Band _detail = Band(id: 'd', type: BandType.detail, height: 80);

ReportDefinition _def(ReportBody body) => ReportDefinition(
    name: 'x', page: PageFormat.a4Portrait, body: body);

void main() {
  test('pure single-detail body exposes its sole detail band', () {
    final ReportDefinition def = _def(const ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[BandNode(_detail)])));
    expect(def.isPureSingleDetailBody, isTrue);
    expect(def.soleDetailBand, _detail);
  });

  test('a title once-band disqualifies the body', () {
    final ReportDefinition def = _def(const ReportBody(
        title: Band(id: 't', type: BandType.title, height: 10),
        root: DetailScope(id: 'root', children: <ScopeNode>[BandNode(_detail)])));
    expect(def.isPureSingleDetailBody, isFalse);
    expect(def.soleDetailBand, isNull);
  });

  test('groups, a footer, a nested scope, or multiple bands disqualify it', () {
    final ReportDefinition grouped = _def(const ReportBody(
        root: DetailScope(id: 'root', groups: <GroupLevel>[
          GroupLevel(id: 'g', name: 'g', key: r'$F{k}')
        ], children: <ScopeNode>[BandNode(_detail)])));
    expect(grouped.soleDetailBand, isNull);

    final ReportDefinition nested = _def(const ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(_detail),
          NestedScope(DetailScope(id: 'n', collectionField: 'lines')),
        ])));
    expect(nested.soleDetailBand, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/sole_detail_band_test.dart`
Expected: FAIL — `The getter 'isPureSingleDetailBody' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

In `lib/src/domain/report_definition.dart`, add these getters to `ReportDefinition` (after the `body` field, before `copyWith`):

```dart
  /// Whether [body] is a pure single-detail flow — the gate for the multi-column
  /// label grid (spec 034): no once-bands, and a root scope with no groups, no
  /// footer, and exactly one [BandNode] child (the label template).
  bool get isPureSingleDetailBody {
    if (body.title != null || body.summary != null || body.noData != null) {
      return false;
    }
    final DetailScope root = body.root;
    if (root.groups.isNotEmpty || root.footer != null) return false;
    if (root.children.length != 1) return false;
    return root.children.single is BandNode;
  }

  /// The lone detail band when [isPureSingleDetailBody] holds, else null. The
  /// label grid activates when this band carries a non-null `columnLayout`.
  Band? get soleDetailBand {
    if (!isPureSingleDetailBody) return null;
    final ScopeNode only = body.root.children.single;
    return only is BandNode ? only.band : null;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/sole_detail_band_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/report_definition.dart packages/jet_print/test/domain/sole_detail_band_test.dart
git commit -m "feat(034): add pure-single-detail-body gate helpers"
```

---

### Task 4: Serialize `Band.columnLayout`

**Files:**
- Modify: `lib/src/domain/serialization/report_definition_codec.dart`
- Test: `test/domain/serialization/report_codec_v2_test.dart`

**Interfaces:**
- Consumes: `Band.columnLayout` (Task 2), `ColumnLayout.toJson`/`fromJson` (Task 1).
- Produces: `_encodeBand` emits `'columnLayout'` only when non-null; `_decodeBand` reads it back. `schemaVersion` is unchanged (`2`).

- [ ] **Step 1: Write the failing test**

Append to `test/domain/serialization/report_codec_v2_test.dart` (inside its existing `main()`; reuse the file's existing `ElementCodecRegistry` setup — most tests in this file build one as `registry`. If the file builds the registry inline per test, mirror that exact construction here):

```dart
  test('Band.columnLayout round-trips and is omitted when null (spec 034)', () {
    final ElementCodecRegistry registry = ElementCodecRegistry()
      ..registerBuiltIns();
    const ColumnLayout grid = ColumnLayout(
        columnCount: 3, columnWidth: 180, columnSpacing: 12, rowSpacing: 8);
    final ReportDefinition def = ReportDefinition(
      name: 'labels',
      page: PageFormat.a4Portrait,
      body: const ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'd', type: BandType.detail, height: 80, columnLayout: grid)),
        ]),
      ),
    );

    final Map<String, Object?> json = encodeDefinition(def, registry);
    expect(decodeDefinition(json, registry), def);

    // Absent when null: a plain band emits no 'columnLayout' key.
    final Map<String, Object?> plain = encodeDefinition(
      ReportDefinition(
        name: 'plain',
        page: PageFormat.a4Portrait,
        body: const ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
            BandNode(Band(id: 'd', type: BandType.detail, height: 80)),
          ]),
        ),
      ),
      registry,
    );
    final Map<String, Object?> rootScope =
        (plain['body']! as Map)['root']! as Map<String, Object?>;
    final Map<String, Object?> bandJson =
        ((rootScope['children']! as List).single as Map)['band']
            as Map<String, Object?>;
    expect(bandJson.containsKey('columnLayout'), isFalse);
  });
```

Ensure the file imports `ColumnLayout` (add `import 'package:jet_print/src/domain/column_layout.dart';` if absent). The exact `ElementCodecRegistry` construction (`ElementCodecRegistry()..registerBuiltIns()` vs a shared helper) must match the other tests already in this file — copy whichever form they use.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/serialization/report_codec_v2_test.dart --plain-name "columnLayout round-trips"`
Expected: FAIL — `decodeDefinition(...)` is not equal to `def` (the decoded band's `columnLayout` is null).

- [ ] **Step 3: Write minimal implementation**

In `lib/src/domain/serialization/report_definition_codec.dart`, add the import after the existing `../band.dart` import:

```dart
import '../column_layout.dart';
```

In `_encodeBand`, add the column-layout key (after the `elements` block, before the closing `};`):

```dart
Map<String, Object?> _encodeBand(Band band, ElementCodecRegistry registry) {
  return <String, Object?>{
    'id': band.id,
    'type': band.type.name,
    'height': band.height,
    if (band.elements.isNotEmpty)
      'elements': <Object?>[
        for (final ReportElement element in band.elements)
          registry.encode(element),
      ],
    if (band.columnLayout != null) 'columnLayout': band.columnLayout!.toJson(),
  };
}
```

In `_decodeBand`, read it back (add the `columnLayout:` argument to the `Band(...)` constructor):

```dart
  return Band(
    id: json['id']! as String,
    type: _parseBandType(json['type']),
    height: (json['height']! as num).toDouble(),
    elements: elements == null
        ? const <ReportElement>[]
        : <ReportElement>[
            for (final Object? element in elements as List)
              registry.decode((element! as Map).cast<String, Object?>()),
          ],
    columnLayout: json['columnLayout'] == null
        ? null
        : ColumnLayout.fromJson(
            (json['columnLayout']! as Map).cast<String, Object?>()),
  );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/serialization/report_codec_v2_test.dart`
Expected: PASS (the new test plus all existing codec tests — proving existing documents are unaffected).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart packages/jet_print/test/domain/serialization/report_codec_v2_test.dart
git commit -m "feat(034): serialize Band.columnLayout (additive, omitted when null)"
```

---

### Task 5: Grid validation

**Files:**
- Modify: `lib/src/domain/report_validation.dart`
- Test: `test/domain/column_layout_validation_test.dart`

**Interfaces:**
- Consumes: `def.soleDetailBand` (Task 3), `ColumnLayout` (Task 1).
- Produces: `validate(def)` additionally — for the active label band — emits errors (FR-007), an element-overflow warning (FR-008), an `column layout ... ignored` warning for a `columnLayout` on any non-active band (FR-009). No new public symbol.

- [ ] **Step 1: Write the failing test**

Create `test/domain/column_layout_validation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/column_layout.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_validation.dart';

// 200x100 page, 10pt margins -> body 180 wide, 80 tall (no furniture).
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

ReportDefinition _labels(ColumnLayout grid,
    {double bandHeight = 30, List<ReportElement> elements = const <ReportElement>[]}) =>
    ReportDefinition(
      name: 'labels',
      page: _page,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'd',
              type: BandType.detail,
              height: bandHeight,
              elements: elements,
              columnLayout: grid)),
        ]),
      ),
    );

List<Diagnostic> _errors(ReportDefinition d) => validate(d)
    .where((Diagnostic x) => x.severity == DiagnosticSeverity.error)
    .toList();
List<Diagnostic> _warnings(ReportDefinition d) => validate(d)
    .where((Diagnostic x) => x.severity == DiagnosticSeverity.warning)
    .toList();

void main() {
  const ColumnLayout ok = ColumnLayout(
      columnCount: 2, columnWidth: 80, columnSpacing: 20, rowSpacing: 10);

  test('a valid grid produces no diagnostics', () {
    expect(validate(_labels(ok)), isEmpty);
  });

  test('columnCount < 1 is an error', () {
    final List<Diagnostic> e = _errors(_labels(
        const ColumnLayout(
            columnCount: 0, columnWidth: 80, columnSpacing: 20, rowSpacing: 10)));
    expect(e.single.message, contains('columnCount'));
  });

  test('a negative dimension is an error', () {
    expect(
        _errors(_labels(const ColumnLayout(
            columnCount: 2,
            columnWidth: 80,
            columnSpacing: -1,
            rowSpacing: 10))),
        isNotEmpty);
  });

  test('grid wider than the body is an error', () {
    // 3 * 80 + 2*20 = 280 > 180.
    final List<Diagnostic> e = _errors(_labels(const ColumnLayout(
        columnCount: 3, columnWidth: 80, columnSpacing: 20, rowSpacing: 10)));
    expect(e.single.message, contains('wider than'));
  });

  test('a label taller than the body is an error', () {
    final List<Diagnostic> e = _errors(_labels(ok, bandHeight: 90));
    expect(e.single.message, contains('taller than'));
  });

  test('an element past columnWidth warns (overflow)', () {
    final List<Diagnostic> w = _warnings(_labels(ok, elements: <ReportElement>[
      ShapeElement(
          id: 's',
          bounds: const JetRect(x: 0, y: 0, width: 120, height: 30),
          kind: ShapeKind.rectangle),
    ]));
    expect(w.single.message, contains('overflows cell width'));
  });

  test('columnLayout on a non-detail (furniture) band is ignored with a warning',
      () {
    final ReportDefinition def = ReportDefinition(
      name: 'x',
      page: _page,
      furniture: const PageFurniture(
        pageHeader: Band(
            id: 'ph',
            type: BandType.pageHeader,
            height: 10,
            columnLayout: ok),
      ),
      body: const ReportBody(
          root: DetailScope(id: 'root', children: <ScopeNode>[
        BandNode(Band(id: 'd', type: BandType.detail, height: 30)),
      ])),
    );
    expect(_warnings(def).single.message, contains('ignored'));
  });

  test('columnLayout on a detail band of a non-pure body is ignored', () {
    final ReportDefinition def = ReportDefinition(
      name: 'x',
      page: _page,
      body: const ReportBody(
        title: Band(id: 't', type: BandType.title, height: 10),
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'd', type: BandType.detail, height: 30, columnLayout: ok)),
        ]),
      ),
    );
    expect(_warnings(def).any((Diagnostic d) => d.message.contains('ignored')),
        isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/column_layout_validation_test.dart`
Expected: FAIL — the valid-grid test passes vacuously but the error/warning tests fail (no column diagnostics emitted yet).

- [ ] **Step 3: Write minimal implementation**

In `lib/src/domain/report_validation.dart`, add the import after the existing `band.dart` import:

```dart
import 'column_layout.dart';
```

Add this private helper at the end of the file (after `_recordFieldRefs`):

```dart
/// Every [Band] in [def], in document order (furniture, body once-bands, then
/// the scope tree). Used to find stray `columnLayout`s (spec 034).
List<Band> _allBands(ReportDefinition def) {
  final List<Band> bands = <Band>[];
  void add(Band? b) {
    if (b != null) bands.add(b);
  }

  add(def.furniture.pageHeader);
  add(def.furniture.pageFooter);
  add(def.furniture.columnHeader);
  add(def.furniture.columnFooter);
  add(def.furniture.background);
  add(def.body.title);
  add(def.body.summary);
  add(def.body.noData);
  void walk(DetailScope s) {
    for (final GroupLevel g in s.groups) {
      add(g.header);
      add(g.footer);
    }
    add(s.footer);
    for (final ScopeNode node in s.children) {
      switch (node) {
        case BandNode(band: final Band b):
          add(b);
        case NestedScope(scope: final DetailScope child):
          walk(child);
      }
    }
  }

  walk(def.body.root);
  return bands;
}

/// Validates the spec-034 label grid: the active band's geometry (FR-007/008)
/// and a fallback warning for any `columnLayout` carried by a band that is not
/// the active label band (FR-009).
void _validateColumns(ReportDefinition def, List<Diagnostic> out) {
  final Band? active =
      def.soleDetailBand?.columnLayout != null ? def.soleDetailBand : null;

  for (final Band b in _allBands(def)) {
    if (b.columnLayout != null && !identical(b, active)) {
      out.add(Diagnostic(
        DiagnosticSeverity.warning,
        'column layout on band "${b.id}" is ignored — it applies only to the '
        'lone detail band of a pure single-detail body',
        elementId: b.id,
      ));
    }
  }

  if (active == null) return;
  final ColumnLayout cl = active.columnLayout!;
  if (cl.columnCount < 1) {
    out.add(Diagnostic(DiagnosticSeverity.error,
        'columnLayout columnCount must be >= 1 (was ${cl.columnCount})',
        elementId: active.id));
  }
  if (cl.columnWidth <= 0 || cl.columnSpacing < 0 || cl.rowSpacing < 0) {
    out.add(Diagnostic(
        DiagnosticSeverity.error,
        'columnLayout dimensions must be non-negative (columnWidth > 0)',
        elementId: active.id));
  }

  final double bodyWidth =
      def.page.width - def.page.margins.left - def.page.margins.right;
  if (cl.columnCount >= 1 && cl.columnWidth > 0) {
    final double gridWidth =
        cl.columnCount * cl.columnWidth + (cl.columnCount - 1) * cl.columnSpacing;
    if (gridWidth > bodyWidth) {
      out.add(Diagnostic(
          DiagnosticSeverity.error,
          'columnLayout grid ($gridWidth pt) is wider than the page body '
          '($bodyWidth pt)',
          elementId: active.id));
    }
  }

  final double headerH = def.furniture.pageHeader?.height ?? 0;
  final double footerH = def.furniture.pageFooter?.height ?? 0;
  final double bodyCapacity = def.page.height -
      def.page.margins.top -
      def.page.margins.bottom -
      headerH -
      footerH;
  if (active.height > bodyCapacity) {
    out.add(Diagnostic(
        DiagnosticSeverity.error,
        'label height (${active.height} pt) is taller than the page body '
        '($bodyCapacity pt); no rows fit',
        elementId: active.id));
  }

  for (final ReportElement el in active.elements) {
    if (el.bounds.x + el.bounds.width > cl.columnWidth) {
      out.add(Diagnostic(
          DiagnosticSeverity.warning,
          'element "${el.id}" overflows cell width (${cl.columnWidth} pt); '
          'it will be clipped',
          elementId: el.id));
    }
  }
}
```

Call it from `validate()`, immediately before the I1 duplicate-id loop (after `walkScope(def.body.root, ...)`):

```dart
  _validateColumns(def, out);

  // I1 — duplicate ids (reported once per offending id, in first-seen order).
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/column_layout_validation_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 5: Verify existing validation tests still pass**

Run: `flutter test test/domain/`
Expected: PASS (the new block only fires when a `columnLayout` is present, so existing definitions are unaffected).

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/report_validation.dart packages/jet_print/test/domain/column_layout_validation_test.dart
git commit -m "feat(034): validate the label grid (geometry + fallback warnings)"
```

---

### Task 6: Grid-placement path in the layouter

**Files:**
- Modify: `lib/src/rendering/layout/report_layouter.dart`
- Test: `test/rendering/layout/multi_column_layout_test.dart`

**Interfaces:**
- Consumes: `def.soleDetailBand` (Task 3), `ColumnLayout` (Task 1), the existing `MeasuredBand`, `_PlacedBand`, `LazyLayout._`.
- Produces: `_PlacedBand` becomes `({MeasuredBand band, double x, double y})`; `_place` gains a `double leftX` parameter; `layoutLazyDefinition` branches onto a grid placement when `def.soleDetailBand?.columnLayout != null` and `filled.bands` is non-empty. No public-signature change (`layoutDefinition`/`layoutLazyDefinition`/`LazyLayout.buildPage` keep their signatures).

This is the one task that touches battle-tested code. The grid test asserts cell `x`/`y`, which forces the `_PlacedBand.x` plumbing; the regression sub-test plus the existing layouter/golden suites guard the linear path (SC-002).

- [ ] **Step 1: Write the failing test**

Create `test/rendering/layout/multi_column_layout_test.dart`:

```dart
// Multi-column label grid placement (spec 034).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/column_layout.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';
import 'package:jet_print/src/rendering/frame/page_frame.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/layout/report_layouter.dart';

// 200x100 page, 10pt margins -> body left=10 top=10, capacity 80 (no furniture).
const PageFormat _page =
    PageFormat(width: 200, height: 100, margins: JetEdgeInsets.all(10));

// 2 columns of 80pt, 20pt gutter, 10pt row gap; 30pt labels.
// rowsPerPage = floor((80+10)/(30+10)) = 2 -> cellsPerPage = 4.
const ColumnLayout _grid = ColumnLayout(
    columnCount: 2, columnWidth: 80, columnSpacing: 20, rowSpacing: 10);

ReportDefinition _def(ColumnLayout? grid) => ReportDefinition(
      name: 'labels',
      page: _page,
      body: ReportBody(
        root: DetailScope(id: 'root', children: <ScopeNode>[
          BandNode(Band(
              id: 'd',
              type: BandType.detail,
              height: 30,
              columnLayout: grid)),
        ]),
      ),
    );

// N detail bands, each a single 80x30 rect filling its cell, ids r0..r(N-1).
FilledReport _filled(int n) => FilledReport(
      page: _page,
      bands: <FilledBand>[
        for (int i = 0; i < n; i++)
          FilledBand(
            type: BandType.detail,
            height: 30,
            elements: <ReportElement>[
              ShapeElement(
                  id: 'r$i',
                  bounds: const JetRect(x: 0, y: 0, width: 80, height: 30),
                  kind: ShapeKind.rectangle),
            ],
            variables: const <String, JetValue>{},
          ),
      ],
    );

JetRect _boundsOf(LayoutResult r, int page, String id) => r.pages[page].primitives
    .whereType<RectPrimitive>()
    .firstWhere((RectPrimitive p) => p.elementId == id)
    .bounds;

void main() {
  test('6 labels fill a 2x2 grid across two pages in horizontal order', () {
    final LayoutResult r =
        ReportLayouter().layoutDefinition(_def(_grid), _filled(6));
    expect(r.pages.length, 2);
    // Page 1: cells (0,0)(0,1)(1,0)(1,1).
    expect(_boundsOf(r, 0, 'r0'),
        const JetRect(x: 10, y: 10, width: 80, height: 30));
    expect(_boundsOf(r, 0, 'r1'),
        const JetRect(x: 110, y: 10, width: 80, height: 30));
    expect(_boundsOf(r, 0, 'r2'),
        const JetRect(x: 10, y: 50, width: 80, height: 30));
    expect(_boundsOf(r, 0, 'r3'),
        const JetRect(x: 110, y: 50, width: 80, height: 30));
    // Page 2: remainder restarts at the grid origin.
    expect(_boundsOf(r, 1, 'r4'),
        const JetRect(x: 10, y: 10, width: 80, height: 30));
    expect(_boundsOf(r, 1, 'r5'),
        const JetRect(x: 110, y: 10, width: 80, height: 30));
  });

  test('page count is ceil(detailCount / cellsPerPage)', () {
    expect(ReportLayouter().layoutDefinition(_def(_grid), _filled(4)).pages.length,
        1);
    expect(ReportLayouter().layoutDefinition(_def(_grid), _filled(5)).pages.length,
        2);
  });

  test('a null columnLayout keeps the linear path byte-identical', () {
    // Linear: band0 at y=10, band1 at y=40 (stacked full width origin x=10).
    final LayoutResult r =
        ReportLayouter().layoutDefinition(_def(null), _filled(2));
    expect(r.pages.length, 1);
    expect(_boundsOf(r, 0, 'r0'),
        const JetRect(x: 10, y: 10, width: 80, height: 30));
    expect(_boundsOf(r, 0, 'r1'),
        const JetRect(x: 10, y: 40, width: 80, height: 30));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/rendering/layout/multi_column_layout_test.dart`
Expected: FAIL — the grid tests fail (`r1` lands at the linear `y=40`, not the cell `x=110, y=10`); the null-columnLayout test passes.

- [ ] **Step 3a: Plumb a per-band `x` through `_PlacedBand` and `_place`**

In `lib/src/rendering/layout/report_layouter.dart`, change the `_PlacedBand` typedef (around line 63):

```dart
/// One body-band placement decided by the boundary pass: the measured [band] at
/// page-absolute (`[x]`, `[y]`). Frame construction replays these on demand.
typedef _PlacedBand = ({MeasuredBand band, double x, double y});
```

Change `_place` to take the left origin as a parameter (replace its signature and the `_left` use):

```dart
  void _place(List<({ReportElement element, JetRect bounds})> boxes,
      double leftX, double topY, FrameBuilder fb) {
    for (final ({ReportElement element, JetRect bounds}) e in boxes) {
      _renderers.rendererFor(e.element).emit(
            e.element,
            _ctx,
            JetRect(
              x: leftX + e.bounds.x,
              y: topY + e.bounds.y,
              width: e.bounds.width,
              height: e.bounds.height,
            ),
            fb,
          );
    }
  }
```

In `buildPage`, update the three `_place` call-sites: the body uses the placed band's `x`; header/footer keep `_left`:

```dart
    for (final _PlacedBand placed in _plans[index]) {
      _place(placed.band.elements, placed.x, placed.y, fb);
    }
    final int pageNumber = index + 1;
    double y = _top;
    for (final Band h in _headers) {
      _place(<({ReportElement element, JetRect bounds})>[
        for (final ReportElement el in h.elements)
          (element: _substitute(el, pageNumber), bounds: el.bounds),
      ], _left, y, fb);
      y += h.height;
    }
    y = _bodyBottom;
    for (final Band f in _footers) {
      _place(<({ReportElement element, JetRect bounds})>[
        for (final ReportElement el in f.elements)
          (element: _substitute(el, pageNumber), bounds: el.bounds),
      ], _left, y, fb);
      y += f.height;
    }
```

- [ ] **Step 3b: Record `x: left` on every linear placement**

In `layoutLazyDefinition`, the linear path has placements in `reEmitHeaders` and the main loop. Update both to carry `x: left`:

In `reEmitHeaders`:

```dart
    void reEmitHeaders() {
      for (final _OpenGroup g in openStack) {
        if (!g.reprint) continue;
        for (final MeasuredBand hmb in g.headers) {
          plans.last.add((band: hmb, x: left, y: cursorY));
          cursorY += hmb.height;
        }
      }
    }
```

In the main loop (the `plans.last.add` near the former line 542):

```dart
      plans.last.add((band: mb, x: left, y: cursorY));
      cursorY += mb.height;
```

- [ ] **Step 3c: Branch onto grid placement**

In `layoutLazyDefinition`, the linear path currently declares `plans` and `cursorY` at what was line 471–473 and fills them in the span pre-pass + main loop (former lines 421–574). Restructure so a grid branch produces `plans` instead. Replace the linear block — from the declaration:

```dart
    final List<_OpenGroup> openStack = <_OpenGroup>[];
    final List<List<_PlacedBand>> plans = <List<_PlacedBand>>[<_PlacedBand>[]];
    double cursorY = bodyTop;
```

down through the end of the main `for` loop (the line `prevHeaderGroup = ... ;` and its closing `}` just before `return LazyLayout._(`) — with:

```dart
    final ColumnLayout? columns = def.soleDetailBand?.columnLayout;
    final List<List<_PlacedBand>> plans;

    if (columns != null && measured.isNotEmpty) {
      // Spec 034 — uniform label grid, horizontal print order. Cells are fixed
      // (designed) height; the next row advances by the pitch, so over-tall
      // content clips rather than reflowing.
      final double labelHeight = def.soleDetailBand!.height;
      final int cols = columns.columnCount < 1 ? 1 : columns.columnCount;
      final double pitch = labelHeight + columns.rowSpacing;
      int rowsPerPage =
          pitch <= 0 ? 1 : ((bodyCapacity + columns.rowSpacing) / pitch).floor();
      if (rowsPerPage < 1) rowsPerPage = 1;
      final int cellsPerPage = rowsPerPage * cols;

      plans = <List<_PlacedBand>>[<_PlacedBand>[]];
      for (int i = 0; i < measured.length; i++) {
        final int k = i % cellsPerPage;
        if (i > 0 && k == 0) plans.add(<_PlacedBand>[]);
        final int row = k ~/ cols;
        final int col = k % cols;
        final double x =
            left + col * (columns.columnWidth + columns.columnSpacing);
        final double y = bodyTop + row * pitch;
        plans.last.add((band: measured[i], x: x, y: y));
      }
    } else {
      final List<_OpenGroup> openStack = <_OpenGroup>[];
      final List<List<_PlacedBand>> linearPlans =
          <List<_PlacedBand>>[<_PlacedBand>[]];
      double cursorY = bodyTop;

      void reEmitHeaders() {
        for (final _OpenGroup g in openStack) {
          if (!g.reprint) continue;
          for (final MeasuredBand hmb in g.headers) {
            linearPlans.last.add((band: hmb, x: left, y: cursorY));
            cursorY += hmb.height;
          }
        }
      }

      void breakPage() {
        linearPlans.add(<_PlacedBand>[]);
        cursorY = bodyTop;
        reEmitHeaders();
      }

      // ... the EXISTING main pagination loop verbatim, except every
      // `plans.last.add(...)` becomes `linearPlans.last.add((band: mb, x: left,
      // y: cursorY))` and `breakPage()`/`reEmitHeaders()` reference linearPlans.

      plans = linearPlans;
    }
```

IMPORTANT: this is a *move*, not a rewrite. The span pre-pass (`cum`/`keepExtent`/`startNewPageAt`, former lines 417–469) is linear-only — move it inside the `else` branch above the loop. Keep the chrome-compilation block, the `measured` list, and the `groups`/`levelOf`/`groupByName` maps where they are (the grid branch ignores the group maps but they are cheap and harmless). The final `return LazyLayout._(... plans: plans, ...)` is unchanged.

- [ ] **Step 4: Run the new test to verify it passes**

Run: `flutter test test/rendering/layout/multi_column_layout_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full layout + engine suites for regression**

Run: `flutter test test/rendering/layout/ test/rendering/engine/`
Expected: PASS (the linear path is byte-identical — `x: left` reproduces the former fixed `_left` origin).

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/layout/report_layouter.dart packages/jet_print/test/rendering/layout/multi_column_layout_test.dart
git commit -m "feat(034): grid-placement path for multi-column label sheets"
```

---

### Task 7: Rendered label-sheet golden (SC-001)

**Files:**
- Create: `test/goldens/label_sheet_test.dart`
- Create (generated): `test/goldens/label_sheet_light.png`

**Interfaces:**
- Consumes: the public API — `ReportDefinition`, `Band`, `ColumnLayout` (exported in Task 1), `JetReportEngine`, `JetInMemoryDataSource`, `JetReportPreview`.

This locks the visual placement end-to-end through the real paint pipeline, mirroring `test/goldens/rendered_invoice_test.dart`.

- [ ] **Step 1: Write the golden test**

Create `test/goldens/label_sheet_test.dart`:

```dart
// Rendered multi-column label sheet golden (spec 034). Public API only;
// regenerate with `--update-goldens`.
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

ReportDefinition _definition() => const ReportDefinition(
      name: 'Labels',
      page: PageFormat(width: 400, height: 300, margins: JetEdgeInsets.all(16)),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'label',
              type: BandType.detail,
              height: 60,
              columnLayout: ColumnLayout(
                  columnCount: 2,
                  columnWidth: 170,
                  columnSpacing: 28,
                  rowSpacing: 12),
              elements: <ReportElement>[
                TextElement(
                  id: 'name',
                  bounds: JetRect(x: 6, y: 6, width: 158, height: 16),
                  text: 'name',
                  style: JetTextStyle(weight: JetFontWeight.bold),
                  expression: r'$F{name}',
                ),
                TextElement(
                  id: 'city',
                  bounds: JetRect(x: 6, y: 26, width: 158, height: 14),
                  text: 'city',
                  expression: r'$F{city}',
                ),
              ],
            )),
          ],
        ),
      ),
    );

RenderedReport _report() => const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (int i = 1; i <= 6; i++)
          <String, Object?>{'name': 'Contact $i', 'city': 'City $i'},
      ]),
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 480));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ShadApp(
    themeMode: ThemeMode.light,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      JetPrintLocalizations.delegate,
    ],
    supportedLocales: JetPrintLocalizations.supportedLocales,
    theme: ShadThemeData(
      brightness: Brightness.light,
      colorScheme: const ShadSlateColorScheme.light(),
    ),
    home: JetReportPreview(report: _report()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rendered label sheet matches its light golden',
      (WidgetTester tester) async {
    await _pump(tester);
    await expectLater(
      find.byType(JetReportPreview),
      matchesGoldenFile('label_sheet_light.png'),
    );
  });
}
```

- [ ] **Step 2: Run to confirm the golden is missing**

Run: `flutter test test/goldens/label_sheet_test.dart`
Expected: FAIL — `Could not be compared against non-existent file ... label_sheet_light.png`.

- [ ] **Step 3: Generate the golden**

Run: `flutter test --update-goldens test/goldens/label_sheet_test.dart`
Expected: PASS; creates `test/goldens/label_sheet_light.png`.

- [ ] **Step 4: Re-run without the flag to confirm it matches**

Run: `flutter test test/goldens/label_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Inspect the PNG before committing**

Open `packages/jet_print/test/goldens/label_sheet_light.png` and confirm it shows a 2-column grid: 6 labels (Contact 1…6) in two columns of three rows, left-to-right reading order. If it does not, the layout is wrong — stop and revisit Task 6 rather than committing a wrong golden.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/goldens/label_sheet_test.dart packages/jet_print/test/goldens/label_sheet_light.png
git commit -m "test(034): rendered label-sheet golden"
```

---

### Task 8: Full-suite verification (SC-002, SC-006)

**Files:** none (verification + final commit only).

- [ ] **Step 1: Analyzer is clean**

Run: `flutter analyze lib test`
Expected: `No issues found!`

- [ ] **Step 2: Full jet_print suite is green**

Run: `flutter test`
Expected: PASS — all existing tests (1568+) plus the new spec-034 tests; **zero golden diffs** for pre-existing goldens (SC-002 / SC-006).

- [ ] **Step 3: Playground suite is green**

Run (from repo root): `cd /Users/ahmeturel/Projects/oss/jet-print && (cd packages/jet_print_playground 2>/dev/null && flutter test) || echo "no playground package here — confirm location"`
Expected: PASS. (If the playground lives elsewhere, run its `flutter test`.)

- [ ] **Step 4: Confirm clean tree**

Run (from repo root): `git status`
Expected: clean (everything already committed by Tasks 1–7). If anything is outstanding, commit it:

```bash
git commit -am "chore(034): finalize multi-column label sheets engine slice"
```

---

## Self-Review

**1. Spec coverage:**
- FR-001 → Tasks 1, 2 (type + `Band` property). FR-002/003/004 → Task 6 (grid arithmetic, horizontal order). FR-005 → Task 6 (furniture via untouched `_headers`/`_footers`; `bodyTop` already excludes them) + Task 8 regression. FR-006 → Task 6 (`plans.length` = exact page count) + Task 6 page-count test. FR-007/008 → Task 5. FR-009 → Tasks 3 (gate) + 5 (warnings) + 6 (layouter gates on same `soleDetailBand`). FR-010 → Task 4. US1 → Task 7. US2/SC-002 → Task 6 null-layout test + Task 8. US3 → Task 5. US4 → Task 6 furniture stays full-width (no test added beyond regression — acceptable; furniture path is unchanged code). US5 → Task 5. US6 → Task 5. SC-001 → Task 7. SC-003 → Task 5. SC-004 → Task 6. SC-005 → Task 4. SC-006 → Task 8.
- Gap noted: US4 (chrome coexists with the grid) has no dedicated assertion. The grid occupies `[bodyTop, bodyBottom]`, which already excludes `pageHeader`/`pageFooter`, and that code is untouched — so the existing chrome tests + Task 8 cover it. Adding a furniture-plus-grid case to Task 6's test would make it explicit; include it if cheap, but it is not load-bearing.

**2. Placeholder scan:** No TBD/TODO. Every code step shows the literal code. Task 6 Step 3c says "the EXISTING main pagination loop verbatim" — this is a deliberate *move* instruction with the exact mechanical change (`plans.last` → `linearPlans.last`, add `x: left`), not a hand-wave, because reproducing 80 lines verbatim would invite transcription drift; the implementer relocates the existing block.

**3. Type consistency:** `ColumnLayout` fields (`columnCount:int`, others `double`) are identical across Tasks 1/2/4/5/6. `soleDetailBand`/`isPureSingleDetailBody` (Task 3) are used verbatim in Tasks 5/6. `_PlacedBand` is `({MeasuredBand band, double x, double y})` in Task 6 and every placement site updated. `_place(boxes, leftX, topY, fb)` arg order matches all call-sites.

**Risk callout (carry into execution):** `Band` is a core immutable type. Per the spec-031 lesson, a new field is silently dropped by any code that *rebuilds* a `Band` via a direct `Band(...)` constructor instead of `copyWith`. The codec is handled (Task 4). Designer rebuilders are **out of scope** (no authoring path sets `columnLayout` yet) and are the follow-up designer spec's concern — but Task 8 Step 1 (`flutter analyze`) plus the full suite will surface any engine-side rebuilder that needs the field. If `git grep -n "Band(" packages/jet_print/lib/src/rendering` reveals a layouter/filler rebuild site, preserve `columnLayout` there.
