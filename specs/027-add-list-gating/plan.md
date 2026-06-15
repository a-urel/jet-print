# Gate "Add list" to Bindable Collections — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Outline "+" menu's flat "Add list" becomes an "Add list ▸ collection" submenu of the collections resolvable at that scope's level; picking one creates a list bound to it. Disabled where no collection is bindable.

**Architecture:** Add a `collectionFieldsForScope` helper next to the existing `scalarFieldsForScope` (sharing one resolution core), then convert the "Add list" `_MenuOption` in `_addMenu` to a submenu exactly like 026's "Add group ▸". No controller change — `createListWithBand` already takes an optional `collectionField` and builds the bound nested scope + detail band.

**Tech Stack:** Dart / Flutter, `shadcn_ui` (`ShadContextMenuItem` hover submenus), `flutter_test` widget tests. This is a near-exact parallel of spec 026 Task 3.

**Conventions:** Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (the `flutter` tool leaves cwd inside the package). Branch is already `027-add-list-gating`.

---

## File Map

- `packages/jet_print/lib/src/designer/layout/panels/scope_field_choices.dart` — **modify**: extract a shared `_inScopeFields` core; keep `scalarFieldsForScope`; add `collectionFieldsForScope`.
- `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart` — **modify**: in `_addMenu`, replace the flat "Add list" option with a collection submenu (+ a `listCollections` local).
- `packages/jet_print/test/designer/outline_add_list_group_test.dart` — **modify**: rewrite the "Add list" test for the submenu; add a disabled-when-no-collection test.

---

## Task 1: Outline "Add list" → bound-collection submenu

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/scope_field_choices.dart`
- Modify: `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart`
- Test (modify): `packages/jet_print/test/designer/outline_add_list_group_test.dart`

- [ ] **Step 1: Update the Outline widget test (write the failing tests first)**

In `outline_add_list_group_test.dart`:

(a) Add a scalars-only schema constant after the existing `_collectionsOnly` constant:

```dart
// A schema with no collection field anywhere — nothing for a list to bind to.
const JetDataSchema _scalarsOnly = JetDataSchema(
  name: 'Flat',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('customerName', type: JetFieldType.string),
  ],
);
```

(b) Replace the entire existing `testWidgets('scope "+" "Add list" creates a nested list with a detail band', ...)` block with these two tests:

```dart
  testWidgets('"Add list ▸ lines" creates a nested list bound to that collection',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _hover(tester, 'jet_print.designer.outline.scope.root.add.list');
    await _tapKey(tester,
        'jet_print.designer.outline.scope.root.add.list.field.lines');

    final List<NestedScope> nested =
        c.definition.body.root.children.whereType<NestedScope>().toList();
    expect(nested, hasLength(1));
    expect(nested.single.scope.collectionField, 'lines',
        reason: 'the list is born bound to the picked collection');
  });

  testWidgets('"Add list" creates nothing when no collection is in scope',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _scalarsOnly);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _hover(tester, 'jet_print.designer.outline.scope.root.add.list');

    // No collection child renders, and no unbound list is created (disabled).
    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.scope.root.add.list.field.invoiceNo')),
        findsNothing);
    expect(c.definition.body.root.children.whereType<NestedScope>(), isEmpty);
  });
```

(The `_invoice`, `_collectionsOnly` schemas, the `_tapKey`/`_hover`/`_openOutline` helpers, and the two "Add group" tests already exist in this file from 026 — leave them.)

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/designer/outline_add_list_group_test.dart`
Expected: the new "Add list ▸ lines" test FAILS — the key `…add.list.field.lines` is not found (today "Add list" is a flat option, not a submenu).

- [ ] **Step 3a: Add `collectionFieldsForScope` (refactor the helper)**

Replace the ENTIRE contents of `scope_field_choices.dart` with:

```dart
/// Scope-level field resolution for the Outline "+" menu submenus: the scalar
/// fields a new group may key on ([scalarFieldsForScope]) and the collection
/// fields a new child list may iterate ([collectionFieldsForScope]). Both read
/// the fields resolvable at a scope's level and filter by kind, so the Outline
/// menu offers only schema-correct, bindable choices. Empty when no schema is
/// attached or the scope does not resolve.
library;

import '../../../data/binding_scope.dart';
import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../../domain/detail_scope.dart';
import '../../../domain/report_definition.dart';
import '../../controller/band_walker.dart';

/// All fields resolvable at [scopeId]'s level — the shared core of the two
/// filters below. Empty when no schema is attached or the scope does not
/// resolve.
List<FieldDef> _inScopeFields(
  JetDataSchema? schema,
  ReportDefinition def,
  String scopeId,
) {
  if (schema == null) return const <FieldDef>[];
  final List<DetailScope> chain = scopePathToScope(def, scopeId);
  if (chain.isEmpty) return const <FieldDef>[];
  return fieldsInScopeForChain(schema, chain);
}

/// The scalar (non-collection) fields a new group on [scopeId] may key on.
List<FieldDef> scalarFieldsForScope(
  JetDataSchema? schema,
  ReportDefinition def,
  String scopeId,
) =>
    <FieldDef>[
      for (final FieldDef f in _inScopeFields(schema, def, scopeId))
        if (f.type != JetFieldType.collection) f,
    ];

/// The collection fields a new child list of [scopeId] may iterate.
List<FieldDef> collectionFieldsForScope(
  JetDataSchema? schema,
  ReportDefinition def,
  String scopeId,
) =>
    <FieldDef>[
      for (final FieldDef f in _inScopeFields(schema, def, scopeId))
        if (f.type == JetFieldType.collection) f,
    ];
```

(`JetFieldType` resolves transitively through the data-layer imports — this file already used `JetFieldType.collection` without a direct `value_type.dart` import in 026, and the analyzer was clean.)

- [ ] **Step 3b: Convert "Add list" to a submenu in `_addMenu`**

In `outline_panel.dart`, inside `_addMenu`, find the line that computes the group fields local:

```dart
    final List<FieldDef> groupFields = _groupFields(controller, scope, schema);
```

and add the list collections local right after it:

```dart
    final List<FieldDef> listCollections =
        collectionFieldsForScope(schema, controller.definition, scope.id);
```

Then replace the flat "Add list" option:

```dart
      _MenuOption(
        optionKey: ValueKey<String>('$scopeBase.add.list'),
        label: l10n.outlineAddList,
        onPick: () => controller.createListWithBand(scope.id),
      ),
```

with the submenu:

```dart
      _MenuOption(
        optionKey: ValueKey<String>('$scopeBase.add.list'),
        label: l10n.outlineAddList,
        enabled: listCollections.isNotEmpty,
        children: <_MenuOption>[
          for (final FieldDef f in listCollections)
            _MenuOption(
              optionKey:
                  ValueKey<String>('$scopeBase.add.list.field.${f.name}'),
              label: f.name,
              onPick: () => controller.createListWithBand(scope.id,
                  collectionField: f.name),
            ),
        ],
      ),
```

(`collectionFieldsForScope` comes from the already-imported `scope_field_choices.dart`; `_MenuOption`'s `children`/`enabled` and the `_TypeMenu` submenu rendering already exist from 026. No new imports.)

- [ ] **Step 4: Run the test to verify it PASSES**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test test/designer/outline_add_list_group_test.dart`
Expected: PASS (4 tests — two "Add list", two "Add group"). If the hover-driven submenu is timing-sensitive, raise the `_hover` pump to `Duration(milliseconds: 400)` (same note as 026).

- [ ] **Step 5: Analyzer is clean**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && dart analyze lib/src/designer/layout/panels/scope_field_choices.dart lib/src/designer/layout/panels/outline_panel.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/scope_field_choices.dart packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart packages/jet_print/test/designer/outline_add_list_group_test.dart
git commit -m "feat(designer): Outline 'Add list' is a bound-collection submenu"
```

---

## Task 2: Full verification sweep

**Files:** none (verification only).

- [ ] **Step 1: Whole-package analyzer**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 2: Full test suite**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && flutter test`
Expected: all tests pass (this is an authoring-only UI change). If any **golden** test fails, inspect it — there should be none, since no rendered output changed; do NOT blindly regenerate. Investigate any failure before proceeding.

- [ ] **Step 3: Confirm the success criteria**

Run: `cd /Users/ahmeturel/Projects/oss/jet-print/packages/jet_print && grep -n "createListWithBand(scope.id)" lib/src/designer/layout/panels/outline_panel.dart`
Expected: no output — the Outline no longer creates an unbound list (the only remaining `createListWithBand(scope.id)` without a `collectionField` is the Data Source path's resolved-scope call and tests, not this menu). Manual GUI confirmation (optional): in the playground, Outline "+" → "Add list" lists collections under root and is disabled inside `lines`.

---

## Self-Review

- **Spec coverage:** FR-001 → Task 1 Step 3a (`collectionFieldsForScope` + shared `_inScopeFields`). FR-002 → Task 1 Step 3b (submenu + `createListWithBand(collectionField:)` + `add.list.field.<name>` key). FR-003 → Task 1 Step 3b (`enabled: listCollections.isNotEmpty`) + Step 1 disabled test. FR-004 → no controller change (Step 3b reuses `createListWithBand`). US1 → Task 1 tests. SC-001/SC-002 → the bound submenu + disabled test + Task 2 Step 3 grep. SC-003 → "Add list" now mirrors "Add group ▸".
- **Placeholder scan:** none — every step has concrete code or an exact command + expected output.
- **Type consistency:** `collectionFieldsForScope(JetDataSchema?, ReportDefinition, String)` matches `scalarFieldsForScope`'s signature and is called identically in `_addMenu`. The widget-key scheme `…add.list.field.<name>` matches between implementation (Step 3b) and tests (Step 1). `createListWithBand(scope.id, collectionField: f.name)` uses the existing method's existing parameter.
