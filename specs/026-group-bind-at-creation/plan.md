# Bind Groups to a Field at Creation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every group a report author creates is born keyed to a real scalar field (`$F{field}`) and named after it, from two entry points (Outline "Add group ▸" submenu + Data Source per-scalar-field "＋ group"), removing the unbound placeholder (`key: '0'`) creation path.

**Architecture:** One schema-agnostic controller action `createGroupBoundToField(scopeId, fieldName)` does the creation; both UI entry points call it. A shared helper `scalarFieldsForScope` resolves the offerable fields (scope chain ∩ schema, collections excluded) so the two entries offer identical choices. The Outline "+" menu gains a nested submenu; the Data Source scalar row gains a trailing affordance. The old `createGroupWithHeader` (placeholder `'0'`) is deleted and its four test callers migrated.

**Tech Stack:** Dart / Flutter, `shadcn_ui` 0.53.x (`ShadContextMenuItem` supports `items:` submenus + `enabled:`), `flutter_test` widget tests, `flutter gen-l10n` ARB localization.

**Conventions:** Run all `flutter`/`dart` commands from `packages/jet_print`. Run all `git` commands from the repo root `/Users/ahmeturel/Projects/oss/jet-print` (the `flutter` tool leaves the cwd inside the package). Branch is already `026-group-bind-at-creation`.

---

## File Map

- `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` — **modify**: add `createGroupBoundToField`; **delete** `createGroupWithHeader` (Task 5).
- `packages/jet_print/lib/src/designer/layout/panels/scope_field_choices.dart` — **create**: shared `scalarFieldsForScope` helper.
- `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart` — **modify**: `_MenuOption` (+`children`,`enabled`, nullable `onPick`), `_TypeMenu` recursive item build, `_addMenu` builds the "Add group ▸" submenu.
- `packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart` — **modify**: thread `parentCollection` into `_FieldRow`; add scalar "＋ group" affordance + `_boundScopeForField`.
- `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb` / `_tr.arb` / `_de.arb` — **modify**: add `dataSourceAddGroup`.
- Tests — **create** `create_group_bound_to_field_test.dart`, `datasource_add_group_test.dart`; **modify** `outline_add_list_group_test.dart`, `group_source_test.dart`, `acceptance_invoice_from_blank_test.dart`, `set_group_name_test.dart`; **delete** `create_group_with_header_test.dart`.

---

## Task 1: Controller action `createGroupBoundToField`

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (insert after `createGroupWithHeader`, ~line 796)
- Test: `packages/jet_print/test/designer/controller/create_group_bound_to_field_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/controller/create_group_bound_to_field_test.dart`:

```dart
// Controller unit test: createGroupBoundToField adds a group keyed to a scalar
// field ($F{field}), named after it, plus a selected header band — one undo step.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('adds a group keyed to the field, named after it, header selected', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);

    c.createGroupBoundToField(c.definition.body.root.id, 'invoiceNo');

    final List<GroupLevel> groups = c.definition.body.root.groups;
    expect(groups, hasLength(1));
    final GroupLevel g = groups.single;
    expect(g.name, 'invoiceNo');
    expect(g.key, r'$F{invoiceNo}');
    expect(g.header, isNotNull, reason: 'the group has a header band');
    expect(g.header!.type, BandType.groupHeader);
    expect(c.selection.bandId, g.header!.id,
        reason: 'the header band is selected');
  });

  test('is one undo step', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.createGroupBoundToField(c.definition.body.root.id, 'invoiceNo');
    c.undo();
    expect(c.definition, before);
  });

  test('no-op for an unknown scope', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.createGroupBoundToField('nope', 'invoiceNo');
    expect(c.definition, before);
  });

  test('no-op for a blank field name', () {
    final JetReportDesignerController c = JetReportDesignerController();
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.createGroupBoundToField(c.definition.body.root.id, '');
    expect(c.definition, before);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/controller/create_group_bound_to_field_test.dart`
Expected: FAIL — `The method 'createGroupBoundToField' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

In `jet_report_designer_controller.dart`, immediately after the closing brace of `createGroupWithHeader` (~line 796), insert:

```dart
  /// Creates a group level on scope [scopeId] keyed to scalar field [fieldName]
  /// (`$F{fieldName}`) and named after it, together with its header band, and
  /// selects the header band — as ONE undoable step. The data-bound creation
  /// path: every authored group is born resolvable against the data source
  /// (spec 026), replacing the placeholder-key path. A no-op for an unknown
  /// scope or a blank [fieldName].
  void createGroupBoundToField(String scopeId, String fieldName) {
    if (fieldName.isEmpty) return;
    if (findScope(_document.definition, scopeId) == null) return;
    final String groupId = _ids.next('group');
    final Band header = Band(
        id: _ids.next('band'),
        type: BandType.groupHeader,
        height: _defaultBandHeight(BandType.groupHeader));
    final GroupLevel group = GroupLevel(
      id: groupId,
      name: fieldName,
      key: '\$F{$fieldName}',
      header: header,
    );
    _commit(DefinitionEditCommand(
      label: 'Add group',
      transform: (ReportDefinition d) => addGroup(d, scopeId, group),
      selection: Selection.band(header.id),
    ));
  }
```

Note: `'\$F{$fieldName}'` yields `$F{invoiceNo}` — `\$` is a literal dollar, `$fieldName` interpolates. Matches the canonical 005a binding form (`value_template_compiler.dart:99`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/controller/create_group_bound_to_field_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart packages/jet_print/test/designer/controller/create_group_bound_to_field_test.dart
git commit -m "feat(designer): createGroupBoundToField — born bound to a field"
```

---

## Task 2: Localization string for the Data Source affordance

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_en.arb`, `jet_print_tr.arb`, `jet_print_de.arb`
- Regenerate: `lib/src/designer/l10n/jet_print_localizations*.dart` via `flutter gen-l10n`

- [ ] **Step 1: Add the English key (template)**

In `jet_print_en.arb`, immediately after the `dataSourceAddList` block (the `"@dataSourceAddList": { ... }` object, ~line 842), insert:

```json
  "dataSourceAddGroup": "Add as group",
  "@dataSourceAddGroup": {
    "description": "Data Source scalar field action: create a group level keyed to this field."
  },
```

- [ ] **Step 2: Add the Turkish + German values**

In `jet_print_tr.arb`, after its `dataSourceAddList` entry, add:

```json
  "dataSourceAddGroup": "Grup olarak ekle",
```

In `jet_print_de.arb`, after its `dataSourceAddList` entry, add:

```json
  "dataSourceAddGroup": "Als Gruppe hinzufügen",
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd packages/jet_print && flutter gen-l10n`
Expected: no errors; `JetPrintLocalizations.dataSourceAddGroup` now exists in the generated `jet_print_localizations*.dart`.

- [ ] **Step 4: Verify it compiles**

Run: `cd packages/jet_print && dart analyze lib/src/designer/l10n`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/l10n
git commit -m "feat(designer,l10n): dataSourceAddGroup string (en/tr/de)"
```

---

## Task 3: Outline "Add group ▸" field submenu

**Files:**
- Create: `packages/jet_print/lib/src/designer/layout/panels/scope_field_choices.dart`
- Modify: `packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart`
- Test (modify): `packages/jet_print/test/designer/outline_add_list_group_test.dart`

- [ ] **Step 1: Write the shared field-resolution helper**

Create `packages/jet_print/lib/src/designer/layout/panels/scope_field_choices.dart`:

```dart
/// Resolves the scalar (non-collection) fields a new group on a scope may key
/// on: the fields in scope at [scopeId] per the data [schema], with collection
/// fields excluded. Shared by the Outline "Add group" submenu and the Data
/// Source scalar "＋ group" affordance so both offer identical, schema-correct
/// choices. Empty when no schema is attached or the scope does not resolve.
library;

import '../../../data/binding_scope.dart';
import '../../../data/data_schema.dart';
import '../../../data/field_def.dart';
import '../../../domain/detail_scope.dart';
import '../../../domain/report_definition.dart';
import '../../../domain/value_type.dart';
import '../../controller/band_walker.dart';

List<FieldDef> scalarFieldsForScope(
  JetDataSchema? schema,
  ReportDefinition def,
  String scopeId,
) {
  if (schema == null) return const <FieldDef>[];
  final List<DetailScope> chain = scopePathToScope(def, scopeId);
  if (chain.isEmpty) return const <FieldDef>[];
  return <FieldDef>[
    for (final FieldDef f in fieldsInScopeForChain(schema, chain))
      if (f.type != JetFieldType.collection) f,
  ];
}
```

- [ ] **Step 2: Extend `_MenuOption` to carry a submenu + enabled flag**

In `outline_panel.dart`, replace the `_MenuOption` class (currently ~lines 519-530) with:

```dart
/// One option in a [_TypeMenu]. A leaf option carries an [onPick]; a submenu
/// parent carries [children] (and no [onPick]). [enabled] greys a parent out
/// (e.g. "Add group" when no scalar field is in scope).
class _MenuOption {
  const _MenuOption({
    required this.optionKey,
    required this.label,
    this.onPick,
    this.children = const <_MenuOption>[],
    this.enabled = true,
  });

  final Key optionKey;
  final String label;
  final VoidCallback? onPick;
  final List<_MenuOption> children;
  final bool enabled;
}
```

- [ ] **Step 3: Make `_TypeMenu` render submenus + disabled items**

In `outline_panel.dart`, in `_TypeMenuState.build`, replace the `items:` list (currently ~lines 568-578) with a call to a recursive builder:

```dart
      items: <Widget>[
        for (final _MenuOption opt in widget.options) _item(opt),
      ],
```

and add this method to `_TypeMenuState` (above `build`):

```dart
  Widget _item(_MenuOption opt) => ShadContextMenuItem(
        key: opt.optionKey,
        enabled: opt.enabled,
        onPressed: opt.children.isEmpty
            ? () {
                _menu.hide();
                opt.onPick?.call();
              }
            : null,
        items: <Widget>[for (final _MenuOption c in opt.children) _item(c)],
        child: Text(opt.label),
      );
```

(`ShadContextMenuItem` opens its submenu on hover when `items` is non-empty, and closes on a leaf tap because `closeOnTap` defaults to `items.isEmpty == true`.)

- [ ] **Step 4: Build the "Add group ▸" submenu in `_addMenu`**

In `outline_panel.dart`:

(a) Add the import near the other panel imports:

```dart
import 'scope_field_choices.dart';
```

and ensure the schema scope import is present (add if missing):

```dart
import '../../designer_schema_scope.dart';
```

(b) Add a `schema` parameter to `_addMenu` (signature currently ~line 188):

```dart
  Widget _addMenu(
    JetReportDesignerController controller,
    DetailScope scope,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
    JetDataSchema? schema,
  ) {
```

(c) Replace the single "Add group" `_MenuOption` (currently ~lines 211-215) with a submenu:

```dart
      _MenuOption(
        optionKey: ValueKey<String>('$scopeBase.add.group'),
        label: l10n.outlineAddGroup,
        enabled: _groupFields(controller, scope, schema).isNotEmpty,
        children: <_MenuOption>[
          for (final FieldDef f in _groupFields(controller, scope, schema))
            _MenuOption(
              optionKey:
                  ValueKey<String>('$scopeBase.add.group.field.${f.name}'),
              label: f.name,
              onPick: () =>
                  controller.createGroupBoundToField(scope.id, f.name),
            ),
        ],
      ),
```

(d) Add the private helper next to `_addMenu`:

```dart
  List<FieldDef> _groupFields(
    JetReportDesignerController controller,
    DetailScope scope,
    JetDataSchema? schema,
  ) =>
      scalarFieldsForScope(schema, controller.definition, scope.id);
```

(e) Add the `FieldDef` import if not already present:

```dart
import '../../../data/field_def.dart';
import '../../../data/data_schema.dart';
```

(f) At the `_addMenu` call site (currently ~line 151, `actions: <Widget>[_addMenu(controller, scope, theme, l10n)]`), pass the schema read from context:

```dart
      actions: <Widget>[
        _addMenu(controller, scope, theme, l10n,
            DesignerSchemaScope.of(context)),
      ],
```

If the enclosing method does not already have a `BuildContext context` in scope, thread it from the nearest `build` (the same context already used to obtain `theme`/`l10n`).

- [ ] **Step 5: Run the analyzer**

Run: `cd packages/jet_print && dart analyze lib/src/designer/layout/panels`
Expected: "No issues found!"

- [ ] **Step 6: Rewrite the Outline widget test**

Replace `packages/jet_print/test/designer/outline_add_list_group_test.dart` with:

```dart
// Widget test: the Outline scope "+" menu creates a nested list, and "Add group"
// is a field submenu that creates a group bound to the picked field; with no
// scalar field in scope it is disabled (no placeholder group).
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

// A schema whose root exposes only a collection — no scalar field to group by.
const JetDataSchema _collectionsOnly = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

Future<void> _tapKey(WidgetTester tester, String key) async {
  final Finder f = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

// shadcn submenus open on hover; move a synthetic mouse over the item and wait
// past its show delay (100ms).
Future<void> _hover(WidgetTester tester, String key) async {
  final TestGesture g =
      await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: Offset.zero);
  addTearDown(g.removePointer);
  await g.moveTo(tester.getCenter(find.byKey(ValueKey<String>(key))));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Future<void> _openOutline(WidgetTester tester) async {
  await tester.tap(find.text('Outline').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('scope "+" "Add list" creates a nested list with a detail band',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add.list');

    expect(
        c.definition.body.root.children.whereType<NestedScope>(), hasLength(1));
  });

  testWidgets('"Add group ▸ invoiceNo" creates a group bound to that field',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _hover(tester, 'jet_print.designer.outline.scope.root.add.group');
    await _tapKey(
        tester, 'jet_print.designer.outline.scope.root.add.group.field.invoiceNo');

    final List<GroupLevel> groups = c.definition.body.root.groups;
    expect(groups, hasLength(1));
    expect(groups.single.name, 'invoiceNo');
    expect(groups.single.key, r'$F{invoiceNo}');
    expect(groups.single.header, isNotNull);
  });

  testWidgets('"Add group" offers no fields and creates nothing when only '
      'collections are in scope', (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _collectionsOnly);
    await _openOutline(tester);

    await _tapKey(tester, 'jet_print.designer.outline.scope.root.add');
    await _hover(tester, 'jet_print.designer.outline.scope.root.add.group');

    // No field child renders, and no group is created (disabled, no placeholder).
    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.outline.scope.root.add.group.field.description')),
        findsNothing);
    expect(c.definition.body.root.groups, isEmpty);
  });
}
```

- [ ] **Step 7: Run the Outline test**

Run: `cd packages/jet_print && flutter test test/designer/outline_add_list_group_test.dart`
Expected: PASS (3 tests). If the submenu hover proves timing-sensitive, raise the `_hover` pump to `Duration(milliseconds: 400)`.

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/scope_field_choices.dart packages/jet_print/lib/src/designer/layout/panels/outline_panel.dart packages/jet_print/test/designer/outline_add_list_group_test.dart
git commit -m "feat(designer): Outline 'Add group' is a bound-field submenu"
```

---

## Task 4: Data Source scalar "＋ group" affordance

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart`
- Test: `packages/jet_print/test/designer/datasource_add_group_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/datasource_add_group_test.dart`:

```dart
// Widget test: a scalar field in the Data Source panel offers a "+ group" that
// creates a group bound to that field under the right scope; a scalar inside a
// collection with no bound scope offers no such affordance.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

import 'support/designer_harness.dart';

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

void main() {
  testWidgets('"+ group" on a top-level scalar creates a root group bound to it',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);

    final Finder add = find.byKey(const ValueKey<String>(
        'jet_print.designer.datasource.addGroup.invoiceNo'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    final List<GroupLevel> groups = c.definition.body.root.groups;
    expect(groups, hasLength(1));
    expect(groups.single.name, 'invoiceNo');
    expect(groups.single.key, r'$F{invoiceNo}');
  });

  testWidgets('a scalar inside a collection with no bound scope offers no '
      '"+ group"', (WidgetTester tester) async {
    await pumpDesignerWith(tester, dataSchema: _invoice);
    // Expand the `lines` collection so its child `description` row renders.
    await tester.tap(find.text('lines'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey<String>(
            'jet_print.designer.datasource.addGroup.description')),
        findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/jet_print && flutter test test/designer/datasource_add_group_test.dart`
Expected: FAIL — the `addGroup.invoiceNo` key is not found.

- [ ] **Step 3: Thread `parentCollection` into `_FieldRow`**

In `data_source_panel.dart`, in `_fieldNode`, change the leaf return (currently line 80) to pass the parent collection:

```dart
  return _FieldRow(field: field, depth: depth, parentCollection: parentCollection);
```

Update `_FieldRow`'s constructor + fields (currently ~lines 97-101):

```dart
class _FieldRow extends StatelessWidget {
  const _FieldRow(
      {required this.field, required this.depth, this.parentCollection});

  final FieldDef field;
  final int depth;
  final String? parentCollection;
```

- [ ] **Step 4: Add the affordance + scope resolver**

In `_FieldRow.build`, after the trailing type-token `Text(...)` inside the `Row` `children` (currently ~lines 127-130), append a conditional "＋ group" affordance. First obtain the controller/definition and target scope at the top of `build`:

```dart
    final JetReportDesignerController controller = DesignerScope.of(context);
    final String? targetScope =
        _boundScopeForField(controller.definition, parentCollection);
    final JetPrintLocalizations l10n = JetPrintLocalizations.of(context);
```

Then add, as the last child of the `Row` (after the type-token `Text`):

```dart
          if (targetScope != null) ...<Widget>[
            const SizedBox(width: 6),
            Semantics(
              button: true,
              label: l10n.dataSourceAddGroup,
              child: GestureDetector(
                key: ValueKey<String>(
                    'jet_print.designer.datasource.addGroup.${field.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => DesignerScope.of(context, listen: false)
                    .createGroupBoundToField(targetScope, field.name),
                child: Icon(LucideIcons.plus,
                    size: 14, color: colors.mutedForeground),
              ),
            ),
          ],
```

Add the scope resolver as a top-level function near `_resolveParentScope` (after line 248):

```dart
/// The scope a new group keyed on a scalar field should attach to: the root
/// scope for a top-level field ([parentCollection] null), or the scope already
/// bound to [parentCollection]. Null when a nested field's collection has no
/// bound scope yet — there is nowhere to put the group, so no affordance shows.
String? _boundScopeForField(ReportDefinition def, String? parentCollection) {
  if (parentCollection == null) return def.body.root.id;
  String? found;
  void walk(DetailScope s) {
    found ??= s.collectionField == parentCollection ? s.id : null;
    for (final ScopeNode n in s.children) {
      if (n is NestedScope) walk(n.scope);
    }
  }

  walk(def.body.root);
  return found;
}
```

Confirm `data_source_panel.dart` already imports `LucideIcons`, `DesignerScope`, `JetPrintLocalizations`, `ReportDefinition`, `DetailScope`, `ScopeNode`/`NestedScope` (it uses all of these elsewhere in the file); add the controller import `../../controller/jet_report_designer_controller.dart` only if `JetReportDesignerController` is not already imported.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd packages/jet_print && flutter test test/designer/datasource_add_group_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the analyzer**

Run: `cd packages/jet_print && dart analyze lib/src/designer/layout/panels/data_source_panel.dart`
Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart packages/jet_print/test/designer/datasource_add_group_test.dart
git commit -m "feat(designer): Data Source scalar '+ group' affordance"
```

---

## Task 5: Remove `createGroupWithHeader` (placeholder path) + migrate callers

No UI calls `createGroupWithHeader` after Task 3. Delete it and migrate its four test callers to the bound path (or the lower-level `createGroup`).

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart`
- Delete: `packages/jet_print/test/designer/controller/create_group_with_header_test.dart`
- Modify: `group_source_test.dart`, `acceptance_invoice_from_blank_test.dart`, `set_group_name_test.dart`

- [ ] **Step 1: Migrate `acceptance_invoice_from_blank_test.dart`**

Replace these three lines (currently ~lines 16-18):

```dart
    c.createGroupWithHeader(root);
    final String groupId = c.definition.body.root.groups.single.id;
    c.setGroupKey(groupId, r'$F{invoiceNo}');
```

with the single bound call (it sets the same `$F{invoiceNo}` key):

```dart
    c.createGroupBoundToField(root, 'invoiceNo');
```

- [ ] **Step 2: Migrate `set_group_name_test.dart`**

In the `grouped()` helper, replace:

```dart
    c.createGroupWithHeader(c.definition.body.root.id);
```

with:

```dart
    c.createGroupBoundToField(c.definition.body.root.id, 'invoiceNo');
```

In the first test, the post-undo baseline name is now the field name, so change:

```dart
    expect(c.definition.body.root.groups.single.name, groupId);
```

to:

```dart
    expect(c.definition.body.root.groups.single.name, 'invoiceNo');
```

(Remove the now-unused `groupId` local if the analyzer flags it: the line `final String groupId = ...` stays — it is still used by `setGroupName(groupId, 'invoice')`. Only the post-undo expectation changes.)

- [ ] **Step 3: Migrate `group_source_test.dart`**

(a) In `_withGroupSelected`, replace:

```dart
  c.createGroupWithHeader(c.definition.body.root.id); // selects the header band
```

with:

```dart
  c.createGroupBoundToField(
      c.definition.body.root.id, 'invoiceNo'); // selects the header band
```

(b) The second test asserted the *creation-time* placeholder `'0'`. Since groups are now born bound, source the non-field key explicitly to keep testing "a non-field key stays editable, and the picker stores `$F{field}`". Replace the whole second `testWidgets(...)` body (currently ~lines 47-66) with:

```dart
  testWidgets(
      'a non-field key shows editable and the picker stores \$F{field}',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _withGroupSelected(tester);
    // A constant expression is a valid but non-field key — set it manually.
    c.setGroupKey(c.definition.body.root.groups.single.id, '0');
    await tester.pumpAndSettle();

    final ShadInput keyInput = tester.widget<ShadInput>(find.byKey(
        const ValueKey<String>(
            'jet_print.designer.properties.field.groupKey')));
    expect(keyInput.controller!.text, '0');
    expect(keyInput.readOnly, isFalse,
        reason: 'a non-field key stays editable');

    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.groupKey.pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.groupKey.pick.invoiceNo')));
    await tester.pumpAndSettle();

    expect(_key(c), r'$F{invoiceNo}');
  });
```

(The first "rename" test and the third "manual edit" test are unaffected — they assert behaviour of `setGroupName`/`setGroupKey`, which are unchanged. Update the file's top comment to drop the "placeholder '0' key" phrasing if desired.)

- [ ] **Step 4: Delete the dedicated placeholder test**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git rm packages/jet_print/test/designer/controller/create_group_with_header_test.dart
```

- [ ] **Step 5: Delete `createGroupWithHeader`**

In `jet_report_designer_controller.dart`, delete the entire `createGroupWithHeader` method (its doc comment ~lines 773-777 plus the method body ~lines 778-796).

- [ ] **Step 6: Run the affected tests**

Run:
```bash
cd packages/jet_print && flutter test \
  test/designer/group_source_test.dart \
  test/designer/acceptance_invoice_from_blank_test.dart \
  test/designer/controller/set_group_name_test.dart
```
Expected: PASS, all three files.

- [ ] **Step 7: Verify no stray references remain**

Run: `cd packages/jet_print && grep -rn "createGroupWithHeader" lib test`
Expected: no output.

- [ ] **Step 8: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add -A packages/jet_print/lib packages/jet_print/test
git commit -m "refactor(designer): remove placeholder createGroupWithHeader path"
```

---

## Task 6: Full verification sweep

**Files:** none (verification only).

- [ ] **Step 1: Analyzer is clean**

Run: `cd packages/jet_print && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 2: Full test suite is green**

Run: `cd packages/jet_print && flutter test`
Expected: all tests pass. If any **golden** test fails because it had captured a group created with the old placeholder key, inspect the diff to confirm the only change is `key: '0'` → `key: $F{...}` (an authoring-state change, never rendered pixels), then regenerate: `flutter test --update-goldens` and re-run `flutter test` to confirm green.

- [ ] **Step 3: Confirm the success criteria**

Run: `cd packages/jet_print && grep -rn "key: '0'\|key: \"0\"" lib test`
Expected: no authoring code path constructs a `'0'` group key (SC-001). Manual GUI confirmation (optional, deferred): open the playground, Outline "+" → "Add group ▸" lists fields; Data Source scalar shows "＋ group"; both create a group whose key resolves.

- [ ] **Step 4: Final commit (if goldens changed)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add -A packages/jet_print
git commit -m "test(designer): regenerate goldens for bound group keys"
```

(Skip this commit if Step 2 reported no golden changes.)

---

## Self-Review

- **Spec coverage:** FR-001 → Task 1. FR-002 → Task 3 (submenu). FR-003 → Task 3 (disabled when empty, Step 6 third test). FR-004 → Task 4. FR-005 → Task 5. FR-006 → Task 1 (`$F{field}`). US1 → Tasks 1+3. US2 → Task 4. SC-001 → Tasks 5 + 6/Step 3. SC-002 → Tasks 1/3/4 assertions. SC-003 → Task 4 (symmetry with lists).
- **Placeholder scan:** none — every step has concrete code or an exact command + expected output.
- **Type consistency:** `createGroupBoundToField(String, String)` is defined in Task 1 and called identically in Tasks 3, 4, 5. `scalarFieldsForScope(JetDataSchema?, ReportDefinition, String)` defined in Task 3 Step 1, called in Task 3 Step 4. `_MenuOption` gains `children`/`enabled`/nullable `onPick` in Task 3 Step 2 before use in Step 4. Widget keys (`...add.group.field.<name>`, `...datasource.addGroup.<name>`) match between implementation and tests.
