# Crosstab / Pivot Grid Engine (Spec A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a paginated crosstab (pivot grid) to the report engine — N row groups x N column groups x M measures, subtotals at every level, column headers reprinted per page, and horizontal continuation pages — renderable and exportable from a JSON-authored report.

**Architecture:** A pure `crosstab/` layer computes everything: an **aggregator** folds rows into a sparse `CrosstabMatrix` in one pass, and a **planner** turns that matrix plus the available page width into ordinary `FilledBand`s plus one synthetic `GroupLevel`. The filler folds rows as it streams and splices the planned bands into the band list afterwards; the layouter gains the synthetic group in its group table, which buys vertical pagination, header reprint and horizontal continuation with no new pagination code. Painter, exporter, printer and preview are untouched.

**Tech Stack:** Dart / Flutter, `flutter_test`. Layers: `domain/` (pure model + codec + validation), `expression/` (reused `JetCalculation` / `VariableAccumulator` / evaluator), `rendering/` (aggregator, planner, filler, layouter).

**Spec:** `docs/superpowers/specs/2026-08-30-crosstab-engine-design.md`

## Global Constraints

- Run `flutter` / `dart` from `packages/jet_print`. Run `git` from the repo root `/Users/ahmeturel/Projects/oss/jet-print` — the `flutter` tool leaves the shell inside the package.
- **Zero golden changes.** No existing golden may move; crosstab-free reports must serialize byte-identically. If a golden moves, stop and find the leak.
- **Test-first (Constitution III).** Every task is Red -> Green. Write the test, watch it fail for the stated reason, then implement.
- **Schema version stays 2.** `kReportDefinitionSchemaVersion` is not bumped.
- Measure aggregates use the existing `JetCalculation` enum (8 values: `none, sum, count, average, min, max, first, last`); `none` is rejected for a measure by `validate()`.
- Expression fields hold **canonical expression strings** (`$F{qty} * $F{price}`), never the designer's `{[qty] * [price]}` template syntax.
- Crosstab is **root-scope only** in Spec A; `validate()` rejects one inside a `NestedScope`.
- Cardinality threshold: **50,000 populated cells** -> one warning, then proceed. Never truncate.
- Dartdoc every public member; `dart format` and a clean `dart analyze` gate every commit.

---

## File Structure

**New — pure domain model (`lib/src/domain/crosstab/`):**
- `crosstab.dart` — `Crosstab` (the block itself) and `CrosstabSort`.
- `crosstab_group.dart` — `CrosstabGroup` (one row- or column-axis level).
- `crosstab_measure.dart` — `CrosstabMeasure`.
- `crosstab_style.dart` — `CrosstabStyle`.
- `crosstab_codec.dart` — JSON for all four, omitting defaults.

**New — pure computation (`lib/src/rendering/crosstab/`):**
- `crosstab_matrix.dart` — `CrosstabAxisNode`, `CrosstabCellKey`, `CrosstabMatrix`. Data only.
- `crosstab_aggregator.dart` — rows -> matrix. One pass, prefix folding.
- `crosstab_planner.dart` — matrix + width -> bands + synthetic group.

**New — codec resilience:**
- `lib/src/domain/unknown_scope_node.dart` — `UnknownScopeNode`, sibling of `UnknownElement`.

**Modified:**
- `lib/src/domain/detail_scope.dart` — the `CrosstabNode` variant.
- `lib/src/domain/serialization/report_definition_codec.dart` — `kind: 'crosstab'`, `UnknownScopeNode` decode.
- `lib/src/domain/report_validation.dart` — crosstab rules.
- `lib/src/designer/controller/band_walker.dart` — exhaustive switches; `allIds` collects crosstab ids.
- `lib/src/rendering/fill/filled_report.dart` — `FilledReport.syntheticGroups`.
- `lib/src/rendering/fill/report_filler.dart` — register / fold / splice.
- `lib/src/rendering/layout/report_layouter.dart` — group-table union + diagnostic exemption.

**Task order rationale:** Task 13 (designer read-only surface) can be done any time after Task 3; it is placed last because it is the only task touching UI and l10n. Task 1 is a standalone refactor that makes the later compile errors appear where they should. Tasks 2-5 build the model outside-in (types, variant, codec, validation) so a crosstab can be authored and round-tripped before anything computes. Tasks 6-9 build the pure computation, testable with no engine at all. Tasks 10-11 wire it into fill and layout. Task 12 proves the whole path end to end.

---

## Task 1: Make `ScopeNode` traversal exhaustive (prep, no crosstab yet)

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/band_walker.dart`
- Modify: `packages/jet_print/lib/src/data/binding_scope.dart:73-77`
- Modify: `packages/jet_print/lib/src/domain/report_validation.dart:82-90`
- Test: `packages/jet_print/test/designer/controller/band_walker_test.dart` (existing, must stay green)

**Interfaces:**
- Consumes: nothing.
- Produces: no API change. Behaviour is identical; only the shape of the traversal changes.

Context — `CrosstabNode` (Task 3) joins a **sealed** hierarchy, so a `switch` over `ScopeNode` becomes a compile error when the variant lands, while an `if (n is NestedScope)` chain compiles on silently. Most of those chains are *recursion* or *filters* where skipping a crosstab is the correct behaviour — this task does not change what they do. Its value is that every site's decision becomes explicit and future variants cannot slip past.

Convert these to `switch`; the filter/`indexWhere` predicates at `band_walker.dart:386`, `:517`, `:533` stay as-is (they select a specific node kind, and a crosstab correctly fails the predicate) but each gains a one-line comment saying so.

- [ ] **Step 1: Convert the recursive walkers in `band_walker.dart`.**

Five sites recurse into nested scopes. Rewrite each `if (n is NestedScope) ...` as an exhaustive switch. `allIds`' walker (`:158-168`) becomes:

```dart
  void walk(DetailScope s) {
    out.add(s.id);
    for (final GroupLevel g in s.groups) {
      out.add(g.id);
    }
    for (final ScopeNode n in s.children) {
      switch (n) {
        case BandNode():
          break; // band ids come from allBands above
        case NestedScope(scope: final DetailScope inner):
          walk(inner);
      }
    }
  }
```

Apply the same shape to `findGroup`'s `search` (`:195-203`), `findScope`'s `search` (`:211-219`), `findGroupOfBand`'s `search` (`:255-262`) and `scopePathToBand`'s `search` (`:315-320`). In the three `search` functions the `NestedScope` arm keeps its `final found = search(inner); if (found != null) return found;` body; the `BandNode` arm is `break`.

- [ ] **Step 2: Convert `binding_scope.dart:73-77`.**

```dart
Set<String> publishedTotalsForScope(DetailScope scope) {
  final Set<String> out = <String>{};
  for (final ScopeNode n in scope.children) {
    switch (n) {
      case BandNode():
        break; // a band publishes nothing
      case NestedScope(scope: final DetailScope s):
        for (final ScopeTotal t in s.totals) {
          out.add(t.name);
        }
    }
  }
  return out;
}
```

- [ ] **Step 3: Convert `report_validation.dart`'s `collectTotals` (`:82-90`).**

```dart
    void collectTotals(DetailScope s) {
      for (final ScopeNode node in s.children) {
        switch (node) {
          case BandNode():
            break; // a band publishes no totals
          case NestedScope(scope: final DetailScope inner):
            for (final ScopeTotal t in inner.totals) {
              publishedTotalNames.add(t.name);
            }
            collectTotals(inner);
        }
      }
    }
```

- [ ] **Step 4: Comment the three predicates that stay.**

At `band_walker.dart:386`, `:517` and `:533`, add above each: `// Predicate, not dispatch: any other node kind correctly fails this test.`

- [ ] **Step 5: Run the full suite — nothing may change.**

Run: `cd packages/jet_print && flutter test`
Expected: PASS, same count as before. This is a pure refactor; a single failure means a converted switch changed behaviour.

- [ ] **Step 6: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib
git commit -m "refactor(domain): exhaustive switches over ScopeNode traversal"
```

---

## Task 2: The crosstab domain model

**Files:**
- Create: `packages/jet_print/lib/src/domain/crosstab/crosstab.dart`
- Create: `packages/jet_print/lib/src/domain/crosstab/crosstab_group.dart`
- Create: `packages/jet_print/lib/src/domain/crosstab/crosstab_measure.dart`
- Create: `packages/jet_print/lib/src/domain/crosstab/crosstab_style.dart`
- Test: `packages/jet_print/test/domain/crosstab/crosstab_model_test.dart`

**Interfaces:**
- Consumes: `JetCalculation` (`domain/report_variable.dart`), `BoolProperty`, `JetTextStyle`, `JetBoxStyle`, `ValueEquality`, `pick` (`domain/copy_support.dart`).
- Produces: `Crosstab`, `CrosstabGroup`, `CrosstabMeasure`, `CrosstabStyle`, `CrosstabSort`. All are `const`-constructible value types with `copyWith`. Later tasks construct these directly.

- [ ] **Step 1: Write the failing test.**

Create `test/domain/crosstab/crosstab_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;

const CrosstabGroup _region = CrosstabGroup(
  id: 'g/region',
  name: 'Region',
  expression: r'$F{region}',
);
const CrosstabMeasure _amount = CrosstabMeasure(
  id: 'm/amount',
  name: 'Amount',
  expression: r'$F{qty} * $F{price}',
  aggregate: JetCalculation.sum,
);
const Crosstab _ct = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[_region],
  columnGroups: <CrosstabGroup>[
    CrosstabGroup(id: 'g/q', name: 'Quarter', expression: r'$F{quarter}'),
  ],
  measures: <CrosstabMeasure>[_amount],
);

void main() {
  group('crosstab model', () {
    test('is a value type over its whole shape', () {
      expect(_ct, equals(_ct.copyWith()));
      expect(_ct.hashCode, equals(_ct.copyWith().hashCode));
      expect(
        _ct.copyWith(measures: <CrosstabMeasure>[
          _amount.copyWith(aggregate: JetCalculation.average),
        ]),
        isNot(equals(_ct)),
      );
    });

    test('defaults: no collection binding, totals on, ascending sort', () {
      expect(_ct.collectionField, isNull);
      expect(_region.showTotal, isTrue);
      expect(_region.sort, CrosstabSort.ascending);
      expect(_ct.style, const CrosstabStyle());
    });

    test('copyWith clears the nullable name via a thunk', () {
      final Crosstab named = _ct.copyWith(name: () => 'Sales pivot');
      expect(named.name, 'Sales pivot');
      expect(named.copyWith(name: () => null).name, isNull);
      expect(named.copyWith().name, 'Sales pivot');
    });

    test('style defaults are the documented point sizes', () {
      const CrosstabStyle s = CrosstabStyle();
      expect(s.rowLabelWidth, 110);
      expect(s.rowLabelIndent, 12);
      expect(s.measureColumnWidth, 64);
      expect(s.rowHeight, 14);
      expect(s.headerRowHeight, 14);
    });
  });
}
```

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/domain/crosstab/crosstab_model_test.dart`
Expected: FAIL — the `crosstab/` files do not exist yet ("Target of URI doesn't exist").

- [ ] **Step 3: Write `crosstab_group.dart`.**

```dart
/// One level of a crosstab axis (spec A): a named group whose per-row
/// [expression] produces the key rows are bucketed by.
library;

import '../value_equality.dart';

/// How a [CrosstabGroup]'s keys are ordered on its axis.
enum CrosstabSort {
  /// Ascending by the typed group key.
  ascending,

  /// Descending by the typed group key.
  descending,

  /// The order keys were first seen while folding rows.
  dataOrder,
}

/// An immutable crosstab axis level.
class CrosstabGroup with ValueEquality {
  /// Creates an axis level identified by [id], labelled [name], bucketing rows
  /// by [expression].
  const CrosstabGroup({
    required this.id,
    required this.name,
    required this.expression,
    this.sort = CrosstabSort.ascending,
    this.showTotal = true,
    this.totalLabel,
  });

  /// Stable identity.
  final String id;

  /// Display label — also the stem of the default total label.
  final String name;

  /// Per-row group key, a canonical expression string (e.g. `$F{region}`).
  final String expression;

  /// How this level's keys are ordered.
  final CrosstabSort sort;

  /// Whether this level emits a subtotal. On the outermost level this is the
  /// grand total — there is no separate grand-total flag.
  final bool showTotal;

  /// Overrides the default `'<name> Total'` label, or null for the default.
  final String? totalLabel;

  /// Returns a copy with the given fields replaced.
  ///
  /// [totalLabel] is nullable, so it takes a thunk: omit to preserve, pass
  /// `() => value` to replace (`() => null` clears).
  CrosstabGroup copyWith({
    String? id,
    String? name,
    String? expression,
    CrosstabSort? sort,
    bool? showTotal,
    String? Function()? totalLabel,
  }) =>
      CrosstabGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        expression: expression ?? this.expression,
        sort: sort ?? this.sort,
        showTotal: showTotal ?? this.showTotal,
        totalLabel: totalLabel == null ? this.totalLabel : totalLabel(),
      );

  @override
  List<Object?> get props =>
      <Object?>[id, name, expression, sort, showTotal, totalLabel];

  @override
  String toString() => 'CrosstabGroup($id, $name'
      '${showTotal ? ', total' : ''})';
}
```

- [ ] **Step 4: Write `crosstab_measure.dart`.**

```dart
/// A crosstab measure (spec A): a per-row [expression] folded by [aggregate]
/// into every cell it contributes to.
library;

import '../report_variable.dart' show JetCalculation;
import '../styles/box_style.dart';
import '../styles/text_style.dart';
import '../value_equality.dart';

/// An immutable measure definition.
class CrosstabMeasure with ValueEquality {
  /// Creates a measure identified by [id], labelled [name].
  const CrosstabMeasure({
    required this.id,
    required this.name,
    required this.expression,
    required this.aggregate,
    this.format,
    this.cellTextStyle,
    this.cellBoxStyle,
  });

  /// Stable identity — also the `m` segment of a cell's element id.
  final String id;

  /// Column header label for this measure.
  final String name;

  /// Per-row value, a canonical expression string (e.g. `$F{qty} * $F{price}`).
  final String expression;

  /// How per-row values fold into a cell. [JetCalculation.none] is rejected by
  /// `validate()` — a cell has no single row to pass through.
  final JetCalculation aggregate;

  /// Optional number/date pattern applied to the folded value.
  final String? format;

  /// Overrides `CrosstabStyle.cellText` for this measure's cells.
  final JetTextStyle? cellTextStyle;

  /// Overrides `CrosstabStyle.cellBox` for this measure's cells.
  final JetBoxStyle? cellBoxStyle;

  /// Returns a copy with the given fields replaced.
  ///
  /// The nullable slots take thunks: omit to preserve, pass `() => value` to
  /// replace (`() => null` clears).
  CrosstabMeasure copyWith({
    String? id,
    String? name,
    String? expression,
    JetCalculation? aggregate,
    String? Function()? format,
    JetTextStyle? Function()? cellTextStyle,
    JetBoxStyle? Function()? cellBoxStyle,
  }) =>
      CrosstabMeasure(
        id: id ?? this.id,
        name: name ?? this.name,
        expression: expression ?? this.expression,
        aggregate: aggregate ?? this.aggregate,
        format: format == null ? this.format : format(),
        cellTextStyle:
            cellTextStyle == null ? this.cellTextStyle : cellTextStyle(),
        cellBoxStyle: cellBoxStyle == null ? this.cellBoxStyle : cellBoxStyle(),
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        expression,
        aggregate,
        format,
        cellTextStyle,
        cellBoxStyle,
      ];

  @override
  String toString() => 'CrosstabMeasure($id, ${aggregate.name})';
}
```

- [ ] **Step 5: Write `crosstab_style.dart`.**

```dart
/// The appearance and metrics of a crosstab (spec A). All distances are points.
library;

import '../styles/box_style.dart';
import '../styles/text_style.dart';
import '../value_equality.dart';

/// An immutable crosstab style. Cell appearance resolves in three layers:
/// a measure's own override, then this style, then the renderer's default.
class CrosstabStyle with ValueEquality {
  /// Creates a style; every field has a documented default.
  const CrosstabStyle({
    this.headerText,
    this.headerBox,
    this.cellText,
    this.cellBox,
    this.totalText,
    this.totalBox,
    this.rowLabelWidth = 110,
    this.rowLabelIndent = 12,
    this.measureColumnWidth = 64,
    this.rowHeight = 14,
    this.headerRowHeight = 14,
  });

  /// Text style for row and column header cells.
  final JetTextStyle? headerText;

  /// Box style behind header cells.
  final JetBoxStyle? headerBox;

  /// Text style for data cells.
  final JetTextStyle? cellText;

  /// Box style behind data cells.
  final JetBoxStyle? cellBox;

  /// Text style for subtotal and grand-total cells.
  final JetTextStyle? totalText;

  /// Box style behind total cells.
  final JetBoxStyle? totalBox;

  /// Width of the row-label column, repeated in every horizontal slice.
  final double rowLabelWidth;

  /// Horizontal indent applied per row-axis depth level.
  final double rowLabelIndent;

  /// Width of one measure column.
  final double measureColumnWidth;

  /// Height of a data or total row.
  final double rowHeight;

  /// Height of one column-header row.
  final double headerRowHeight;

  /// Returns a copy with the given fields replaced.
  ///
  /// The nullable style slots take thunks: omit to preserve, pass
  /// `() => value` to replace (`() => null` clears).
  CrosstabStyle copyWith({
    JetTextStyle? Function()? headerText,
    JetBoxStyle? Function()? headerBox,
    JetTextStyle? Function()? cellText,
    JetBoxStyle? Function()? cellBox,
    JetTextStyle? Function()? totalText,
    JetBoxStyle? Function()? totalBox,
    double? rowLabelWidth,
    double? rowLabelIndent,
    double? measureColumnWidth,
    double? rowHeight,
    double? headerRowHeight,
  }) =>
      CrosstabStyle(
        headerText: headerText == null ? this.headerText : headerText(),
        headerBox: headerBox == null ? this.headerBox : headerBox(),
        cellText: cellText == null ? this.cellText : cellText(),
        cellBox: cellBox == null ? this.cellBox : cellBox(),
        totalText: totalText == null ? this.totalText : totalText(),
        totalBox: totalBox == null ? this.totalBox : totalBox(),
        rowLabelWidth: rowLabelWidth ?? this.rowLabelWidth,
        rowLabelIndent: rowLabelIndent ?? this.rowLabelIndent,
        measureColumnWidth: measureColumnWidth ?? this.measureColumnWidth,
        rowHeight: rowHeight ?? this.rowHeight,
        headerRowHeight: headerRowHeight ?? this.headerRowHeight,
      );

  @override
  List<Object?> get props => <Object?>[
        headerText,
        headerBox,
        cellText,
        cellBox,
        totalText,
        totalBox,
        rowLabelWidth,
        rowLabelIndent,
        measureColumnWidth,
        rowHeight,
        headerRowHeight,
      ];

  @override
  String toString() =>
      'CrosstabStyle(label ${rowLabelWidth}pt, col ${measureColumnWidth}pt, '
      'row ${rowHeight}pt)';
}
```

- [ ] **Step 6: Write `crosstab.dart`.**

```dart
/// A crosstab (pivot grid) block — spec A.
///
/// Pure domain: the crosstab declares its axes and measures; the aggregator and
/// planner (rendering layer) turn it plus data into bands.
library;

import '../bool_property.dart';
import '../value_equality.dart';
import 'crosstab_group.dart';
import 'crosstab_measure.dart';
import 'crosstab_style.dart';

export 'crosstab_group.dart' show CrosstabSort;

/// An immutable crosstab: [rowGroups] x [columnGroups] of [measures].
///
/// Measures occupy the innermost column axis: each leaf column group is
/// followed by one column per measure.
class Crosstab with ValueEquality {
  /// Creates a crosstab identified by [id].
  const Crosstab({
    required this.id,
    this.name,
    this.collectionField,
    required this.rowGroups,
    required this.columnGroups,
    required this.measures,
    this.style = const CrosstabStyle(),
    this.visible = const BoolProperty(),
  });

  /// Stable identity — the `ct` segment of every cell's element id.
  final String id;

  /// Optional display name; the Outline falls back to a localized label.
  final String? name;

  /// The nested collection this crosstab pools across the scope's rows, or null
  /// to fold the scope's own rows.
  final String? collectionField;

  /// Row axis levels, outermost first. At least one.
  final List<CrosstabGroup> rowGroups;

  /// Column axis levels, outermost first. At least one.
  final List<CrosstabGroup> columnGroups;

  /// The measures, in column order. At least one.
  final List<CrosstabMeasure> measures;

  /// Appearance and metrics.
  final CrosstabStyle style;

  /// Whether the crosstab renders. Evaluated **without a row** (params and
  /// report variables only), since a crosstab prints outside the row loop.
  final BoolProperty visible;

  /// Returns a copy with the given fields replaced.
  ///
  /// [name] and [collectionField] are nullable, so they take thunks: omit to
  /// preserve, pass `() => value` to replace (`() => null` clears).
  Crosstab copyWith({
    String? id,
    String? Function()? name,
    String? Function()? collectionField,
    List<CrosstabGroup>? rowGroups,
    List<CrosstabGroup>? columnGroups,
    List<CrosstabMeasure>? measures,
    CrosstabStyle? style,
    BoolProperty? visible,
  }) =>
      Crosstab(
        id: id ?? this.id,
        name: name == null ? this.name : name(),
        collectionField: collectionField == null
            ? this.collectionField
            : collectionField(),
        rowGroups: rowGroups ?? this.rowGroups,
        columnGroups: columnGroups ?? this.columnGroups,
        measures: measures ?? this.measures,
        style: style ?? this.style,
        visible: visible ?? this.visible,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        name,
        collectionField,
        rowGroups,
        columnGroups,
        measures,
        style,
        visible,
      ];

  @override
  String toString() => 'Crosstab($id, ${rowGroups.length}x'
      '${columnGroups.length}, ${measures.length} measure(s))';
}
```

- [ ] **Step 7: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/domain/crosstab/crosstab_model_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 8: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/domain/crosstab packages/jet_print/test/domain/crosstab
git commit -m "feat(domain): crosstab model (axes, measures, style)"
```

---

## Task 3: The `CrosstabNode` variant and its fallout

**Files:**
- Modify: `packages/jet_print/lib/src/domain/detail_scope.dart`
- Modify: `packages/jet_print/lib/src/designer/controller/band_walker.dart` (`allIds`, plus every switch Task 1 created)
- Modify: `packages/jet_print/lib/src/data/binding_scope.dart`, `packages/jet_print/lib/src/domain/report_validation.dart` (the switches from Task 1)
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart` (`emitNode` — a documented no-op for now)
- Modify: `packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart` (`_encodeNode` — throw for now, real encoding in Task 4)
- Test: `packages/jet_print/test/designer/controller/band_walker_test.dart` (extend)

**Interfaces:**
- Consumes: `Crosstab` (Task 2).
- Produces: `final class CrosstabNode extends ScopeNode` with `final Crosstab crosstab`, constructed as `CrosstabNode(crosstab)`. `allIds(def)` now yields the crosstab's id.

Context — adding the variant breaks every exhaustive switch. That is the point: work through the compile errors and give each site an explicit arm. **`allIds` is the one real behavioural gap**: without an arm, a crosstab's id is not collected, so id minting could hand out a colliding id.

- [ ] **Step 1: Write the failing test.**

Append to `test/designer/controller/band_walker_test.dart`:

```dart
  group('crosstab nodes', () {
    const Crosstab ct = Crosstab(
      id: 'ct1',
      rowGroups: <CrosstabGroup>[
        CrosstabGroup(id: 'g/r', name: 'R', expression: r'$F{region}'),
      ],
      columnGroups: <CrosstabGroup>[
        CrosstabGroup(id: 'g/c', name: 'C', expression: r'$F{quarter}'),
      ],
      measures: <CrosstabMeasure>[
        CrosstabMeasure(
          id: 'm/a',
          name: 'A',
          expression: r'$F{amount}',
          aggregate: JetCalculation.sum,
        ),
      ],
    );
    final ReportDefinition def = ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 12)),
            CrosstabNode(ct),
          ],
        ),
      ),
    );

    test('allIds collects the crosstab id so minting cannot collide', () {
      expect(allIds(def), contains('ct1'));
    });

    test('allBands ignores a crosstab (it owns no bands)', () {
      expect(allBands(def).map((Band b) => b.id), <String>['detail']);
    });

    test('findScope still walks past a crosstab sibling', () {
      expect(findScope(def, 'root')?.id, 'root');
    });
  });
```

Add the imports the group needs: `crosstab.dart`, `crosstab_group.dart`, `crosstab_measure.dart`, and `report_variable.dart show JetCalculation`.

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/designer/controller/band_walker_test.dart`
Expected: FAIL — `CrosstabNode` is undefined.

- [ ] **Step 3: Add the variant to `detail_scope.dart`.**

Add the import `import 'crosstab/crosstab.dart';` and, after `NestedScope`:

```dart
/// A crosstab block rendered within the owning scope.
///
/// Unlike a [BandNode], a crosstab is **not** per-row: it folds the scope's rows
/// as they stream and prints once — before the row loop when it precedes every
/// row-producing sibling, otherwise after it.
final class CrosstabNode extends ScopeNode with ValueEquality {
  /// Wraps [crosstab] as a scope child.
  const CrosstabNode(this.crosstab);

  /// The crosstab printed once within the owning scope.
  final Crosstab crosstab;

  @override
  List<Object?> get props => <Object?>[crosstab];

  @override
  String toString() => 'CrosstabNode(${crosstab.id})';
}
```

- [ ] **Step 4: Work through the compile errors.**

Run `cd packages/jet_print && dart analyze` and give every non-exhaustive switch an arm:

- `band_walker.dart` `allIds` walker — **the behavioural fix**:
  ```dart
        case CrosstabNode(crosstab: final Crosstab ct):
          out.add(ct.id); // minting must not reuse it
  ```
- `band_walker.dart` `findGroup` / `findScope` / `findGroupOfBand` / `scopePathToBand` searches, `binding_scope.dart` `publishedTotalsForScope`, `report_validation.dart` `collectTotals` — a crosstab owns no bands, scopes, groups or published totals:
  ```dart
        case CrosstabNode():
          break; // a crosstab owns no bands, scopes or published totals
  ```
- `report_filler.dart` `emitNode` — a documented no-op; Task 11 does the real work:
  ```dart
        case CrosstabNode():
          // Not a per-row node: a crosstab folds during the scope's row walk and
          // its bands are spliced in afterwards (see the crosstab registry).
          break;
  ```
- `report_definition_codec.dart` `_encodeNode` — a temporary throw, replaced in Task 4:
  ```dart
      CrosstabNode() => throw UnimplementedError('crosstab codec — Task 4'),
  ```

- [ ] **Step 5: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/designer/controller/band_walker_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full suite.**

Run: `cd packages/jet_print && flutter test`
Expected: PASS. No golden may move — nothing constructs a `CrosstabNode` yet outside the new test.

- [ ] **Step 7: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib packages/jet_print/test
git commit -m "feat(domain): CrosstabNode scope variant; allIds collects crosstab ids"
```

---

## Task 4: Serialization — `kind: 'crosstab'` and `UnknownScopeNode`

**Files:**
- Create: `packages/jet_print/lib/src/domain/crosstab/crosstab_codec.dart`
- Create: `packages/jet_print/lib/src/domain/unknown_scope_node.dart`
- Modify: `packages/jet_print/lib/src/domain/serialization/report_definition_codec.dart` (`_encodeNode`, `_decodeNode`)
- Test: `packages/jet_print/test/domain/crosstab/crosstab_codec_test.dart`

**Interfaces:**
- Consumes: `Crosstab` and friends (Task 2), `CrosstabNode` (Task 3).
- Produces: `Map<String, Object?> encodeCrosstab(Crosstab)` and `Crosstab decodeCrosstab(Map<String, Object?>)`; `UnknownScopeNode(rawJson: ...)` with `final Map<String, Object?> rawJson`.

Context — defaults must be **omitted** so crosstab-free reports stay byte-identical and a minimal crosstab stays small. Copy the omission style of `ReportVariable.toJson` and the codec's own `_encodeGroup` / `_encodeBand`; do **not** copy `ColumnLayout.toJson`, which writes all fields unconditionally.

`_decodeNode`'s `default:` arm stops throwing and returns `UnknownScopeNode` instead, so a future node kind round-trips rather than failing the whole file.

- [ ] **Step 1: Write the failing test.**

Create `test/domain/crosstab/crosstab_codec_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/band.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_codec.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart' show BandType;
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/domain/serialization/built_in_element_codecs.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_definition_codec.dart';
import 'package:jet_print/src/domain/unknown_scope_node.dart';

const Crosstab _minimal = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[
    CrosstabGroup(id: 'g/r', name: 'R', expression: r'$F{region}'),
  ],
  columnGroups: <CrosstabGroup>[
    CrosstabGroup(id: 'g/c', name: 'C', expression: r'$F{quarter}'),
  ],
  measures: <CrosstabMeasure>[
    CrosstabMeasure(
      id: 'm/a',
      name: 'A',
      expression: r'$F{amount}',
      aggregate: JetCalculation.sum,
    ),
  ],
);

ElementCodecRegistry _registry() {
  final ElementCodecRegistry r = ElementCodecRegistry();
  registerBuiltInElementCodecs(r);
  return r;
}

void main() {
  group('crosstab codec', () {
    test('round-trips a minimal crosstab', () {
      expect(decodeCrosstab(encodeCrosstab(_minimal)), equals(_minimal));
    });

    test('omits defaults', () {
      final Map<String, Object?> json = encodeCrosstab(_minimal);
      expect(json.containsKey('style'), isFalse);
      expect(json.containsKey('name'), isFalse);
      expect(json.containsKey('collectionField'), isFalse);
      final Map<String, Object?> g =
          (json['rowGroups']! as List<Object?>).first! as Map<String, Object?>;
      expect(g.containsKey('sort'), isFalse, reason: 'ascending is default');
      expect(g.containsKey('showTotal'), isFalse, reason: 'true is default');
    });

    test('round-trips a fully populated crosstab', () {
      final Crosstab full = _minimal.copyWith(
        name: () => 'Sales',
        collectionField: () => 'lines',
        style: const CrosstabStyle(rowLabelWidth: 90, rowHeight: 16),
        rowGroups: <CrosstabGroup>[
          _minimal.rowGroups.first.copyWith(
            sort: CrosstabSort.descending,
            showTotal: false,
            totalLabel: () => 'All regions',
          ),
        ],
        measures: <CrosstabMeasure>[
          _minimal.measures.first.copyWith(
            aggregate: JetCalculation.average,
            format: () => '#,##0.00',
          ),
        ],
      );
      expect(decodeCrosstab(encodeCrosstab(full)), equals(full));
    });

    test('a crosstab survives a whole-definition round-trip', () {
      final ReportDefinition def = ReportDefinition(
        name: 'R',
        page: PageFormat.a4Portrait,
        body: const ReportBody(
          root: DetailScope(
            id: 'root',
            children: <ScopeNode>[
              BandNode(Band(id: 'd', type: BandType.detail, height: 12)),
              CrosstabNode(_minimal),
            ],
          ),
        ),
      );
      final ReportDefinition back =
          decodeDefinition(encodeDefinition(def, _registry()), _registry());
      expect(back, equals(def));
    });

    test('an unknown scope-node kind round-trips instead of throwing', () {
      final Map<String, Object?> json =
          encodeDefinition(
            ReportDefinition(
              name: 'R',
              page: PageFormat.a4Portrait,
              body: const ReportBody(
                root: DetailScope(id: 'root', children: <ScopeNode>[]),
              ),
            ),
            _registry(),
          );
      final Map<String, Object?> body = json['body']! as Map<String, Object?>;
      final Map<String, Object?> root = body['root']! as Map<String, Object?>;
      const Map<String, Object?> alien = <String, Object?>{
        'kind': 'sparkline',
        'payload': <String, Object?>{'id': 'x1'},
      };
      root['children'] = <Object?>[alien];

      final ReportDefinition back = decodeDefinition(json, _registry());
      final ScopeNode node = back.body.root.children.single;
      expect(node, isA<UnknownScopeNode>());
      expect((node as UnknownScopeNode).rawJson, alien);

      final Map<String, Object?> reJson = encodeDefinition(back, _registry());
      final Map<String, Object?> reBody = reJson['body']! as Map<String, Object?>;
      final Map<String, Object?> reRoot = reBody['root']! as Map<String, Object?>;
      expect((reRoot['children']! as List<Object?>).single, alien);
    });
  });
}
```

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/domain/crosstab/crosstab_codec_test.dart`
Expected: FAIL — `crosstab_codec.dart` and `unknown_scope_node.dart` do not exist.

- [ ] **Step 3: Write `unknown_scope_node.dart`.**

```dart
/// Preserves a scope node whose `kind` is not known to this build.
library;

import 'detail_scope.dart';
import 'value_equality.dart';

/// A [ScopeNode] standing in for a `kind` this build does not recognize.
///
/// It keeps the node's original JSON verbatim ([rawJson]) so a definition
/// authored by a newer build round-trips **losslessly** (Constitution V) rather
/// than failing the whole file. It renders nothing.
final class UnknownScopeNode extends ScopeNode with ValueEquality {
  /// Wraps [rawJson] for an unrecognized node kind.
  const UnknownScopeNode({required this.rawJson});

  /// The node's original JSON, written back unchanged on save.
  final Map<String, Object?> rawJson;

  /// The unrecognized `kind` string, or null when the JSON had none.
  String? get kind => rawJson['kind'] is String ? rawJson['kind']! as String : null;

  @override
  List<Object?> get props => <Object?>[
        <Object?>[
          for (final MapEntry<String, Object?> e in rawJson.entries) ...<Object?>[
            e.key,
            e.value,
          ],
        ],
      ];

  @override
  String toString() => 'UnknownScopeNode(${kind ?? '?'})';
}
```

- [ ] **Step 4: Write `crosstab_codec.dart`.**

```dart
/// JSON for the crosstab model (spec A). Defaults are omitted, so a crosstab-free
/// report is byte-identical to one written before crosstabs existed and a minimal
/// crosstab stays small.
library;

import '../report_variable.dart' show JetCalculation;
import '../styles/box_style.dart';
import '../styles/text_style.dart';
import 'crosstab.dart';
import 'crosstab_group.dart';
import 'crosstab_measure.dart';
import 'crosstab_style.dart';

const CrosstabStyle _defaultStyle = CrosstabStyle();

/// Encodes [ct] to a JSON-safe map.
Map<String, Object?> encodeCrosstab(Crosstab ct) => <String, Object?>{
      'id': ct.id,
      if (ct.name != null) 'name': ct.name,
      if (ct.collectionField != null) 'collectionField': ct.collectionField,
      'rowGroups': <Object?>[for (final CrosstabGroup g in ct.rowGroups) _group(g)],
      'columnGroups': <Object?>[
        for (final CrosstabGroup g in ct.columnGroups) _group(g),
      ],
      'measures': <Object?>[
        for (final CrosstabMeasure m in ct.measures) _measure(m),
      ],
      if (ct.style != _defaultStyle) 'style': _style(ct.style),
      if (ct.visible != const BoolProperty()) 'visible': ct.visible.toJson(),
    };

/// Reads a [Crosstab] from its [encodeCrosstab] map.
Crosstab decodeCrosstab(Map<String, Object?> json) => Crosstab(
      id: json['id']! as String,
      name: json['name'] as String?,
      collectionField: json['collectionField'] as String?,
      rowGroups: <CrosstabGroup>[
        for (final Object? g in json['rowGroups']! as List<Object?>)
          _readGroup((g! as Map).cast<String, Object?>()),
      ],
      columnGroups: <CrosstabGroup>[
        for (final Object? g in json['columnGroups']! as List<Object?>)
          _readGroup((g! as Map).cast<String, Object?>()),
      ],
      measures: <CrosstabMeasure>[
        for (final Object? m in json['measures']! as List<Object?>)
          _readMeasure((m! as Map).cast<String, Object?>()),
      ],
      style: json['style'] == null
          ? const CrosstabStyle()
          : _readStyle((json['style']! as Map).cast<String, Object?>()),
      visible: json['visible'] == null
          ? const BoolProperty()
          : BoolProperty.fromJson(
              (json['visible']! as Map).cast<String, Object?>()),
    );

Map<String, Object?> _group(CrosstabGroup g) => <String, Object?>{
      'id': g.id,
      'name': g.name,
      'expression': g.expression,
      if (g.sort != CrosstabSort.ascending) 'sort': g.sort.name,
      if (!g.showTotal) 'showTotal': false,
      if (g.totalLabel != null) 'totalLabel': g.totalLabel,
    };

CrosstabGroup _readGroup(Map<String, Object?> j) => CrosstabGroup(
      id: j['id']! as String,
      name: j['name']! as String,
      expression: j['expression']! as String,
      sort: j['sort'] == null
          ? CrosstabSort.ascending
          : CrosstabSort.values.byName(j['sort']! as String),
      showTotal: j['showTotal'] as bool? ?? true,
      totalLabel: j['totalLabel'] as String?,
    );

Map<String, Object?> _measure(CrosstabMeasure m) => <String, Object?>{
      'id': m.id,
      'name': m.name,
      'expression': m.expression,
      'aggregate': m.aggregate.name,
      if (m.format != null) 'format': m.format,
      if (m.cellTextStyle != null) 'cellTextStyle': m.cellTextStyle!.toJson(),
      if (m.cellBoxStyle != null) 'cellBoxStyle': m.cellBoxStyle!.toJson(),
    };

CrosstabMeasure _readMeasure(Map<String, Object?> j) => CrosstabMeasure(
      id: j['id']! as String,
      name: j['name']! as String,
      expression: j['expression']! as String,
      aggregate: JetCalculation.values.byName(j['aggregate']! as String),
      format: j['format'] as String?,
      cellTextStyle: j['cellTextStyle'] == null
          ? null
          : JetTextStyle.fromJson((j['cellTextStyle']! as Map).cast<String, Object?>()),
      cellBoxStyle: j['cellBoxStyle'] == null
          ? null
          : JetBoxStyle.fromJson((j['cellBoxStyle']! as Map).cast<String, Object?>()),
    );

Map<String, Object?> _style(CrosstabStyle s) => <String, Object?>{
      if (s.headerText != null) 'headerText': s.headerText!.toJson(),
      if (s.headerBox != null) 'headerBox': s.headerBox!.toJson(),
      if (s.cellText != null) 'cellText': s.cellText!.toJson(),
      if (s.cellBox != null) 'cellBox': s.cellBox!.toJson(),
      if (s.totalText != null) 'totalText': s.totalText!.toJson(),
      if (s.totalBox != null) 'totalBox': s.totalBox!.toJson(),
      if (s.rowLabelWidth != _defaultStyle.rowLabelWidth)
        'rowLabelWidth': s.rowLabelWidth,
      if (s.rowLabelIndent != _defaultStyle.rowLabelIndent)
        'rowLabelIndent': s.rowLabelIndent,
      if (s.measureColumnWidth != _defaultStyle.measureColumnWidth)
        'measureColumnWidth': s.measureColumnWidth,
      if (s.rowHeight != _defaultStyle.rowHeight) 'rowHeight': s.rowHeight,
      if (s.headerRowHeight != _defaultStyle.headerRowHeight)
        'headerRowHeight': s.headerRowHeight,
    };

CrosstabStyle _readStyle(Map<String, Object?> j) {
  JetTextStyle? text(String k) => j[k] == null
      ? null
      : JetTextStyle.fromJson((j[k]! as Map).cast<String, Object?>());
  JetBoxStyle? box(String k) => j[k] == null
      ? null
      : JetBoxStyle.fromJson((j[k]! as Map).cast<String, Object?>());
  double num_(String k, double fallback) =>
      (j[k] as num?)?.toDouble() ?? fallback;
  return CrosstabStyle(
    headerText: text('headerText'),
    headerBox: box('headerBox'),
    cellText: text('cellText'),
    cellBox: box('cellBox'),
    totalText: text('totalText'),
    totalBox: box('totalBox'),
    rowLabelWidth: num_('rowLabelWidth', _defaultStyle.rowLabelWidth),
    rowLabelIndent: num_('rowLabelIndent', _defaultStyle.rowLabelIndent),
    measureColumnWidth:
        num_('measureColumnWidth', _defaultStyle.measureColumnWidth),
    rowHeight: num_('rowHeight', _defaultStyle.rowHeight),
    headerRowHeight: num_('headerRowHeight', _defaultStyle.headerRowHeight),
  );
}
```

Import `BoolProperty` from `../bool_property.dart`. It has `toJson()` / `fromJson(Map)` but no `isDefault` getter, hence the `!= const BoolProperty()` comparison above.

- [ ] **Step 5: Wire the two codec arms in `report_definition_codec.dart`.**

Replace the Task 3 placeholder in `_encodeNode`:

```dart
    CrosstabNode(crosstab: final Crosstab ct) => <String, Object?>{
        'kind': 'crosstab',
        'crosstab': encodeCrosstab(ct),
      },
    UnknownScopeNode(rawJson: final Map<String, Object?> raw) => raw,
```

And in `_decodeNode`:

```dart
    case 'crosstab':
      return CrosstabNode(
          decodeCrosstab((json['crosstab']! as Map).cast<String, Object?>()));
    default:
      return UnknownScopeNode(rawJson: Map<String, Object?>.unmodifiable(json));
```

Delete the `ReportFormatException` throw and, if it becomes unused, its now-dead import.

- [ ] **Step 6: Give every switch an `UnknownScopeNode` arm.**

`UnknownScopeNode` is a **second** new variant of the same sealed hierarchy, so it breaks every
switch Task 3 just fixed. Run `cd packages/jet_print && dart analyze` and add to each:

```dart
      case UnknownScopeNode():
        break; // preserved verbatim for round-trip; renders nothing
```

In `band_walker.dart`'s `allIds` walker it is also a `break` — an unknown node's ids are opaque, and
minting cannot collide with a name it cannot read. `_encodeNode` already handles it (Step 5).

- [ ] **Step 7: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/domain/crosstab/crosstab_codec_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 8: Prove byte-identity for crosstab-free reports.**

Run: `cd packages/jet_print && flutter test test/domain`
Expected: PASS. The existing codec round-trip and golden-JSON tests must be untouched — if any serialized output changed, an omit-default guard is missing.

- [ ] **Step 9: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib packages/jet_print/test
git commit -m "feat(domain): crosstab JSON codec; UnknownScopeNode preserves future node kinds"
```

---

## Task 5: `validate()` rules for crosstabs

**Files:**
- Modify: `packages/jet_print/lib/src/domain/report_validation.dart`
- Test: `packages/jet_print/test/domain/crosstab/crosstab_validation_test.dart`

**Interfaces:**
- Consumes: `Crosstab`, `CrosstabNode`, the existing `validate(ReportDefinition, {JetDataSchema? schema})` and `Diagnostic(severity, message, {elementId})`.
- Produces: no new API. `validate()` gains crosstab diagnostics, each tagged `elementId: crosstab.id`.

Nine rules, in this order. Errors first so a broken crosstab reports its worst problem first.

| Rule | Severity | Message stem |
|---|---|---|
| `rowGroups` empty | error | `crosstab "<id>" has no row groups` |
| `columnGroups` empty | error | `crosstab "<id>" has no column groups` |
| `measures` empty | error | `crosstab "<id>" has no measures` |
| A measure's `aggregate` is `JetCalculation.none` | error | `measure "<name>" cannot use calculation "none"` |
| A group or measure expression fails to parse | error | `crosstab "<id>" expression does not parse: <detail>` |
| The crosstab sits in a `NestedScope` | error | `crosstab "<id>" must be in the root scope` |
| `rowLabelWidth`, `measureColumnWidth` or `rowHeight` <= 0 | error | `crosstab "<id>" has a non-positive <field>` |
| `visible` expression references `$F{}` | warning | `crosstab "<id>" visibility cannot use fields` |
| `rowLabelWidth + measures.length * measureColumnWidth` > body width | warning | `crosstab "<id>" is wider than the page body` |

A schema-aware rule (fields resolve in scope) rides the existing field-resolution pass when `schema != null`, emitting a warning per unresolved name — mirror how band elements are already checked in this file rather than inventing a second mechanism.

- [ ] **Step 1: Write the failing test.**

Create `test/domain/crosstab/crosstab_validation_test.dart`. Build a helper that wraps a crosstab in a minimal definition, then assert one rule per test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/detail_scope.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_definition.dart';
import 'package:jet_print/src/domain/report_validation.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;

const CrosstabGroup _row =
    CrosstabGroup(id: 'g/r', name: 'R', expression: r'$F{region}');
const CrosstabGroup _col =
    CrosstabGroup(id: 'g/c', name: 'C', expression: r'$F{quarter}');
const CrosstabMeasure _m = CrosstabMeasure(
  id: 'm/a',
  name: 'Amount',
  expression: r'$F{amount}',
  aggregate: JetCalculation.sum,
);
const Crosstab _ok = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[_row],
  columnGroups: <CrosstabGroup>[_col],
  measures: <CrosstabMeasure>[_m],
);

/// Wraps [ct] at the root, or one level down when [nested] is true.
ReportDefinition _def(Crosstab ct, {bool nested = false}) => ReportDefinition(
      name: 'R',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            if (nested)
              NestedScope(DetailScope(
                id: 'lines',
                collectionField: 'lines',
                children: <ScopeNode>[CrosstabNode(ct)],
              ))
            else
              CrosstabNode(ct),
          ],
        ),
      ),
    );

Iterable<String> _messages(ReportDefinition def, DiagnosticSeverity s) =>
    validate(def)
        .where((Diagnostic d) => d.severity == s)
        .map((Diagnostic d) => d.message);

void main() {
  group('crosstab validation', () {
    test('a well-formed root crosstab is clean', () {
      expect(
        validate(_def(_ok)).where((Diagnostic d) => d.elementId == 'ct1'),
        isEmpty,
      );
    });

    test('empty axes and measures are errors', () {
      expect(
        _messages(_def(_ok.copyWith(rowGroups: <CrosstabGroup>[])),
            DiagnosticSeverity.error),
        anyElement(contains('no row groups')),
      );
      expect(
        _messages(_def(_ok.copyWith(columnGroups: <CrosstabGroup>[])),
            DiagnosticSeverity.error),
        anyElement(contains('no column groups')),
      );
      expect(
        _messages(_def(_ok.copyWith(measures: <CrosstabMeasure>[])),
            DiagnosticSeverity.error),
        anyElement(contains('no measures')),
      );
    });

    test('calculation "none" is rejected for a measure', () {
      final Crosstab bad = _ok.copyWith(measures: <CrosstabMeasure>[
        _m.copyWith(aggregate: JetCalculation.none),
      ]);
      expect(_messages(_def(bad), DiagnosticSeverity.error),
          anyElement(contains('none')));
    });

    test('an unparseable expression is an error', () {
      final Crosstab bad = _ok.copyWith(
        rowGroups: <CrosstabGroup>[_row.copyWith(expression: r'$F{')],
      );
      expect(_messages(_def(bad), DiagnosticSeverity.error),
          anyElement(contains('does not parse')));
    });

    test('a crosstab in a nested scope is rejected in Spec A', () {
      expect(_messages(_def(_ok, nested: true), DiagnosticSeverity.error),
          anyElement(contains('root scope')));
    });

    test('non-positive metrics are errors', () {
      final Crosstab bad =
          _ok.copyWith(style: const CrosstabStyle(rowHeight: 0));
      expect(_messages(_def(bad), DiagnosticSeverity.error),
          anyElement(contains('non-positive')));
    });

    test('a crosstab too wide for the body warns', () {
      final Crosstab wide =
          _ok.copyWith(style: const CrosstabStyle(measureColumnWidth: 900));
      expect(_messages(_def(wide), DiagnosticSeverity.warning),
          anyElement(contains('wider than the page body')));
    });

    test('a field reference in visible warns (a crosstab has no row)', () {
      final Crosstab bad =
          _ok.copyWith(visible: const BoolProperty(expression: r'$F{flag}'));
      expect(_messages(_def(bad), DiagnosticSeverity.warning),
          anyElement(contains('visibility cannot use fields')));
    });
  });
}
```

Check `BoolProperty`'s constructor before writing the last test — use whatever parameter names it actually declares for an expression-backed property.

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/domain/crosstab/crosstab_validation_test.dart`
Expected: FAIL — every rule is missing; only the "well-formed is clean" test passes.

- [ ] **Step 3: Implement the rules.**

In `report_validation.dart`, add a `_validateCrosstab(Crosstab ct, ReportDefinition def, List<Diagnostic> out, {required bool inRootScope})` helper and call it from the scope walk — the `CrosstabNode` arm added in Task 3 now does work instead of `break`. Walk the root's children with `inRootScope: true` and nested scopes' children with `inRootScope: false`.

Body width is `def.page.width - def.page.margins.left - def.page.margins.right`. Parse checks use the existing `Expression.parse` inside a `try` / `on ExpressionException` — follow how band elements are already checked in this file.

- [ ] **Step 4: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/domain/crosstab/crosstab_validation_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Run the domain suite.**

Run: `cd packages/jet_print && flutter test test/domain`
Expected: PASS. Existing validation tests must be untouched — crosstab rules only fire on `CrosstabNode`.

- [ ] **Step 6: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib packages/jet_print/test
git commit -m "feat(domain): validate() rules for crosstabs"
```

---

## Task 6: The matrix value types

**Files:**
- Create: `packages/jet_print/lib/src/rendering/crosstab/crosstab_matrix.dart`
- Test: `packages/jet_print/test/rendering/crosstab/crosstab_matrix_test.dart`

**Interfaces:**
- Consumes: `JetValue` (`expression/value.dart`), `CrosstabMeasure`, `ValueEquality`.
- Produces:
  - `CrosstabAxisNode({required JetValue key, required String pathKey, required String label, required int depth, List<CrosstabAxisNode> children, bool isTotal})`
  - `CrosstabCellKey(List<String> rowPath, List<String> colPath, String measureId)` — a value type, usable as a map key
  - `CrosstabMatrix({required List<CrosstabAxisNode> rowAxis, required List<CrosstabAxisNode> columnAxis, required List<CrosstabMeasure> measures, required Map<CrosstabCellKey, JetValue> cells, List<Diagnostic> diagnostics})`
  - `List<CrosstabAxisNode> leavesOf(List<CrosstabAxisNode> axis)` — depth-first leaves, used by the planner for column layout.

Data only, no computation. Splitting it from the aggregator lets the planner's tests build a matrix by hand without running an aggregation.

- [ ] **Step 1: Write the failing test.**

Create `test/rendering/crosstab/crosstab_matrix_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';

CrosstabAxisNode _node(String k, {List<CrosstabAxisNode> children = const <CrosstabAxisNode>[], bool isTotal = false, int depth = 0}) =>
    CrosstabAxisNode(
      key: JetString(k),
      pathKey: k,
      label: k,
      depth: depth,
      children: children,
      isTotal: isTotal,
    );

void main() {
  group('CrosstabCellKey', () {
    test('equal paths make equal keys, so it works as a map key', () {
      const CrosstabCellKey a =
          CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a');
      const CrosstabCellKey b =
          CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a');
      expect(a, equals(b));
      final Map<CrosstabCellKey, JetValue> cells = <CrosstabCellKey, JetValue>{
        a: const JetNumber(1),
      };
      expect(cells[b], const JetNumber(1));
    });

    test('a shortened path is a different key — that is the subtotal', () {
      const CrosstabCellKey leaf =
          CrosstabCellKey(<String>['North', 'Istanbul'], <String>['Q1'], 'm/a');
      const CrosstabCellKey total =
          CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a');
      expect(leaf, isNot(equals(total)));
    });
  });

  group('leavesOf', () {
    test('returns depth-first leaves', () {
      final List<CrosstabAxisNode> axis = <CrosstabAxisNode>[
        _node('2025', children: <CrosstabAxisNode>[
          _node('Q1', depth: 1),
          _node('Q2', depth: 1),
        ]),
        _node('2026', children: <CrosstabAxisNode>[_node('Q1', depth: 1)]),
      ];
      expect(leavesOf(axis).map((CrosstabAxisNode n) => n.pathKey),
          <String>['Q1', 'Q2', 'Q1']);
    });

    test('a childless root is itself a leaf', () {
      expect(leavesOf(<CrosstabAxisNode>[_node('All')]).single.pathKey, 'All');
    });
  });
}
```

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_matrix_test.dart`
Expected: FAIL — `crosstab_matrix.dart` does not exist.

- [ ] **Step 3: Implement `crosstab_matrix.dart`.**

```dart
/// The crosstab aggregation result (spec A): two axis trees plus a sparse cell
/// map. Pure data with value equality, so a matrix is a snapshot-testable data
/// golden independent of any geometry.
library;

import '../../domain/crosstab/crosstab_measure.dart';
import '../../domain/diagnostic.dart';
import '../../domain/value_equality.dart';
import '../../expression/value.dart';

/// One node of a resolved axis tree.
class CrosstabAxisNode with ValueEquality {
  /// Creates an axis node.
  const CrosstabAxisNode({
    required this.key,
    required this.pathKey,
    required this.label,
    required this.depth,
    this.children = const <CrosstabAxisNode>[],
    this.isTotal = false,
  });

  /// The typed group key — **the sort key**. Kept typed so `9` orders before
  /// `10` and dates order chronologically.
  final JetValue key;

  /// The stringified key, used in cell paths and element ids.
  final String pathKey;

  /// The text printed for this node.
  final String label;

  /// Nesting depth; 0 is the outermost level.
  final int depth;

  /// Child nodes; empty means this node is a leaf.
  final List<CrosstabAxisNode> children;

  /// Whether this node is a subtotal (or, at depth 0, the grand total).
  final bool isTotal;

  @override
  List<Object?> get props =>
      <Object?>[key, pathKey, label, depth, children, isTotal];

  @override
  String toString() =>
      'CrosstabAxisNode($pathKey${isTotal ? ' total' : ''}, d$depth)';
}

/// The address of one cell: a row path, a column path and a measure id.
///
/// A **shortened** path addresses that level's subtotal; the full leaf paths
/// address a data cell.
class CrosstabCellKey with ValueEquality {
  /// Creates a cell address.
  const CrosstabCellKey(this.rowPath, this.colPath, this.measureId);

  /// Row-axis `pathKey`s, outermost first.
  final List<String> rowPath;

  /// Column-axis `pathKey`s, outermost first.
  final List<String> colPath;

  /// The measure this cell holds.
  final String measureId;

  @override
  List<Object?> get props => <Object?>[rowPath, colPath, measureId];

  @override
  String toString() =>
      'CrosstabCellKey(${rowPath.join('/')} x ${colPath.join('/')} : $measureId)';
}

/// A resolved crosstab: both axis trees, the measures in column order, and the
/// **sparse** cell map — an intersection that saw no rows has no entry, which is
/// how an empty cell stays distinguishable from a zero.
class CrosstabMatrix with ValueEquality {
  /// Creates a matrix.
  const CrosstabMatrix({
    required this.rowAxis,
    required this.columnAxis,
    required this.measures,
    required this.cells,
    this.diagnostics = const <Diagnostic>[],
  });

  /// Row axis roots, in sorted order.
  final List<CrosstabAxisNode> rowAxis;

  /// Column axis roots, in sorted order.
  final List<CrosstabAxisNode> columnAxis;

  /// The measures, in column order.
  final List<CrosstabMeasure> measures;

  /// Populated cells only.
  final Map<CrosstabCellKey, JetValue> cells;

  /// Issues raised while folding (e.g. the cardinality warning).
  final List<Diagnostic> diagnostics;

  @override
  List<Object?> get props => <Object?>[
        rowAxis,
        columnAxis,
        measures,
        <Object?>[
          for (final MapEntry<CrosstabCellKey, JetValue> e in cells.entries)
            ...<Object?>[e.key, e.value],
        ],
        diagnostics,
      ];

  @override
  String toString() => 'CrosstabMatrix(${rowAxis.length} row root(s) x '
      '${columnAxis.length} column root(s), ${cells.length} cell(s))';
}

/// The depth-first leaves of [axis]; a childless node is its own leaf.
List<CrosstabAxisNode> leavesOf(List<CrosstabAxisNode> axis) {
  final List<CrosstabAxisNode> out = <CrosstabAxisNode>[];
  void walk(CrosstabAxisNode n) {
    if (n.children.isEmpty) {
      out.add(n);
      return;
    }
    for (final CrosstabAxisNode c in n.children) {
      walk(c);
    }
  }

  for (final CrosstabAxisNode n in axis) {
    walk(n);
  }
  return out;
}
```

- [ ] **Step 4: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_matrix_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/crosstab packages/jet_print/test/rendering/crosstab
git commit -m "feat(rendering): crosstab matrix value types"
```

---

## Task 7: The aggregator — rows to matrix in one pass

**Files:**
- Create: `packages/jet_print/lib/src/rendering/crosstab/crosstab_aggregator.dart`
- Test: `packages/jet_print/test/rendering/crosstab/crosstab_aggregator_test.dart`

**Interfaces:**
- Consumes: `Crosstab`, `CrosstabMatrix` types (Task 6), `DataRow`, `Expression.parse(String)` / `Expression.evaluate(EvalContext)`, `VariableAccumulator(JetCalculation)` with `.fold(JetValue)` and `.value`.
- Produces:
  ```dart
  class CrosstabAggregation {
    CrosstabAggregation(Crosstab ct, {required EvalContext Function(DataRow) makeContext});
    void fold(DataRow row);          // call once per row, in stream order
    CrosstabMatrix build();          // call after the last row
  }
  ```
  A stateful object rather than a one-shot function, because Task 11's filler folds rows as they stream and never holds them.

Context — **prefix folding.** For each row, evaluate the row-axis expressions into a path and the column-axis expressions into a path, then fold each measure's value into every `(row-path prefix) x (column-path prefix)` combination. A shortened prefix *is* that level's subtotal, so subtotals cost nothing extra and `average` stays correct at every level (rolling leaf averages upward would give an average of averages).

A level whose `showTotal` is false contributes no shortened prefix — its subtotal is never folded.

Sorting uses the **typed** `JetValue` key; `pathKey` and `label` are the stringified forms.

- [ ] **Step 1: Write the failing test.**

Create `test/rendering/crosstab/crosstab_aggregator_test.dart`. A tiny fake context keeps the test free of the fill engine:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/data/data_row.dart';
import 'package:jet_print/src/data/field_def.dart';
import 'package:jet_print/src/domain/crosstab/crosstab.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_group.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/expression/eval_context.dart';
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_aggregator.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';

/// The smallest context that resolves `$F{}` against a row and nothing else.
class _RowContext implements EvalContext {
  _RowContext(this.row);
  final DataRow row;

  @override
  JetValue resolveField(String name) =>
      row.hasField(name) ? JetValue.from(row.field(name)) : const JetNull();

  @override
  JetValue resolveParam(String name) => const JetNull();

  @override
  JetValue resolveVariable(String name) => const JetNull();

  @override
  JetValue callFunction(String name, List<JetValue> args) => const JetNull();
}

const List<FieldDef> _fields = <FieldDef>[
  FieldDef(name: 'region', type: JetFieldType.string),
  FieldDef(name: 'city', type: JetFieldType.string),
  FieldDef(name: 'quarter', type: JetFieldType.string),
  FieldDef(name: 'amount', type: JetFieldType.number),
];

DataRow _row(String region, String city, String quarter, num amount) => DataRow(
      fields: _fields,
      values: <String, Object?>{
        'region': region,
        'city': city,
        'quarter': quarter,
        'amount': amount,
      },
    );

const CrosstabMeasure _sum = CrosstabMeasure(
  id: 'm/a',
  name: 'Amount',
  expression: r'$F{amount}',
  aggregate: JetCalculation.sum,
);

Crosstab _ct({
  List<CrosstabGroup>? rowGroups,
  List<CrosstabMeasure>? measures,
}) =>
    Crosstab(
      id: 'ct1',
      rowGroups: rowGroups ??
          const <CrosstabGroup>[
            CrosstabGroup(id: 'g/r', name: 'Region', expression: r'$F{region}'),
            CrosstabGroup(id: 'g/c2', name: 'City', expression: r'$F{city}'),
          ],
      columnGroups: const <CrosstabGroup>[
        CrosstabGroup(id: 'g/q', name: 'Quarter', expression: r'$F{quarter}'),
      ],
      measures: measures ?? const <CrosstabMeasure>[_sum],
    );

CrosstabMatrix _run(Crosstab ct, List<DataRow> rows) {
  final CrosstabAggregation agg =
      CrosstabAggregation(ct, makeContext: (DataRow r) => _RowContext(r));
  for (final DataRow r in rows) {
    agg.fold(r);
  }
  return agg.build();
}

double? _cell(CrosstabMatrix m, List<String> rowPath, List<String> colPath) {
  final JetValue? v = m.cells[CrosstabCellKey(rowPath, colPath, 'm/a')];
  return v is JetNumber ? v.value : null;
}

void main() {
  final List<DataRow> rows = <DataRow>[
    _row('North', 'Istanbul', 'Q1', 120),
    _row('North', 'Ankara', 'Q1', 80),
    _row('North', 'Istanbul', 'Q2', 140),
    _row('South', 'Izmir', 'Q1', 50),
  ];

  group('prefix folding', () {
    test('leaf cells hold their own rows', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(_cell(m, <String>['North', 'Istanbul'], <String>['Q1']), 120);
      expect(_cell(m, <String>['North', 'Ankara'], <String>['Q1']), 80);
    });

    test('a shortened row path is that level subtotal', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(_cell(m, <String>['North'], <String>['Q1']), 200);
    });

    test('a shortened column path totals across columns', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(_cell(m, <String>['North', 'Istanbul'], <String>[]), 260);
    });

    test('both paths shortened is the grand total', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(_cell(m, <String>[], <String>[]), 390);
    });

    test('average is the mean of rows, not the mean of subtotals', () {
      // North: 120, 80, 140 -> mean 113.33; an average of the Q1/Q2 subtotals
      // (200 and 140) would give 170.
      final CrosstabMatrix m = _run(
        _ct(measures: <CrosstabMeasure>[
          _sum.copyWith(aggregate: JetCalculation.average),
        ]),
        rows,
      );
      expect(_cell(m, <String>['North'], <String>[])!, closeTo(113.333, 0.01));
    });
  });

  group('sparse cells', () {
    test('an intersection with no rows has no entry at all', () {
      final CrosstabMatrix m = _run(_ct(), rows);
      expect(
        m.cells.containsKey(
            const CrosstabCellKey(<String>['South', 'Izmir'], <String>['Q2'], 'm/a')),
        isFalse,
      );
    });

    test('count does not invent a zero for an empty intersection', () {
      final CrosstabMatrix m = _run(
        _ct(measures: <CrosstabMeasure>[
          _sum.copyWith(aggregate: JetCalculation.count),
        ]),
        rows,
      );
      expect(
        m.cells.containsKey(
            const CrosstabCellKey(<String>['South', 'Izmir'], <String>['Q2'], 'm/a')),
        isFalse,
      );
    });
  });

  group('axis construction', () {
    test('showTotal false suppresses that level subtotal', () {
      final CrosstabMatrix m = _run(
        _ct(rowGroups: const <CrosstabGroup>[
          CrosstabGroup(
              id: 'g/r',
              name: 'Region',
              expression: r'$F{region}',
              showTotal: false),
          CrosstabGroup(id: 'g/c2', name: 'City', expression: r'$F{city}'),
        ]),
        rows,
      );
      expect(_cell(m, <String>['North'], <String>['Q1']), isNull);
      expect(_cell(m, <String>['North', 'Istanbul'], <String>['Q1']), 120);
    });

    test('keys sort by their typed value, not their text', () {
      final List<DataRow> numeric = <DataRow>[
        _row('9', 'x', 'Q1', 1),
        _row('10', 'x', 'Q1', 1),
      ];
      final CrosstabMatrix m = _run(_ct(), numeric);
      // '9' and '10' are strings here, so they sort as strings: '10' first.
      expect(m.rowAxis.map((CrosstabAxisNode n) => n.pathKey),
          <String>['10', '9']);
    });

    test('dataOrder keeps first-seen order', () {
      final CrosstabMatrix m = _run(
        _ct(rowGroups: const <CrosstabGroup>[
          CrosstabGroup(
              id: 'g/r',
              name: 'Region',
              expression: r'$F{region}',
              sort: CrosstabSort.dataOrder),
        ]),
        rows,
      );
      expect(m.rowAxis.map((CrosstabAxisNode n) => n.pathKey),
          <String>['North', 'South']);
    });

    test('descending reverses the typed order', () {
      final CrosstabMatrix m = _run(
        _ct(rowGroups: const <CrosstabGroup>[
          CrosstabGroup(
              id: 'g/r',
              name: 'Region',
              expression: r'$F{region}',
              sort: CrosstabSort.descending),
        ]),
        rows,
      );
      expect(m.rowAxis.first.pathKey, 'South');
    });
  });
}
```

Check `EvalContext`'s actual member list before writing `_RowContext` — implement exactly the members it declares. Likewise confirm `JetValue.from` exists; if not, map the raw value with the constructor the codebase already uses for row values.

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_aggregator_test.dart`
Expected: FAIL — `CrosstabAggregation` is undefined.

- [ ] **Step 3: Implement the aggregator.**

Shape to follow:

```dart
class CrosstabAggregation {
  CrosstabAggregation(this._ct, {required EvalContext Function(DataRow) makeContext})
      : _makeContext = makeContext,
        _rowExprs = _compile(_ct.rowGroups),
        _colExprs = _compile(_ct.columnGroups),
        _measureExprs = <String, Expression?>{
          for (final CrosstabMeasure m in _ct.measures)
            m.id: _tryParse(m.expression),
        };

  // Accumulators, keyed by cell address.
  final Map<CrosstabCellKey, VariableAccumulator> _acc = {};
  // First-seen order and typed key per axis path, for tree building + sorting.
  final Map<String, JetValue> _rowKeys = {};   // pathKey -> typed key
  final Map<String, JetValue> _colKeys = {};
  final Map<String, Set<String>> _rowChildren = {}; // parent path -> child pathKeys
  final Map<String, Set<String>> _colChildren = {};

  void fold(DataRow row) {
    final EvalContext ctx = _makeContext(row);
    final List<JetValue> rowKeys = [for (final e in _rowExprs) e?.evaluate(ctx) ?? const JetNull()];
    final List<JetValue> colKeys = [for (final e in _colExprs) e?.evaluate(ctx) ?? const JetNull()];
    // Record keys + parent/child links (ordered sets preserve first-seen order).
    // Then, for each measure, fold its value into every prefix pair.
    for (final CrosstabMeasure m in _ct.measures) {
      final JetValue v = _measureExprs[m.id]?.evaluate(ctx) ?? const JetNull();
      for (final List<String> rp in _prefixes(rowKeys, _ct.rowGroups)) {
        for (final List<String> cp in _prefixes(colKeys, _ct.columnGroups)) {
          (_acc[CrosstabCellKey(rp, cp, m.id)] ??=
                  VariableAccumulator(m.aggregate))
              .fold(v);
        }
      }
    }
  }

  CrosstabMatrix build() { /* sort keys, build trees, convert accumulators */ }
}
```

`_prefixes(keys, groups)` yields the full path plus every shortened prefix whose *dropped* level has `showTotal: true` — including the empty prefix when the outermost level has `showTotal: true` (that is the grand total). Return `List<String>` of `pathKey`s.

Sorting: `ascending` / `descending` compare the typed `JetValue`s (numbers numerically, dates chronologically, otherwise by their string form); `dataOrder` uses insertion order.

Cardinality: after folding, if `_acc.length > 50000`, add one warning `Diagnostic` to the matrix — `'crosstab "<id>" produced <n> cells; check the group bindings'` — and **still build the matrix**. Never truncate.

- [ ] **Step 4: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_aggregator_test.dart`
Expected: PASS, 11 tests.

- [ ] **Step 5: Add a cardinality test and make it pass.**

```dart
    test('above 50k cells it warns once and still builds', () {
      final List<DataRow> many = <DataRow>[
        for (int i = 0; i < 26000; i++) _row('r$i', 'c$i', 'Q1', 1),
      ];
      final CrosstabMatrix m = _run(_ct(), many);
      expect(m.diagnostics.where((Diagnostic d) => d.message.contains('cells')),
          hasLength(1));
      expect(m.cells, isNotEmpty);
    });
```

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_aggregator_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib packages/jet_print/test
git commit -m "feat(rendering): crosstab aggregator (single-pass prefix folding)"
```

---

## Task 8: Column layout and horizontal slicing

**Files:**
- Create: `packages/jet_print/lib/src/rendering/crosstab/crosstab_planner.dart` (slicing half)
- Test: `packages/jet_print/test/rendering/crosstab/crosstab_slicing_test.dart`

**Interfaces:**
- Consumes: `CrosstabMatrix`, `leavesOf` (Task 6), `CrosstabStyle`.
- Produces:
  ```dart
  class CrosstabColumn {                 // one printed data column
    final CrosstabAxisNode leaf;         // its column-axis leaf
    final CrosstabMeasure measure;
    final double width;
  }
  class CrosstabSlice {                  // one horizontal page-slice
    final int index;                     // 0-based; index > 0 starts a new page
    final List<CrosstabColumn> columns;
  }
  List<CrosstabSlice> sliceColumns(CrosstabMatrix m, CrosstabStyle style,
      {required double availableWidth, required List<Diagnostic> diagnostics});
  ```

Two rules make this non-trivial:

1. **A slice never splits a leaf column group.** All M measures of one leaf stay together, otherwise the leaf's header span would be cut across a page boundary.
2. **The grand-total column's width is reserved while packing the slice that will hold the final leaf.** Without the reservation the grand total spills onto a continuation page of its own. If it still cannot fit, it does get its own slice and a diagnostic says so.

Every slice implicitly carries the row-label column (`style.rowLabelWidth`), so the packing budget is `availableWidth - style.rowLabelWidth`.

The grand-total leaf is the column-axis node with `isTotal: true` at depth 0 — the aggregator emits it when the outermost column group has `showTotal: true`.

- [ ] **Step 1: Write the failing test.**

Create `test/rendering/crosstab/crosstab_slicing_test.dart`. Build matrices by hand (Task 6's types make this cheap — no aggregation needed):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_measure.dart';
import 'package:jet_print/src/domain/crosstab/crosstab_style.dart';
import 'package:jet_print/src/domain/diagnostic.dart';
import 'package:jet_print/src/domain/report_variable.dart' show JetCalculation;
import 'package:jet_print/src/expression/value.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_matrix.dart';
import 'package:jet_print/src/rendering/crosstab/crosstab_planner.dart';

CrosstabAxisNode _leaf(String k, {bool isTotal = false}) => CrosstabAxisNode(
      key: JetString(k),
      pathKey: k,
      label: k,
      depth: 0,
      isTotal: isTotal,
    );

CrosstabMeasure _m(String id) => CrosstabMeasure(
      id: id,
      name: id,
      expression: r'$F{amount}',
      aggregate: JetCalculation.sum,
    );

CrosstabMatrix _matrix(List<CrosstabAxisNode> columnAxis, int measureCount) =>
    CrosstabMatrix(
      rowAxis: <CrosstabAxisNode>[_leaf('North')],
      columnAxis: columnAxis,
      measures: <CrosstabMeasure>[
        for (int i = 0; i < measureCount; i++) _m('m$i'),
      ],
      cells: const <CrosstabCellKey, JetValue>{},
    );

void main() {
  const CrosstabStyle style =
      CrosstabStyle(rowLabelWidth: 100, measureColumnWidth: 50);

  group('sliceColumns', () {
    test('everything in one slice when it fits', () {
      final List<Diagnostic> diags = <Diagnostic>[];
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Q1'), _leaf('Q2')], 1),
        style,
        availableWidth: 400,
        diagnostics: diags,
      );
      expect(slices, hasLength(1));
      expect(slices.single.columns, hasLength(2));
      expect(diags, isEmpty);
    });

    test('overflowing leaves move to a second slice', () {
      // budget = 300 - 100 = 200 -> four 50pt columns fit, the fifth does not.
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[
          for (int i = 0; i < 6; i++) _leaf('Q$i'),
        ], 1),
        style,
        availableWidth: 300,
        diagnostics: <Diagnostic>[],
      );
      expect(slices.map((CrosstabSlice s) => s.columns.length), <int>[4, 2]);
      expect(slices[1].index, 1);
    });

    test('a leaf group is never split across slices', () {
      // 2 measures -> a leaf is 100pt wide; budget 250 fits two leaves, and the
      // third must move rather than leaving one measure behind.
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Q1'), _leaf('Q2'), _leaf('Q3')], 2),
        style,
        availableWidth: 350,
        diagnostics: <Diagnostic>[],
      );
      expect(slices.map((CrosstabSlice s) => s.columns.length), <int>[4, 2]);
      for (final CrosstabSlice s in slices) {
        expect(s.columns.length.isEven, isTrue,
            reason: 'each leaf contributes both of its measures');
      }
    });

    test('the grand total keeps its width in the final slice', () {
      // 5 data leaves + a grand total, budget 200 = four 50pt columns per slice.
      // Without reservation the total would start a sixth-column slice alone.
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[
          for (int i = 0; i < 5; i++) _leaf('Q$i'),
          _leaf('Total', isTotal: true),
        ], 1),
        style,
        availableWidth: 300,
        diagnostics: <Diagnostic>[],
      );
      expect(slices.last.columns.last.leaf.isTotal, isTrue);
      expect(slices.last.columns, hasLength(greaterThan(1)),
          reason: 'the total must not be alone on a continuation page');
    });

    test('a single leaf wider than the page still prints, with a diagnostic', () {
      final List<Diagnostic> diags = <Diagnostic>[];
      final List<CrosstabSlice> slices = sliceColumns(
        _matrix(<CrosstabAxisNode>[_leaf('Q1')], 4), // 200pt of measures
        const CrosstabStyle(rowLabelWidth: 100, measureColumnWidth: 50),
        availableWidth: 180, // budget 80 — not even one measure fits
        diagnostics: diags,
      );
      expect(slices.single.columns, hasLength(4));
      expect(diags.map((Diagnostic d) => d.message),
          anyElement(contains('wider than')));
    });
  });
}
```

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_slicing_test.dart`
Expected: FAIL — `crosstab_planner.dart` does not exist.

- [ ] **Step 3: Implement `sliceColumns` in `crosstab_planner.dart`.**

Algorithm:

1. `leaves = leavesOf(m.columnAxis)`; split off a trailing `isTotal` leaf at depth 0 as `grandTotalLeaf` (may be null).
2. `leafWidth = m.measures.length * style.measureColumnWidth`.
3. `budget = availableWidth - style.rowLabelWidth`.
4. Pack data leaves greedily. Before appending a leaf, compute the width still needed: `leafWidth`, plus `grandTotalLeafWidth` when this is the **last** data leaf and a grand total exists. If it does not fit and the current slice is non-empty, start a new slice.
5. Append the grand-total leaf to the final slice; if it does not fit even there, give it its own slice and add a `Diagnostic.warning`.
6. If `leafWidth > budget`, emit one warning per crosstab (`'crosstab column group is wider than the page body'`) and place the leaf anyway — never drop data.

Each `CrosstabColumn` gets `width: style.measureColumnWidth`; a measure's own width override is out of scope for Spec A.

- [ ] **Step 4: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_slicing_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib packages/jet_print/test
git commit -m "feat(rendering): crosstab horizontal slicing"
```

---

## Task 9: The planner — matrix to bands

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/crosstab/crosstab_planner.dart` (add band emission)
- Test: `packages/jet_print/test/rendering/crosstab/crosstab_planner_test.dart`

**Interfaces:**
- Consumes: `sliceColumns` (Task 8), `CrosstabMatrix`, `Crosstab`, `FilledBand`, `GroupLevel`, `TextElement`, `ShapeElement`, `applyJetFormat`, `jetStringify`.
- Produces:
  ```dart
  class CrosstabPlan {
    final List<FilledBand> bands;
    final List<GroupLevel> syntheticGroups;
    final List<Diagnostic> diagnostics;
  }
  CrosstabPlan planCrosstab(Crosstab ct, CrosstabMatrix m,
      {required double availableWidth, Set<String> takenGroupNames = const <String>{}});
  ```

Three details that are easy to get wrong:

- **One synthetic group for the whole crosstab, not one per slice.** The layouter breaks on `startNewPage` only for the *second and later* instances of a group name (`report_layouter.dart:589-591` — `!seenStartNewPageGroup.add(name)`, so the first `add` returns true and does not break). A group per slice would have one instance each and never break, silently killing horizontal continuation. With a single group named `'<ct.id>#ct'` and `startNewPage: true`, slice 0 does not break and slices 1..N each do.
- **`GroupLevel` requires `name` and `key`.** The layouter's maps key on `name`, so the unique token goes there; `key` is a group-break expression the layouter never reads, so a stub (`"'<ct.id>'"`, a literal string expression) is safe. If `takenGroupNames` already contains the synthetic name, emit an error diagnostic — a user group of the same name would otherwise win the map.
- **A trailing zero-height `groupFooter` closes the group.** Nothing else would: an open group pops only on a lower-level header, a matching footer, or `summary`/`noData`, and crosstab rows are `detail` bands. Without the footer the column header reprints on every page of any long detail run that follows the crosstab.

Band order, per slice `s`:

1. One `groupHeader` band per column-group level (`style.headerRowHeight` tall). A header cell spans its leaves: `width = (leaves beneath it in this slice) * measureColumnWidth`, centered.
2. When `measures.length > 1`, one more `groupHeader` band of measure names.
3. Row-axis walk, depth-first, emitting `detail` bands:
   - an inner node -> a label-only row, no indent beyond its depth;
   - a leaf -> indented label (`depth * style.rowLabelIndent`) plus one cell per column in this slice;
   - on leaving a node whose group has `showTotal` -> a total row, styled with `totalText` / `totalBox`.
4. After the last slice, one zero-height `groupFooter` band.

Cell text is `jetStringify(measure.format == null ? value : applyJetFormat(value, measure.format!))` — `applyJetFormat` returns a `JetValue`, not a `String`, and `format` is nullable. A missing cell key prints an empty string. A `ShapeElement` rectangle is emitted behind a cell **only** when the resolved box style is non-null, so an unstyled crosstab emits no shapes.

Element ids: `'<ct.id>/s<slice>/r<rowIx>/c<colIx>/m<measureId>'`; row-label ids use `'<ct.id>/s<slice>/r<rowIx>/label'`; header ids `'<ct.id>/s<slice>/h<level>/c<colIx>'`.

- [ ] **Step 1: Write the failing test.**

Create `test/rendering/crosstab/crosstab_planner_test.dart` with a hand-built 2x2 matrix and assert the plan's shape:

```dart
void main() {
  group('planCrosstab', () {
    test('emits header bands, row bands, and a closing footer', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix, availableWidth: 500);
      expect(plan.bands.first.type, BandType.groupHeader);
      expect(plan.bands.last.type, BandType.groupFooter);
      expect(plan.bands.last.height, 0);
      expect(plan.bands.where((FilledBand b) => b.type == BandType.detail),
          isNotEmpty);
    });

    test('exactly one synthetic group, with reprint and startNewPage', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix, availableWidth: 500);
      expect(plan.syntheticGroups, hasLength(1));
      final GroupLevel g = plan.syntheticGroups.single;
      expect(g.name, 'ct1#ct');
      expect(g.reprintHeaderOnEachPage, isTrue);
      expect(g.startNewPage, isTrue);
      expect(plan.bands
          .where((FilledBand b) => b.group != null)
          .every((FilledBand b) => b.group == 'ct1#ct'), isTrue);
    });

    test('a colliding user group name is an error diagnostic', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix,
          availableWidth: 500, takenGroupNames: <String>{'ct1#ct'});
      expect(plan.diagnostics.map((Diagnostic d) => d.message),
          anyElement(contains('group name')));
    });

    test('a header cell spans the leaves beneath it', () {
      // Year 2025 over Q1 and Q2, one measure of 50pt -> a 100pt header cell.
      final CrosstabPlan plan = planCrosstab(ct2, matrix2, availableWidth: 500);
      final FilledBand top = plan.bands.first;
      expect((top.elements.first as TextElement).bounds.width, 100);
    });

    test('a leaf row is indented by its depth', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix, availableWidth: 500);
      final FilledBand leafRow = plan.bands
          .firstWhere((FilledBand b) => b.type == BandType.detail);
      expect(leafRow.elements.first.bounds.x, greaterThan(0));
    });

    test('an empty intersection prints an empty string, not a zero', () {
      final CrosstabPlan plan = planCrosstab(ct, sparseMatrix, availableWidth: 500);
      final Iterable<String> texts = plan.bands
          .expand((FilledBand b) => b.elements)
          .whereType<TextElement>()
          .map((TextElement e) => e.text);
      expect(texts, contains(''));
      expect(texts, isNot(contains('0')));
    });

    test('an unstyled crosstab emits no shapes', () {
      final CrosstabPlan plan = planCrosstab(ct, matrix, availableWidth: 500);
      expect(
        plan.bands.expand((FilledBand b) => b.elements).whereType<ShapeElement>(),
        isEmpty,
      );
    });

    test('element ids are deterministic and slice-scoped', () {
      final CrosstabPlan a = planCrosstab(ct, matrix, availableWidth: 500);
      final CrosstabPlan b = planCrosstab(ct, matrix, availableWidth: 500);
      List<String> ids(CrosstabPlan p) => <String>[
            for (final FilledBand band in p.bands)
              for (final ReportElement e in band.elements) e.id,
          ];
      expect(ids(a), equals(ids(b)));
      expect(ids(a), anyElement(startsWith('ct1/s0/')));
    });

    test('a narrow page produces slice-1 bands after slice-0 bands', () {
      final CrosstabPlan plan = planCrosstab(ct, wideMatrix, availableWidth: 220);
      final List<String> ids = <String>[
        for (final FilledBand band in plan.bands)
          for (final ReportElement e in band.elements) e.id,
      ];
      expect(ids.where((String i) => i.contains('/s1/')), isNotEmpty);
      expect(ids.indexWhere((String i) => i.contains('/s1/')),
          greaterThan(ids.lastIndexWhere((String i) => i.contains('/s0/')) - 1));
    });
  });
}
```

The fixtures, at the top of the file:

```dart
CrosstabAxisNode _n(String k,
        {int depth = 0,
        List<CrosstabAxisNode> children = const <CrosstabAxisNode>[],
        bool isTotal = false}) =>
    CrosstabAxisNode(
      key: JetString(k),
      pathKey: k,
      label: k,
      depth: depth,
      children: children,
      isTotal: isTotal,
    );

const CrosstabMeasure _amount = CrosstabMeasure(
  id: 'm/a',
  name: 'Amount',
  expression: r'$F{amount}',
  aggregate: JetCalculation.sum,
);

const CrosstabGroup _gRow =
    CrosstabGroup(id: 'g/r', name: 'Region', expression: r'$F{region}');
const CrosstabGroup _gCol =
    CrosstabGroup(id: 'g/c', name: 'Quarter', expression: r'$F{quarter}');

/// A single-level crosstab, 50pt columns, 100pt row labels.
const Crosstab ct = Crosstab(
  id: 'ct1',
  rowGroups: <CrosstabGroup>[_gRow],
  columnGroups: <CrosstabGroup>[_gCol],
  measures: <CrosstabMeasure>[_amount],
  style: CrosstabStyle(rowLabelWidth: 100, measureColumnWidth: 50),
);

/// North/South x Q1/Q2, fully populated.
final CrosstabMatrix matrix = CrosstabMatrix(
  rowAxis: <CrosstabAxisNode>[_n('North'), _n('South')],
  columnAxis: <CrosstabAxisNode>[_n('Q1'), _n('Q2')],
  measures: const <CrosstabMeasure>[_amount],
  cells: <CrosstabCellKey, JetValue>{
    const CrosstabCellKey(<String>['North'], <String>['Q1'], 'm/a'):
        const JetNumber(120),
    const CrosstabCellKey(<String>['North'], <String>['Q2'], 'm/a'):
        const JetNumber(140),
    const CrosstabCellKey(<String>['South'], <String>['Q1'], 'm/a'):
        const JetNumber(80),
    const CrosstabCellKey(<String>['South'], <String>['Q2'], 'm/a'):
        const JetNumber(110),
  },
);

/// Two column levels: 2025 over Q1/Q2 — for the header-span assertion.
final Crosstab ct2 = ct.copyWith(columnGroups: <CrosstabGroup>[
  const CrosstabGroup(id: 'g/y', name: 'Year', expression: r'$F{year}'),
  _gCol,
]);
final CrosstabMatrix matrix2 = CrosstabMatrix(
  rowAxis: <CrosstabAxisNode>[_n('North')],
  columnAxis: <CrosstabAxisNode>[
    _n('2025', children: <CrosstabAxisNode>[
      _n('Q1', depth: 1),
      _n('Q2', depth: 1),
    ]),
  ],
  measures: const <CrosstabMeasure>[_amount],
  cells: <CrosstabCellKey, JetValue>{
    const CrosstabCellKey(<String>['North'], <String>['2025', 'Q1'], 'm/a'):
        const JetNumber(120),
  },
);

/// South x Q2 is missing — the empty-cell case.
final CrosstabMatrix sparseMatrix = CrosstabMatrix(
  rowAxis: matrix.rowAxis,
  columnAxis: matrix.columnAxis,
  measures: const <CrosstabMeasure>[_amount],
  cells: <CrosstabCellKey, JetValue>{
    const CrosstabCellKey(<String>['South'], <String>['Q1'], 'm/a'):
        const JetNumber(80),
  },
);

/// Eight columns — forces a second slice at a 220pt page width.
final CrosstabMatrix wideMatrix = CrosstabMatrix(
  rowAxis: <CrosstabAxisNode>[_n('North')],
  columnAxis: <CrosstabAxisNode>[for (int i = 0; i < 8; i++) _n('Q$i')],
  measures: const <CrosstabMeasure>[_amount],
  cells: <CrosstabCellKey, JetValue>{
    for (int i = 0; i < 8; i++)
      CrosstabCellKey(const <String>['North'], <String>['Q$i'], 'm/a'):
          JetNumber(i.toDouble()),
  },
);
```

Note the refined signature: the planner takes the **`Crosstab`** as well as the matrix (it needs
`ct.id` for element ids and the synthetic group name, and `ct.style` for metrics). The design
document sketches it as `planCrosstab(matrix, style, ...)`; this plan's signature supersedes it.

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_planner_test.dart`
Expected: FAIL — `planCrosstab` is undefined.

- [ ] **Step 3: Implement `planCrosstab`.**

Follow the band order above. Construct the synthetic group as:

```dart
  final String groupName = '${ct.id}#ct';
  final GroupLevel synthetic = GroupLevel(
    id: groupName,
    name: groupName,
    key: "'${ct.id}'", // a literal expression; the layouter never evaluates it
    reprintHeaderOnEachPage: true,
    startNewPage: true,
  );
```

Every header band is `FilledBand(type: BandType.groupHeader, height: style.headerRowHeight, elements: ..., variables: const {}, group: groupName)`; the closing band is `FilledBand(type: BandType.groupFooter, height: 0, elements: const [], variables: const {}, group: groupName)`. Row and total bands are `BandType.detail` with `group: null`.

- [ ] **Step 4: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_planner_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib packages/jet_print/test
git commit -m "feat(rendering): crosstab planner emits bands and one synthetic group"
```

---

## Task 10: Layout — synthetic groups in the layouter's group table

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/filled_report.dart` (add `syntheticGroups`)
- Modify: `packages/jet_print/lib/src/rendering/layout/report_layouter.dart:510-529` (group-table union + diagnostic exemption)
- Test: `packages/jet_print/test/rendering/crosstab/crosstab_layout_test.dart`

**Interfaces:**
- Consumes: `CrosstabPlan` (Task 9).
- Produces: `FilledReport({..., List<GroupLevel> syntheticGroups = const <GroupLevel>[]})` exposing `final List<GroupLevel> syntheticGroups` (unmodifiable). The layouter reads it; nothing else does.

Context — the layouter builds `levelOf` and `groupByName` from `def.body.root.groups` alone (`:510-516`), and a band whose `group` is not in `levelOf` is treated as a non-group band (`:637-639`) — no crash, but no reprint and no page break either. Appending the synthetic groups **after** the definition's groups makes them the innermost levels, so they nest correctly inside any open master group.

One exemption: the "sets keepTogether/reprintHeaderOnEachPage but has no header" info diagnostic (`:518-529`) inspects `GroupLevel.header`, which a synthetic group does not have — its header bands live in the stream. Skip synthetic groups in that loop.

`syntheticGroups` must be excluded from `FilledReport`'s `==` / `hashCode` for the same reason `fields` is: equal definitions over equal data imply equal synthetic groups, so including them would only churn fill-snapshot goldens.

- [ ] **Step 1: Write the failing test.**

Create `test/rendering/crosstab/crosstab_layout_test.dart`. Build a `FilledReport` by hand from a `CrosstabPlan` (no filler needed yet) and lay it out:

```dart
void main() {
  group('crosstab pagination', () {
    test('the column header reprints on every page of a long crosstab', () {
      // A crosstab with enough rows to fill two pages.
      final LayoutResult r = _layout(_planWithRows(120));
      expect(r.pages, hasLength(greaterThan(1)));
      for (final PageFrame page in r.pages) {
        expect(_texts(page), contains('Q1'),
            reason: 'every page repeats the column header');
      }
    });

    test('slice 1 starts on a new page', () {
      // Narrow page -> two slices. Slice 0 fits on page 1 with room to spare;
      // slice 1 must still begin on page 2, from startNewPage.
      final LayoutResult r = _layout(_planWithSlices(availableWidth: 220));
      final int firstPageWithSlice1 =
          r.pages.indexWhere((PageFrame p) => _ids(p).any((String i) => i.contains('/s1/')));
      final int lastPageWithSlice0 =
          r.pages.lastIndexWhere((PageFrame p) => _ids(p).any((String i) => i.contains('/s0/')));
      expect(firstPageWithSlice1, greaterThan(lastPageWithSlice0));
    });

    test('the closing footer stops the reprint for later detail bands', () {
      // crosstab, then 200 plain detail bands. The crosstab header must not
      // appear on the pages those detail bands occupy.
      final LayoutResult r = _layout(_planThenDetailRun(200));
      final PageFrame last = r.pages.last;
      expect(_texts(last), isNot(contains('Q1')));
    });

    test('a synthetic group raises no "reprint but no header" info', () {
      final LayoutResult r = _layout(_planWithRows(10));
      expect(
        r.diagnostics.map((Diagnostic d) => d.message),
        isNot(anyElement(contains('reprintHeaderOnEachPage'))),
      );
    });
  });
}
```

The helpers:

```dart
/// Lays out a plan as if the filler had produced it, with no definition groups.
LayoutResult _layout(CrosstabPlan plan, {double pageWidth = 595}) {
  final ReportDefinition def = ReportDefinition(
    name: 'R',
    page: PageFormat.a4Portrait.copyWith(width: pageWidth),
    body: const ReportBody(root: DetailScope(id: 'root')),
  );
  final FilledReport filled = FilledReport(
    page: def.page,
    bands: plan.bands,
    syntheticGroups: plan.syntheticGroups,
  );
  return ReportLayouter().layoutDefinition(def, filled);
}

/// Every string drawn on [page].
Iterable<String> _texts(PageFrame page) => page.primitives
    .whereType<TextPrimitive>()
    .map((TextPrimitive p) => p.text);
```

`_ids(page)` is only needed if `PageFrame` primitives carry element ids; check
`frame/primitive.dart` first. If they do not, assert slice separation through the drawn text
instead — give slice 1 a distinguishable column label in the fixture (`'Q7'`) and check which page
it lands on. Do not add an id to the primitive model just for the test.

`_planWithRows(n)`, `_planWithSlices({availableWidth})` and `_planThenDetailRun(n)` build a matrix
of the requested size with the Task 6 constructors, call `planCrosstab`, and — for
`_planThenDetailRun` — append `n` plain `FilledBand(type: BandType.detail, height: 14, elements: ..., variables: const {})`
entries after the plan's bands. Reuse the fixture helpers from the Task 9 test file rather than
writing new ones; if that means extracting them into
`test/rendering/crosstab/crosstab_fixtures.dart`, do that as the first step of this task.

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_layout_test.dart`
Expected: FAIL — `FilledReport` has no `syntheticGroups` parameter.

- [ ] **Step 3: Add `syntheticGroups` to `FilledReport`.**

```dart
  FilledReport({
    required this.page,
    required List<FilledBand> bands,
    Map<String, JetValue> params = const <String, JetValue>{},
    List<GroupLevel> syntheticGroups = const <GroupLevel>[],
  })  : bands = List<FilledBand>.unmodifiable(bands),
        params = Map<String, JetValue>.unmodifiable(params),
        syntheticGroups = List<GroupLevel>.unmodifiable(syntheticGroups);

  /// Group levels contributed by planner-built band runs (crosstabs), appended
  /// to the definition's own groups when the layouter builds its group table.
  /// Excluded from `==`/`hashCode` for the same reason as [FilledBand.fields]:
  /// equal designs over equal data imply equal synthetic groups, so including
  /// them would only churn fill-snapshot goldens.
  final List<GroupLevel> syntheticGroups;
```

Leave `==` and `hashCode` untouched.

- [ ] **Step 4: Union the groups in the layouter.**

At `report_layouter.dart:510-516`:

```dart
    // Group lookup keyed by display name (FilledBand.group carries the name).
    // Synthetic groups (crosstabs) are appended last, so they become the
    // innermost levels and nest inside any open master group.
    final List<GroupLevel> definitionGroups = def.body.root.groups;
    final List<GroupLevel> groups = <GroupLevel>[
      ...definitionGroups,
      ...filled.syntheticGroups,
    ];
```

`levelOf` and `groupByName` keep their existing bodies over the new `groups` list.

- [ ] **Step 5: Exempt synthetic groups from the header-less info diagnostic.**

At `:522-529`, iterate `definitionGroups` instead of `groups`, with a comment: `// Synthetic groups carry their header bands in the stream, not in the model.`

- [ ] **Step 6: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_layout_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 7: Run the whole rendering suite, goldens included.**

Run: `cd packages/jet_print && flutter test test/rendering test/goldens`
Expected: PASS with **zero golden changes**. `syntheticGroups` defaults to empty, so no existing report can reach the new code path. A golden move here means the group union changed behaviour for definition groups — stop and investigate.

- [ ] **Step 8: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib packages/jet_print/test
git commit -m "feat(rendering): layouter honours planner-built synthetic groups"
```

---

## Task 11: Fill — register, fold, splice

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test: `packages/jet_print/test/rendering/crosstab/crosstab_fill_test.dart`

**Interfaces:**
- Consumes: `CrosstabAggregation` (Task 7), `planCrosstab` (Task 9), `FilledReport.syntheticGroups` (Task 10), `coerceCollectionRows`.
- Produces: no new public API. `fillReport` now emits crosstab bands and populates `syntheticGroups`.

Context — this is the task the design was rewritten for. **The obvious approach does not work:** `emitNode` runs per row (`emitDetail(row)` at `:579` calls `emitNode(node, row)` at `:520`; nested scopes recurse per child row at `:458-461`), and master rows arrive from a forward-only cursor (`DataSet.moveNext()` / `current`) with no rewind and no materialized list. An `emitNode` arm would emit the whole crosstab once per row, and there is no row pool to read.

**A crosstab needs a fold, not rows.** So:

1. **Register** before the row loop. Walk `def.body.root.children`; for each `CrosstabNode`, create a `CrosstabAggregation` and classify it: *before-loop* if it precedes every `BandNode` / `NestedScope` sibling, otherwise *after-loop*. A before-loop crosstab records `reservedIndex = bands.length` — the position its bands will occupy. In a body with no row-producing sibling at all, every crosstab is before-loop and they keep their `children` order. Skip any crosstab whose `visible` resolves false (evaluated with `row: null` — params and report variables only); a skipped crosstab folds nothing and contributes no group.
2. **Fold** inside the existing master-row walk, right after `calc.advance(row, ...)`. For each registered crosstab: `agg.fold(row)` when `collectionField` is null, otherwise `agg.fold(childRow)` for each row from `coerceCollectionRows(row.field(collectionField), ...)`. No row is retained.
3. **Plan and splice** after the loop. For each crosstab in registration order call `planCrosstab(ct, agg.build(), availableWidth: page width minus horizontal margins, takenGroupNames: {for (final g in def.body.root.groups) g.name})`. Append after-loop bands at the current end; insert before-loop bands at `reservedIndex`, adjusting later reserved indices by the number inserted. Collect every plan's `syntheticGroups` into the `FilledReport`, and route plan and matrix `Diagnostic`s into the filler's diagnostic sink.

The `emitNode` arm stays the no-op from Task 3.

- [ ] **Step 1: Write the failing test.**

Create `test/rendering/crosstab/crosstab_fill_test.dart`:

```dart
void main() {
  group('crosstab fill', () {
    test('a crosstab after the detail band prints once, after every row', () {
      final FilledReport r = _fill(_defWithCrosstab(after: true), _rows4());
      final List<BandType> types =
          r.bands.map((FilledBand b) => b.type).toList();
      expect(types.where((BandType t) => t == BandType.detail).length,
          greaterThan(4), reason: '4 data rows plus the crosstab rows');
      expect(types.indexOf(BandType.groupHeader),
          greaterThan(types.indexOf(BandType.detail)));
      expect(types.where((BandType t) => t == BandType.groupFooter), hasLength(1));
    });

    test('a crosstab before the detail band prints once, before every row', () {
      final FilledReport r = _fill(_defWithCrosstab(after: false), _rows4());
      final List<BandType> types =
          r.bands.map((FilledBand b) => b.type).toList();
      expect(types.first, BandType.groupHeader,
          reason: 'the crosstab header opens the body');
    });

    test('a crosstab-only body still prints the crosstab once', () {
      final FilledReport r = _fill(_crosstabOnlyDef(), _rows4());
      expect(r.bands.where((FilledBand b) => b.type == BandType.groupFooter),
          hasLength(1));
    });

    test('the synthetic group reaches the FilledReport', () {
      final FilledReport r = _fill(_defWithCrosstab(after: true), _rows4());
      expect(r.syntheticGroups.map((GroupLevel g) => g.name), <String>['ct1#ct']);
    });

    test('visible: false skips the crosstab entirely', () {
      final FilledReport r = _fill(_defWithCrosstab(after: true, visible: false), _rows4());
      expect(r.bands.where((FilledBand b) => b.group != null), isEmpty);
      expect(r.syntheticGroups, isEmpty);
    });

    test('collectionField pools a nested collection across master rows', () {
      // Two master rows, each with two line items; the crosstab folds all four.
      final FilledReport r = _fill(_defWithNestedCrosstab(), _rowsWithLines());
      expect(_cellTexts(r), contains('400')); // 100+100+100+100
    });

    test('folding retains no rows: a 20k-row source fills without buffering', () {
      // Guards the design decision. If this ever needs to materialize rows it
      // will show up as a memory spike, not a failure — keep the row count high
      // enough to be meaningful but fast.
      final FilledReport r = _fill(_defWithCrosstab(after: true), _rowsN(20000));
      expect(r.bands, isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_fill_test.dart`
Expected: FAIL — no crosstab bands are emitted; `syntheticGroups` is empty.

- [ ] **Step 3: Implement registration and classification.**

Add a small private class near the top of `fillReport`:

```dart
  final class _RegisteredCrosstab {
    _RegisteredCrosstab(this.crosstab, this.aggregation, this.reservedIndex);
    final Crosstab crosstab;
    final CrosstabAggregation aggregation;
    /// The band index a before-loop crosstab's bands are inserted at, or null
    /// for an after-loop crosstab (appended at the end).
    final int? reservedIndex;
  }
```

Build the list before the row loop by walking `definition.body.root.children` once, tracking whether a row-producing node has been seen.

- [ ] **Step 4: Fold during the row walk.**

Inside `while (ds.moveNext())`, after `calc.advance(row, params: params)`, add the fold loop described above. Use the filler's existing `childRowsOf` helper when `collectionField` is set, so schema inference and malformed-entry diagnostics stay on the shared seam.

- [ ] **Step 5: Plan and splice after the loop.**

After the row loop and its group-footer flush, before the summary band, build each plan and splice. Insert before-loop plans in registration order, shifting subsequent reserved indices by the number of bands inserted.

- [ ] **Step 6: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/rendering/crosstab/crosstab_fill_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 7: Full suite, goldens included.**

Run: `cd packages/jet_print && flutter test`
Expected: PASS with **zero golden changes**. No existing definition contains a `CrosstabNode`, so the registration walk must find nothing and the loop must behave exactly as before.

- [ ] **Step 8: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib packages/jet_print/test
git commit -m "feat(rendering): fill folds crosstabs during the row walk and splices their bands"
```

---

## Task 12: Public API, playground demo, and the end-to-end golden

**Files:**
- Modify: `packages/jet_print/lib/jet_print.dart` (barrel export)
- Modify: `packages/jet_print/test/public_api_test.dart`
- Create: `apps/jet_print_playground/lib/pivot_sample.dart`
- Create: `apps/jet_print_playground/lib/rendered_pivot_example.dart`
- Modify: `apps/jet_print_playground/lib/demo_nav_list.dart`, `apps/jet_print_playground/lib/main.dart`
- Create: `packages/jet_print/test/goldens/pivot_test.dart`
- Test: golden PNG under `packages/jet_print/test/goldens/`

**Interfaces:**
- Consumes: everything from Tasks 2-11.
- Produces: `Crosstab`, `CrosstabGroup`, `CrosstabMeasure`, `CrosstabStyle`, `CrosstabSort`, `CrosstabNode`, `UnknownScopeNode` on the public surface.

Context — the playground samples follow a pair convention: `<name>_sample.dart` builds the `ReportDefinition` plus its data, and `rendered_<name>_example.dart` renders it. Copy the closest existing pair (`sales_chart_sample.dart` / `rendered_sales_chart_example.dart`) rather than inventing a shape.

The sample should exercise the parts that would otherwise only be unit-tested: two row levels with subtotals, two column levels, two measures, and enough columns that a narrow page produces a second slice.

- [ ] **Step 1: Export the new types from the barrel.**

Add to `lib/jet_print.dart`:

```dart
export 'src/domain/crosstab/crosstab.dart';
export 'src/domain/crosstab/crosstab_group.dart';
export 'src/domain/crosstab/crosstab_measure.dart';
export 'src/domain/crosstab/crosstab_style.dart';
export 'src/domain/unknown_scope_node.dart';
```

`CrosstabNode` rides the existing `detail_scope.dart` export.

- [ ] **Step 2: Extend `public_api_test.dart` and run it.**

Add the new type names to whatever list that test asserts over, following its existing style.

Run: `cd packages/jet_print && flutter test test/public_api_test.dart`
Expected: PASS. Also confirms the barrel does not leak `src/` internals — `CrosstabMatrix`, `CrosstabPlan` and the aggregator stay internal.

- [ ] **Step 3: Write the playground sample.**

Create `apps/jet_print_playground/lib/pivot_sample.dart` with a `pivotDefinition()` returning a `ReportDefinition` whose root scope holds a title band and a `CrosstabNode`, plus a `pivotData()` returning rows shaped `{region, city, year, quarter, qty, amount}`. Region over City on the row axis (both with `showTotal: true`), Year over Quarter on the column axis, and two measures — `Qty` (`count` or `sum` of `$F{qty}`) and `Amount` (`sum` of `$F{qty} * $F{price}`, format `#,##0.00`).

- [ ] **Step 4: Wire it into the demo navigation.**

Create `rendered_pivot_example.dart` mirroring `rendered_sales_chart_example.dart`, then add the entry to `demo_nav_list.dart` and `main.dart` exactly as the chart demo is registered.

- [ ] **Step 5: Run the playground's own tests.**

Run: `cd apps/jet_print_playground && flutter test`
Expected: PASS. The nav-list test asserts the demo set — update its expected list to include the new demo.

- [ ] **Step 6: Write the golden test.**

Create `packages/jet_print/test/goldens/pivot_test.dart` following `label_sheet_test.dart`: render page 1 of the pivot definition and compare against `pivot_light.png`. Add a second expectation that renders at a narrow page width and asserts the layout produced more than one page, so the horizontal-continuation path is covered by the golden suite rather than only by unit tests.

- [ ] **Step 7: Generate the golden, then verify it.**

```bash
cd packages/jet_print && flutter test test/goldens/pivot_test.dart --update-goldens
```
Open the produced PNG and check it by eye: subtotal rows present, column headers spanning their leaves, numbers right-aligned, no clipped labels.

Then run without the flag:
```bash
cd packages/jet_print && flutter test test/goldens/pivot_test.dart
```
Expected: PASS.

- [ ] **Step 8: Full sweep across both packages.**

```bash
cd packages/jet_print && flutter test
cd ../../apps/jet_print_playground && flutter test
```
Expected: PASS in both, with **no pre-existing golden changed** — only the new `pivot_*.png` files are added.

- [ ] **Step 9: Analyze, format, commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart format lib test && dart analyze
cd ../../apps/jet_print_playground && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print apps/jet_print_playground
git commit -m "feat(jet_print): export crosstab API; add pivot playground demo and goldens"
```

---

## Task 13: Designer read-only surface

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/outline_panel/rows.dart`
- Modify: `packages/jet_print/lib/src/designer/canvas/design_time_layout.dart`
- Modify: `packages/jet_print/lib/src/designer/l10n/*.arb` and the generated localizations
- Test: `packages/jet_print/test/designer/crosstab_outline_test.dart`

**Interfaces:**
- Consumes: `CrosstabNode`, `Crosstab`.
- Produces: no API change. The designer *shows* a crosstab; authoring is Spec B.

Context — the spec's fallout table promises the designer gives a crosstab a minimum representation
in Spec A: a read-only Outline row and a placeholder block on the canvas. Without this a report
containing a crosstab opens in the designer with the crosstab **invisible**, which reads as data
loss even though the file is intact.

Scope discipline: no selection handles, no Properties inspector, no drag, no delete. A row and a
block, nothing more.

- [ ] **Step 1: Write the failing test.**

```dart
void main() {
  testWidgets('a crosstab appears as a read-only outline row', (WidgetTester t) async {
    await t.pumpWidget(_designerWith(_defWithCrosstab()));
    await t.pumpAndSettle();
    expect(find.text('Sales pivot'), findsOneWidget); // its name
  });

  testWidgets('a nameless crosstab falls back to the localized label',
      (WidgetTester t) async {
    await t.pumpWidget(_designerWith(_defWithCrosstab(name: null)));
    await t.pumpAndSettle();
    expect(find.text('Crosstab'), findsOneWidget);
  });

  testWidgets('the canvas reserves a block for the crosstab', (WidgetTester t) async {
    await t.pumpWidget(_designerWith(_defWithCrosstab()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('crosstab-placeholder-ct1')),
        findsOneWidget);
  });
}
```

Scope the finders to the Outline panel the way the existing outline tests do — check
`test/designer/` for the established helper before writing `_designerWith`.

- [ ] **Step 2: Run it to confirm it fails.**

Run: `cd packages/jet_print && flutter test test/designer/crosstab_outline_test.dart`
Expected: FAIL — the crosstab does not appear anywhere.

- [ ] **Step 3: Add the l10n key.**

Add `crosstabLabel` (`"Crosstab"`) to the English ARB, then to the German and Turkish ARBs
(`Kreuztabelle`, `Çapraz tablo`), and regenerate. Follow the repo's existing l10n workflow — every
key must exist in **all** ARBs, not only in the generated Dart.

- [ ] **Step 4: Add the Outline row.**

In `outline_panel/rows.dart`, give `CrosstabNode` a row that shows `crosstab.name` when non-blank,
otherwise the localized label, with a distinct glyph. It has no children and no context actions.

- [ ] **Step 5: Add the canvas placeholder.**

In `design_time_layout.dart`, lay out a `CrosstabNode` as a fixed-height block
(`style.headerRowHeight * columnGroups.length + style.rowHeight * 3` is a reasonable stand-in)
keyed `ValueKey('crosstab-placeholder-<id>')`, drawn as an outlined rectangle with the crosstab's
label. It is not selectable and not hit-testable in Spec A.

- [ ] **Step 6: Run the test — it must pass.**

Run: `cd packages/jet_print && flutter test test/designer/crosstab_outline_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 7: Run the designer suite and the goldens.**

Run: `cd packages/jet_print && flutter test test/designer test/goldens`
Expected: PASS with zero golden changes — no existing definition contains a crosstab, so no canvas
golden can reach the new branch. If one moves, the placeholder is being laid out for non-crosstab
nodes too.

- [ ] **Step 8: Analyze, format, commit.**

```bash
cd packages/jet_print && dart format lib test && dart analyze
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib packages/jet_print/test
git commit -m "feat(designer): read-only outline row and canvas placeholder for crosstabs"
```

---

## Acceptance check (after Task 13)

Walk the spec's success criteria and confirm each has a passing test:

- **SC-001** — the pivot golden renders; the playground demo previews and exports.
- **SC-002** — Task 7 covers `sum` and `average`; add the remaining folding calculations (`count`, `min`, `max`, `first`, `last`) to the aggregator test if they are not yet asserted. `none` is rejected by Task 5.
- **SC-003** — Task 10, "the column header reprints on every page".
- **SC-004** — Task 10, "slice 1 starts on a new page"; Task 8 covers the grand-total reservation.
- **SC-005** — Task 7, "an empty intersection has no entry"; Task 9, "prints an empty string, not a zero".
- **SC-006** — every task's full-suite step.
- **SC-007** — Task 4, "an unknown scope-node kind round-trips instead of throwing".
- **SC-008** — Task 11, the 20k-row fill test.

Also confirm the designer promise from the spec's fallout table: opening a crosstab report in the
designer shows it (Task 13) rather than silently omitting it.

Any criterion without a test is a missing task — add it before declaring the plan done.
