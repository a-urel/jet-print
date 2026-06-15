# Group Source Affordances + Field-Format Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a group's source a schema field-picker and a rename field (symmetric to the list binding), and standardize every binding input on the `[fieldName]` shorthand so the inspector speaks the same field language as the canvas.

**Architecture:** UI-only, in `properties_panel.dart` + one new designer-layer controller method (`setGroupName`). The group key field gets a `_FieldPicker` (scalar fields in scope) and the `[field]`⇄`$F{field}` compile machinery already used by the element value field. The shared `_BindingField` (collection + image bindings) is switched to display/accept `[name]` while still storing the bare name. No domain/codec/schema change; render goldens stay byte-identical (binding fields render only on selection).

**Tech Stack:** Dart/Flutter, `shadcn_ui`, `flutter gen-l10n` (.arb), `flutter_test` widget tests. Library: `packages/jet_print`.

---

## Design source

Implements [docs/superpowers/specs/2026-06-15-group-source-affordances-design.md](../specs/2026-06-15-group-source-affordances-design.md). Continues on branch `025-designer-authoring-affordances`; the branch is finished after this lands.

## Key facts (verified)

- **Compile machinery** in `packages/jet_print/lib/src/designer/template/value_template_compiler.dart`, already imported by `properties_panel.dart` (line 38):
  - `reverseCompile(String expression) → ValueDisplay` where `ValueDisplay{ String text; bool editable; }`. A simple `$F{field}` → `ValueDisplay('[field]', editable: true)`. **Any other expression** (a number like `'0'`, a composite like `YEAR($F{date})`) → `ValueDisplay('{$expression}', editable: false)`. ← we must NOT show the read-only `{…}` form for the group key; show the raw key instead.
  - `parseValueField(String raw) → ValueParse` (sealed: `LiteralValue(String text)` | `BindingValue(String expression)`). `'[invoiceNo]'` → `BindingValue('$F{invoiceNo}')`; `'$F{x}'` → `LiteralValue('$F{x}')`; `'0'` → `LiteralValue('0')`. For a group key, both arms yield the right stored 005a string (BindingValue → its expression; LiteralValue → its text, which IS the verbatim expression).
- **`setGroupKey`/`UpdateGroupCommand`** in `jet_report_designer_controller.dart` (line 803) / `controller/commands/group_commands.dart` (line 54). `setGroupKey` stores the raw key string verbatim.
- **Scalar fields in scope for a band**: `scopePathToBand(def, bandId)` (band_walker.dart) + `fieldsInScopeForChain(schema, chain)` (binding_scope.dart), filtered to `f.type != JetFieldType.collection` — exactly what `_valueFieldChoices` (properties_panel.dart:455) does for an element.
- **`_groupSection`** (properties_panel.dart:605) is invoked from `_bandInspector` (line 571); `_bandInspector` already has `schema` in scope (added by the 025 feature).
- **`_BindingField`** (properties_panel.dart:2015) call sites: image binding (line 336), scope collection (line 655), band collection (line 722). All three are name-typed (store a bare field name).
- **`_TextInput`** (properties_panel.dart:1413) is the plain field used for the report name and the group key; it has no picker today.

## Conventions (every task)

- TDD red→green; never implement before the test fails.
- After editing `.arb` files run `flutter pub get` (regenerates the committed `jet_print_localizations*.dart`) before referencing the new getter.
- New `.arb` keys in all three files (en with `@key` description; tr; de).
- Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print`.
- Per task: `flutter test packages/jet_print/test/designer/<file>.dart`, then `dart analyze <changed files>` (zero warnings). Final task runs the full gates incl. goldens.
- Do NOT run `--update-goldens`.

## File map

| File | Change |
|------|--------|
| `lib/src/designer/controller/jet_report_designer_controller.dart` | add `setGroupName` |
| `lib/src/designer/layout/panels/properties_panel.dart` | `_BindingField` bracket format; `_TextInput` optional picker; `_groupSection` name field + key picker; `_groupKeyDisplay`/`_compileKey`/`_groupKeyChoices` helpers |
| `lib/src/designer/l10n/jet_print_{en,tr,de}.arb` | `propertiesGroupName` |
| `test/designer/**` | new + updated tests |

---

### Task 1: Controller — `setGroupName`

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart` (after `setGroupKey`, ~line 807)
- Test: `packages/jet_print/test/designer/controller/set_group_name_test.dart` (create)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  ReportDefinition _grouped() {
    final JetReportDesignerController c = JetReportDesignerController();
    c.createGroupWithHeader(c.definition.body.root.id);
    final ReportDefinition d = c.definition;
    c.dispose();
    return d;
  }

  test('setGroupName renames the group as one undoable step', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _grouped());
    addTearDown(c.dispose);
    final String groupId = c.definition.body.root.groups.single.id;

    c.setGroupName(groupId, 'invoice');

    expect(c.definition.body.root.groups.single.name, 'invoice');
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.definition.body.root.groups.single.name, groupId);
  });

  test('setGroupName is a no-op for an unknown group', () {
    final JetReportDesignerController c =
        JetReportDesignerController(definition: _grouped());
    addTearDown(c.dispose);
    final ReportDefinition before = c.definition;
    c.setGroupName('nope', 'x');
    expect(c.definition, before);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test packages/jet_print/test/designer/controller/set_group_name_test.dart`
Expected: FAIL — `setGroupName` undefined.

- [ ] **Step 3: Implement**

Add after `setGroupKey` (~line 807):

```dart
  /// Renames group [groupId] (a display label only; groups are referenced by
  /// id, not name) as one undoable step. A no-op for an unknown group or an
  /// unchanged name.
  void setGroupName(String groupId, String name) => _commit(UpdateGroupCommand(
        groupId: groupId,
        label: 'Set group name',
        update: (GroupLevel g) => g.copyWith(name: name),
      ));
```

`UpdateGroupCommand` and `GroupLevel` are already imported (used by `setGroupKey`). The `UpdateGroupCommand` is a no-op for an unknown group and when the value is unchanged (its docstring guarantees this), so the no-op test passes.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test packages/jet_print/test/designer/controller/set_group_name_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart packages/jet_print/test/designer/controller/set_group_name_test.dart
git commit -m "feat(designer): setGroupName controller method

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `[fieldName]` format for name-typed bindings (`_BindingField`)

Make `_BindingField` display the stored bare value as `[value]`, have its picker insert `[field]`, and strip brackets on commit — so the list collection binding reads `[lines]` (matching the canvas) while the stored `collectionField` stays `lines`. Affects scope/band collection bindings and the image binding (all name-typed).

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (`_BindingField`, ~lines 2015–2142)
- Test: `packages/jet_print/test/designer/binding_field_format_test.dart` (create)

- [ ] **Step 1: Write the failing test**

```dart
// A nested-list detail band's "List" binding shows the bracketed [lines] form
// while the stored collectionField stays the bare name.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

void main() {
  testWidgets('the list collection binding displays [lines], stores bare lines',
      (WidgetTester tester) async {
    final JetReportDesignerController c =
        await pumpDesignerWith(tester, dataSchema: _invoice);
    c.createListWithBand(c.definition.body.root.id, collectionField: 'lines');
    await tester.pumpAndSettle();

    final ShadInput input = tester.widget<ShadInput>(find.byKey(
        const ValueKey<String>(
            'jet_print.designer.properties.field.bandCollection')));
    expect(input.controller!.text, '[lines]',
        reason: 'the binding field shows the bracketed shorthand');
    expect(
        c.definition.body.root.children
            .whereType<NestedScope>()
            .single
            .scope
            .collectionField,
        'lines',
        reason: 'the stored value stays the bare field name');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test packages/jet_print/test/designer/binding_field_format_test.dart`
Expected: FAIL — the field shows `lines`, not `[lines]`.

- [ ] **Step 3: Add the wrap/strip helpers and rewire `_BindingField`**

In `_BindingFieldState` (the State class for `_BindingField`), add two static helpers at the top of the class body:

```dart
  /// Wraps a stored bare field name as the `[name]` shorthand for display.
  static String _wrap(String v) => v.isEmpty ? '' : '[$v]';

  /// Strips a surrounding `[ ]` to recover the bare field name on commit.
  static String _strip(String v) {
    final String t = v.trim();
    return t.length >= 2 && t.startsWith('[') && t.endsWith(']')
        ? t.substring(1, t.length - 1).trim()
        : t;
  }
```

Change the controller initializer from:

```dart
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
```

to:

```dart
  late final TextEditingController _controller =
      TextEditingController(text: _wrap(widget.value));
```

In `didUpdateWidget`, change `_controller.text = widget.value;` to `_controller.text = _wrap(widget.value);`.

Change `_commit()` to strip before comparing/committing:

```dart
  void _commit() {
    final String text = _strip(_controller.text);
    if (text.isEmpty) {
      if (widget.value.isNotEmpty) widget.onClear();
    } else if (text != widget.value) {
      widget.onSet(text);
    }
  }
```

Change `_pick()` to show the bracketed form but emit the bare name:

```dart
  void _pick(String field) {
    _picker.hide();
    _controller.text = _wrap(field);
    if (field != widget.value) widget.onSet(field);
  }
```

`_clear()` is unchanged (it empties the field and calls `onClear`). The three call sites (image, scope collection, band collection) are unchanged — they still pass a bare `value` and receive a bare `onSet`.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test packages/jet_print/test/designer/binding_field_format_test.dart`
Expected: PASS.

- [ ] **Step 5: Re-run the binding/Task-4 suites; update any bare-text assertions**

Run: `flutter test packages/jet_print/test/designer/band_list_section_test.dart packages/jet_print/test/designer/`
Most binding tests assert by widget key, not by the displayed string, so they pass unchanged. **If** a test asserts a bare displayed value (e.g. expects the text `lines` or an image field name without brackets in a `_BindingField`), update that assertion to the bracketed `[…]` form — this is a correct consequence of the format change, not a weakening. Note any such change in the commit body.

- [ ] **Step 6: Analyze + commit**

```bash
dart analyze packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/test/designer/binding_field_format_test.dart
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/test/designer/
git commit -m "feat(designer): binding fields display the [fieldName] shorthand (store bare name)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Group section — name field + key schema picker (`[field]`)

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` (`_TextInput` ~1413; `_groupSection` ~605; call site ~571; new helpers near `_valueFieldChoices` ~455)
- Modify: the three `.arb` files
- Test: `packages/jet_print/test/designer/group_source_test.dart` (create)

- [ ] **Step 1: Write the failing test**

```dart
// The group source: a rename field and a schema field-picker on the key that
// stores $F{field}; manual expression edits and the placeholder '0' key stay
// editable.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'support/designer_harness.dart';

const JetDataSchema _invoice = JetDataSchema(
  name: 'Invoice',
  fields: <FieldDef>[
    FieldDef('invoiceNo', type: JetFieldType.string),
    FieldDef('customerName', type: JetFieldType.string),
    FieldDef('lines', type: JetFieldType.collection, fields: <FieldDef>[
      FieldDef('description', type: JetFieldType.string),
    ]),
  ],
);

Future<JetReportDesignerController> _withGroupSelected(WidgetTester tester) async {
  final JetReportDesignerController c =
      await pumpDesignerWith(tester, dataSchema: _invoice);
  c.createGroupWithHeader(c.definition.body.root.id); // selects the header band
  await openPropertiesTab(tester);
  await tester.pumpAndSettle();
  return c;
}

String _key(JetReportDesignerController c) =>
    c.definition.body.root.groups.single.key;

void main() {
  testWidgets('the group name field renames the group', (WidgetTester tester) async {
    final JetReportDesignerController c = await _withGroupSelected(tester);
    final Finder f = find.byKey(
        const ValueKey<String>('jet_print.designer.properties.field.groupName'));
    await tester.enterText(f, 'invoice');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.definition.body.root.groups.single.name, 'invoice');
  });

  testWidgets('the placeholder key 0 shows editable and the picker stores \$F{field}',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _withGroupSelected(tester);
    final ShadInput keyInput = tester.widget<ShadInput>(find.byKey(
        const ValueKey<String>('jet_print.designer.properties.field.groupKey')));
    expect(keyInput.controller!.text, '0');
    expect(keyInput.readOnly, isFalse, reason: 'a non-field key stays editable');

    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.groupKey.pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>(
        'jet_print.designer.properties.field.groupKey.pick.invoiceNo')));
    await tester.pumpAndSettle();

    expect(_key(c), r'$F{invoiceNo}');
  });

  testWidgets('typing a raw expression updates the key (manual edit path)',
      (WidgetTester tester) async {
    final JetReportDesignerController c = await _withGroupSelected(tester);
    final Finder f = find.byKey(
        const ValueKey<String>('jet_print.designer.properties.field.groupKey'));
    await tester.enterText(f, r'$F{customerName}');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_key(c), r'$F{customerName}');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test packages/jet_print/test/designer/group_source_test.dart`
Expected: FAIL — no `groupName` field / no key picker.

- [ ] **Step 3: Add the l10n string**

`jet_print_en.arb`:

```json
  "propertiesGroupName": "Group name",
  "@propertiesGroupName": {
    "description": "Inspector label for a group's display name (editable)."
  },
```

`jet_print_tr.arb`:

```json
  "propertiesGroupName": "Grup adı",
```

`jet_print_de.arb`:

```json
  "propertiesGroupName": "Gruppenname",
```

- [ ] **Step 4: Regenerate localizations**

Run: `flutter pub get`

- [ ] **Step 5: Give `_TextInput` an optional field-picker**

In `_TextInput` (the `StatefulWidget`), add three optional constructor params after `onCommit`:

```dart
    this.fields = const <FieldDef>[],
    this.pickerTooltip = '',
    this.pickerKeyPrefix = '',
```

and the matching fields with docs:

```dart
  /// In-scope fields offered by an optional suffix picker; empty ⇒ no picker.
  /// Picking inserts the `[field]` shorthand (the caller compiles it).
  final List<FieldDef> fields;

  /// Tooltip for the picker button (used only when [fields] is non-empty).
  final String pickerTooltip;

  /// Key namespace for the picker test seam (used only when [fields] is non-empty).
  final String pickerKeyPrefix;
```

In `_TextInputState`, add a picker controller and a `_pick`, and dispose it:

```dart
  final ShadPopoverController _picker = ShadPopoverController();
```

```dart
  void _pick(String field) {
    _picker.hide();
    _controller.text = '[$field]';
    _commit();
  }
```

In `dispose()`, add `_picker.dispose();` (before `_focus.dispose()`).

In `build()`, give the `ShadInput` a trailing picker when fields are present:

```dart
  @override
  Widget build(BuildContext context) {
    return ShadInput(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focus,
      placeholder: Text(widget.placeholder),
      onSubmitted: (_) => _commit(),
      trailing: widget.fields.isEmpty
          ? null
          : _FieldPicker(
              controller: _picker,
              fields: widget.fields,
              tooltip: widget.pickerTooltip,
              keyPrefix: widget.pickerKeyPrefix,
              onPick: _pick,
            ),
    );
  }
```

(`_FieldPicker` already supports a `keyPrefix` and renders items keyed `'$keyPrefix.<fieldName>'`, and a trigger keyed `'$keyPrefix'` — that is what the test taps.)

- [ ] **Step 6: Add the group-key helpers**

Near `_valueFieldChoices` (~line 455) add:

```dart
  /// The group key shown in the inspector: a simple `$F{field}` reads as the
  /// editable `[field]` shorthand; any other expression (a composite, or the
  /// placeholder constant) is shown verbatim and editable (NOT the read-only
  /// `{…}` token `reverseCompile` would produce).
  String _groupKeyDisplay(String key) {
    final ValueDisplay d = reverseCompile(key);
    return d.editable ? d.text : key;
  }

  /// Maps the group-key field input to a stored 005a expression: a `[field]`
  /// shorthand compiles to `$F{field}`; any other input is the expression
  /// verbatim (it is already 005a, e.g. `$F{x}`, `YEAR($F{date})`, `0`).
  String _compileKey(String input) => switch (parseValueField(input)) {
        BindingValue(:final String expression) => expression,
        LiteralValue(:final String text) => text,
      };

  /// The scalar (non-collection) fields a group key can reference, resolved at
  /// the group's header (or footer) band level — the scalar counterpart of the
  /// list collection picker.
  List<FieldDef> _groupKeyChoices(
    JetDataSchema? schema,
    JetReportDesignerController controller,
    GroupLevel group,
  ) {
    if (schema == null) return const <FieldDef>[];
    final String? bandId = group.header?.id ?? group.footer?.id;
    if (bandId == null) return const <FieldDef>[];
    final List<DetailScope> chain =
        scopePathToBand(controller.definition, bandId);
    return <FieldDef>[
      for (final FieldDef f in fieldsInScopeForChain(schema, chain))
        if (f.type != JetFieldType.collection) f,
    ];
  }
```

`reverseCompile`, `parseValueField`, `ValueDisplay`, `BindingValue`, `LiteralValue` are imported at properties_panel.dart line 38. `scopePathToBand`, `fieldsInScopeForChain`, `GroupLevel`, `DetailScope`, `FieldDef`, `JetFieldType` are already used in this file.

- [ ] **Step 7: Rewrite `_groupSection` to add the name field + key picker**

Change the `_groupSection` signature to take `schema`:

```dart
  List<Widget> _groupSection(
    JetReportDesignerController controller,
    String groupId,
    ShadThemeData theme,
    JetPrintLocalizations l10n,
    JetDataSchema? schema,
  ) {
    final GroupLevel? group = findGroup(controller.definition, groupId);
    if (group == null) return const <Widget>[];
    return <Widget>[
      SectionLabel(l10n.propertiesGroupName),
      const SizedBox(height: 8),
      _TextInput(
        fieldKey: const ValueKey<String>('$_p.field.groupName'),
        value: group.name,
        placeholder: l10n.propertiesGroupName,
        onCommit: (String v) => controller.setGroupName(groupId, v),
      ),
      const SizedBox(height: 12),
      SectionLabel(l10n.propertiesGroupKey),
      const SizedBox(height: 8),
      _TextInput(
        fieldKey: const ValueKey<String>('$_p.field.groupKey'),
        value: _groupKeyDisplay(group.key),
        placeholder: l10n.bindingExpressionHint,
        fields: _groupKeyChoices(schema, controller, group),
        pickerTooltip: l10n.bindingFieldPickerTooltip,
        pickerKeyPrefix: '$_p.field.groupKey.pick',
        onCommit: (String v) => controller.setGroupKey(groupId, _compileKey(v)),
      ),
      const SizedBox(height: 12),
      ShadSwitch(
        key: const ValueKey<String>('$_p.field.groupNewPage'),
        value: group.startNewPage,
        onChanged: (bool v) => controller.setGroupStartNewPage(groupId, v),
        label: Text(l10n.propertiesGroupNewPage),
      ),
    ];
  }
```

Update the call site in `_bandInspector` (~line 571) to pass `schema`:

```dart
        ..addAll(_groupSection(controller, group.id, theme, l10n, schema));
```

(`schema` is already a parameter of `_bandInspector`.) Also check `_groupInspector` (the fallback shown when a group id is selected directly) — it does NOT call `_groupSection`, so no change there.

- [ ] **Step 8: Run it to verify it passes**

Run: `flutter test packages/jet_print/test/designer/group_source_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 9: Re-run the group inspector suite (regression)**

Run: `flutter test packages/jet_print/test/designer/group_inspector_test.dart`
Expected: PASS. The existing `field.groupKey` / `field.groupNewPage` seams are unchanged; the added `field.groupName` is additive. If `group_inspector_test.dart` asserts the exact group-section widget count or the groupKey field's displayed text for a `$F{…}` key, update it to the new layout/`[field]` display — note any such change.

- [ ] **Step 10: Analyze + commit**

```bash
dart analyze packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/test/designer/group_source_test.dart
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/lib/src/designer/l10n/ packages/jet_print/test/designer/group_source_test.dart packages/jet_print/test/designer/group_inspector_test.dart
git commit -m "feat(designer): group rename + group-key schema picker ([field] shorthand)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Full gates + regression

**Files:** none (verification + any small test-assertion updates surfaced here).

- [ ] **Step 1: Full suite (golden guard)**

Run, from the repo root:

```bash
flutter test packages/jet_print
```

Expected: all pass, **no golden failures** (binding/group fields render only on selection; default goldens are unaffected). If a golden fails, a render path was touched by mistake — STOP and report; do not `--update-goldens`. If a non-golden test fails because it asserted a bare binding display or the old group-section layout, fix that assertion to the new `[field]`/layout form (a correct consequence) and re-run.

- [ ] **Step 2: Consumer app + analyzer + format**

```bash
flutter test apps/jet_print_playground
flutter analyze
dart format --output=none --set-exit-if-changed .
```

Expected: all clean. If `dart format` reports files needing formatting, run `dart format .`, then commit as `style: dart format`.

- [ ] **Step 3: Manual GUI check (human)**

Build/select a group from blank in the playground: select the group header band → rename it in the new Group name field → pick the group key field from the schema (`[invoiceNo]`) → confirm the LIST binding now reads `[lines]`. (Human acceptance; note results in the PR.)

- [ ] **Step 4: Commit any formatting fixups**

```bash
git add -A
git commit -m "style: dart format" || echo "nothing to format"
```

---

## Deferred (unchanged from the design)

Group-as-selectable-Outline-node; inline group diagnostics; hidden pagination flags; composite-expression cursor insertion; any rendering/codec/schema change.

## Plan self-review

- **Spec coverage:** A1 group key picker → Task 3 (Steps 5–7); A2 group rename → Task 1 + Task 3; B `[fieldName]` for name-typed bindings → Task 2, for the group key (expression-typed) → Task 3 via `parseValueField`/`reverseCompile`; the element value field already uses `[field]` (untouched); manual key-edit path verified → Task 3 Step 1 test 3; localization → Task 3 Step 3; goldens byte-identical → Task 4. ✔
- **Placeholder scan:** every code step shows the code; the one open spot (existing-test assertion updates) is bounded and explained (update bare→bracketed / old layout→new), not a blank TODO. ✔
- **Type consistency:** stable names across tasks — `setGroupName(String,String)`, `_wrap`/`_strip`, `_groupKeyDisplay`/`_compileKey`/`_groupKeyChoices`, seams `…field.groupName` / `…field.groupKey` / `…field.groupKey.pick`. `_compileKey` matches the verified `ValueParse` arms (`BindingValue.expression`, `LiteralValue.text`). `_groupSection` gains a `schema` param consistently at definition + call site. ✔
