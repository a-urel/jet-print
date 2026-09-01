# Crosstab Designer Authoring (Spec B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a crosstab addable, selectable, editable, reorderable and deletable in the jet_print designer, with undo/redo, three-locale strings, and tests.

**Architecture:** Designer-only. The domain model, codec and engine are untouched — Spec A already ships `Crosstab` with full `copyWith`, complete `validate()` rules, `allIds` coverage for minted ids, and a computed canvas rect. This plan adds a fifth `Selection` target, three commands behind one controller-API extension, an Outline row with actions, a Properties inspector `part` file, and a selectable schematic canvas block.

**Tech Stack:** Dart / Flutter, `shadcn_ui`, `flutter gen-l10n` (ARB source of truth), `flutter test` with golden files.

**Spec:** `docs/superpowers/specs/2026-09-01-crosstab-designer-authoring-design.md`
(depends on `docs/superpowers/specs/2026-08-30-crosstab-engine-design.md`)

## Global Constraints

- **No domain-model change.** No new field on `Crosstab`, `CrosstabGroup`, `CrosstabMeasure`, `CrosstabStyle`; no codec change; no schema version bump. A task that needs one is a plan defect — stop and report.
- **No engine change.** Nothing under `lib/src/rendering/` is edited.
- **Format only touched files.** `dart format <the files you changed>` — never `dart format lib test`, which reformats ~8 unrelated files in this repo.
- **Revert `pubspec.lock`.** `flutter test` rewrites it (intl 0.20.2→0.20.3); run `git checkout -- pubspec.lock` before every commit.
- **Zero unintended golden changes.** Exactly one task (Task 11) regenerates goldens. A golden diff in any other task is a bug in that task.
- **ARBs are the source of truth.** Every new key goes into all three of `jet_print_en.arb`, `jet_print_tr.arb`, `jet_print_de.arb`, then `flutter gen-l10n`. Never hand-edit `jet_print_localizations*.dart`.
- **Public extensions must be in the barrel's `show` list.** `lib/jet_print.dart` line ~47 lists controller extensions; a public extension missing there is uncallable through the barrel and only `public_api_test` catches it.
- **Commands are tested black-box** through the controller — `encapsulation_test.dart` forbids reaching into command internals.
- **A crosstab must always keep ≥1 row group, ≥1 column group, ≥1 measure** — `validate()` errors otherwise.
- Run from the repo root; `flutter` leaves the shell cwd inside the package.
- Test command: `flutter test` in `packages/jet_print`; the playground suite is `flutter test` in `apps/jet_print_playground`.

---

### Task 1: Generalize scope-child reorder to any node kind

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/band_walker.dart:614-630`
- Modify: `packages/jet_print/lib/src/designer/controller/api/bands.dart:107-117` (call site)
- Test: `packages/jet_print/test/designer/controller/band_walker_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ReportDefinition reorderScopeNode(ReportDefinition def, String scopeId, String nodeId, int delta)` — moves the child of `scopeId` whose id is `nodeId` by `delta`, clamped to the child list; returns `def` unchanged when the node is absent or the move is clamped to a no-op. `reorderScopeChild` is **removed** (renamed, not kept as an alias).

- [ ] **Step 1: Write the failing test**

Add to `band_walker_test.dart`:

```dart
test('reorderScopeNode moves a crosstab among its siblings', () {
  final ReportDefinition def = ReportDefinition(
    name: 'r',
    page: PageFormat.a4Portrait,
    body: ReportBody(
      root: DetailScope(
        id: 'root',
        children: <ScopeNode>[
          BandNode(Band(id: 'b1', type: BandType.detail, height: 10)),
          CrosstabNode(_ct('ct1')),
        ],
      ),
    ),
  );
  final ReportDefinition moved = reorderScopeNode(def, 'root', 'ct1', -1);
  expect(moved.body.root.children.first, isA<CrosstabNode>());
});
```

`_ct(String id)` is a local helper building a minimal valid crosstab (one row group, one column group, one sum measure) — copy the shape from `test/domain/crosstab/crosstab_model_test.dart`.

- [ ] **Step 2: Run it and watch it fail**

Run: `cd packages/jet_print && flutter test test/designer/controller/band_walker_test.dart`
Expected: FAIL — `reorderScopeNode` is not defined.

- [ ] **Step 3: Generalize the function**

Replace the body of `reorderScopeChild` with:

```dart
/// Moves the child of [scopeId] whose id is [nodeId] by [delta] positions,
/// clamped to the child list. Any node kind moves — a band, a nested list, or
/// a crosstab (whose position decides whether it prints before or after the
/// row loop). A no-op for an unknown scope or node, or a clamped move.
ReportDefinition reorderScopeNode(
        ReportDefinition def, String scopeId, String nodeId, int delta) =>
    mapScopes(def, (DetailScope s) {
      if (s.id != scopeId) return s;
      final int idx = s.children.indexWhere((ScopeNode n) => switch (n) {
            BandNode(band: final Band b) => b.id == nodeId,
            NestedScope(scope: final DetailScope inner) => inner.id == nodeId,
            CrosstabNode(crosstab: final Crosstab ct) => ct.id == nodeId,
            UnknownScopeNode() => false,
          });
      if (idx < 0) return s;
      final int target = (idx + delta).clamp(0, s.children.length - 1);
      if (target == idx) return s;
      final List<ScopeNode> children = <ScopeNode>[...s.children];
      final ScopeNode node = children.removeAt(idx);
      children.insert(target, node);
      return s.copyWith(children: children);
    });
```

Keep whatever the existing tail of the function does after `insert` (return shape) — read lines 626-632 and preserve it exactly.

Update the one call site in `api/bands.dart:114` to `reorderScopeNode(d, scope.id, bandId, delta)`.

- [ ] **Step 4: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS, including every pre-existing band-reorder test unchanged.

- [ ] **Step 5: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "refactor(designer): reorder any scope child by id, not just bands"
```

---

### Task 2: Crosstab walker helpers

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/band_walker.dart`
- Test: `packages/jet_print/test/designer/controller/band_walker_test.dart`

**Interfaces:**
- Consumes: `reorderScopeNode` (Task 1).
- Produces:
  - `Crosstab? findCrosstab(ReportDefinition def, String crosstabId)`
  - `DetailScope? findScopeOfCrosstab(ReportDefinition def, String crosstabId)`
  - `ReportDefinition mapCrosstabs(ReportDefinition def, Crosstab Function(Crosstab) transform)`
  - `ReportDefinition removeCrosstab(ReportDefinition def, String crosstabId)`

- [ ] **Step 1: Write the failing tests**

```dart
test('findCrosstab returns the crosstab and its scope', () {
  final ReportDefinition def = _defWithCrosstab();
  expect(findCrosstab(def, 'ct1')?.id, 'ct1');
  expect(findScopeOfCrosstab(def, 'ct1')?.id, 'root');
  expect(findCrosstab(def, 'nope'), isNull);
});

test('mapCrosstabs rewrites in place and removeCrosstab drops the node', () {
  final ReportDefinition def = _defWithCrosstab();
  final ReportDefinition renamed = mapCrosstabs(
      def, (Crosstab c) => c.copyWith(name: () => 'Pivot'));
  expect(findCrosstab(renamed, 'ct1')?.name, 'Pivot');
  expect(findCrosstab(removeCrosstab(def, 'ct1'), 'ct1'), isNull);
});
```

- [ ] **Step 2: Run and watch them fail**

Run: `cd packages/jet_print && flutter test test/designer/controller/band_walker_test.dart`
Expected: FAIL — undefined names.

- [ ] **Step 3: Implement**

Follow the existing `findScope` / `mapScopes` / `removeScope` implementations in the same file for structure, walking `def.body.root` recursively through `NestedScope` children. `mapCrosstabs` rebuilds `CrosstabNode(transform(ct))` and must return every other node kind unchanged (use an exhaustive `switch`, not an `is`-chain — the file's own convention since Spec A's prep task). `removeCrosstab` filters the node out of `children`.

- [ ] **Step 4: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "feat(designer): crosstab lookup and rewrite helpers in band_walker"
```

---

### Task 3: A crosstab selection target

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/selection.dart`
- Modify: `packages/jet_print/lib/src/designer/controller/api/selection.dart`
- Test: `packages/jet_print/test/designer/controller/selection_test.dart` (create if absent)

**Interfaces:**
- Produces: `Selection.crosstab(String crosstabId)`, `Selection.crosstabId`, and `void JetReportDesignerController.selectCrosstab(String crosstabId)`.

- [ ] **Step 1: Write the failing test**

```dart
test('each factory produces exactly one non-empty target', () {
  final List<Selection> all = <Selection>[
    Selection.of(<String>['e1']),
    Selection.band('b1'),
    Selection.group('g1'),
    Selection.scope('s1'),
    Selection.crosstab('ct1'),
    Selection.report(),
  ];
  for (final Selection s in all) {
    final int targets = (s.ids.isNotEmpty ? 1 : 0) +
        (s.bandId != null ? 1 : 0) +
        (s.groupId != null ? 1 : 0) +
        (s.scopeId != null ? 1 : 0) +
        (s.crosstabId != null ? 1 : 0) +
        (s.isReport ? 1 : 0);
    expect(targets, 1, reason: '$s');
    expect(s.isEmpty, isFalse);
  }
  // Pairwise distinct.
  for (int i = 0; i < all.length; i++) {
    for (int j = i + 1; j < all.length; j++) {
      expect(all[i] == all[j], isFalse);
    }
  }
});

test('Selection.empty has no target', () {
  expect(Selection.empty.crosstabId, isNull);
  expect(Selection.empty.isEmpty, isTrue);
});
```

- [ ] **Step 2: Run and watch it fail**

Run: `cd packages/jet_print && flutter test test/designer/controller/selection_test.dart`
Expected: FAIL — `crosstabId` is not defined.

- [ ] **Step 3: Implement**

Add `this.crosstabId` to the private constructor, the field with a doc comment matching the neighbours, the `Selection.crosstab` factory, and extend `isEmpty`, `==`, `hashCode` (add to the `Object.hash` argument list) and `toString` (`'Selection(crosstab $crosstabId)'`). Update the class-level doc comment: the invariant is now "exactly one of five".

In `api/selection.dart`, add beside `selectBand`:

```dart
/// Selects the crosstab with stable id [crosstabId] (Spec B). A selection-only
/// change: no model edit, so it records no history entry of its own.
void selectCrosstab(String crosstabId) =>
    _setSelection(Selection.crosstab(crosstabId));
```

Match the exact history/notify shape of the `selectBand` implementation next to it.

- [ ] **Step 4: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "feat(designer): add a crosstab selection target"
```

---

### Task 4: Crosstab lifecycle commands and controller API

**Files:**
- Create: `packages/jet_print/lib/src/designer/controller/commands/crosstab_commands.dart`
- Create: `packages/jet_print/lib/src/designer/controller/api/crosstab.dart`
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (imports + `part`)
- Modify: `packages/jet_print/lib/jet_print.dart` (barrel `show` list)
- Test: `packages/jet_print/test/designer/controller/crosstab_commands_test.dart` (create)

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces:
  - `CreateCrosstabCommand({required String parentScopeId, required Crosstab crosstab})`
  - `DeleteCrosstabCommand(String crosstabId)`
  - `UpdateCrosstabCommand({required String crosstabId, required String label, required Crosstab Function(Crosstab) update})`
  - extension `CtrlCrosstab` with `createCrosstab(String scopeId, {String? collectionField})`, `deleteCrosstab`, `moveCrosstab(String, int)`, `renameCrosstab(String, String?)`, `setCrosstabCollection(String, String?)`, `setCrosstabVisible(String, BoolProperty)`, `setCrosstabStyle(String, CrosstabStyle)`.
- `createCrosstab` seeds from the schema reachable at `scopeId` (see step 3) and selects the new crosstab.

- [ ] **Step 1: Write the failing tests**

```dart
test('createCrosstab makes a crosstab that validates clean', () {
  final JetReportDesignerController c = JetReportDesignerController(
      definition: _emptyDef(), schema: _salesSchema());
  c.createCrosstab(c.definition.body.root.id);
  final List<Diagnostic> errors = validate(c.definition)
      .where((Diagnostic d) => d.severity == DiagnosticSeverity.error)
      .toList();
  expect(errors, isEmpty, reason: errors.map((Diagnostic d) => d.message).join('; '));
  expect(c.selection.crosstabId, isNotNull);
});

test('rename, collection and delete each undo in one step', () {
  final JetReportDesignerController c = ...;
  c.createCrosstab(c.definition.body.root.id);
  final String id = c.selection.crosstabId!;
  final ReportDefinition afterCreate = c.definition;
  c.renameCrosstab(id, 'Pivot');
  expect(findCrosstab(c.definition, id)!.name, 'Pivot');
  c.undo();
  expect(c.definition, afterCreate);
  c.deleteCrosstab(id);
  expect(findCrosstab(c.definition, id), isNull);
  expect(c.selection.isEmpty, isTrue);
  c.undo();
  expect(c.definition, afterCreate);
});
```

Build `_salesSchema()` with a string field, a second string field and a double field so the seeding rule has all three inputs. Read the controller's real constructor signature from `jet_report_designer_controller.dart` before writing these — do not guess it.

- [ ] **Step 2: Run and watch them fail**

Run: `cd packages/jet_print && flutter test test/designer/controller/crosstab_commands_test.dart`
Expected: FAIL — `createCrosstab` is not defined.

- [ ] **Step 3: Implement the commands and the API**

`crosstab_commands.dart` mirrors `scope_commands.dart`:

```dart
class CreateCrosstabCommand extends EditCommand {
  const CreateCrosstabCommand({required this.parentScopeId, required this.crosstab});
  final String parentScopeId;
  final Crosstab crosstab;

  @override
  String get label => 'Add crosstab';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        addScopeChild(before.definition, parentScopeId, CrosstabNode(crosstab)),
        selection: Selection.crosstab(crosstab.id),
      );
}

class DeleteCrosstabCommand extends EditCommand {
  const DeleteCrosstabCommand(this.crosstabId);
  final String crosstabId;

  @override
  String get label => 'Delete crosstab';

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        removeCrosstab(before.definition, crosstabId),
        selection: Selection.empty,
      );
}

class UpdateCrosstabCommand extends EditCommand {
  const UpdateCrosstabCommand({
    required this.crosstabId,
    required this.label,
    required this.update,
  });
  final String crosstabId;
  @override
  final String label;
  final Crosstab Function(Crosstab) update;

  @override
  DesignerDocument apply(DesignerDocument before) => before.withDefinition(
        mapCrosstabs(before.definition,
            (Crosstab c) => c.id == crosstabId ? update(c) : c),
      );
}
```

`api/crosstab.dart` (a `part of '../jet_report_designer_controller.dart';`):

```dart
extension CtrlCrosstab on JetReportDesignerController {
  /// Adds a crosstab to scope [scopeId], seeded from the schema so it is born
  /// valid (Spec B decision 2), and selects it — one undoable step. A no-op for
  /// an unknown scope, or when no scalar field is reachable to bucket by.
  void createCrosstab(String scopeId, {String? collectionField}) {
    if (findScope(_document.definition, scopeId) == null) return;
    final Crosstab? seeded = _seedCrosstab(scopeId, collectionField);
    if (seeded == null) return;
    _commit(CreateCrosstabCommand(parentScopeId: scopeId, crosstab: seeded));
  }

  void deleteCrosstab(String crosstabId) =>
      _commit(DeleteCrosstabCommand(crosstabId));

  /// Moves crosstab [crosstabId] by [delta] among its siblings. The position is
  /// meaningful: above the first row-producing sibling it prints once BEFORE the
  /// row loop, below it once AFTER (Spec A decision 7).
  void moveCrosstab(String crosstabId, int delta) {
    final DetailScope? scope =
        findScopeOfCrosstab(_document.definition, crosstabId);
    if (scope == null) return;
    _commit(DefinitionEditCommand(
      label: 'Reorder crosstab',
      transform: (ReportDefinition d) =>
          reorderScopeNode(d, scope.id, crosstabId, delta),
    ));
  }

  void renameCrosstab(String crosstabId, String? name) =>
      _updateCrosstab(crosstabId, 'Rename crosstab',
          (Crosstab c) => c.copyWith(name: () => _blankToNull(name)));

  void setCrosstabCollection(String crosstabId, String? collectionField) =>
      _updateCrosstab(crosstabId, 'Bind crosstab',
          (Crosstab c) => c.copyWith(collectionField: () => collectionField));

  void setCrosstabVisible(String crosstabId, BoolProperty visible) =>
      _updateCrosstab(crosstabId, 'Set crosstab visibility',
          (Crosstab c) => c.copyWith(visible: visible));

  void setCrosstabStyle(String crosstabId, CrosstabStyle style) =>
      _updateCrosstab(crosstabId, 'Set crosstab style',
          (Crosstab c) => c.copyWith(style: style));

  void _updateCrosstab(
          String id, String label, Crosstab Function(Crosstab) update) =>
      _commit(UpdateCrosstabCommand(
          crosstabId: id, label: label, update: update));
}
```

`_blankToNull` trims and returns null for an empty string — copy the exact helper `renameBand` uses (read `api/bands.dart`; if it inlines the logic, inline it the same way rather than inventing a helper).

**The seeding rule** (`_seedCrosstab`, private in the same extension file):

1. Resolve the fields: when `collectionField` is null, the scalar fields in scope at `scopeId` (`scalarFieldsForScope`, the same call `_groupFields` in `add_menus.dart` makes); when it is set, that collection's own child fields.
2. `scalars` = fields whose type is not `collection`; return null when empty.
3. Row group = `scalars[0]`; column group = `scalars.length > 1 ? scalars[1] : scalars[0]`.
4. Measure = the first field whose type is `integer` or `double`, with `JetCalculation.sum`; when there is none, `scalars[0]` with `JetCalculation.count`.
5. Ids from `_ids.next('crosstab')`, `_ids.next('ctgroup')`, `_ids.next('ctmeasure')`; expressions are `'\$F{<field>}'`; group and measure `name`s are the field names.

Wire the new files: add `import` lines for `crosstab_commands.dart` and the crosstab domain types plus `part 'api/crosstab.dart';` in `jet_report_designer_controller.dart`, beside the existing ones.

Add `CtrlCrosstab` to the barrel's controller-extension `show` list in `lib/jet_print.dart` (~line 57, alphabetical among the neighbours).

- [ ] **Step 4: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS, `public_api_test` included.

- [ ] **Step 5: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "feat(designer): crosstab create/delete/move/rename commands"
```

---

### Task 5: Axis and measure editing API

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/api/crosstab.dart`
- Test: `packages/jet_print/test/designer/controller/crosstab_commands_test.dart`

**Interfaces:**
- Consumes: Task 4's `_updateCrosstab` and `CtrlCrosstab`.
- Produces: `addCrosstabGroup(String crosstabId, {required bool row, required String fieldName})`, `removeCrosstabGroup(String crosstabId, String groupId)`, `moveCrosstabGroup(String crosstabId, String groupId, int delta)`, `updateCrosstabGroup(String crosstabId, String groupId, CrosstabGroup Function(CrosstabGroup) update)`, and the four `*CrosstabMeasure` equivalents (`addCrosstabMeasure(String crosstabId, {required String fieldName})`).

- [ ] **Step 1: Write the failing tests**

```dart
test('the last row group, column group and measure cannot be removed', () {
  final JetReportDesignerController c = ...;
  c.createCrosstab(c.definition.body.root.id);
  final String id = c.selection.crosstabId!;
  final Crosstab ct = findCrosstab(c.definition, id)!;
  final ReportDefinition before = c.definition;
  c.removeCrosstabGroup(id, ct.rowGroups.single.id);
  c.removeCrosstabGroup(id, ct.columnGroups.single.id);
  c.removeCrosstabMeasure(id, ct.measures.single.id);
  expect(c.definition, before, reason: 'refusals must not edit or add history');
});

test('a second measure can be added, edited, moved and removed', () {
  ...
  c.addCrosstabMeasure(id, fieldName: 'units');
  expect(findCrosstab(c.definition, id)!.measures, hasLength(2));
  final String m2 = findCrosstab(c.definition, id)!.measures.last.id;
  c.updateCrosstabMeasure(id, m2,
      (CrosstabMeasure m) => m.copyWith(aggregate: JetCalculation.average));
  expect(findCrosstab(c.definition, id)!.measures.last.aggregate,
      JetCalculation.average);
  c.moveCrosstabMeasure(id, m2, -1);
  expect(findCrosstab(c.definition, id)!.measures.first.id, m2);
  c.removeCrosstabMeasure(id, m2);
  expect(findCrosstab(c.definition, id)!.measures, hasLength(1));
});
```

Mirror the measure test for row groups and column groups (`row: true` / `row: false`).

- [ ] **Step 2: Run and watch them fail**

Run: `cd packages/jet_print && flutter test test/designer/controller/crosstab_commands_test.dart`
Expected: FAIL — `removeCrosstabGroup` is not defined.

- [ ] **Step 3: Implement**

Every method is an `_updateCrosstab` whose thunk rebuilds one list:

```dart
  /// Appends an axis level bound to [fieldName] — to the row axis when [row] is
  /// true, else the column axis.
  void addCrosstabGroup(String crosstabId,
      {required bool row, required String fieldName}) {
    if (fieldName.trim().isEmpty) return;
    final CrosstabGroup g = CrosstabGroup(
      id: _ids.next('ctgroup'),
      name: fieldName,
      expression: '\$F{$fieldName}',
    );
    _updateCrosstab(crosstabId, 'Add crosstab group', (Crosstab c) => row
        ? c.copyWith(rowGroups: <CrosstabGroup>[...c.rowGroups, g])
        : c.copyWith(columnGroups: <CrosstabGroup>[...c.columnGroups, g]));
  }

  /// Removes axis level [groupId]. Refuses to remove the last level on either
  /// axis — `validate()` requires at least one on each, so the invariant is
  /// enforced here, not only by a disabled button.
  void removeCrosstabGroup(String crosstabId, String groupId) =>
      _updateCrosstab(crosstabId, 'Remove crosstab group', (Crosstab c) {
        if (c.rowGroups.any((CrosstabGroup g) => g.id == groupId)) {
          if (c.rowGroups.length == 1) return c;
          return c.copyWith(
              rowGroups: c.rowGroups
                  .where((CrosstabGroup g) => g.id != groupId)
                  .toList());
        }
        if (c.columnGroups.length == 1) return c;
        return c.copyWith(
            columnGroups: c.columnGroups
                .where((CrosstabGroup g) => g.id != groupId)
                .toList());
      });
```

`move*` clamps with `(index + delta).clamp(0, list.length - 1)` and returns the crosstab unchanged when the target equals the index — the same shape as `reorderScopeNode`. `update*` maps the matching entry through the caller's thunk. The measure family is the identical shape over `c.measures`, with `addCrosstabMeasure` defaulting to `JetCalculation.sum`.

A refusal returns the crosstab unchanged, which leaves the whole definition value-equal, which the controller's `_commit` guard already turns into "no history entry" — that is what the first test asserts.

- [ ] **Step 4: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "feat(designer): crosstab axis and measure editing API"
```

---

### Task 6: Localization keys

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_tr.arb`, `jet_print_de.arb`
- Regenerate: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations*.dart`

**Interfaces:**
- Produces the `JetPrintLocalizations` getters Tasks 7-9 call. Exact key names, all three locales:

| Key | en | tr | de |
|---|---|---|---|
| `outlineAddCrosstab` | Add crosstab | Çapraz tablo ekle | Kreuztabelle hinzufügen |
| `crosstabScopeRows` | (rows of this scope) | (bu kapsamın satırları) | (Zeilen dieses Bereichs) |
| `crosstabMoveUpHint` | Move up — above the first band a crosstab prints once, before the rows | Yukarı taşı — ilk banttan önce çapraz tablo satır döngüsünden önce bir kez yazılır | Nach oben — über dem ersten Band wird die Kreuztabelle einmal vor den Zeilen gedruckt |
| `crosstabMoveDownHint` | Move down — below the bands a crosstab prints once, after the rows | Aşağı taşı — bantların altında çapraz tablo satır döngüsünden sonra bir kez yazılır | Nach unten — unter den Bändern wird die Kreuztabelle einmal nach den Zeilen gedruckt |
| `crosstabRowGroups` | Row groups | Satır grupları | Zeilengruppen |
| `crosstabColumnGroups` | Column groups | Sütun grupları | Spaltengruppen |
| `crosstabMeasures` | Measures | Ölçüler | Kennzahlen |
| `crosstabLayout` | Layout | Yerleşim | Layout |
| `crosstabAddLevel` | Add level | Düzey ekle | Ebene hinzufügen |
| `crosstabAddMeasure` | Add measure | Ölçü ekle | Kennzahl hinzufügen |
| `crosstabSort` | Sort | Sıralama | Sortierung |
| `crosstabSortAscending` | Ascending | Artan | Aufsteigend |
| `crosstabSortDescending` | Descending | Azalan | Absteigend |
| `crosstabSortDataOrder` | Data order | Veri sırası | Datenreihenfolge |
| `crosstabShowTotal` | Show total | Toplamı göster | Summe anzeigen |
| `crosstabTotalLabel` | Total label | Toplam etiketi | Summenbezeichnung |
| `crosstabAggregate` | Aggregate | Toplama | Aggregat |
| `crosstabRowLabelWidth` | Row label width | Satır etiketi genişliği | Zeilenbeschriftungsbreite |
| `crosstabRowLabelIndent` | Row label indent | Satır etiketi girintisi | Zeilenbeschriftungseinzug |
| `crosstabMeasureColumnWidth` | Measure column width | Ölçü sütunu genişliği | Kennzahlspaltenbreite |
| `crosstabRowHeight` | Row height | Satır yüksekliği | Zeilenhöhe |
| `crosstabHeaderRowHeight` | Header row height | Başlık satırı yüksekliği | Kopfzeilenhöhe |
| `crosstabTooWide` | Wider than the page body | Sayfa gövdesinden geniş | Breiter als der Seitenkörper |

- [ ] **Step 1: Add the keys**

Add each key to all three ARBs, each with an `@key` block carrying a `description` in the English file (the repo's convention: descriptions live in the template locale). Keep the files' existing ordering convention — read the neighbours of `crosstabLabel` (en:962) and insert alongside.

- [ ] **Step 2: Regenerate**

Run: `cd packages/jet_print && flutter gen-l10n`
Expected: `jet_print_localizations.dart` and the three per-locale files gain the getters.

- [ ] **Step 3: Verify no key is generated-only**

Run:
```bash
cd packages/jet_print && for k in outlineAddCrosstab crosstabRowGroups crosstabTooWide; do
  for f in lib/src/designer/l10n/jet_print_*.arb; do grep -q "\"$k\"" $f || echo "MISSING $k in $f"; done
done
```
Expected: no output.

- [ ] **Step 4: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS (no behaviour change yet).

- [ ] **Step 5: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "i18n(designer): crosstab authoring strings in en/tr/de"
```

---

### Task 7: An interactive Outline row and the add-menu entry

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/outline_panel/rows.dart:163-215` (`_addCrosstabRow`) and the `_leafRow` builder in the same file
- Modify: `packages/jet_print/lib/src/designer/layout/panels/outline_panel/add_menus.dart` (`_addMenu`)
- Test: `packages/jet_print/test/designer/crosstab_outline_test.dart` (exists — extend it)

**Interfaces:**
- Consumes: `selectCrosstab`, `renameCrosstab`, `moveCrosstab`, `deleteCrosstab`, `createCrosstab` (Tasks 3-5); the Task 6 strings.
- Produces: widget keys `jet_print.designer.outline.crosstab.<id>` (the row, unchanged), `.up`, `.down`, `.remove` (actions), and `jet_print.designer.outline.scope.<scopeId>.add.crosstab` / `.add.crosstab.field.<name>` / `.add.crosstab.rows` (menu options).

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('tapping a crosstab row selects it', (WidgetTester tester) async {
  await tester.pumpWidget(_designerWith(_defWithCrosstab()));
  await tester.tap(find.byKey(
      const ValueKey<String>('jet_print.designer.outline.crosstab.ct1')));
  await tester.pump();
  expect(controller.selection.crosstabId, 'ct1');
});

testWidgets('the remove action deletes it', ...);       // key '...crosstab.ct1.remove'
testWidgets('the add menu offers a crosstab on the root scope only', ...);
```

Follow the existing `crosstab_outline_test.dart` harness for how the designer is pumped and how the controller is reached — do not invent a new one.

- [ ] **Step 2: Run and watch them fail**

Run: `cd packages/jet_print && flutter test test/designer/crosstab_outline_test.dart`
Expected: FAIL — the row has no tap handler, so the selection stays empty.

- [ ] **Step 3: Give `_leafRow` optional actions**

Add `List<Widget> actions = const <Widget>[]` as a named parameter, rendered in a trailing `Row` exactly the way `_branchRow` renders its own `actions` (copy that subtree so the two row kinds look identical). Element rows pass nothing and are visually unchanged.

- [ ] **Step 4: Rewrite `_addCrosstabRow`**

Replace the `Padding`/`Row` body with a `_leafRow` call:

```dart
  void _addCrosstabRow(
    List<Widget> rows,
    Crosstab crosstab,
    int depth,
    JetReportDesignerController controller,
    Selection selection,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
  ) {
    final String base = 'jet_print.designer.outline.crosstab.${crosstab.id}';
    final ShadColorScheme colors = theme.colorScheme;
    rows.add(_leafRow(
      rowKey: ValueKey<String>(base),
      depth: depth,
      icon: LucideIcons.table2,
      label: crosstabDisplayLabel(crosstab, l10n),
      rawName: crosstab.name,
      fallback: l10n.crosstabLabel,
      editing: _editingId == crosstab.id,
      onEditingEnd: () => _rebuild(() => _editingId = null),
      onCommit: (String? name) {
        controller.renameCrosstab(crosstab.id, name);
        _rebuild(() => _editingId = null);
      },
      selected: selection.crosstabId == crosstab.id,
      onSelect: () => _handleTap(
        crosstab.id,
        () => controller.selectCrosstab(crosstab.id),
        () => _rebuild(() => _editingId = crosstab.id),
      ),
      theme: theme,
      actions: <Widget>[
        _act('$base.up', LucideIcons.arrowUp, l10n.crosstabMoveUpHint,
            () => controller.moveCrosstab(crosstab.id, -1), colors),
        _act('$base.down', LucideIcons.arrowDown, l10n.crosstabMoveDownHint,
            () => controller.moveCrosstab(crosstab.id, 1), colors),
        _act('$base.remove', LucideIcons.trash2, l10n.outlineRemove,
            () => controller.deleteCrosstab(crosstab.id), colors),
      ],
    ));
  }
```

Update its call site at `rows.dart:72` to pass `controller` and `selection`, and rewrite the stale comment ("Read-only surface only (spec A, Task 13)…") to describe the authoring row.

- [ ] **Step 5: Add the menu entry**

In `_addMenu`, after the "Add list ▸" option, add — only when `scope.id == controller.definition.body.root.id` (Spec A restricts crosstabs to the root scope):

```dart
      if (scope.id == controller.definition.body.root.id)
        _MenuOption(
          optionKey: ValueKey<String>('$scopeBase.add.crosstab'),
          label: l10n.outlineAddCrosstab,
          enabled: _groupFields(controller, scope, schema).isNotEmpty ||
              listCollections.isNotEmpty,
          children: <_MenuOption>[
            _MenuOption(
              optionKey: ValueKey<String>('$scopeBase.add.crosstab.rows'),
              label: l10n.crosstabScopeRows,
              enabled: _groupFields(controller, scope, schema).isNotEmpty,
              onPick: () => controller.createCrosstab(scope.id),
            ),
            for (final FieldDef f in listCollections)
              _MenuOption(
                optionKey: ValueKey<String>(
                    '$scopeBase.add.crosstab.field.${f.name}'),
                label: f.name,
                onPick: () => controller.createCrosstab(scope.id,
                    collectionField: f.name),
              ),
          ],
        ),
```

- [ ] **Step 6: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS. If an outline golden moves, the row height changed — reconcile it here rather than deferring, since Task 11 owns canvas goldens only.

- [ ] **Step 7: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "feat(designer): select, rename, reorder and delete a crosstab from the Outline"
```

---

### Task 8: Properties inspector — identity, data, axes, measures

**Files:**
- Create: `packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/crosstab_inspector.dart`
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (imports, `part`, dispatch at ~:243, `inspectedKey` at ~:233)
- Test: `packages/jet_print/test/designer/crosstab_inspector_test.dart` (create)

**Interfaces:**
- Consumes: Tasks 3-6.
- Produces: `List<Widget> _crosstabInspector(JetReportDesignerController controller, String crosstabId, ShadThemeData theme, JetPrintLocalizations l10n, JetDataSchema? schema)`; widget keys `jet_print.designer.props.crosstab.<field>` and per-item `...crosstab.group.<groupId>.<field>` / `...crosstab.measure.<measureId>.<field>`.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('the crosstab inspector renders and renames', (WidgetTester tester) async {
  ...
  controller.selectCrosstab('ct1');
  await tester.pump();
  expect(find.byKey(const ValueKey<String>(
      'jet_print.designer.props.crosstab.name')), findsOneWidget);
  expect(find.text(l10n.crosstabRowGroups), findsOneWidget);
});
```

Copy the pump harness from `properties_editor_test.dart`.

- [ ] **Step 2: Run and watch it fail**

Run: `cd packages/jet_print && flutter test test/designer/crosstab_inspector_test.dart`
Expected: FAIL — the panel shows the empty-selection placeholder.

- [ ] **Step 3: Add the dispatch arm**

In `properties_panel.dart`, extend `inspectedKey` with `?? selection.crosstabId`, and add before the group arm:

```dart
    } else if (selection.crosstabId case final String crosstabId
        when findCrosstab(controller.definition, crosstabId) != null) {
      children =
          _crosstabInspector(controller, crosstabId, theme, l10n, schema);
```

Add `part 'properties/inspectors/crosstab_inspector.dart';` beside the element-inspector part, and the crosstab domain imports.

- [ ] **Step 4: Build the inspector's first four sections**

In the new part file, an `extension` on the panel state (match `element_inspector.dart`'s exact structure — read it first):

- **Identity** — the name text input, committing `renameCrosstab`; blank clears to the fallback.
- **Data** — a collection picker over `_scopeCollectionChoices`-style choices for the crosstab's scope, with a clear action calling `setCrosstabCollection(id, null)`; label it with `l10n.crosstabScopeRows` when null.
- **Row groups** / **Column groups** — a section header (`l10n.crosstabRowGroups` / `crosstabColumnGroups`) then one card per level: name input (`updateCrosstabGroup … copyWith(name: v)`), expression via the existing field picker plus the `fx` `expression_editor_dialog`, a sort dropdown over `CrosstabSort.values`, a show-total switch, and a total-label input **disabled while show-total is off**. Trailing per-card actions: move up, move down, remove (remove disabled when the axis has one level). A trailing "Add level ▸" menu listing the scalar fields, calling `addCrosstabGroup(id, row: …, fieldName: …)`.
- **Measures** — the same shape: name, expression, an aggregate dropdown over `JetCalculation.values.where((c) => c != JetCalculation.none)`, a format picker from `format_presets.dart`, and an "Add measure ▸" menu over the numeric fields.

Reuse `_TextInput`, `_ValueField`, the section/`RegionChrome` heading widgets and the pickers already in the panel's `part` files. Do not introduce a new styling vocabulary.

- [ ] **Step 5: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "feat(designer): crosstab Properties inspector — identity, data, axes, measures"
```

---

### Task 9: Properties inspector — layout, style, visibility, width warning

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties/inspectors/crosstab_inspector.dart`
- Test: `packages/jet_print/test/designer/crosstab_inspector_test.dart`

**Interfaces:**
- Consumes: Task 8's inspector and `setCrosstabStyle` / `setCrosstabVisible`.
- Produces: no new public names; adds the Layout, Style and Visibility sections and the localized width warning.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('the width warning appears exactly at the overflow threshold',
    (WidgetTester tester) async {
  // A4 portrait body width is 595.28 - margins; seed a crosstab whose
  // rowLabelWidth + measureColumnWidth stays under it, assert no warning,
  // then widen rowLabelWidth past it and assert the warning text appears.
  ...
  expect(find.text(l10n.crosstabTooWide), findsNothing);
  controller.setCrosstabStyle('ct1', ct.style.copyWith(rowLabelWidth: 900));
  await tester.pump();
  expect(find.text(l10n.crosstabTooWide), findsOneWidget);
});
```

Read the real body-width expression from `report_validation.dart`'s crosstab width check and use the identical formula in the test's setup so the two cannot drift.

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — the warning is never rendered.

- [ ] **Step 3: Implement the three sections**

- **Layout** — five numeric fields (`rowLabelWidth`, `rowLabelIndent`, `measureColumnWidth`, `rowHeight`, `headerRowHeight`), each committing `setCrosstabStyle(id, style.copyWith(...))`. Use the same numeric-input widget the band-height and column-layout fields use.
- **Width warning** — rendered inside the Layout section, deriving the condition locally the way `_columnDiagnostics` does:

```dart
  /// True when the crosstab cannot fit the page body even at its minimum width
  /// (the row-label column plus one column per measure). Derived here, not read
  /// from the engine's `Diagnostic`, because engine messages are not localized —
  /// the same split `_columnDiagnostics` (spec 035) already makes.
  bool _crosstabTooWide(ReportDefinition def, Crosstab ct) { ... }
```

- **Style** — header / cell / total text and box styles through the existing `style_editors.dart` widgets, each committing `setCrosstabStyle`.
- **Visibility** — the `BoolProperty` editor bands and elements already use, committing `setCrosstabVisible`.

- [ ] **Step 4: Check the German width**

Run the inspector test with a `Locale('de')` wrapper (the pattern in the preview-thumbnail tests: one isolate per non-English locale) and confirm no `RenderFlex` overflow is logged.

- [ ] **Step 5: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "feat(designer): crosstab layout, style and visibility properties"
```

---

### Task 10: Canvas selection

**Files:**
- Modify: `packages/jet_print/lib/src/designer/canvas/design_time_layout.dart`
- Modify: `packages/jet_print/lib/src/designer/canvas/design_canvas/gestures.dart:129-149`
- Modify: `packages/jet_print/lib/src/designer/canvas/design_canvas/build_helpers.dart:189-222`
- Modify: `packages/jet_print/lib/src/designer/canvas/selection_overlay.dart:120-130`
- Modify: `packages/jet_print/lib/src/designer/canvas/ruler_metrics.dart:39`
- Test: `packages/jet_print/test/designer/canvas/crosstab_selection_test.dart` (create)

**Interfaces:**
- Consumes: `Selection.crosstab`, `selectCrosstab`.
- Produces: `String? DesignTimeLayout.crosstabIdAt(JetOffset page)` and `JetRect? DesignTimeLayout.crosstabRect(String id)`.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('a tap inside the crosstab block selects it', (WidgetTester tester) async {
  ...
  await tester.tapAt(_pageToScreen(centerOfCrosstabBlock));
  await tester.pump();
  expect(controller.selection.crosstabId, 'ct1');
});

testWidgets('a tap outside it still selects the band underneath', ...);
```

Follow `crosstab_placeholder_height_test.dart` for building the layout and mapping page coordinates to screen.

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — the selection stays empty (the block is wrapped in `IgnorePointer` and no hit test exists).

- [ ] **Step 3: Implement**

- `design_time_layout.dart`: keep the already-computed `crosstabRects` map as a field, expose `crosstabRect(String id)` mirroring `bandRect`, and add `crosstabIdAt(JetOffset page)` scanning `crosstabs` for the first rect containing the point.
- `gestures.dart` `_selectEmptyTarget`: try `layout.crosstabIdAt(page)` **before** `layout.bandIdAt(page)` and call `controller.selectCrosstab` on a hit.
- `build_helpers.dart`: drop the `IgnorePointer` wrapper (the canvas gesture detector owns hit-testing, exactly as element regions do) and rewrite the stale comment.
- `selection_overlay.dart`: add a crosstab arm beside `_bandChrome`, drawing the outline with the same colours and stroke the band chrome uses. **No resize handles** — the block's size is model-derived.
- `ruler_metrics.dart`: add `if (selection.crosstabId case final String id) return layout.crosstabRect(id);` beside the band line.

- [ ] **Step 4: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS. Goldens must not move — the block's pixels are unchanged in this task; only chrome for a *selected* crosstab is new, and no golden selects one.

- [ ] **Step 5: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "feat(designer): select a crosstab on the canvas"
```

---

### Task 11: Canvas schematic

**Files:**
- Modify: `packages/jet_print/lib/src/designer/canvas/design_canvas/build_helpers.dart` (`_crosstabPlaceholders`)
- Test: `packages/jet_print/test/designer/canvas/crosstab_placeholder_height_test.dart` (extend)
- Regenerate: the designer canvas goldens that contain a crosstab

**Interfaces:**
- Consumes: Task 10's non-`IgnorePointer` block.
- Produces: no new names; the block's content changes.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('the schematic labels every axis level and measure',
    (WidgetTester tester) async {
  // A crosstab with row groups [Region, City], column groups [Year] and
  // measures [Revenue, Units].
  ...
  for (final String label in <String>['Region', 'City', 'Year', 'Revenue', 'Units']) {
    expect(find.text(label), findsWidgets);
  }
});
```

- [ ] **Step 2: Run and watch it fail**

Expected: FAIL — the block shows only the crosstab's display label.

- [ ] **Step 3: Draw the schematic**

Inside the existing `Positioned` block, replace the centered label with a column laid out at the model's own metrics, scaled by `scale`:

- one header row per column-group level at `style.headerRowHeight`, each showing that level's `name`, spanning the data-column area;
- a measure-name row at `style.headerRowHeight` when `measures.length > 1`, one cell per measure at `style.measureColumnWidth`;
- one stub row per row-group level at `style.rowHeight`, its label indented by `depth * style.rowLabelIndent` inside a left column of `style.rowLabelWidth`;
- a single trailing ellipsis row and a single trailing ellipsis column, standing in for the data-driven counts the designer cannot know;
- the crosstab's display label as a caption above the grid.

Everything is drawn from the model — no data access, no `planCrosstab` call. Clip the content to the block so an over-wide crosstab visibly overflows its rect rather than painting outside it.

- [ ] **Step 4: Regenerate the goldens**

Run: `cd packages/jet_print && flutter test --update-goldens`
Then inspect **every** changed golden: `git diff --stat` must list only goldens whose report contains a crosstab. Any other changed golden is a bug in this task — fix it rather than accepting the diff.

- [ ] **Step 5: Run the suite**

Run: `cd packages/jet_print && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock
git add -A && git commit -m "feat(designer): schematic crosstab block on the design canvas"
```

---

### Task 12: End-to-end walk, playground check and changelog

**Files:**
- Test: `packages/jet_print/test/designer/crosstab_authoring_walk_test.dart` (create)
- Modify: `packages/jet_print/CHANGELOG.md`
- Verify: `apps/jet_print_playground` suite

**Interfaces:**
- Consumes: everything.

- [ ] **Step 1: Write the end-to-end walk**

```dart
test('create, edit, add a measure, reorder, delete — then undo back', () {
  final JetReportDesignerController c = ...;   // pivot playground schema
  final ReportDefinition original = c.definition;
  c.createCrosstab(c.definition.body.root.id);
  final String id = c.selection.crosstabId!;
  c.renameCrosstab(id, 'Sales pivot');
  c.updateCrosstabGroup(id, findCrosstab(c.definition, id)!.rowGroups.single.id,
      (CrosstabGroup g) => g.copyWith(sort: CrosstabSort.descending));
  c.addCrosstabMeasure(id, fieldName: 'units');
  c.moveCrosstab(id, -1);
  c.deleteCrosstab(id);
  for (int i = 0; i < 6; i++) {
    c.undo();
  }
  expect(c.definition, original);
  final List<Diagnostic> errors = validate(c.definition)
      .where((Diagnostic d) => d.severity == DiagnosticSeverity.error)
      .toList();
  expect(errors, isEmpty);
});
```

Adjust the undo count to the number of history entries the walk actually records (a clamped `moveCrosstab` records none) — run it and read the failure before fixing the number.

- [ ] **Step 2: Run everything**

```bash
cd packages/jet_print && flutter test && dart analyze
cd ../../apps/jet_print_playground && flutter test && dart analyze
```
Expected: both suites green, analyzer clean.

- [ ] **Step 3: Changelog**

Add one bullet under `## Unreleased` describing designer crosstab authoring, matching the surrounding entries' voice.

- [ ] **Step 4: Commit**

```bash
git checkout -- packages/jet_print/pubspec.lock apps/jet_print_playground/pubspec.lock
git add -A && git commit -m "test(designer): end-to-end crosstab authoring walk"
```

---

## Self-review notes

- **Spec coverage:** §1 → Task 3; §2 → Tasks 1, 2, 4, 5; §3 → Task 7; §4 → Tasks 8, 9; §5 → Tasks 10, 11; §6 → Task 6; §7 → every task's tests plus Task 12.
- **Naming consistency:** `crosstabId` (never `ctId`) in every signature; `findCrosstab` / `mapCrosstabs` / `removeCrosstab` match `findScope` / `mapScopes` / `removeScope`; `reorderScopeNode` replaces `reorderScopeChild` everywhere in one task.
- **Risk order:** the two riskiest edits (the `reorderScopeChild` rename, and the `Selection` invariant) are Tasks 1 and 3 — early, isolated, and each with the whole suite as its net.
