# Multi-Column Label Sheets — Designer UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a designer author the band-level `ColumnLayout` on the detail band — add/edit/remove with a gated affordance, validation feedback, and a canvas grid cue — with no engine, serialization, or `validate()` change.

**Architecture:** Four isolated units on the existing designer pipeline. (1) Two `EditCommand`s + controller methods set/clear `Band.columnLayout` through the unchanged `_commit`/undo pipeline. (2) A "Column Layout" section in the Properties band inspector renders three states (add / edit+remove / disabled-add) gated on `ReportDefinition.isPureSingleDetailBody`. (3) The section surfaces `controller.diagnostics` (the existing `validate()` output) filtered to the active band, rendered verbatim, plus a localized inactive notice. (4) A pure `labelGridCue` geometry helper + a `_LabelGridPainter` overlay the cell boundary and read-only ghost columns on the canvas; element emission and drag bounds are untouched.

**Tech Stack:** Dart/Flutter, `shadcn_ui` (ShadButton/ShadTooltip/ShadInput), `flutter_gen-l10n` (ARB → `JetPrintLocalizations`), `flutter_test` widget + unit tests. Tests and `flutter analyze` run from `packages/jet_print`; git runs from the repo root `/Users/ahmeturel/Projects/oss/jet-print`.

## Global Constraints

- **Designer-only.** No change to `lib/src/domain/**` (except none), `lib/src/rendering/**`, serialization, or `validate()`. The grid math, the `isPureSingleDetailBody` gate predicate, and the spec-034 diagnostic set are reused exactly as shipped.
- **Single source of truth for eligibility:** the UI and validator both read `ReportDefinition.isPureSingleDetailBody` / `soleDetailBand` — never a re-derived predicate.
- **Diagnostics render verbatim.** Localize only designer-authored chrome (section/field labels, Add tooltip, inactive notice). `validate()` message strings are shown unmodified (FR-010 decision 2026-06-18). The UI never re-implements the grid arithmetic.
- **Removal preserves all other band fields.** `Band.copyWith(columnLayout:)` cannot null a field; clearing rebuilds the `Band` via its constructor, carrying `id`/`type`/`height`/`elements` (spec-031 silent-drop guard).
- **Byte-identical goldens (Constitution IV).** Engine output is untouched; no pre-existing designer-canvas golden covers an active label band. The canvas cue is additive chrome only.
- **No `schemaVersion` change** (Constitution V) — no serialization touched.
- **Localization fallback:** `en` stays the first supported locale; new keys added to all three ARB files (`en`/`de`/`tr`) and the generated `JetPrintLocalizations` regenerated via `flutter gen-l10n`.
- **Commit-on-blur numeric editing** reuses the existing `_NumberField` widget (parses on blur/submit, reverts unparseable input, ignores sub-precision re-commits).

---

## File Structure

**Create:**
- `lib/src/designer/controller/commands/set_column_layout_command.dart` — sets `Band.columnLayout` (Task 1).
- `lib/src/designer/controller/commands/remove_column_layout_command.dart` — clears it, preserving other fields (Task 1).
- `lib/src/designer/canvas/label_grid_geometry.dart` — pure `labelGridCue` helper + `LabelGridCue` typedef (Task 4).
- `test/designer/controller/column_layout_command_test.dart` (Task 1).
- `test/designer/column_layout_section_test.dart` (Task 2, extended in Task 3).
- `test/designer/canvas/label_grid_geometry_test.dart` (Task 4).

**Modify:**
- `lib/src/designer/controller/jet_report_designer_controller.dart` — `setColumnLayout` / `removeColumnLayout` + imports (Task 1).
- `lib/src/designer/layout/panels/properties_panel.dart` — `_bandInspector` wiring, `_columnLayoutSection`, two button widgets, diagnostics filter (Tasks 2 + 3).
- `lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb` — new chrome keys (Tasks 2 + 3), then `flutter gen-l10n` regenerates `jet_print_localizations*.dart`.
- `lib/src/designer/canvas/design_canvas.dart` — `_LabelGridPainter` + a CustomPaint layer + a ghost color constant (Task 4).

---

## Task 1: Column-layout commands + controller methods

**Files:**
- Create: `packages/jet_print/lib/src/designer/controller/commands/set_column_layout_command.dart`
- Create: `packages/jet_print/lib/src/designer/controller/commands/remove_column_layout_command.dart`
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (imports near line 36; methods after `setBandHeight`/`_applyBandHeight`, ~line 631)
- Test: `packages/jet_print/test/designer/controller/column_layout_command_test.dart`

**Interfaces:**
- Consumes: `updateBand(ReportDefinition, String, Band Function(Band))` and `findBand(ReportDefinition, String)` from `band_walker.dart`; `DesignerDocument.withDefinition(ReportDefinition, {Selection selection})`; `EditCommand` base (`String get label`, `DesignerDocument apply(DesignerDocument)`); `Selection.band(String)`; `ColumnLayout` (`columnCount/columnWidth/columnSpacing/rowSpacing`, `copyWith`); `Band.copyWith({ColumnLayout? columnLayout})`.
- Produces: `class SetColumnLayoutCommand({required String bandId, required ColumnLayout layout})`; `class RemoveColumnLayoutCommand({required String bandId})`; `controller.setColumnLayout(String bandId, ColumnLayout layout)`; `controller.removeColumnLayout(String bandId)`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/controller/column_layout_command_test.dart`:

```dart
// Column-layout set/remove commands + controller methods (spec 035 / Task 1).
// Public-API controller tests (no `src/` imports), mirroring
// band_collection_command_test.dart and controller_history_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

/// A pure single-detail body: one root scope, one detail BandNode with one
/// element, no groups/footer/title/summary/noData — the eligible label shape.
ReportDefinition _pureSingleDetail() => const ReportDefinition(
      name: 'labels',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 80,
              elements: <ReportElement>[
                TextElement(
                  id: 't',
                  bounds: JetRect(x: 0, y: 0, width: 100, height: 20),
                  text: 'x',
                ),
              ],
            )),
          ],
        ),
      ),
    );

/// The sole detail band, read through the public scope tree.
Band _detail(JetReportDesignerController c) =>
    (c.definition.body.root.children.single as BandNode).band;

void main() {
  test('setColumnLayout sets the layout as one undoable step', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _pureSingleDetail());
    addTearDown(c.dispose);
    const ColumnLayout layout = ColumnLayout(
        columnCount: 2, columnWidth: 200, columnSpacing: 8, rowSpacing: 4);

    c.setColumnLayout('detail', layout);
    expect(_detail(c).columnLayout, layout);

    c.undo();
    expect(_detail(c).columnLayout, isNull);
    c.redo();
    expect(_detail(c).columnLayout, layout);
  });

  test('removeColumnLayout clears the layout, preserving id/type/height/elements',
      () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _pureSingleDetail());
    addTearDown(c.dispose);
    c.setColumnLayout('detail',
        const ColumnLayout(columnCount: 3, columnWidth: 120, columnSpacing: 0, rowSpacing: 0));

    c.removeColumnLayout('detail');

    final Band b = _detail(c);
    expect(b.columnLayout, isNull);
    expect(b.id, 'detail');
    expect(b.type, BandType.detail);
    expect(b.height, 80);
    expect(b.elements.map((ReportElement e) => e.id), <String>['t']);
  });

  test('setColumnLayout is a no-op for an unknown band id', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _pureSingleDetail());
    addTearDown(c.dispose);

    c.setColumnLayout('nope',
        const ColumnLayout(columnCount: 2, columnWidth: 200, columnSpacing: 0, rowSpacing: 0));

    expect(_detail(c).columnLayout, isNull);
    expect(c.canUndo, isFalse);
  });

  test('removeColumnLayout is a no-op when the band has no layout', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _pureSingleDetail());
    addTearDown(c.dispose);

    c.removeColumnLayout('detail');

    expect(c.canUndo, isFalse);
  });
}
```

> If `canUndo`/`undo()`/`redo()` differ from the controller's actual history API, match the names used in `test/designer/controller/controller_history_test.dart` (do not invent names).

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/controller/column_layout_command_test.dart`
Expected: FAIL — `setColumnLayout`/`removeColumnLayout` are not defined on `JetReportDesignerController`.

- [ ] **Step 3: Create the set command**

Create `packages/jet_print/lib/src/designer/controller/commands/set_column_layout_command.dart`:

```dart
/// The command that sets (or replaces) a band's multi-column label layout
/// (spec 035).
library;

import '../../../domain/band.dart';
import '../../../domain/column_layout.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Sets the [ColumnLayout] of the band with stable id [bandId].
///
/// A single-field change on the band, mirroring `SetBandHeightCommand`: the
/// controller bakes in the exact layout so redo reproduces it, and leaves the
/// band selected. A no-op for an unknown [bandId] (the band-walker transform
/// matches nothing) or a value-equal layout (the controller's commit treats an
/// unchanged definition as a no-op).
class SetColumnLayoutCommand extends EditCommand {
  /// Creates a command setting band [bandId]'s [layout].
  const SetColumnLayoutCommand({required this.bandId, required this.layout});

  /// The stable id of the band carrying the label grid.
  final String bandId;

  /// The new column layout.
  final ColumnLayout layout;

  @override
  String get label => 'Set column layout';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateBand(before.definition, bandId,
            (Band b) => b.copyWith(columnLayout: layout)),
        selection: Selection.band(bandId),
      );
}
```

- [ ] **Step 4: Create the remove command**

Create `packages/jet_print/lib/src/designer/controller/commands/remove_column_layout_command.dart`:

```dart
/// The command that clears a band's multi-column label layout (spec 035).
library;

import '../../../domain/band.dart';
import '../band_walker.dart';
import '../designer_document.dart';
import '../edit_command.dart';
import '../selection.dart';

/// Clears the column layout of band [bandId], turning a label sheet back into a
/// plain detail band.
///
/// `Band.copyWith` cannot null a field (`columnLayout ?? this.columnLayout`), so
/// removal rebuilds the band through its constructor, explicitly carrying every
/// OTHER field (id, type, height, elements) and omitting `columnLayout` — the
/// spec-031 silent-drop guard. A no-op for an unknown [bandId] or a band that
/// already has no layout (the rebuilt band is value-equal, so commit no-ops).
class RemoveColumnLayoutCommand extends EditCommand {
  /// Creates a command clearing band [bandId]'s column layout.
  const RemoveColumnLayoutCommand({required this.bandId});

  /// The stable id of the band whose layout is cleared.
  final String bandId;

  @override
  String get label => 'Remove column layout';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        updateBand(
          before.definition,
          bandId,
          (Band b) => Band(
            id: b.id,
            type: b.type,
            height: b.height,
            elements: b.elements,
          ),
        ),
        selection: Selection.band(bandId),
      );
}
```

- [ ] **Step 5: Wire the controller methods**

In `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`, add the imports alongside the other `commands/` imports (~line 36) **and** the domain `ColumnLayout` import with the other domain imports:

```dart
import 'commands/remove_column_layout_command.dart';
import 'commands/set_column_layout_command.dart';
```

```dart
import '../../domain/column_layout.dart';
```

> If `column_layout.dart` is already imported transitively, the analyzer will flag the duplicate — only add it if missing. `Band` is already imported (used by `setBandHeight`).

Then add these methods immediately after `_applyBandHeight` (~line 639):

```dart
  /// Sets band [bandId]'s multi-column label [layout] as one undoable step
  /// (spec 035). An unknown id is ignored; a value-equal layout records no
  /// history (routed through `_commit`).
  void setColumnLayout(String bandId, ColumnLayout layout) {
    if (findBand(_document.definition, bandId) == null) return;
    _commit(SetColumnLayoutCommand(bandId: bandId, layout: layout));
  }

  /// Clears band [bandId]'s column layout as one undoable step (spec 035). An
  /// unknown id — or a band that already has no layout — is ignored.
  void removeColumnLayout(String bandId) {
    final Band? band = findBand(_document.definition, bandId);
    if (band == null || band.columnLayout == null) return;
    _commit(RemoveColumnLayoutCommand(bandId: bandId));
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/controller/column_layout_command_test.dart`
Expected: PASS (4/4).

- [ ] **Step 7: Analyze**

Run: `cd packages/jet_print && flutter analyze lib/src/designer/controller test/designer/controller/column_layout_command_test.dart`
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/controller packages/jet_print/test/designer/controller/column_layout_command_test.dart
git commit -m "feat(035): column-layout set/remove commands + controller methods"
```

---

## Task 2: Properties "Column Layout" section — add / edit / remove + gating + chrome i18n

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (`_bandInspector` ~line 653; new `_columnLayoutSection` method; new `_ColumnLayoutAddButton` / `_ColumnLayoutRemoveButton` widgets near the other private widgets ~line 1085; imports)
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb`
- Test: `packages/jet_print/test/designer/column_layout_section_test.dart`

**Interfaces:**
- Consumes: `controller.setColumnLayout` / `controller.removeColumnLayout` (Task 1); `findBand`; `ReportDefinition.isPureSingleDetailBody`, `ReportDefinition.soleDetailBand`; `ColumnLayout` + `copyWith`; existing `_NumberField`, `_LabeledRow`, `_Header`, `SectionLabel` widgets; `ShadButton.outline`/`ShadButton.ghost`, `ShadButtonSize.sm`, `ShadTooltip`; the file-level `const String _p`.
- Produces: `_columnLayoutSection(controller, bandId, theme, l10n)` returning `List<Widget>`; widget keys `'$_p.field.columnLayoutAdd'`, `'$_p.field.columnLayoutRemove'`, `'$_p.field.columnCount'`, `'$_p.field.columnWidth'`, `'$_p.field.columnSpacing'`, `'$_p.field.rowSpacing'`; l10n getters `propertiesColumnLayout`, `propertiesColumnLayoutAdd`, `propertiesColumnLayoutAddDisabled`, `propertiesColumnLayoutRemove`, `propertiesColumnCount`, `propertiesColumnWidth`, `propertiesColumnSpacing`, `propertiesRowSpacing`.

- [ ] **Step 1: Add the ARB chrome keys (all three locales)**

In `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, before the closing `}`, add (keep the trailing-comma style of the file — the last existing key needs a comma added before these):

```json
  "propertiesColumnLayout": "Column Layout",
  "@propertiesColumnLayout": {
    "description": "Properties section heading for a detail band's multi-column label grid (spec 035)."
  },
  "propertiesColumnLayoutAdd": "Add column layout",
  "@propertiesColumnLayoutAdd": {
    "description": "Button: turn the selected detail band into a multi-column label sheet."
  },
  "propertiesColumnLayoutAddDisabled": "Requires a single detail band with no title, summary, groups, or footer.",
  "@propertiesColumnLayoutAddDisabled": {
    "description": "Tooltip on the disabled Add-column-layout button when the report is not a pure single-detail body."
  },
  "propertiesColumnLayoutRemove": "Remove column layout",
  "@propertiesColumnLayoutRemove": {
    "description": "Button: clear the column layout, restoring a plain detail band."
  },
  "propertiesColumnCount": "Columns",
  "@propertiesColumnCount": {
    "description": "Label for the number-of-columns field in the Column Layout section."
  },
  "propertiesColumnWidth": "Column width",
  "@propertiesColumnWidth": {
    "description": "Label for the per-column (cell) width field, in points."
  },
  "propertiesColumnSpacing": "Column spacing",
  "@propertiesColumnSpacing": {
    "description": "Label for the horizontal gutter-between-columns field, in points."
  },
  "propertiesRowSpacing": "Row spacing",
  "@propertiesRowSpacing": {
    "description": "Label for the vertical gap-between-label-rows field, in points."
  }
```

In `jet_print_de.arb`, add the same keys with German values (no `@` metadata needed in non-template ARBs):

```json
  "propertiesColumnLayout": "Spaltenlayout",
  "propertiesColumnLayoutAdd": "Spaltenlayout hinzufügen",
  "propertiesColumnLayoutAddDisabled": "Erfordert ein einzelnes Detailband ohne Titel, Zusammenfassung, Gruppen oder Fußzeile.",
  "propertiesColumnLayoutRemove": "Spaltenlayout entfernen",
  "propertiesColumnCount": "Spalten",
  "propertiesColumnWidth": "Spaltenbreite",
  "propertiesColumnSpacing": "Spaltenabstand",
  "propertiesRowSpacing": "Zeilenabstand"
```

In `jet_print_tr.arb`, add the same keys with Turkish values:

```json
  "propertiesColumnLayout": "Sütun düzeni",
  "propertiesColumnLayoutAdd": "Sütun düzeni ekle",
  "propertiesColumnLayoutAddDisabled": "Başlık, özet, grup veya alt bilgi içermeyen tek bir ayrıntı bandı gerektirir.",
  "propertiesColumnLayoutRemove": "Sütun düzenini kaldır",
  "propertiesColumnCount": "Sütunlar",
  "propertiesColumnWidth": "Sütun genişliği",
  "propertiesColumnSpacing": "Sütun aralığı",
  "propertiesRowSpacing": "Satır aralığı"
```

> Match each file's existing comma/format style; an ARB with a trailing comma before `}` or a missing comma between entries fails to parse.

- [ ] **Step 2: Regenerate localizations**

Run: `cd packages/jet_print && flutter gen-l10n`
Expected: `lib/src/designer/l10n/jet_print_localizations.dart` (+ `_en/_de/_tr`) regenerated; new abstract getters `propertiesColumnLayout` … `propertiesRowSpacing` present.

- [ ] **Step 3: Write the failing widget test**

Create `packages/jet_print/test/designer/column_layout_section_test.dart`:

```dart
// Properties "Column Layout" section: add / edit / remove + gating (spec 035 /
// Task 2). Drives the public JetReportDesigner via the shared harness.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const String _p = 'jet_print.designer.properties';
Finder _add = find.byKey(const ValueKey<String>('$_p.field.columnLayoutAdd'));
Finder _remove =
    find.byKey(const ValueKey<String>('$_p.field.columnLayoutRemove'));
Finder _field(String name) =>
    find.byKey(ValueKey<String>('$_p.field.$name'));
Finder _editable(String name) =>
    find.descendant(of: _field(name), matching: find.byType(EditableText));

Future<void> _openProperties(WidgetTester tester) async {
  final Finder tab = find.text('Properties');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Eligible: one root scope, one detail band, nothing else.
ReportDefinition _pure() => const ReportDefinition(
      name: 'labels',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );

/// Ineligible: a title once-band makes the body not pure-single-detail.
ReportDefinition _withTitle() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(id: 'title', type: BandType.title, height: 30),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );

Band _detail(JetReportDesignerController c) =>
    (c.definition.body.root.children.single as BandNode).band;

void main() {
  testWidgets('Add is enabled on a pure single-detail body and creates a default layout',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();

    expect(_add, findsOneWidget);
    await tester.tap(_add);
    await tester.pumpAndSettle();

    final ColumnLayout? layout = _detail(c).columnLayout;
    final double bodyWidth = c.definition.page.width -
        c.definition.page.margins.left -
        c.definition.page.margins.right;
    expect(layout, isNotNull);
    expect(layout!.columnCount, 2);
    expect(layout.columnWidth, bodyWidth / 2);
    expect(layout.columnSpacing, 0);
    expect(layout.rowSpacing, 0);
  });

  testWidgets('Add does nothing on an ineligible body', (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        controller: JetReportDesignerController(definition: _withTitle()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();

    expect(_add, findsOneWidget); // shown, but disabled
    await tester.tap(_add, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(_detail(c).columnLayout, isNull);
  });

  testWidgets('editing the Columns field commits the rounded value',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();
    await tester.tap(_add);
    await tester.pumpAndSettle();

    await tester.enterText(_editable('columnCount'), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_detail(c).columnLayout!.columnCount, 3);
  });

  testWidgets('Remove clears the layout', (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();
    await tester.tap(_add);
    await tester.pumpAndSettle();

    expect(_remove, findsOneWidget);
    await tester.tap(_remove);
    await tester.pumpAndSettle();

    expect(_detail(c).columnLayout, isNull);
  });
}
```

> `pumpDesignerWith(tester, controller: …)` is in `test/designer/support/designer_harness.dart`. If it disposes the controller on tear-down already, do not add a second `addTearDown`. Confirm `selectBand` is the public selection method (it is used in `properties_editor_test.dart`).

- [ ] **Step 4: Run the test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/column_layout_section_test.dart`
Expected: FAIL — the Add button key is not found (the section doesn't exist yet).

- [ ] **Step 5: Add the imports to the panel**

In `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`, ensure these domain imports exist (add any missing):

```dart
import '../../../domain/column_layout.dart';
```

> `Band`, `BandType`, `ReportDefinition`, `findBand`, `JetPrintLocalizations`, `LucideIcons`, `ShadButton`, `ShadTooltip` are already imported (used elsewhere in the file). Add only what the analyzer reports missing.

- [ ] **Step 6: Wire the section into `_bandInspector`**

In `_bandInspector`, replace the `if (band.type == BandType.detail) { … }` block (~lines 653–657) with:

```dart
    if (band.type == BandType.detail) {
      children
        ..add(const SizedBox(height: 18))
        ..addAll(_bandListSection(controller, bandId, theme, l10n, schema))
        ..addAll(_columnLayoutSection(controller, bandId, theme, l10n));
    }
```

- [ ] **Step 7: Add the `_columnLayoutSection` method**

Add this method to the same `State` class, after `_bandListSection` (~line 853):

```dart
  /// The label-grid (multi-column) editor for a detail band (spec 035). Shown
  /// only for detail bands. Three states: no layout + eligible body → an
  /// enabled "Add column layout"; no layout + ineligible → the Add disabled with
  /// a tooltip; layout present → the four geometry fields + Remove (editable
  /// even when ineligible, so an orphaned layout stays fixable). Validation rows
  /// and the inactive notice are appended by Task 3.
  List<Widget> _columnLayoutSection(
    JetReportDesignerController controller,
    String bandId,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final ReportDefinition def = controller.definition;
    final Band? band = findBand(def, bandId);
    if (band == null || band.type != BandType.detail) return const <Widget>[];
    final ColumnLayout? layout = band.columnLayout;
    final bool eligible =
        def.isPureSingleDetailBody && def.soleDetailBand?.id == bandId;

    final List<Widget> out = <Widget>[
      const SizedBox(height: 18),
      _Header(
        icon: LucideIcons.columns3,
        title: l10n.propertiesColumnLayout,
        theme: theme,
      ),
      const SizedBox(height: 14),
    ];

    if (layout == null) {
      out.add(_ColumnLayoutAddButton(
        enabled: eligible,
        label: l10n.propertiesColumnLayoutAdd,
        disabledTooltip: l10n.propertiesColumnLayoutAddDisabled,
        onAdd: () {
          final double bodyWidth =
              def.page.width - def.page.margins.left - def.page.margins.right;
          controller.setColumnLayout(
            bandId,
            ColumnLayout(
              columnCount: 2,
              columnWidth: bodyWidth / 2,
              columnSpacing: 0,
              rowSpacing: 0,
            ),
          );
        },
      ));
      return out;
    }

    out
      ..add(_LabeledRow(
        label: l10n.propertiesColumnCount,
        child: _NumberField(
          fieldKey: const ValueKey<String>('$_p.field.columnCount'),
          prefix: LucideIcons.columns3,
          value: layout.columnCount.toDouble(),
          onCommit: (double v) => controller.setColumnLayout(
              bandId, layout.copyWith(columnCount: v.round())),
        ),
      ))
      ..add(_LabeledRow(
        label: l10n.propertiesColumnWidth,
        child: _NumberField(
          fieldKey: const ValueKey<String>('$_p.field.columnWidth'),
          prefix: LucideIcons.moveHorizontal,
          value: layout.columnWidth,
          onCommit: (double v) =>
              controller.setColumnLayout(bandId, layout.copyWith(columnWidth: v)),
        ),
      ))
      ..add(_LabeledRow(
        label: l10n.propertiesColumnSpacing,
        child: _NumberField(
          fieldKey: const ValueKey<String>('$_p.field.columnSpacing'),
          prefix: LucideIcons.moveHorizontal,
          value: layout.columnSpacing,
          onCommit: (double v) => controller.setColumnLayout(
              bandId, layout.copyWith(columnSpacing: v)),
        ),
      ))
      ..add(_LabeledRow(
        label: l10n.propertiesRowSpacing,
        child: _NumberField(
          fieldKey: const ValueKey<String>('$_p.field.rowSpacing'),
          prefix: LucideIcons.moveVertical,
          value: layout.rowSpacing,
          onCommit: (double v) =>
              controller.setColumnLayout(bandId, layout.copyWith(rowSpacing: v)),
        ),
      ))
      ..add(const SizedBox(height: 8))
      ..add(_ColumnLayoutRemoveButton(
        label: l10n.propertiesColumnLayoutRemove,
        onRemove: () => controller.removeColumnLayout(bandId),
      ));
    return out;
  }
```

> `columnCount` commits as `v.round()` — **not** clamped — so a `< 1` value still surfaces the spec-034 `validate()` error in Task 3 (advisory validation; values commit as typed).

- [ ] **Step 8: Add the two button widgets**

Add near the other private widgets (e.g. after `_InlineWarning`, ~line 1144):

```dart
/// The "Add column layout" affordance. Disabled (greyed, non-tappable) when the
/// report shape can't host a label grid, wrapped in a tooltip that explains the
/// requirement (spec 035 / FR-003). Enabled, it commits a default layout.
class _ColumnLayoutAddButton extends StatelessWidget {
  const _ColumnLayoutAddButton({
    required this.enabled,
    required this.label,
    required this.disabledTooltip,
    required this.onAdd,
  });

  final bool enabled;
  final String label;
  final String disabledTooltip;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final Widget button = ShadButton.outline(
      key: const ValueKey<String>('$_p.field.columnLayoutAdd'),
      size: ShadButtonSize.sm,
      enabled: enabled,
      onPressed: enabled ? onAdd : null,
      leading: const Icon(LucideIcons.columns3, size: 14),
      child: Text(label),
    );
    final Widget aligned = Align(alignment: Alignment.centerLeft, child: button);
    if (enabled) return aligned;
    // The disabled button still hosts a hover tooltip explaining why.
    return Align(
      alignment: Alignment.centerLeft,
      child: ShadTooltip(builder: (_) => Text(disabledTooltip), child: button),
    );
  }
}

/// The "Remove column layout" affordance — restores a plain detail band.
class _ColumnLayoutRemoveButton extends StatelessWidget {
  const _ColumnLayoutRemoveButton({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: ShadButton.ghost(
          key: const ValueKey<String>('$_p.field.columnLayoutRemove'),
          size: ShadButtonSize.sm,
          onPressed: onRemove,
          leading: const Icon(LucideIcons.trash2, size: 14),
          child: Text(label),
        ),
      );
}
```

> If `ShadButton.outline`/`.ghost` does not expose an `enabled:` parameter in the pinned `shadcn_ui` version, drop it — passing `onPressed: null` already disables the button (and the tooltip still wraps it). If `LucideIcons.columns3`/`trash2` are absent, use the closest available glyph (`LucideIcons.columns2` / `LucideIcons.trash`).

- [ ] **Step 9: Run the test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/column_layout_section_test.dart`
Expected: PASS (4/4).

- [ ] **Step 10: Analyze**

Run: `cd packages/jet_print && flutter analyze lib/src/designer/layout/panels/properties_panel.dart test/designer/column_layout_section_test.dart`
Expected: No issues.

- [ ] **Step 11: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/lib/src/designer/l10n packages/jet_print/test/designer/column_layout_section_test.dart
git commit -m "feat(035): Column Layout properties section (add/edit/remove + gating)"
```

---

## Task 3: Validation feedback + inactive notice

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (`_columnLayoutSection` state-B tail; new top-level `_isColumnDiagnostic`; imports)
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_de.arb`, `jet_print_tr.arb` (one key)
- Test: `packages/jet_print/test/designer/column_layout_section_test.dart` (extend)

**Interfaces:**
- Consumes: `controller.diagnostics` → `List<Diagnostic>` (`severity`: `DiagnosticSeverity`, `message`: `String`, `elementId`: `String?`); existing `_UnresolvedHint(message:)`, `_InlineWarning(text:, theme:)`; l10n getter `propertiesColumnLayoutInactive`.
- Produces: l10n getter `propertiesColumnLayoutInactive`; top-level `bool _isColumnDiagnostic(String message)`.

- [ ] **Step 1: Add the inactive-notice ARB key (all three locales)**

`jet_print_en.arb` (with metadata):

```json
  "propertiesColumnLayoutInactive": "Column layout is inactive: the report isn't a single detail band.",
  "@propertiesColumnLayoutInactive": {
    "description": "Notice shown when a band carries a column layout but the report shape no longer satisfies the activation gate (spec 035 / FR-009)."
  }
```

`jet_print_de.arb`:

```json
  "propertiesColumnLayoutInactive": "Spaltenlayout ist inaktiv: Der Bericht ist kein einzelnes Detailband."
```

`jet_print_tr.arb`:

```json
  "propertiesColumnLayoutInactive": "Sütun düzeni etkin değil: rapor tek bir ayrıntı bandı değil."
```

- [ ] **Step 2: Regenerate localizations**

Run: `cd packages/jet_print && flutter gen-l10n`
Expected: `propertiesColumnLayoutInactive` getter present in the generated file.

- [ ] **Step 3: Write the failing tests (extend the section test)**

Append these tests to `packages/jet_print/test/designer/column_layout_section_test.dart`'s `main()`, and add the fixtures/finders below to the top of the file:

```dart
Finder _textContains(String needle) =>
    find.byWidgetPredicate((Widget w) => w is Text && (w.data?.contains(needle) ?? false));

/// Orphaned: a title makes the body ineligible, yet the detail band still
/// carries a column layout (the user added it earlier, then added a title).
ReportDefinition _orphaned() => const ReportDefinition(
      name: 'r',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(id: 'title', type: BandType.title, height: 30),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 80,
              columnLayout: ColumnLayout(
                  columnCount: 2, columnWidth: 100, columnSpacing: 0, rowSpacing: 0),
            )),
          ],
        ),
      ),
    );
```

```dart
  testWidgets('a grid wider than the body shows a verbatim error row',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: _pure()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();
    await tester.tap(_add);
    await tester.pumpAndSettle();

    // Make the single column wider than the whole page body.
    final double tooWide = c.definition.page.width;
    await tester.enterText(_editable('columnWidth'), tooWide.toStringAsFixed(0));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_textContains('wider than the page body'), findsOneWidget);
  });

  testWidgets('an orphaned layout shows the inactive notice and stays editable',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await pumpDesignerWith(tester,
        controller: JetReportDesignerController(definition: _orphaned()));
    await _openProperties(tester);
    c.selectBand('detail');
    await tester.pumpAndSettle();

    expect(_field('columnCount'), findsOneWidget); // fields still shown
    expect(_remove, findsOneWidget); // remove still available
    expect(_textContains('inactive'), findsOneWidget); // localized notice
    // The raw engine "is ignored" stray-band warning is NOT also shown.
    expect(_textContains('is ignored'), findsNothing);
  });
```

- [ ] **Step 4: Run to verify the new tests fail**

Run: `cd packages/jet_print && flutter test test/designer/column_layout_section_test.dart`
Expected: the two new tests FAIL (no error row / no inactive notice rendered yet); the four Task-2 tests still PASS.

- [ ] **Step 5: Add the diagnostic imports to the panel**

Add to `properties_panel.dart` if missing:

```dart
import '../../../domain/diagnostic.dart';
```

- [ ] **Step 6: Append diagnostics + inactive notice to `_columnLayoutSection`**

Immediately before the final `return out;` of `_columnLayoutSection` (in the layout-present branch, after the Remove button is added), insert:

```dart
    // Inactive notice (FR-009): a layout exists but the report shape no longer
    // activates the grid. Presented as the localized twin of the engine's
    // stray-`columnLayout` warning, so that raw warning is filtered out below.
    if (!eligible) {
      out
        ..add(const SizedBox(height: 8))
        ..add(_InlineWarning(
            text: l10n.propertiesColumnLayoutInactive, theme: theme));
    }

    // Verbatim column diagnostics for this band (FR-008/FR-010): reuse
    // `validate()` output — never re-derive the grid math — filtered to this
    // band (band-level ids + this band's element ids) and to the spec-034
    // column-diagnostic messages.
    final Set<String> elementIds =
        band.elements.map((ReportElement e) => e.id).toSet();
    for (final Diagnostic d in controller.diagnostics) {
      final String? id = d.elementId;
      final bool mine =
          id == bandId || (id != null && elementIds.contains(id));
      if (!mine || !_isColumnDiagnostic(d.message)) continue;
      out.add(const SizedBox(height: 6));
      out.add(d.severity == DiagnosticSeverity.error
          ? _UnresolvedHint(message: d.message)
          : _InlineWarning(text: d.message, theme: theme));
    }
    return out;
```

- [ ] **Step 7: Add the diagnostic matcher**

Add at the top level of `properties_panel.dart` (near `const String _p`):

```dart
/// Whether [message] is one of the spec-034 column-layout diagnostics emitted by
/// `validate()` (`_validateColumns`). Matched by stable English prefix because
/// the domain `Diagnostic` carries no code; the designer renders these strings
/// verbatim (spec 035 / FR-010), so this coupling is intentional and local. The
/// stray "column layout on band … is ignored" warning is deliberately excluded —
/// the localized inactive notice covers that case.
bool _isColumnDiagnostic(String message) =>
    message.startsWith('columnLayout ') ||
    message.startsWith('label height (') ||
    message.contains('overflows cell width');
```

- [ ] **Step 8: Run to verify all section tests pass**

Run: `cd packages/jet_print && flutter test test/designer/column_layout_section_test.dart`
Expected: PASS (6/6).

- [ ] **Step 9: Analyze**

Run: `cd packages/jet_print && flutter analyze lib/src/designer/layout/panels/properties_panel.dart`
Expected: No issues.

- [ ] **Step 10: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/lib/src/designer/l10n packages/jet_print/test/designer/column_layout_section_test.dart
git commit -m "feat(035): surface column diagnostics verbatim + inactive notice"
```

---

## Task 4: Canvas cue — cell boundary + ghost columns

**Files:**
- Create: `packages/jet_print/lib/src/designer/canvas/label_grid_geometry.dart`
- Modify: `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` (new `_LabelGridPainter`; a CustomPaint layer after `_BandChromePainter` ~line 1084; a ghost color constant; import)
- Test: `packages/jet_print/test/designer/canvas/label_grid_geometry_test.dart`

**Interfaces:**
- Consumes: `DesignTimeLayout.bandRect(String) → JetRect?`; `ReportDefinition.isPureSingleDetailBody`, `ReportDefinition.soleDetailBand`; `Band.columnLayout`; `JetRect(x,y,width,height)`.
- Produces: `typedef LabelGridCue = ({JetRect cell, List<JetRect> ghosts})`; `LabelGridCue? labelGridCue(ReportDefinition def, DesignTimeLayout layout)`.

- [ ] **Step 1: Write the failing geometry test**

Create `packages/jet_print/test/designer/canvas/label_grid_geometry_test.dart`:

```dart
// Pure label-grid cue geometry (spec 035 / Task 4). Tests the data the canvas
// overlay draws — no widget pump. Uses src/ imports (internal canvas helper),
// like the other canvas-geometry tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/designer/canvas/design_time_layout.dart';
import 'package:jet_print/src/designer/canvas/label_grid_geometry.dart';

ReportDefinition _withLayout(ColumnLayout cl) => ReportDefinition(
      name: 'labels',
      page: const PageFormat(
        width: 600,
        height: 800,
        margins: EdgeInsetsGeometryLike(left: 50, top: 50, right: 50, bottom: 50),
      ),
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
                id: 'detail', type: BandType.detail, height: 80, columnLayout: cl)),
          ],
        ),
      ),
    );

void main() {
  test('two columns that exactly fill the body: one ghost, no clipping', () {
    // content width = 600 - 50 - 50 = 500; two 250-wide columns, no spacing.
    final ReportDefinition def = _withLayout(const ColumnLayout(
        columnCount: 2, columnWidth: 250, columnSpacing: 0, rowSpacing: 0));
    final LabelGridCue? cue = labelGridCue(def, DesignTimeLayout.of(def));

    expect(cue, isNotNull);
    expect(cue!.cell.x, 50);
    expect(cue.cell.width, 250);
    expect(cue.ghosts.length, 1);
    expect(cue.ghosts.single.x, 300); // 50 + 250
    expect(cue.ghosts.single.width, 250);
  });

  test('a column count that overflows the body clips the last ghost', () {
    // content width 500; three 200-wide columns would span 600 > 500.
    final ReportDefinition def = _withLayout(const ColumnLayout(
        columnCount: 3, columnWidth: 200, columnSpacing: 0, rowSpacing: 0));
    final LabelGridCue? cue = labelGridCue(def, DesignTimeLayout.of(def));

    expect(cue, isNotNull);
    // Ghosts start at x=250 (w=200, fits to 450) and x=450 (clipped to 100).
    expect(cue!.ghosts.map((JetRect g) => g.x), <double>[250, 450]);
    expect(cue.ghosts.last.width, 100); // 500-content-right (550) - 450
  });

  test('null when the body is not a pure single-detail body', () {
    final ReportDefinition def = ReportDefinition(
      name: 'r',
      page: const PageFormat(
          width: 600,
          height: 800,
          margins: EdgeInsetsGeometryLike(left: 50, top: 50, right: 50, bottom: 50)),
      body: ReportBody(
        title: const Band(id: 'title', type: BandType.title, height: 30),
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(const Band(
                id: 'detail',
                type: BandType.detail,
                height: 80,
                columnLayout: ColumnLayout(
                    columnCount: 2, columnWidth: 250, columnSpacing: 0, rowSpacing: 0))),
          ],
        ),
      ),
    );
    expect(labelGridCue(def, DesignTimeLayout.of(def)), isNull);
  });

  test('null when the sole detail band has no column layout', () {
    final ReportDefinition def = ReportDefinition(
      name: 'r',
      page: const PageFormat(
          width: 600,
          height: 800,
          margins: EdgeInsetsGeometryLike(left: 50, top: 50, right: 50, bottom: 50)),
      body: const ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(id: 'detail', type: BandType.detail, height: 80)),
          ],
        ),
      ),
    );
    expect(labelGridCue(def, DesignTimeLayout.of(def)), isNull);
  });
}
```

> Use the project's actual `PageFormat` margin type and constructor — `EdgeInsetsGeometryLike(...)` is a placeholder for whatever `PageFormat.margins` uses (check `lib/src/domain/page_format.dart`; e.g. it may be `PageMargins(...)`). Replace the margin literal accordingly. If a positive-margins page preset is simpler, build from `PageFormat.a4Portrait` and read its real content width instead of hard-coding 500.

- [ ] **Step 2: Run to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/canvas/label_grid_geometry_test.dart`
Expected: FAIL — `label_grid_geometry.dart` / `labelGridCue` does not exist.

- [ ] **Step 3: Create the geometry helper**

Create `packages/jet_print/lib/src/designer/canvas/label_grid_geometry.dart`:

```dart
/// Design-time geometry of a label grid's cells, for the canvas cue (spec 035).
///
/// Pure data: given a definition and its [DesignTimeLayout], it produces the
/// first editable cell rect plus the read-only ghost cell rects that cue the
/// repeated grid. The active band's design rect spans the full content width
/// (the canvas does NOT narrow it — element drag/resize stay unchanged, FR-013);
/// this overlay draws a cell at `columnWidth` and `columnCount - 1` ghosts at
/// pitch, clipped to the content's right edge. Nothing here changes layout.
library;

import 'dart:math' as math;

import '../../domain/band.dart';
import '../../domain/column_layout.dart';
import '../../domain/geometry.dart';
import '../../domain/report_definition.dart';
import 'design_time_layout.dart';

/// The first (editable) cell rect plus the read-only ghost cell rects.
typedef LabelGridCue = ({JetRect cell, List<JetRect> ghosts});

/// Computes the [LabelGridCue] for [def]'s active label band, or null when no
/// grid is active — i.e. the body is not a pure single-detail body, the sole
/// detail band has no [ColumnLayout], the layout has a non-positive cell width,
/// or the band has no design rect.
LabelGridCue? labelGridCue(ReportDefinition def, DesignTimeLayout layout) {
  if (!def.isPureSingleDetailBody) return null;
  final Band? band = def.soleDetailBand;
  final ColumnLayout? cl = band?.columnLayout;
  if (band == null || cl == null || cl.columnWidth <= 0) return null;
  final JetRect? rect = layout.bandRect(band.id);
  if (rect == null) return null;

  final double contentRight = rect.x + rect.width;
  final JetRect cell = JetRect(
    x: rect.x,
    y: rect.y,
    width: math.min(cl.columnWidth, rect.width),
    height: rect.height,
  );
  final List<JetRect> ghosts = <JetRect>[];
  final double pitch = cl.columnWidth + cl.columnSpacing;
  for (int i = 1; i < cl.columnCount; i++) {
    final double x = rect.x + i * pitch;
    if (x >= contentRight) break;
    final double w = math.min(cl.columnWidth, contentRight - x);
    if (w <= 0) break;
    ghosts.add(JetRect(x: x, y: rect.y, width: w, height: rect.height));
  }
  return (cell: cell, ghosts: ghosts);
}
```

- [ ] **Step 4: Run to verify the geometry test passes**

Run: `cd packages/jet_print && flutter test test/designer/canvas/label_grid_geometry_test.dart`
Expected: PASS (4/4).

- [ ] **Step 5: Add the painter + ghost color to `design_canvas.dart`**

Add the import near the other canvas imports:

```dart
import 'label_grid_geometry.dart';
```

Add a faint chrome color constant alongside the other `_…Color` consts (e.g. near `_bandSeparatorColor`):

```dart
/// The label-grid cue stroke — a faint slate outline for the editable cell
/// boundary and the read-only ghost columns (design-only chrome).
const Color _labelGridCueColor = Color(0x553B82F6); // slate/blue @ ~33%
```

Add the painter near `_BandChromePainter` (~line 1410):

```dart
/// Draws the multi-column label cue (spec 035): the editable cell's boundary
/// plus faint read-only ghost outlines for the remaining columns. Design-only
/// chrome — non-interactive, never part of the shared render pipeline.
class _LabelGridPainter extends CustomPainter {
  const _LabelGridPainter({
    required this.cue,
    required this.scale,
    required this.color,
  });

  final LabelGridCue cue;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    Rect scaled(JetRect r) =>
        Rect.fromLTWH(r.x * scale, r.y * scale, r.width * scale, r.height * scale);
    canvas.drawRect(scaled(cue.cell), stroke);
    for (final JetRect g in cue.ghosts) {
      canvas.drawRect(scaled(g), stroke);
    }
  }

  @override
  bool shouldRepaint(_LabelGridPainter oldDelegate) =>
      oldDelegate.cue != cue ||
      oldDelegate.scale != scale ||
      oldDelegate.color != color;
}
```

> `LabelGridCue` is a record, so `oldDelegate.cue != cue` is value equality over `JetRect`s — correct.

- [ ] **Step 6: Wire the cue layer into `_buildPage`**

In `_buildPage`, immediately after the `_BandChromePainter` `Positioned.fill(...)` (closes ~line 1084) and before the `_bandBadges(...)` spread, insert:

```dart
                  // Multi-column label cue (spec 035): the editable cell
                  // boundary + read-only ghost columns. Drawn above band chrome,
                  // below element appearance; absent unless a grid is active.
                  if (labelGridCue(controller.definition, displayLayout)
                      case final LabelGridCue cue)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LabelGridPainter(
                          cue: cue,
                          scale: scale,
                          color: _labelGridCueColor,
                        ),
                      ),
                    ),
```

- [ ] **Step 7: Write a canvas smoke test**

Append to `packages/jet_print/test/designer/canvas/label_grid_geometry_test.dart` a widget smoke test verifying the designer renders (no exception) with an active label band selected:

```dart
// (append the imports at the top of the file)
// import 'package:flutter/widgets.dart';
// import 'package:flutter_test/flutter_test.dart';
// import '../support/designer_harness.dart';

  testWidgets('the canvas renders with an active label band (no exception)',
      (WidgetTester tester) async {
    final ReportDefinition def = _withLayout(const ColumnLayout(
        columnCount: 2, columnWidth: 250, columnSpacing: 0, rowSpacing: 0));
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, controller: JetReportDesignerController(definition: def));
    c.selectBand('detail');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
```

> Keep imports tidy — `flutter/widgets.dart`, `flutter_test`, and the harness import go at the top of the file with the others; remove the comment block once added.

- [ ] **Step 8: Run the full canvas test**

Run: `cd packages/jet_print && flutter test test/designer/canvas/label_grid_geometry_test.dart`
Expected: PASS (5/5).

- [ ] **Step 9: Analyze**

Run: `cd packages/jet_print && flutter analyze lib/src/designer/canvas test/designer/canvas/label_grid_geometry_test.dart`
Expected: No issues.

- [ ] **Step 10: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/canvas test/designer/canvas/label_grid_geometry_test.dart 2>/dev/null; git add packages/jet_print/test/designer/canvas/label_grid_geometry_test.dart
git commit -m "feat(035): canvas label-grid cue (cell boundary + ghost columns)"
```

---

## Final Verification (after all tasks)

- [ ] **Full suite green**

Run: `cd packages/jet_print && flutter test`
Expected: all tests pass, including the spec-034 engine + golden tests unchanged.

- [ ] **Analyzer clean**

Run: `cd packages/jet_print && flutter analyze`
Expected: No issues.

- [ ] **Goldens byte-identical (Constitution IV)**

The run above re-renders every golden; expect zero golden diffs (designer-only change). If a golden flags, investigate before proceeding — engine output must not have moved.

- [ ] **Localization round-trip**

Confirm the generated `jet_print_localizations_de.dart` / `_tr.dart` carry every new key (no English fallback for `de`/`tr` chrome): `cd packages/jet_print && flutter gen-l10n` produces no warnings about untranslated messages for the new keys.

---

## Self-Review

**1. Spec coverage**

- FR-001 (detail-only section after Size) → Task 2 Step 6/7.
- FR-002 (Add enabled on eligible, default 2 / bodyWidth÷2 / 0 / 0) → Task 2 Step 7 + test.
- FR-003 (Add disabled + tooltip on ineligible) → Task 2 Step 8 (`_ColumnLayoutAddButton`) + test.
- FR-004 (four commit-on-blur fields, editable regardless of eligibility, columnCount rounded) → Task 2 Step 7 + test.
- FR-005 (Remove) → Task 2 Step 7/8 + test.
- FR-006 (removal preserves id/type/height/elements) → Task 1 `RemoveColumnLayoutCommand` + test asserting elements/height survive.
- FR-007 (commands via `_commit`, undo/redo, no-op on missing id) → Task 1 + tests.
- FR-008 (reuse `controller.diagnostics`, filtered to band, no re-derived math) → Task 3 Step 6 + matcher.
- FR-009 (inactive notice) → Task 3 Step 6 + test.
- FR-010 (chrome localized; diagnostics verbatim) → Task 2/3 ARB keys + Task 3 verbatim rendering.
- FR-011 (canvas cell at columnWidth + columnCount−1 ghosts, clipped) → Task 4 geometry + painter + tests.
- FR-012 (no layout / ineligible → unchanged full-width) → Task 4 `labelGridCue` returns null → layer absent; geometry tests cover null cases.
- FR-013 (drag/resize unchanged; ghosts non-interactive) → Task 4 draws overlay only, never touches `DesignTimeLayout` rects or hit-testing; smoke test.

**2. Placeholder scan** — No TBD/TODO. The two flagged uncertainties (exact `PageFormat.margins` type in Task 4's test; `ShadButton.enabled`/`LucideIcons.columns3` availability) are called out with concrete fallbacks, not left vague.

**3. Type consistency** — `setColumnLayout(String, ColumnLayout)` / `removeColumnLayout(String)` / `SetColumnLayoutCommand({bandId, layout})` / `RemoveColumnLayoutCommand({bandId})` / `labelGridCue(ReportDefinition, DesignTimeLayout) → LabelGridCue?` / `LabelGridCue = ({JetRect cell, List<JetRect> ghosts})` are used identically across the producing task and every consumer. Widget keys (`columnLayoutAdd`, `columnLayoutRemove`, `columnCount`, `columnWidth`, `columnSpacing`, `rowSpacing`) match between the panel and the tests.
