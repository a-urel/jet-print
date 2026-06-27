# Chart Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is Red→Green TDD (Constitution III).

**Goal:** Add bar/line/pie charts as a first-class `ChartElement`, bound to a collection field, resolved to a concrete series at fill time, and drawn as frame primitives so canvas, PDF, and PNG agree (WYSIWYG).

**Architecture:** One `ChartElement` (subtype of `ReportElement`) carries a `ChartType {bar,line,pie}`, a bound `collectionField`, and category/value expressions. The fill phase (`ElementResolver`) reads the row's collection, evaluates the expressions per item, and produces a resolved copy carrying a concrete `List<ChartPoint>`. A pure-Dart `chart_geometry.dart` turns a series + box into bar rects / line polylines / pie wedges + a nice-number axis; `ChartElementRenderer` emits those as existing `RectPrimitive`/`LinePrimitive`/`PathPrimitive`/`TextRunPrimitive`. No widget chart library, no new frame-primitive types, no schema bump.

**Tech Stack:** Dart / Flutter, `flutter_test`. Mirrors the `ShapeElement` slice (domain + codec + renderer + `shapePath` geometry) and the `BarcodeElement` slice (pure-Dart geometry behind a renderer). Spec: `docs/superpowers/specs/2026-06-27-chart-support-design.md`.

## Global Constraints

- **No widget chart lib, zero new dependencies.** Charts draw via existing frame primitives only (the render seam is Flutter-free; PDF generation is pure Dart). Verbatim from spec §"Constraints".
- **Resolved-element seam.** Renderers never evaluate expressions; the fill phase produces a resolved element with literals. `ChartElement.points` is a fill-time artifact — never serialized.
- **Serialize-by-name, omit-when-default, no schema-version bump.** `ChartType` serializes by `.name`; codec omits any field equal to its default; unknown type round-trips through `UnknownElement` untouched.
- **Goldens are the contract (Constitution IV).** Any unexpected golden change during the filler refactor (Task 2) means a behavior change — STOP and inspect.
- **Run `flutter`/`dart` from `packages/jet_print`** (and `apps/jet_print_playground` for the demo). **Run `git` from repo root** `/Users/ahmeturel/Projects/oss/jet-print` (`flutter` leaves cwd inside the package).
- **A new visual type touches more than one switch.** Enumerated explicitly in Task 7: `DesignerToolType` enum, `buildDefaultElement`, `kDefaultElementSize`, the toolbox, and the properties panel. Every `ChartElement` rebuilder (`withBounds`/`withName`/`withVisible`/`copyWith`/codec/commands) must preserve all fields — the recurring silent-field-drop trap; Task 1 and Task 6 round-trip tests guard it.

---

## File Map

**Create:**
- `lib/src/domain/elements/chart_element.dart` — `ChartType` enum, `ChartPoint`, `ChartElement`.
- `lib/src/domain/serialization/chart_element_codec.dart` — `ChartElementCodec`.
- `lib/src/data/collection_rows.dart` — shared `coerceCollectionRows(...)` (extracted from the filler).
- `lib/src/rendering/elements/chart/chart_geometry.dart` — pure axis/bar/line/pie math.
- `lib/src/rendering/elements/renderers/chart_element_renderer.dart` — `ChartElementRenderer`.
- `lib/src/designer/controller/commands/set_chart_options_command.dart` — chart-property edits.
- Tests mirroring each (paths under `test/...`).

**Modify:**
- `lib/jet_print.dart` — export `ChartElement`, `ChartType`, `ChartPoint`.
- `lib/src/rendering/fill/report_filler.dart` — call the shared `coerceCollectionRows`.
- `lib/src/rendering/fill/element_resolver.dart` — add the `ChartElement` branch (`_resolveChart`).
- `lib/src/rendering/elements/built_in_element_renderers.dart` — register the `chart` pair.
- `lib/src/designer/canvas/design_tunables.dart` — `DesignerToolType.chart` + `kDefaultElementSize`.
- `lib/src/designer/controller/commands/create_element_command.dart` — `buildDefaultElement` chart case.
- `lib/src/designer/layout/designer_toolbox.dart` — chart tool button.
- `lib/src/designer/layout/panels/properties_panel.dart` — chart property editors.
- `apps/jet_print_playground/...` — a "Sales chart" demo + goldens.

---

## Task 1: Domain — `ChartElement`, `ChartType`, `ChartPoint`

**Files:**
- Create: `packages/jet_print/lib/src/domain/elements/chart_element.dart`
- Modify: `packages/jet_print/lib/jet_print.dart`
- Test: `packages/jet_print/test/domain/elements/chart_element_test.dart`

**Interfaces:**
- Produces:
  - `enum ChartType { bar, line, pie }`
  - `class ChartPoint { const ChartPoint(this.label, this.value); final String label; final double value; }` (value `==`/`hashCode`/`toString`)
  - `class ChartElement extends ReportElement` with fields `chartType`, `collectionField` (String), `categoryExpression` (String?), `valueExpression` (String), `title` (String?), `showAxes` (bool), `showValueLabels` (bool), `showLegend` (bool), `seriesColor` (JetColor), `points` (List<ChartPoint>, fill-time only, default `const []`); `typeKey => 'chart'`; `copyWith(...)`; `withBounds`/`withName`/`withVisible`; value `==`/`hashCode`.
  - `const JetColor kDefaultChartColor = JetColor(0xFF4F8DF7);`

- [ ] **Step 1: Write the failing test.**

```dart
// test/domain/elements/chart_element_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  const bounds = JetRect(x: 0, y: 0, width: 200, height: 120);
  ChartElement make() => const ChartElement(
        id: 'c1',
        bounds: bounds,
        chartType: ChartType.bar,
        collectionField: 'months',
        categoryExpression: r'$F{label}',
        valueExpression: r'$F{revenue}',
        title: 'Revenue',
      );

  test('typeKey is chart', () => expect(make().typeKey, 'chart'));

  test('withBounds preserves every other field', () {
    final moved = make().withBounds(const JetRect(x: 5, y: 6, width: 50, height: 40));
    expect(moved.bounds, const JetRect(x: 5, y: 6, width: 50, height: 40));
    expect(moved.chartType, ChartType.bar);
    expect(moved.collectionField, 'months');
    expect(moved.categoryExpression, r'$F{label}');
    expect(moved.valueExpression, r'$F{revenue}');
    expect(moved.title, 'Revenue');
  });

  test('withName / withVisible preserve binding fields', () {
    final named = make().withName('Chart A');
    expect(named.name, 'Chart A');
    expect(named.collectionField, 'months');
    final vis = make().withVisible(const BoolProperty.expression(r'$F{show}'));
    expect(vis.collectionField, 'months');
    expect(vis.valueExpression, r'$F{revenue}');
  });

  test('copyWith replaces only named fields', () {
    final c = make().copyWith(chartType: ChartType.pie, showAxes: false);
    expect(c.chartType, ChartType.pie);
    expect(c.showAxes, false);
    expect(c.collectionField, 'months');
  });

  test('points default empty and carry through copyWith', () {
    expect(make().points, isEmpty);
    final withPts = make().copyWith(points: const [ChartPoint('Jan', 10), ChartPoint('Feb', 20)]);
    expect(withPts.points, const [ChartPoint('Jan', 10), ChartPoint('Feb', 20)]);
  });

  test('equality is by value', () {
    expect(make(), equals(make()));
    expect(make().copyWith(title: 'Other'), isNot(equals(make())));
  });
}
```

> Check `BoolProperty.expression(...)` exists (used in the test). If the constructor differs, read `lib/src/domain/bool_property.dart` and adjust the test's `withVisible` line to the real API; everything else stands.

- [ ] **Step 2: Run to verify it fails.**
  Run: `cd packages/jet_print && flutter test test/domain/elements/chart_element_test.dart`
  Expected: FAIL — `ChartElement`/`ChartType`/`ChartPoint` undefined.

- [ ] **Step 3: Write the implementation.**

```dart
// lib/src/domain/elements/chart_element.dart
/// A chart element (spec 2026-06-27): a bar, line, or pie chart bound to a
/// collection field, resolved to a concrete [points] series at fill time and
/// drawn as frame primitives so canvas, preview, and export agree.
library;

import '../bool_property.dart';
import '../geometry.dart';
import '../report_element.dart';
import '../styles/color.dart';

/// The default series color for a new chart (a mid blue).
const JetColor kDefaultChartColor = JetColor(0xFF4F8DF7);

/// The form a [ChartElement] draws. Serializes by [name] — additive, so a chart
/// authored before a new type existed loads byte-for-byte unchanged.
enum ChartType {
  /// Vertical bars, one per series point, scaled to a nice-number value axis.
  bar,

  /// A polyline across the series points, scaled to a nice-number value axis.
  line,

  /// A pie: one wedge per point, angle proportional to its share of the total.
  pie,
}

/// One resolved series point: a [label] (category) and its numeric [value].
/// Produced at fill time from a [ChartElement]'s category/value expressions;
/// never serialized (a fill-time artifact, like a [TextElement]'s resolved text).
class ChartPoint {
  /// Creates a point.
  const ChartPoint(this.label, this.value);

  /// The category label (X axis / pie slice label).
  final String label;

  /// The numeric value (bar/line height, pie slice share).
  final double value;

  @override
  bool operator ==(Object other) =>
      other is ChartPoint && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => 'ChartPoint($label, $value)';
}

/// A chart bound to [collectionField], iterating it to build a series via
/// [categoryExpression] (label) and [valueExpression] (value).
///
/// [points] is empty in an authored element; the fill phase returns a resolved
/// copy with [points] filled and the binding fields left intact. The renderer
/// reads only [points] + the chrome flags.
class ChartElement extends ReportElement {
  /// Creates a chart element.
  const ChartElement({
    required super.id,
    required super.bounds,
    required this.chartType,
    required this.collectionField,
    required this.valueExpression,
    this.categoryExpression,
    this.title,
    this.showAxes = true,
    this.showValueLabels = false,
    this.showLegend = false,
    this.seriesColor = kDefaultChartColor,
    this.points = const <ChartPoint>[],
    super.name,
    super.visible,
  });

  /// The chart form (bar/line/pie).
  final ChartType chartType;

  /// The name of the bound collection field, resolved in the element's band scope.
  final String collectionField;

  /// Per-item value expression (e.g. `$F{revenue}`). Required.
  final String valueExpression;

  /// Per-item label expression (e.g. `$F{month}`). Null → the point index.
  final String? categoryExpression;

  /// Optional chart title drawn above the plot.
  final String? title;

  /// Draw the value axis (ticks + gridlines) and category labels (bar/line).
  final bool showAxes;

  /// Draw a value/percent label on each bar/slice.
  final bool showValueLabels;

  /// Draw a single-series legend swatch.
  final bool showLegend;

  /// The bar/line series color (pie derives a per-slice palette).
  final JetColor seriesColor;

  /// The resolved series. Empty until the fill phase fills it; never serialized.
  final List<ChartPoint> points;

  /// Returns a copy with the named fields replaced and the rest preserved.
  ChartElement copyWith({
    JetRect? bounds,
    ChartType? chartType,
    String? collectionField,
    String? valueExpression,
    String? categoryExpression,
    String? title,
    bool? showAxes,
    bool? showValueLabels,
    bool? showLegend,
    JetColor? seriesColor,
    List<ChartPoint>? points,
    String? name,
    BoolProperty? visible,
  }) =>
      ChartElement(
        id: id,
        bounds: bounds ?? this.bounds,
        chartType: chartType ?? this.chartType,
        collectionField: collectionField ?? this.collectionField,
        valueExpression: valueExpression ?? this.valueExpression,
        categoryExpression: categoryExpression ?? this.categoryExpression,
        title: title ?? this.title,
        showAxes: showAxes ?? this.showAxes,
        showValueLabels: showValueLabels ?? this.showValueLabels,
        showLegend: showLegend ?? this.showLegend,
        seriesColor: seriesColor ?? this.seriesColor,
        points: points ?? this.points,
        name: name ?? this.name,
        visible: visible ?? this.visible,
      );

  @override
  String get typeKey => 'chart';

  @override
  ChartElement withBounds(JetRect bounds) => copyWith(bounds: bounds);

  @override
  ChartElement withName(String? name) => ChartElement(
        id: id,
        bounds: bounds,
        chartType: chartType,
        collectionField: collectionField,
        valueExpression: valueExpression,
        categoryExpression: categoryExpression,
        title: title,
        showAxes: showAxes,
        showValueLabels: showValueLabels,
        showLegend: showLegend,
        seriesColor: seriesColor,
        points: points,
        name: name,
        visible: visible,
      );

  @override
  ChartElement withVisible(BoolProperty visible) =>
      copyWith(visible: visible);

  @override
  bool operator ==(Object other) =>
      other is ChartElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.chartType == chartType &&
      other.collectionField == collectionField &&
      other.valueExpression == valueExpression &&
      other.categoryExpression == categoryExpression &&
      other.title == title &&
      other.showAxes == showAxes &&
      other.showValueLabels == showValueLabels &&
      other.showLegend == showLegend &&
      other.seriesColor == seriesColor &&
      _pointsEqual(other.points, points) &&
      other.name == name &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(
        id, bounds, chartType, collectionField, valueExpression,
        categoryExpression, title, showAxes, showValueLabels, showLegend,
        seriesColor, Object.hashAll(points), name, visible,
      );

  @override
  String toString() => 'ChartElement($id, ${chartType.name}, $collectionField)';
}

bool _pointsEqual(List<ChartPoint> a, List<ChartPoint> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

> Note: `withName` is written out longhand (not via `copyWith`) because `copyWith` cannot set `name`/`categoryExpression`/`title` back to `null` (the `?? this.x` idiom can't express "clear"). `withName(null)` must clear the name — same reason `ShapeElement.withName` is longhand. `withBounds`/`withVisible` never clear a nullable, so they may use `copyWith`.

- [ ] **Step 4: Export from the barrel.** In `lib/jet_print.dart`, beside the other element exports (near line 86), add:

```dart
export 'src/domain/elements/chart_element.dart'
    show ChartElement, ChartType, ChartPoint, kDefaultChartColor;
```

- [ ] **Step 5: Run to verify it passes.**
  Run: `cd packages/jet_print && flutter test test/domain/elements/chart_element_test.dart`
  Expected: PASS.

- [ ] **Step 6: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format lib/src/domain/elements/chart_element.dart test/domain/elements/chart_element_test.dart lib/jet_print.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/elements/chart_element.dart packages/jet_print/lib/jet_print.dart packages/jet_print/test/domain/elements/chart_element_test.dart
git commit -m "feat(domain): ChartElement + ChartType + ChartPoint"
```

---

## Task 2: Shared collection coercion helper

Extract the raw-value → `List<DataRow>` coercion currently inline in `report_filler.dart` (`childRowsOf`, ~L284-318) into one pure helper, so the chart resolver (Task 3) and the filler coerce identically. Behavior-preserving — **goldens must not change**.

**Files:**
- Create: `packages/jet_print/lib/src/data/collection_rows.dart`
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test: `packages/jet_print/test/data/collection_rows_test.dart`

**Interfaces:**
- Produces: `List<DataRow> coerceCollectionRows(Object? raw, {required List<FieldDef> declaredChildFields, void Function(String entryKey, String message)? onSkippedEntry})` — coerces a raw list-of-maps into rows projected onto `declaredChildFields` (or, when that list is empty, onto each entry's own keys). Non-`List` → `const []`. Non-`Map` entries are skipped via `onSkippedEntry`.

- [ ] **Step 1: Write the failing test.**

```dart
// test/data/collection_rows_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/collection_rows.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';

void main() {
  test('coerces a list of maps into rows', () {
    final rows = coerceCollectionRows(
      <Object?>[
        <String, Object?>{'label': 'Jan', 'revenue': 10},
        <String, Object?>{'label': 'Feb', 'revenue': 20},
      ],
      declaredChildFields: const <FieldDef>[],
    );
    expect(rows, hasLength(2));
    expect(rows.first.field('label'), 'Jan');
    expect(rows[1].field('revenue'), 20);
  });

  test('null and non-list raw → empty', () {
    expect(coerceCollectionRows(null, declaredChildFields: const []), isEmpty);
    expect(coerceCollectionRows(42, declaredChildFields: const []), isEmpty);
  });

  test('non-map entries are skipped and reported', () {
    final skipped = <String>[];
    final rows = coerceCollectionRows(
      <Object?>[<String, Object?>{'label': 'ok', 'revenue': 1}, 'oops'],
      declaredChildFields: const <FieldDef>[],
      onSkippedEntry: (k, m) => skipped.add(m),
    );
    expect(rows, hasLength(1));
    expect(skipped, hasLength(1));
  });
}
```

- [ ] **Step 2: Run to verify it fails.**
  Run: `cd packages/jet_print && flutter test test/data/collection_rows_test.dart`
  Expected: FAIL — `coerceCollectionRows` undefined.

- [ ] **Step 3: Implement the helper.** Mirror the existing filler logic (read `report_filler.dart:284-330` for the exact projection rules — when `declaredChildFields` is non-empty the filler projects each map onto those fields; when empty it uses the entry's own keys). 

```dart
// lib/src/data/collection_rows.dart
/// Coerces a raw collection value (a list of row-maps) into [DataRow]s.
///
/// The single source of truth for how a nested collection field's raw value
/// becomes rows — shared by the fill engine (a nested band's children) and the
/// chart resolver (a chart's bound series). A non-`List` [raw] yields no rows;
/// a non-`Map` entry is skipped (reported via [onSkippedEntry]).
library;

import 'data_row.dart';
import 'field_def.dart';

/// Projects [raw] onto rows. When [declaredChildFields] is non-empty each entry
/// is projected onto exactly those fields (missing keys → null); otherwise each
/// entry's own keys define its row.
List<DataRow> coerceCollectionRows(
  Object? raw, {
  required List<FieldDef> declaredChildFields,
  void Function(String entryKey, String message)? onSkippedEntry,
}) {
  if (raw is! List) return const <DataRow>[];
  final List<Map<String, Object?>> maps = <Map<String, Object?>>[];
  for (final Object? entry in raw) {
    if (entry is Map) {
      maps.add(entry.map((Object? k, Object? v) =>
          MapEntry<String, Object?>(k.toString(), v)));
    } else {
      onSkippedEntry?.call(
          'coll-entry', 'Collection contains a non-row entry; it is skipped');
    }
  }
  return <DataRow>[
    for (final Map<String, Object?> m in maps)
      _rowFrom(m, declaredChildFields),
  ];
}

DataRow _rowFrom(Map<String, Object?> m, List<FieldDef> declared) {
  if (declared.isEmpty) {
    return DataRow(
      fields: <FieldDef>[for (final String k in m.keys) FieldDef(k)],
      values: m,
    );
  }
  return DataRow(
    fields: declared,
    values: <String, Object?>{for (final FieldDef f in declared) f.name: m[f.name]},
  );
}
```

> VERIFY against the filler: confirm `FieldDef`'s single-arg constructor is `FieldDef(String name)` (the filler uses `const FieldDef('')`). Confirm `DataRow({required fields, required values})`. If the filler infers child field *types* (not just names) when `declared` is empty, replicate that here so the refactor stays behavior-identical.

- [ ] **Step 4: Run to verify the helper passes.**
  Run: `cd packages/jet_print && flutter test test/data/collection_rows_test.dart`
  Expected: PASS.

- [ ] **Step 5: Refactor the filler to use it.** In `report_filler.dart` `childRowsOf`, replace the inline `maps`/projection block (the body after the `raw is! List` guard, ~L303-330) with a call to `coerceCollectionRows`, threading the existing `declared` child fields and routing skipped-entry reports to the existing `budget.recordRowIssue(...)`. Keep the existing `warnedCollections` warnings for "not in schema" / "did not resolve to a collection" exactly as they are (those guards stay in the filler; only the per-entry projection moves).

- [ ] **Step 6: Run the FULL package suite — goldens must be unchanged.**
  Run: `cd packages/jet_print && flutter test`
  Expected: ALL PASS, **zero golden diffs**. If any golden changes, the refactor altered behavior — STOP and reconcile before continuing.

- [ ] **Step 7: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format lib/src/data/collection_rows.dart lib/src/rendering/fill/report_filler.dart test/data/collection_rows_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/data/collection_rows.dart packages/jet_print/lib/src/rendering/fill/report_filler.dart packages/jet_print/test/data/collection_rows_test.dart
git commit -m "refactor(fill): extract coerceCollectionRows (shared by filler + charts)"
```

---

## Task 3: Fill — resolve a chart's bound collection into a series

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/element_resolver.dart`
- Test: `packages/jet_print/test/rendering/fill/chart_resolver_test.dart`

**Interfaces:**
- Consumes: `ChartElement` (Task 1), `coerceCollectionRows` (Task 2), `FillEvalContext`/`Expression`/`JetValue` (existing, see `_resolveText`).
- Produces: an `ElementResolver.resolve` branch returning a resolved `ChartElement` with `points` filled.

- [ ] **Step 1: Write the failing test.**

```dart
// test/rendering/fill/chart_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/expression/function_registry.dart';
import 'package:jet_print/src/rendering/fill/element_resolver.dart';
import 'package:jet_print/src/rendering/fill/report_diagnostics.dart';

void main() {
  ElementResolver resolver() => ElementResolver(
        functions: JetFunctionRegistry.standard(),
        diagnostics: ReportDiagnostics(),
      );

  DataRow rowWith(Object? months) => DataRow(
        fields: const <FieldDef>[FieldDef('months')],
        values: <String, Object?>{'months': months},
      );

  const chart = ChartElement(
    id: 'c1',
    bounds: JetRect(x: 0, y: 0, width: 200, height: 120),
    chartType: ChartType.bar,
    collectionField: 'months',
    categoryExpression: r'$F{label}',
    valueExpression: r'$F{revenue}',
  );

  test('resolves the bound collection into a series', () {
    final r = resolver().resolve(chart, row: rowWith(<Object?>[
      <String, Object?>{'label': 'Jan', 'revenue': 10},
      <String, Object?>{'label': 'Feb', 'revenue': 25},
    ])) as ChartElement;
    expect(r.points, const <ChartPoint>[ChartPoint('Jan', 10), ChartPoint('Feb', 25)]);
    expect(r.collectionField, 'months'); // binding preserved
  });

  test('empty / missing collection → empty series, no throw', () {
    expect((resolver().resolve(chart, row: rowWith(<Object?>[])) as ChartElement).points, isEmpty);
    expect((resolver().resolve(chart, row: rowWith(null)) as ChartElement).points, isEmpty);
  });

  test('non-numeric value resolves to 0 and warns', () {
    final diags = ReportDiagnostics();
    final r = ElementResolver(functions: JetFunctionRegistry.standard(), diagnostics: diags)
        .resolve(chart, row: rowWith(<Object?>[
          <String, Object?>{'label': 'Jan', 'revenue': 'oops'},
        ])) as ChartElement;
    expect(r.points.single.value, 0);
    expect(diags.entries, isNotEmpty);
  });

  test('null categoryExpression labels by index', () {
    const noCat = ChartElement(
      id: 'c2', bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
      chartType: ChartType.pie, collectionField: 'months', valueExpression: r'$F{revenue}');
    final r = resolver().resolve(noCat, row: rowWith(<Object?>[
      <String, Object?>{'revenue': 5}, <String, Object?>{'revenue': 7},
    ])) as ChartElement;
    expect(r.points.map((p) => p.label).toList(), <String>['1', '2']);
  });
}
```

> VERIFY the exact constructors used: `JetFunctionRegistry.standard()` (or whatever the existing resolver tests use to build a registry — grep `test/rendering/fill` for how `ElementResolver` is constructed and copy that), and `ReportDiagnostics` + how to read its recorded entries (`diags.entries` is a guess — use the real accessor). Adjust the test to the real names; the assertions stand.

- [ ] **Step 2: Run to verify it fails.**
  Run: `cd packages/jet_print && flutter test test/rendering/fill/chart_resolver_test.dart`
  Expected: FAIL — chart resolves unchanged (no `points`).

- [ ] **Step 3: Implement `_resolveChart`.** In `element_resolver.dart`, add a branch at the top of `resolve(...)` (beside the `BarcodeElement`/`TextElement` branches):

```dart
if (element is ChartElement) {
  return _resolveChart(element, row: row, params: params, variables: variables);
}
```

Add imports for `ChartElement`/`ChartPoint` (`../../domain/elements/chart_element.dart`), `coerceCollectionRows` (`../../data/collection_rows.dart`), and the existing `data_row.dart`. Then add the method (mirror `_resolveText`'s context-building):

```dart
ChartElement _resolveChart(
  ChartElement el, {
  required DataRow? row,
  required Map<String, Object?> params,
  required Map<String, JetValue> variables,
}) {
  final Object? raw = row?.hasField(el.collectionField) ?? false
      ? row!.field(el.collectionField)
      : null;
  final List<DataRow> rows = coerceCollectionRows(raw,
      declaredChildFields: const <FieldDef>[]);
  final Expression valueExpr = Expression.parse(el.valueExpression);
  final Expression? catExpr =
      el.categoryExpression == null ? null : Expression.parse(el.categoryExpression!);
  final List<ChartPoint> pts = <ChartPoint>[];
  for (var i = 0; i < rows.length; i++) {
    final FillEvalContext ctx = FillEvalContext(
      row: rows[i],
      params: params,
      variables: variables,
      functions: functions,
      diagnostics: diagnostics,
      warnedFields: warnedFields,
      pageRefs: <String>{},
      elementId: el.id,
      budget: budget,
    );
    final JetValue v = valueExpr.evaluate(ctx);
    final double value;
    if (v is JetNumber) {
      value = v.value.toDouble();
    } else {
      value = 0;
      if (warnedFields.add('chart-nan:${el.id}')) {
        diagnostics.warning(
            'Chart "${el.id}" value expression did not resolve to a number',
            elementId: el.id);
      }
    }
    final String label = catExpr == null
        ? '${i + 1}'
        : jetStringify(catExpr.evaluate(ctx));
    pts.add(ChartPoint(label, value));
  }
  return el.copyWith(points: pts);
}
```

> VERIFY: `Expression.parse`, `FillEvalContext(...)` field list, `JetNumber`, and `jetStringify` are all already imported by `element_resolver.dart` (they are — see `_resolveText`). Add only the three new imports. If `Expression.parse` can throw `ExpressionException`, wrap the two `parse` calls in a try/catch that records `diagnostics.error(...)` and returns `el.copyWith(points: const [])` (mirror `_resolveText`'s parse guard).

- [ ] **Step 4: Run to verify it passes.**
  Run: `cd packages/jet_print && flutter test test/rendering/fill/chart_resolver_test.dart`
  Expected: PASS.

- [ ] **Step 5: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format lib/src/rendering/fill/element_resolver.dart test/rendering/fill/chart_resolver_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill/element_resolver.dart packages/jet_print/test/rendering/fill/chart_resolver_test.dart
git commit -m "feat(fill): resolve ChartElement collection binding into a series"
```

---

## Task 4: Pure chart geometry (axis, bars, line, pie)

**Files:**
- Create: `packages/jet_print/lib/src/rendering/elements/chart/chart_geometry.dart`
- Test: `packages/jet_print/test/rendering/elements/chart/chart_geometry_test.dart`

**Interfaces:**
- Produces (all pure, no Flutter, no measurer):
  - `class AxisScale { const AxisScale({required this.niceMax, required this.step, required this.ticks}); final double niceMax; final double step; final List<double> ticks; }`
  - `AxisScale niceAxis(double maxValue, {int targetTicks = 4})`
  - `List<JetRect> barRects(List<ChartPoint> pts, JetRect plot, AxisScale axis, {double gapRatio = 0.25})`
  - `List<JetOffset> linePolyline(List<ChartPoint> pts, JetRect plot, AxisScale axis)`
  - `class PieSlice { const PieSlice({required this.commands, required this.startAngle, required this.sweepAngle, required this.value, required this.index}); final List<PathCommand> commands; final double startAngle; final double sweepAngle; final double value; final int index; }`
  - `List<PieSlice> pieSlices(List<ChartPoint> pts, JetRect box, {int arcSegments = 24})`

- [ ] **Step 1: Write the failing test.**

```dart
// test/rendering/elements/chart/chart_geometry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/elements/chart/chart_geometry.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';

void main() {
  group('niceAxis', () {
    test('rounds the max up to a nice multiple', () {
      final a = niceAxis(23);
      expect(a.niceMax, 24); // step 6, ceil(23/6)*6
      expect(a.step, 6);
      expect(a.ticks, <double>[0, 6, 12, 18, 24]);
    });
    test('non-positive max is safe', () {
      expect(niceAxis(0).niceMax, greaterThan(0));
      expect(niceAxis(-5).niceMax, greaterThan(0));
    });
  });

  test('barRects: one rect per point, scaled to niceMax, inside the plot', () {
    const plot = JetRect(x: 10, y: 10, width: 100, height: 50);
    final axis = niceAxis(10); // niceMax 10
    final rects = barRects(const <ChartPoint>[ChartPoint('a', 5), ChartPoint('b', 10)], plot, axis);
    expect(rects, hasLength(2));
    expect(rects[0].height, closeTo(25, 1e-9)); // 5/10 * 50
    expect(rects[1].height, closeTo(50, 1e-9)); // full
    // bottom-aligned to the plot's bottom edge
    expect(rects[1].y + rects[1].height, closeTo(plot.y + plot.height, 1e-9));
    // within horizontal bounds
    expect(rects[0].x, greaterThanOrEqualTo(plot.x));
  });

  test('linePolyline: one point per series point at the value height', () {
    const plot = JetRect(x: 0, y: 0, width: 100, height: 40);
    final pts = linePolyline(const <ChartPoint>[ChartPoint('a', 0), ChartPoint('b', 20)], plot, niceAxis(20));
    expect(pts, hasLength(2));
    expect(pts[0].dy, closeTo(40, 1e-9)); // value 0 → bottom
    expect(pts[1].dy, closeTo(0, 1e-9));  // value 20 (=niceMax) → top
  });

  group('pieSlices', () {
    const box = JetRect(x: 0, y: 0, width: 100, height: 100);
    test('sweep angles sum to 2*pi and split by value share', () {
      final slices = pieSlices(const <ChartPoint>[ChartPoint('a', 1), ChartPoint('b', 3)], box);
      expect(slices, hasLength(2));
      final total = slices.fold<double>(0, (s, x) => s + x.sweepAngle);
      expect(total, closeTo(2 * 3.141592653589793, 1e-6));
      expect(slices[1].sweepAngle, closeTo(3 * slices[0].sweepAngle, 1e-6));
    });
    test('each slice is a closed path (MoveTo .. ClosePath)', () {
      final s = pieSlices(const <ChartPoint>[ChartPoint('a', 1)], box).single;
      expect(s.commands.first, isA<MoveTo>());
      expect(s.commands.last, isA<ClosePath>());
    });
  });

  test('empty series → empty geometry, no throw', () {
    const plot = JetRect(x: 0, y: 0, width: 10, height: 10);
    expect(barRects(const <ChartPoint>[], plot, niceAxis(1)), isEmpty);
    expect(pieSlices(const <ChartPoint>[], plot), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails.**
  Run: `cd packages/jet_print && flutter test test/rendering/elements/chart/chart_geometry_test.dart`
  Expected: FAIL — module undefined.

- [ ] **Step 3: Implement the geometry.**

```dart
// lib/src/rendering/elements/chart/chart_geometry.dart
/// Pure-Dart chart geometry: turns a resolved series + a target box into bar
/// rects, a line polyline, or pie wedges plus a nice-number value axis. No
/// Flutter, no chart library, no text measurement — the single source the chart
/// renderer replays into frame primitives (so canvas/preview/export agree).
library;

import 'dart:math' as math;

import '../../../domain/elements/chart_element.dart';
import '../../../domain/geometry.dart';
import '../../frame/primitive.dart';

/// A nice-number value axis: the rounded-up [niceMax], the tick [step], and the
/// tick values from 0..niceMax inclusive.
class AxisScale {
  /// Creates an axis scale.
  const AxisScale({required this.niceMax, required this.step, required this.ticks});

  /// The axis maximum (>= the data max), a whole multiple of [step].
  final double niceMax;

  /// The spacing between ticks.
  final double step;

  /// Tick values, 0..[niceMax] inclusive.
  final List<double> ticks;
}

/// A nice-number axis covering 0..[maxValue] in roughly [targetTicks] steps,
/// using the classic 1/2/5×10ⁿ ladder. Non-positive [maxValue] yields a safe
/// unit axis (so an all-zero or empty series still draws).
AxisScale niceAxis(double maxValue, {int targetTicks = 4}) {
  if (!(maxValue > 0)) {
    return const AxisScale(niceMax: 1, step: 1, ticks: <double>[0, 1]);
  }
  final double rawStep = maxValue / targetTicks;
  final double mag = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final double norm = rawStep / mag;
  final double niceNorm = norm < 1.5 ? 1 : (norm < 3 ? 2 : (norm < 7 ? 5 : 10));
  final double step = niceNorm * mag;
  final double niceMax = (maxValue / step).ceil() * step;
  final List<double> ticks = <double>[];
  for (double v = 0; v <= niceMax + step * 1e-9; v += step) {
    ticks.add(v);
  }
  return AxisScale(niceMax: niceMax, step: step, ticks: ticks);
}

/// One bottom-aligned bar rect per point, scaled to [axis].niceMax within [plot].
List<JetRect> barRects(List<ChartPoint> pts, JetRect plot, AxisScale axis,
    {double gapRatio = 0.25}) {
  if (pts.isEmpty || axis.niceMax <= 0) return const <JetRect>[];
  final double slot = plot.width / pts.length;
  final double barW = slot * (1 - gapRatio);
  return <JetRect>[
    for (var i = 0; i < pts.length; i++)
      () {
        final double h = (pts[i].value.clamp(0, axis.niceMax) / axis.niceMax) * plot.height;
        return JetRect(
          x: plot.x + i * slot + (slot - barW) / 2,
          y: plot.y + plot.height - h,
          width: barW,
          height: h,
        );
      }(),
  ];
}

/// One polyline vertex per point, at the slot centre and the value's height.
List<JetOffset> linePolyline(List<ChartPoint> pts, JetRect plot, AxisScale axis) {
  if (pts.isEmpty || axis.niceMax <= 0) return const <JetOffset>[];
  final double slot = plot.width / pts.length;
  return <JetOffset>[
    for (var i = 0; i < pts.length; i++)
      JetOffset(
        plot.x + (i + 0.5) * slot,
        plot.y + plot.height -
            (pts[i].value.clamp(0, axis.niceMax) / axis.niceMax) * plot.height,
      ),
  ];
}

/// A wedge of a pie. [commands] is a closed path (centre → arc → close).
class PieSlice {
  /// Creates a slice.
  const PieSlice({
    required this.commands,
    required this.startAngle,
    required this.sweepAngle,
    required this.value,
    required this.index,
  });

  /// The closed wedge path.
  final List<PathCommand> commands;

  /// Start angle (radians; -pi/2 is the top).
  final double startAngle;

  /// Sweep (radians), proportional to the value share.
  final double sweepAngle;

  /// The slice's value.
  final double value;

  /// The slice's index in the series (drives palette colour).
  final int index;
}

/// One wedge per positive-valued point, summing to a full circle, inscribed in
/// [box]. Non-positive values are dropped (a pie of a negative share is undefined).
List<PieSlice> pieSlices(List<ChartPoint> pts, JetRect box, {int arcSegments = 24}) {
  final List<ChartPoint> pos = <ChartPoint>[
    for (final ChartPoint p in pts) if (p.value > 0) p
  ];
  final double total = pos.fold<double>(0, (double s, ChartPoint p) => s + p.value);
  if (total <= 0) return const <PieSlice>[];
  final double cx = box.x + box.width / 2;
  final double cy = box.y + box.height / 2;
  final double r = math.min(box.width, box.height) / 2;
  final List<PieSlice> out = <PieSlice>[];
  double start = -math.pi / 2;
  for (var i = 0; i < pos.length; i++) {
    final double sweep = (pos[i].value / total) * 2 * math.pi;
    final List<PathCommand> cmds = <PathCommand>[MoveTo(JetOffset(cx, cy))];
    for (var s = 0; s <= arcSegments; s++) {
      final double a = start + sweep * (s / arcSegments);
      cmds.add(LineTo(JetOffset(cx + r * math.cos(a), cy + r * math.sin(a))));
    }
    cmds.add(const ClosePath());
    out.add(PieSlice(
        commands: cmds, startAngle: start, sweepAngle: sweep, value: pos[i].value, index: i));
    start += sweep;
  }
  return out;
}
```

> VERIFY `math.pow` returns `num` (hence `.toDouble()`); `JetRect`/`JetOffset` field names (`x/y/width/height`, `dx/dy`) match Task notes. `num.clamp` returns `num` — `(.. as double)` may be needed if the analyzer complains; wrap with `.toDouble()` if so.

- [ ] **Step 4: Run to verify it passes.**
  Run: `cd packages/jet_print && flutter test test/rendering/elements/chart/chart_geometry_test.dart`
  Expected: PASS.

- [ ] **Step 5: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format lib/src/rendering/elements/chart/chart_geometry.dart test/rendering/elements/chart/chart_geometry_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/elements/chart/chart_geometry.dart packages/jet_print/test/rendering/elements/chart/chart_geometry_test.dart
git commit -m "feat(render): pure chart geometry (niceAxis, barRects, linePolyline, pieSlices)"
```

---

## Task 5: `ChartElementRenderer` — geometry → frame primitives

**Files:**
- Create: `packages/jet_print/lib/src/rendering/elements/renderers/chart_element_renderer.dart`
- Test: `packages/jet_print/test/rendering/elements/renderers/chart_element_renderer_test.dart`

**Interfaces:**
- Consumes: `chart_geometry.dart` (Task 4), the primitives, `RenderContext.measurer` (for labels/title).
- Produces: `class ChartElementRenderer extends ElementRenderer<ChartElement>` — `measure` returns the element box; `emit` appends primitives.
- Tunables (top of file): `const double kChartGutterLeft = 28; const double kChartGutterBottom = 14; const double kChartTitleGutter = 14;` and a palette `const List<JetColor> kChartPalette = <JetColor>[ ... 6 colours ... ];`

- [ ] **Step 1: Write the failing test.** Assert primitive *kinds and counts*, not exact geometry (the geometry is unit-tested in Task 4). Use the same fake/real measurer the other renderer tests use (grep `test/rendering/elements/renderers` for how they build a `RenderContext` — copy that helper).

```dart
// test/rendering/elements/renderers/chart_element_renderer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/elements/renderers/chart_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
// import the test measurer helper used by the sibling renderer tests

void main() {
  const bounds = JetRect(x: 0, y: 0, width: 200, height: 120);
  final ctx = RenderContext(measurer: /* the test measurer */);
  const renderer = ChartElementRenderer();

  ChartElement chart(ChartType t) => ChartElement(
        id: 'c1', bounds: bounds, chartType: t,
        collectionField: 'm', valueExpression: r'$F{v}',
        points: const <ChartPoint>[ChartPoint('Jan', 10), ChartPoint('Feb', 20), ChartPoint('Mar', 30)],
      );

  test('measure returns the element box', () {
    expect(renderer.measure(chart(ChartType.bar), ctx, const JetConstraints()),
        const JetSize(200, 120));
  });

  test('bar: one RectPrimitive per point (plus axis chrome)', () {
    final out = FrameBuilder();
    renderer.emit(chart(ChartType.bar), ctx, bounds, out);
    final rects = out.primitives.whereType<RectPrimitive>().where((r) => r.elementId == 'c1');
    expect(rects.length, greaterThanOrEqualTo(3));
    // axis present
    expect(out.primitives.whereType<LinePrimitive>(), isNotEmpty);
  });

  test('line: emits a PathPrimitive polyline', () {
    final out = FrameBuilder();
    renderer.emit(chart(ChartType.line), ctx, bounds, out);
    expect(out.primitives.whereType<PathPrimitive>(), isNotEmpty);
  });

  test('pie: one PathPrimitive per slice', () {
    final out = FrameBuilder();
    renderer.emit(chart(ChartType.pie), ctx, bounds, out);
    expect(out.primitives.whereType<PathPrimitive>().length, greaterThanOrEqualTo(3));
  });

  test('empty series does not throw', () {
    final out = FrameBuilder();
    renderer.emit(
        const ChartElement(id: 'e', bounds: bounds, chartType: ChartType.bar,
            collectionField: 'm', valueExpression: r'$F{v}'),
        ctx, bounds, out);
    // no exception; may emit only chrome
  });
}
```

> VERIFY: `FrameBuilder`'s accessor for accumulated primitives (`out.primitives` is a guess — read `lib/src/rendering/frame/frame_builder.dart` and use the real getter), and how sibling tests construct a `RenderContext`/measurer. Fix those two references; assertions stand.

- [ ] **Step 2: Run to verify it fails.**
  Run: `cd packages/jet_print && flutter test test/rendering/elements/renderers/chart_element_renderer_test.dart`
  Expected: FAIL — renderer undefined.

- [ ] **Step 3: Implement the renderer.** Compute the plot rect by insetting `bounds` (left gutter for axis labels when `showAxes`, bottom gutter for category labels, top gutter for the title), then dispatch on `chartType`, emitting primitives. Use `RectPrimitive` for bars, `PathPrimitive` (commands `MoveTo`+`LineTo`s) for the line polyline and for pie wedges, `LinePrimitive` for axis gridlines, and `TextRunPrimitive` (via `ctx.measurer.measure(...)`) for the title, axis tick labels, category labels, and value labels.

```dart
// lib/src/rendering/elements/renderers/chart_element_renderer.dart
/// Renders a [ChartElement] by replaying pure [chart_geometry] into frame
/// primitives (rects/paths/lines/text) — no widget chart library, so canvas,
/// preview, and export agree by construction.
library;

import '../../../domain/elements/chart_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/styles/color.dart';
import '../../../domain/styles/text_style.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../chart/chart_geometry.dart';
import '../element_renderer.dart';
import '../render_context.dart';

/// Left gutter (points) reserved for the value-axis tick labels.
const double kChartGutterLeft = 28;

/// Bottom gutter (points) reserved for category labels.
const double kChartGutterBottom = 14;

/// Top gutter (points) reserved for the title (used only when a title is set).
const double kChartTitleGutter = 14;

/// The slice palette for pie charts (bar/line use the element's seriesColor).
const List<JetColor> kChartPalette = <JetColor>[
  JetColor(0xFF4F8DF7), JetColor(0xFFF7894F), JetColor(0xFF4FB76B),
  JetColor(0xFFB74F9E), JetColor(0xFFE0C341), JetColor(0xFF5FC6C9),
];

/// The built-in renderer for `chart` elements.
class ChartElementRenderer extends ElementRenderer<ChartElement> {
  /// Const constructor.
  const ChartElementRenderer();

  static const JetTextStyle _labelStyle = JetTextStyle(size: 7);

  @override
  JetSize measure(ChartElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(ChartElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    final double top = bounds.y + (el.title != null ? kChartTitleGutter : 0);
    final bool axes = el.showAxes && el.chartType != ChartType.pie;
    final double left = bounds.x + (axes ? kChartGutterLeft : 0);
    final double bottom =
        bounds.y + bounds.height - (axes ? kChartGutterBottom : 0);
    final JetRect plot = JetRect(
        x: left, y: top, width: (bounds.x + bounds.width) - left, height: bottom - top);

    if (el.title != null) {
      _text(ctx, out, el.title!, JetRect(x: bounds.x, y: bounds.y, width: bounds.width, height: kChartTitleGutter), el.id);
    }

    switch (el.chartType) {
      case ChartType.bar:
        _emitCartesian(el, ctx, plot, out, bars: true);
      case ChartType.line:
        _emitCartesian(el, ctx, plot, out, bars: false);
      case ChartType.pie:
        for (final PieSlice s in pieSlices(el.points, plot)) {
          out.add(PathPrimitive(
            bounds: plot,
            commands: s.commands,
            fill: kChartPalette[s.index % kChartPalette.length],
            elementId: el.id,
          ));
        }
    }
  }

  void _emitCartesian(ChartElement el, RenderContext ctx, JetRect plot,
      FrameBuilder out, {required bool bars}) {
    if (el.points.isEmpty) return;
    final double maxV = el.points.fold<double>(0, (m, p) => p.value > m ? p.value : m);
    final AxisScale axis = niceAxis(maxV);
    if (el.showAxes) {
      for (final double t in axis.ticks) {
        final double y = plot.y + plot.height - (t / axis.niceMax) * plot.height;
        out.add(LinePrimitive(
          bounds: plot,
          start: JetOffset(plot.x, y),
          end: JetOffset(plot.x + plot.width, y),
          color: const JetColor(0xFFDDDDDD),
          strokeWidth: 0.5,
          elementId: el.id,
        ));
        _text(ctx, out, t.toStringAsFixed(0),
            JetRect(x: plot.x - kChartGutterLeft, y: y - 4, width: kChartGutterLeft - 2, height: 8), el.id);
      }
    }
    if (bars) {
      final List<JetRect> rects = barRects(el.points, plot, axis);
      for (var i = 0; i < rects.length; i++) {
        out.add(RectPrimitive(bounds: rects[i], fill: el.seriesColor, elementId: el.id));
        if (el.showValueLabels) {
          _text(ctx, out, el.points[i].value.toStringAsFixed(0),
              JetRect(x: rects[i].x, y: rects[i].y - 8, width: rects[i].width, height: 8), el.id);
        }
      }
    } else {
      final List<JetOffset> line = linePolyline(el.points, plot, axis);
      out.add(PathPrimitive(
        bounds: plot,
        commands: <PathCommand>[
          MoveTo(line.first),
          for (final JetOffset p in line.skip(1)) LineTo(p),
        ],
        stroke: el.seriesColor,
        strokeWidth: 1.5,
        elementId: el.id,
      ));
    }
    if (el.showAxes) {
      final double slot = plot.width / el.points.length;
      for (var i = 0; i < el.points.length; i++) {
        _text(ctx, out, el.points[i].label,
            JetRect(x: plot.x + i * slot, y: plot.y + plot.height + 2, width: slot, height: kChartGutterBottom - 2), el.id);
      }
    }
  }

  void _text(RenderContext ctx, FrameBuilder out, String s, JetRect box, String id) {
    final m = ctx.measurer.measure(s, _labelStyle, maxWidth: box.width);
    out.add(TextRunPrimitive(
        bounds: box, lines: m.lines, style: _labelStyle, fontFamily: m.fontFamily, elementId: id));
  }
}
```

> VERIFY: `JetTextStyle(size: 7)` — confirm the param is `size` (read `text_style.dart`); if it's `fontSize`, rename. Confirm `FrameBuilder.add(...)` is the append method (the shape renderer uses `out.add(...)`, so yes). `num`→`double` casts may be needed on `t / axis.niceMax`.

- [ ] **Step 4: Run to verify it passes.**
  Run: `cd packages/jet_print && flutter test test/rendering/elements/renderers/chart_element_renderer_test.dart`
  Expected: PASS.

- [ ] **Step 5: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format lib/src/rendering/elements/renderers/chart_element_renderer.dart test/rendering/elements/renderers/chart_element_renderer_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/elements/renderers/chart_element_renderer.dart packages/jet_print/test/rendering/elements/renderers/chart_element_renderer_test.dart
git commit -m "feat(render): ChartElementRenderer (bar/line/pie + axes/labels/title)"
```

---

## Task 6: Codec + register the `chart` type

**Files:**
- Create: `packages/jet_print/lib/src/domain/serialization/chart_element_codec.dart`
- Modify: `packages/jet_print/lib/src/rendering/elements/built_in_element_renderers.dart`
- Test: `packages/jet_print/test/domain/serialization/chart_element_codec_test.dart`

**Interfaces:**
- Consumes: `ChartElement` (Task 1), `ChartElementRenderer` (Task 5), `ElementCodec` base.
- Produces: `class ChartElementCodec extends ElementCodec<ChartElement>` and a registry entry.

- [ ] **Step 1: Write the failing test.**

```dart
// test/domain/serialization/chart_element_codec_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/domain/serialization/chart_element_codec.dart';

void main() {
  const codec = ChartElementCodec();

  test('round-trips every authored field', () {
    const el = ChartElement(
      id: 'c1', bounds: JetRect(x: 1, y: 2, width: 200, height: 120),
      chartType: ChartType.pie, collectionField: 'months',
      categoryExpression: r'$F{label}', valueExpression: r'$F{revenue}',
      title: 'Revenue', showAxes: false, showValueLabels: true, showLegend: true,
      seriesColor: JetColor(0xFF112233), name: 'Chart A');
    final back = codec.fromJson(codec.toJson(el));
    expect(back, equals(el));
  });

  test('omit-when-default keeps the JSON minimal', () {
    const el = ChartElement(
      id: 'c2', bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
      chartType: ChartType.bar, collectionField: 'm', valueExpression: r'$F{v}');
    final json = codec.toJson(el);
    expect(json.containsKey('title'), isFalse);
    expect(json.containsKey('categoryExpression'), isFalse);
    expect(json.containsKey('showAxes'), isFalse); // default true
    expect(json.containsKey('showValueLabels'), isFalse); // default false
    expect(json['type'] ?? json['chartType'], 'bar'); // serialize-by-name
  });

  test('points are never serialized (fill-time artifact)', () {
    const el = ChartElement(
      id: 'c3', bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
      chartType: ChartType.bar, collectionField: 'm', valueExpression: r'$F{v}',
      points: <ChartPoint>[ChartPoint('Jan', 1)]);
    expect(codec.toJson(el).containsKey('points'), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails.**
  Run: `cd packages/jet_print && flutter test test/domain/serialization/chart_element_codec_test.dart`
  Expected: FAIL — codec undefined.

- [ ] **Step 3: Implement the codec.** Mirror `shape_element_codec.dart` exactly (tolerant `chartType` parse → unknown name falls back to `ChartType.bar`; omit-when-default; never write `points`). Field key for the type: use `chartType` (do NOT use `type` — `type` is the element-type-key slot owned by the registry envelope; confirm by reading how `shape_element_codec` avoids colliding with the envelope's `type`).

```dart
// lib/src/domain/serialization/chart_element_codec.dart
/// JSON codec for [ChartElement]. Serialize-by-name, omit-when-default; the
/// fill-time [ChartElement.points] are never persisted.
library;

import '../bool_property.dart';
import '../elements/chart_element.dart';
import '../geometry.dart';
import '../styles/color.dart';
import 'element_codec.dart';

/// Serializes [ChartElement] to/from its field map.
class ChartElementCodec extends ElementCodec<ChartElement> {
  /// Const constructor (stateless).
  const ChartElementCodec();

  @override
  ChartElement fromJson(Map<String, Object?> json) {
    final String rawType = json['chartType'] as String? ?? 'bar';
    final ChartType type = ChartType.values.asNameMap()[rawType] ?? ChartType.bar;
    return ChartElement(
      id: json['id']! as String,
      bounds: JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
      chartType: type,
      collectionField: json['collectionField'] as String? ?? '',
      valueExpression: json['valueExpression'] as String? ?? '',
      categoryExpression: json['categoryExpression'] as String?,
      title: json['title'] as String?,
      showAxes: (json['showAxes'] as bool?) ?? true,
      showValueLabels: (json['showValueLabels'] as bool?) ?? false,
      showLegend: (json['showLegend'] as bool?) ?? false,
      seriesColor: json['seriesColor'] is int
          ? JetColor(json['seriesColor']! as int)
          : kDefaultChartColor,
      name: json['name'] as String?,
      visible: json['visible'] is Map
          ? BoolProperty.fromJson((json['visible']! as Map).cast<String, Object?>())
          : const BoolProperty(),
    );
  }

  @override
  Map<String, Object?> toJson(ChartElement el) => <String, Object?>{
        'id': el.id,
        'bounds': el.bounds.toJson(),
        'chartType': el.chartType.name,
        'collectionField': el.collectionField,
        'valueExpression': el.valueExpression,
        if (el.categoryExpression != null) 'categoryExpression': el.categoryExpression,
        if (el.title != null) 'title': el.title,
        if (!el.showAxes) 'showAxes': false,
        if (el.showValueLabels) 'showValueLabels': true,
        if (el.showLegend) 'showLegend': true,
        if (el.seriesColor != kDefaultChartColor) 'seriesColor': el.seriesColor.argb,
        if (el.name != null) 'name': el.name,
        if (el.visible != const BoolProperty()) 'visible': el.visible.toJson(),
      };
}
```

> VERIFY: `JetColor.argb` is the int accessor (read `color.dart`; the field is `final int argb`). `BoolProperty.fromJson`/`toJson` exist (the shape codec uses them).

- [ ] **Step 4: Register the pair.** In `built_in_element_renderers.dart`, add imports for `chart_element.dart`, `chart_element_codec.dart`, `chart_element_renderer.dart`, and append to the cascade:

```dart
    ..register<ChartElement>(
        'chart', const ChartElementCodec(), const ChartElementRenderer());
```

Update the file's dartdoc to mention `chart`.

- [ ] **Step 5: Run codec + a registry-dispatch check.**
  Run: `cd packages/jet_print && flutter test test/domain/serialization/chart_element_codec_test.dart`
  Expected: PASS. Then run any existing built-in-registry test (grep `test` for `registerBuiltInElementTypes`) to confirm the new pair doesn't break registration.

- [ ] **Step 6: Full package suite (regression).**
  Run: `cd packages/jet_print && flutter test`
  Expected: ALL PASS, no golden diffs (nothing here touches an existing render path).

- [ ] **Step 7: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format lib/src/domain/serialization/chart_element_codec.dart lib/src/rendering/elements/built_in_element_renderers.dart test/domain/serialization/chart_element_codec_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/serialization/chart_element_codec.dart packages/jet_print/lib/src/rendering/elements/built_in_element_renderers.dart packages/jet_print/test/domain/serialization/chart_element_codec_test.dart
git commit -m "feat(serialization): ChartElementCodec + register chart element type"
```

---

## Task 7: Designer — create, configure, and edit a chart

This task threads the chart through every designer switch a new visual type touches. **The switch checklist** (all must be updated, or the type is half-wired): (a) `DesignerToolType` enum, (b) `kDefaultElementSize`, (c) `buildDefaultElement`, (d) the toolbox button, (e) the properties panel. Plus the edit command. Each command/factory must preserve **all** `ChartElement` fields (the silent-drop trap).

**Files:**
- Modify: `packages/jet_print/lib/src/designer/canvas/design_tunables.dart` (a + b)
- Modify: `packages/jet_print/lib/src/designer/controller/commands/create_element_command.dart` (c)
- Modify: `packages/jet_print/lib/src/designer/layout/designer_toolbox.dart` (d)
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (e)
- Create: `packages/jet_print/lib/src/designer/controller/commands/set_chart_options_command.dart`
- Test: `packages/jet_print/test/designer/controller/commands/set_chart_options_command_test.dart`
- Test: `packages/jet_print/test/designer/chart_authoring_test.dart` (widget-level)

**Interfaces:**
- Produces: `enum DesignerToolType { ..., chart }`; `SetChartOptionsCommand({required String id, ChartType? chartType, String? collectionField, String? valueExpression, ... })` updating the `ChartElement` `id` via `copyWith`, a no-op for a non-chart/absent id.

- [ ] **Step 1 (command): Write the failing test.**

```dart
// test/designer/controller/commands/set_chart_options_command_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/controller/commands/set_chart_options_command.dart';
import 'package:jet_print/src/designer/controller/designer_document.dart';
// build a DesignerDocument containing one ChartElement (mirror a sibling command test's harness)

void main() {
  test('sets chartType, preserving binding fields', () {
    // document with chart 'c1' bound to collectionField 'months', value $F{revenue}
    final before = /* harness document */;
    final after = const SetChartOptionsCommand(id: 'c1', chartType: ChartType.line).apply(before);
    final el = /* find element c1 in after */ as ChartElement;
    expect(el.chartType, ChartType.line);
    expect(el.collectionField, 'months');
    expect(el.valueExpression, r'$F{revenue}');
  });

  test('no-op for a missing id', () {
    final before = /* harness */;
    expect(const SetChartOptionsCommand(id: 'nope', chartType: ChartType.pie).apply(before), before);
  });
}
```

> Read a sibling command test (`test/designer/controller/commands/set_shape_kind_command_test.dart` or the barcode-option one) for the exact `DesignerDocument` harness + element-lookup helper, and copy it.

- [ ] **Step 2: Run → FAIL.** Run: `cd packages/jet_print && flutter test test/designer/controller/commands/set_chart_options_command_test.dart`

- [ ] **Step 3: Implement the command** (mirror `set_shape_kind_command.dart` + `updateElement`):

```dart
// lib/src/designer/controller/commands/set_chart_options_command.dart
/// Edits a [ChartElement]'s properties in one undoable step, preserving every
/// field not named. A no-op for a non-chart or absent [id].
library;

import '../../../domain/elements/chart_element.dart';
import '../../../domain/report_element.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';

/// Sets the named chart properties on element [id].
class SetChartOptionsCommand extends EditCommand {
  /// Creates a chart-options edit.
  const SetChartOptionsCommand({
    required this.id,
    this.chartType,
    this.collectionField,
    this.valueExpression,
    this.categoryExpression,
    this.title,
    this.showAxes,
    this.showValueLabels,
    this.showLegend,
    this.seriesColor,
  });

  /// The target chart element.
  final String id;

  // The fields to set (null = leave unchanged). categoryExpression/title use the
  // same "null = leave" convention; clearing them is out of scope (toggle off
  // via an empty string handled in the panel).
  final ChartType? chartType;
  final String? collectionField;
  final String? valueExpression;
  final String? categoryExpression;
  final String? title;
  final bool? showAxes;
  final bool? showValueLabels;
  final bool? showLegend;
  final JetColor? seriesColor;

  @override
  String get label => 'Edit chart';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateElement(
          before.definition,
          id,
          (ReportElement e) => e is ChartElement
              ? e.copyWith(
                  chartType: chartType,
                  collectionField: collectionField,
                  valueExpression: valueExpression,
                  categoryExpression: categoryExpression,
                  title: title,
                  showAxes: showAxes,
                  showValueLabels: showValueLabels,
                  showLegend: showLegend,
                  seriesColor: seriesColor,
                )
              : e,
        ),
      );
}
```

Add `import '../../../domain/styles/color.dart';` for `JetColor`. VERIFY `updateElement` + `DesignerDocument.withDefinition` signatures against `set_shape_kind_command.dart`.

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Wire the switch checklist.**
  - (a) `design_tunables.dart`: add `chart` to `enum DesignerToolType` with a dartdoc line.
  - (b) `design_tunables.dart`: add `DesignerToolType.chart: JetSize(200, 130),` to `kDefaultElementSize`.
  - (c) `create_element_command.dart` `buildDefaultElement`: add
    ```dart
    case DesignerToolType.chart:
      return ChartElement(
        id: id, bounds: bounds, chartType: ChartType.bar,
        collectionField: '', valueExpression: '');
    ```
    (import `chart_element.dart`).
  - (d) `designer_toolbox.dart`: add a tool button for `DesignerToolType.chart` (copy the barcode button block — same widget, new icon + label; reuse the existing icon set, e.g. a bar-chart glyph).
  - (e) `properties_panel.dart`: add a `ChartElement` branch rendering editors: a `ChartType` segmented/dropdown (→ `SetChartOptionsCommand(chartType:)`), a collection-field picker driven by `collectionFieldsForScope(schema, definition, scopeOfBand)` (→ `collectionField:`), category & value expression fields via the fx editor (→ `categoryExpression:`/`valueExpression:`), a title field, and `showAxes`/`showValueLabels`/`showLegend` toggles + a colour swatch. Mirror the existing barcode/shape property sections for widget choice and command dispatch.

- [ ] **Step 6 (widget): authoring smoke test.** Mirror `test/designer/band_collection_binding_test.dart`'s harness: load a document with a collection schema, drop a chart via the toolbox (or insert one), select it, and assert the properties panel shows the chart-type control and the collection-field picker lists the in-scope collection. Assert editing the value field dispatches an edit (the element's `valueExpression` changes).

```dart
// test/designer/chart_authoring_test.dart — skeleton; fill from the sibling harness
testWidgets('chart properties panel edits binding', (tester) async {
  // pump designer with a document containing chart 'c1' + a schema with collection 'months'
  // tap the chart to select; expect a ChartType control + 'months' in the collection picker
  // enter $F{revenue} into the value field; expect controller.definition's c1.valueExpression updated
});
```

- [ ] **Step 7: Run designer suite.**
  Run: `cd packages/jet_print && flutter test test/designer`
  Expected: PASS. Some tests asserting an exact `DesignerToolType.values` length or toolbox button count will legitimately need `+1` — update them deliberately and note why. **No golden should change** unless a deliberate toolbox golden now includes the new button (regenerate that one intentionally if so).

- [ ] **Step 8: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format lib test
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer packages/jet_print/test/designer
git commit -m "feat(designer): author + configure ChartElement (tool, panel, edit command)"
```

---

## Task 8: Playground demo + WYSIWYG goldens

Prove the three chart types render identically across canvas, PDF, and PNG, and give a hand-authored sample.

**Files:**
- Create: `apps/jet_print_playground/lib/demos/sales_chart_demo.dart` (or follow the existing demo file convention — grep `apps/jet_print_playground/lib` for how `packing_slip`/`payroll` demos are structured and registered).
- Modify: the playground demo registry/nav (wherever demos are listed).
- Test: `packages/jet_print/test/rendering/chart_golden_test.dart` (+ generated golden PNGs).

**Interfaces:**
- Consumes: the full public API (`ChartElement`, `ReportDefinition`, the renderer/exporter) from Task 1–6.

- [ ] **Step 1: Author the sample definition.** Build a `ReportDefinition` with a master row carrying a `months` collection (`[{label:'Jan',revenue:1200}, ...]`) and a summary/footer band holding three `ChartElement`s bound to `months` — one each `ChartType.bar`/`line`/`pie`, with `title` + `showAxes` (bar/line) + `showValueLabels`. Put it in a demo widget mirroring an existing demo (e.g. `packing_slip_demo.dart`).

- [ ] **Step 2: Write the golden test.** Mirror an existing render-golden test (grep `test` for `matchesGoldenFile` + how preview/PDF/PNG goldens are produced for a definition). Render the sample to: the canvas/preview image, the PDF (via `JetReportExporter`), and the PNG; assert each `matchesGoldenFile(...)`.

```dart
// test/rendering/chart_golden_test.dart — mirror the existing export/preview golden harness
// 1. build the sample definition (3 charts, in-memory data source with `months`)
// 2. render preview frame -> matchesGoldenFile('goldens/chart_preview.png')
// 3. export PDF -> rasterize first page -> matchesGoldenFile('goldens/chart_pdf.png')
// (follow whatever the existing slice does — e.g. spec 012 export goldens)
```

- [ ] **Step 3: Generate goldens.**
  Run: `cd packages/jet_print && flutter test --update-goldens test/rendering/chart_golden_test.dart`
  Then **inspect the generated PNGs by eye** — confirm bars/line/pie look correct (axis at left, bars bottom-aligned, pie wedges summing to a full circle, labels legible). A golden that looks wrong is a bug, not a baseline.

- [ ] **Step 4: Re-run without `--update-goldens` to confirm determinism.**
  Run: `cd packages/jet_print && flutter test test/rendering/chart_golden_test.dart`
  Expected: PASS.

- [ ] **Step 5: Full verification sweep.**
  - `cd packages/jet_print && flutter analyze` → clean.
  - `dart format --output=none --set-exit-if-changed lib test` → clean.
  - `cd packages/jet_print && flutter test` → all green, only the new chart goldens added.
  - `cd apps/jet_print_playground && flutter analyze && flutter test` → green.

- [ ] **Step 6: Manual GUI smoke (optional but recommended).**
  Run: `cd apps/jet_print_playground && flutter run -d macos`; open the Sales chart demo; confirm all three charts render and Preview/PDF export matches.

- [ ] **Step 7: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground packages/jet_print/test/rendering/chart_golden_test.dart packages/jet_print/test/rendering/goldens
git commit -m "test(chart): WYSIWYG goldens (bar/line/pie across preview + PDF) + playground demo"
```

---

## Self-Review

**Spec coverage:**
- §"One element type, enum-discriminated" → Task 1 (`ChartType` enum, one `ChartElement`).
- §Domain fields → Task 1. §Serialization (omit-when-default, by-name, no bump, points not persisted) → Task 6.
- §Fill resolved series + shared coercion → Tasks 2–3.
- §Placement via existing scope rules → no new code; the collection-field picker (Task 7e) reuses `collectionFieldsForScope`; the resolver reads whatever collection the row carries.
- §Render in-house geometry → frame primitives → Tasks 4–5. §Chrome (axes, value labels, title, legend) → Task 5 (legend toggle wired; minimal swatch — acceptable per spec's "simple legend").
- §Designer (3-switch checklist, commands) → Task 7.
- §Testing strategy (geometry/resolver/codec/golden/designer) → Tasks 4/3/6/8/7.
- §Risks (silent field-drop, three switches, coercion divergence, goldens) → Task 1 & 6 round-trip tests, Task 7 checklist, Task 2 shared helper + golden gate.

**Placeholder scan:** The designer (Task 7) and golden (Task 8) tasks intentionally reference sibling-test harnesses to copy rather than reproducing a 200-line widget-test scaffold verbatim — each names the exact file to mirror and the exact assertions to make. All engine tasks (1–6) carry complete code. No "TBD"/"add error handling"/"similar to" hand-waves remain.

**Type consistency:** `ChartElement.copyWith` parameter names match the command (Task 7) and resolver (Task 3) call sites; `ChartPoint(label, value)` positional everywhere; `niceAxis`/`barRects`/`linePolyline`/`pieSlices`/`AxisScale`/`PieSlice` signatures match between Task 4 (definition) and Task 5 (use); codec key `chartType` matches between `toJson`/`fromJson` and the round-trip test.

**Open verifications flagged inline** (the implementer must confirm before trusting the sketch): `BoolProperty.expression(...)`, `JetFunctionRegistry`/`ReportDiagnostics` accessors, `FrameBuilder` primitives getter + `RenderContext`/measurer test helper, `JetTextStyle` size param name, `JetColor.argb`, `updateElement`/`DesignerDocument` signatures, the playground demo + golden harness conventions. Each is a name-level check against a cited existing file, not a design hole.
