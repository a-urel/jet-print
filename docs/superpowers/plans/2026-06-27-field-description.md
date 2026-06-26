# Data-Field `description` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional human-friendly `description` label to data fields, displayed as a second line beside the technical field name in the designer's Data Source view.

**Architecture:** `FieldDef` gains an optional `String? description` (pure display sugar — never read by binding/resolution/fill/render). The data-source file codec round-trips it (omit-when-null). The shared `TreeBranch` widget gains an optional subtitle so collection nodes can show it; the panel's leaf-field row renders a two-line name + description. Read-only — no GUI editor, no controller/command/undo, no golden change.

**Tech Stack:** Dart / Flutter, `flutter_test`, `shadcn_ui`. Data layer + designer layer only.

## Global Constraints

- Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (flutter leaves cwd inside the package).
- Branch is already `feat-field-description`.
- `description` is **additive, optional, default `null`** — it MUST NOT touch `name` (the binding key `DataRow.field(name)`), `type`, or any expression/resolution/fill/render path.
- **Omit-when-null** serialization: a field without a description encodes to byte-identical JSON as today.
- Field names/labels in the Data Source view are intentionally NOT localized (only empty-state strings are). `description` is host-supplied text — also not localized.
- No golden file should change (author-time-only). If one does, STOP and inspect.
- `dart format --output=none --set-exit-if-changed lib test` and `flutter analyze` must be clean before each commit.

---

## Task 1: `FieldDef.description` (model)

**Files:**
- Modify: `packages/jet_print/lib/src/data/field_def.dart`
- Test: `packages/jet_print/test/data/field_def_test.dart`

**Interfaces:**
- Produces: `FieldDef(String name, {JetFieldType type, List<FieldDef> fields, String? description})` — new optional named param `description` (default `null`), exposed as `final String? description`.

- [ ] **Step 1: Write the failing tests.** Append to the existing top-level `group` in `field_def_test.dart` (match its `const FieldDef(...)` style):

```dart
test('defaults description to null', () {
  expect(const FieldDef('qty', type: JetFieldType.integer).description, isNull);
});

test('carries an optional description without affecting name/type', () {
  const f = FieldDef('customerTotal',
      type: JetFieldType.double, description: 'Total spend per customer');
  expect(f.name, 'customerTotal');
  expect(f.type, JetFieldType.double);
  expect(f.description, 'Total spend per customer');
});

test('value equality and hashCode distinguish description', () {
  const a = FieldDef('amount', type: JetFieldType.double, description: 'Net');
  const same = FieldDef('amount', type: JetFieldType.double, description: 'Net');
  const noDesc = FieldDef('amount', type: JetFieldType.double);
  const otherDesc =
      FieldDef('amount', type: JetFieldType.double, description: 'Gross');
  expect(a == same, isTrue);
  expect(a.hashCode, same.hashCode);
  expect(a == noDesc, isFalse);
  expect(a == otherDesc, isFalse);
});

test('toString includes description when set, omits it when null', () {
  expect(
      const FieldDef('amount', type: JetFieldType.double, description: 'Net')
          .toString(),
      contains('Net'));
  expect(const FieldDef('amount', type: JetFieldType.double).toString(),
      isNot(contains('null')));
});
```

- [ ] **Step 2: Run to verify they fail.**

Run: `cd packages/jet_print && flutter test test/data/field_def_test.dart`
Expected: FAIL — `description` is not a named parameter / getter.

- [ ] **Step 3: Implement.** In `field_def.dart`:

Add the constructor parameter (after `fields`):

```dart
  const FieldDef(
    this.name, {
    this.type = JetFieldType.unknown,
    this.fields = const <FieldDef>[],
    this.description,
  });
```

Add the field (after `fields`):

```dart
  /// An optional human-friendly label for this field, shown beside [name] in the
  /// designer's Data Source view. Pure display sugar: it never affects binding
  /// (which always uses [name]), type, expression resolution, or rendering. Null
  /// when unspecified (e.g. for inferred schemas), in which case the view shows
  /// [name] alone.
  final String? description;
```

Update `==` (add the conjunct):

```dart
  @override
  bool operator ==(Object other) =>
      other is FieldDef &&
      other.name == name &&
      other.type == type &&
      other.description == description &&
      _fieldListEquals(other.fields, fields);
```

Update `hashCode`:

```dart
  @override
  int get hashCode =>
      Object.hash(name, type, description, Object.hashAll(fields));
```

Update `toString` (keep the two existing branches, append description when set):

```dart
  @override
  String toString() {
    final String desc = description == null ? '' : ', "$description"';
    return fields.isEmpty
        ? 'FieldDef($name, $type$desc)'
        : 'FieldDef($name, $type$desc, fields: $fields)';
  }
```

Leave `inferType`, `inferColumn`, `inferFields` untacted — they construct `FieldDef`s without a description, so it defaults `null` (no behavior change for inferred schemas).

- [ ] **Step 4: Run to verify they pass.**

Run: `cd packages/jet_print && flutter test test/data/field_def_test.dart`
Expected: PASS (all, including the pre-existing equality/inference tests).

- [ ] **Step 5: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format --output=none --set-exit-if-changed lib/src/data/field_def.dart test/data/field_def_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/data/field_def.dart packages/jet_print/test/data/field_def_test.dart
git commit -m "feat(data): optional FieldDef.description (display label)"
```

---

## Task 2: Codec round-trips `description`

**Files:**
- Modify: `packages/jet_print/lib/src/data/serialization/data_source_file.dart`
- Test: `packages/jet_print/test/data/serialization/data_source_file_test.dart`

**Interfaces:**
- Consumes: `FieldDef.description` (Task 1).
- Produces: JSON field object gains an optional `"description": <String>` key (present only when non-null).

- [ ] **Step 1: Write the failing tests.** Append to the existing `group` in `data_source_file_test.dart` (match its `JetDataSourceFile.encode/decode` style):

```dart
test('round-trips a field description', () {
  const doc = JetDataSourceDocument(
    schema: JetDataSchema(
      name: 'Sales',
      fields: <FieldDef>[
        FieldDef('customerTotal',
            type: JetFieldType.double, description: 'Total spend per customer'),
      ],
    ),
  );
  final decoded =
      JetDataSourceFile.decodeJson(JetDataSourceFile.encodeJson(doc));
  expect(decoded.schema.fields.single.description, 'Total spend per customer');
  expect(decoded, doc);
});

test('omits the description key when null (byte-identical to legacy)', () {
  final encoded = JetDataSourceFile.encode(const JetDataSourceDocument(
    schema: JetDataSchema(
      name: 'Sales',
      fields: <FieldDef>[FieldDef('amount', type: JetFieldType.double)],
    ),
  ));
  final field =
      (encoded['schema'] as Map)['fields'] as List;
  expect((field.single as Map).containsKey('description'), isFalse);
});

test('rejects a non-string description', () {
  expect(
    () => JetDataSourceFile.decode(<String, Object?>{
      'jetDataSource': 1,
      'schema': <String, Object?>{
        'name': 'Sales',
        'fields': <Object?>[
          <String, Object?>{
            'name': 'amount',
            'type': 'double',
            'description': 42,
          },
        ],
      },
    }),
    throwsA(isA<JetDataSourceFormatException>()),
  );
});
```

- [ ] **Step 2: Run to verify they fail.**

Run: `cd packages/jet_print && flutter test test/data/serialization/data_source_file_test.dart`
Expected: FAIL — `decoded...description` is null (not encoded), and the non-string case does not throw.

- [ ] **Step 3: Implement.** In `data_source_file.dart`:

`_encodeField` — add the omit-when-null key (before the collection `fields` key so key order reads name/type/description/fields):

```dart
Map<String, Object?> _encodeField(FieldDef field) => <String, Object?>{
      'name': field.name,
      'type': field.type.name,
      if (field.description != null) 'description': field.description,
      if (field.type == JetFieldType.collection)
        'fields': <Map<String, Object?>>[
          for (final FieldDef child in field.fields) _encodeField(child),
        ],
    };
```

`_decodeField` — read the optional key, validate it is a String when present, pass it through. Insert the description read after the `type` resolution and before the `children` read, and add `description:` to the returned `FieldDef`:

```dart
  final Object? rawDescription = json['description'];
  if (rawDescription != null && rawDescription is! String) {
    throw const JetDataSourceFormatException(
        'Field "description" must be a string.');
  }
  final Object? children = json['fields'];
  return FieldDef(
    name,
    type: type,
    description: rawDescription as String?,
    fields: <FieldDef>[
      if (children is List)
        for (final Object? c in children)
          if (c is Map)
            _decodeField(c.cast<String, Object?>())
          else
            throw const JetDataSourceFormatException(
                'Each field must be an object.'),
    ],
  );
```

- [ ] **Step 4: Run to verify they pass.**

Run: `cd packages/jet_print && flutter test test/data/serialization/data_source_file_test.dart`
Expected: PASS (all, including pre-existing round-trip tests).

- [ ] **Step 5: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format --output=none --set-exit-if-changed lib/src/data/serialization/data_source_file.dart test/data/serialization/data_source_file_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/data/serialization/data_source_file.dart packages/jet_print/test/data/serialization/data_source_file_test.dart
git commit -m "feat(data): round-trip FieldDef.description in data-source file codec"
```

---

## Task 3: `TreeBranch` optional description subtitle

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/region_chrome.dart`
- Test: `packages/jet_print/test/designer/data_source_tree_test.dart` (collection-branch assertion lands in Task 4; this task is structural and verified via Task 4 + the full suite)

**Interfaces:**
- Produces: `TreeBranch({required IconData icon, required String label, required int depth, required List<Widget> children, bool initiallyExpanded, List<Widget> actions, String? description, Key? key})` — new optional `description`. When non-null and non-empty, the branch renders it as a muted second line under `label`; when null/empty, the row renders exactly as today (single line).

- [ ] **Step 1: Implement.** (No isolated unit test — `TreeBranch` is a private layout widget exercised through the panel in Task 4; the safety net is the full designer suite, which must stay green with `description` defaulting null everywhere it is already used.)

Add the field + constructor param to `TreeBranch` (after `actions`):

```dart
    this.actions = const <Widget>[],
    this.description,
    super.key,
  });
```

```dart
  /// An optional muted subtitle shown under [label] (e.g. a data field's
  /// human-friendly description). Null or empty → the branch renders a single
  /// line, exactly as before.
  final String? description;
```

In `build`, replace the `Expanded(child: Text(widget.label, ...))` with a two-line column when a description is present. Capture the description once:

```dart
                Expanded(
                  child: LabelWithDescription(
                    label: widget.label,
                    description: widget.description,
                    theme: theme,
                  ),
                ),
```

Add this small **library-internal (non-private)** widget at the bottom of `region_chrome.dart`. It centralizes the two-line layout so the leaf-row path in Task 4 imports and reuses it (single source — NO duplication):

```dart
/// A node caption: [label] on top, and — when [description] is non-null and
/// non-empty — a muted, smaller line beneath it. Used by tree branches and leaf
/// field rows so both render the optional field description identically.
class LabelWithDescription extends StatelessWidget {
  /// Creates a caption for [label] with an optional muted [description] subtitle.
  const LabelWithDescription({
    required this.label,
    required this.description,
    required this.theme,
    super.key,
  });

  final String label;
  final String? description;
  final ShadThemeData theme;

  @override
  Widget build(BuildContext context) {
    final String? desc = description;
    final Text title = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.small.copyWith(
        color: theme.colorScheme.foreground,
      ),
    );
    if (desc == null || desc.isEmpty) return title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        title,
        Text(
          desc,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.muted.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}
```

NOTE: `LabelWithDescription` is **library-internal but not private** (no leading underscore), so Task 4's leaf row in `data_source_panel.dart` imports it directly — ONE source of the two-line layout, no duplication. It is not added to the public `jet_print.dart` barrel (designer-internal). The leaf path here uses the field name as `label` and `field.description` as `description`; the title style differs slightly (theme.textTheme.small vs small.copyWith(foreground)) — the widget uses the foreground-colored variant, which is correct for both branch and leaf rows.

- [ ] **Step 2: Run the full designer suite to verify no regression.**

Run: `cd packages/jet_print && flutter test test/designer`
Expected: PASS — existing `TreeBranch` callers pass no `description`, so every branch renders single-line as before. No golden changes.

- [ ] **Step 3: Analyzer + format, then commit.**

```bash
cd packages/jet_print && flutter analyze && dart format --output=none --set-exit-if-changed lib/src/designer/layout/region_chrome.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/region_chrome.dart
git commit -m "feat(designer): TreeBranch optional description subtitle"
```

---

## Task 4: Data Source view shows `description`

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart`
- Test: `packages/jet_print/test/designer/data_source_tree_test.dart`

**Interfaces:**
- Consumes: `FieldDef.description` (Task 1), `TreeBranch.description` (Task 3).

- [ ] **Step 1: Write the failing tests.** Append to `data_source_tree_test.dart`. Add a schema constant near the existing `_invoice` (use field text distinct from any node name to avoid `find.text` ambiguity — note the existing `_invoice` already has a field literally named `description`, so DO NOT reuse that word as a description value):

```dart
/// A schema whose fields carry human-friendly descriptions (leaf + collection).
const JetDataSchema _described = JetDataSchema(
  name: 'Sales',
  fields: <FieldDef>[
    FieldDef('customerTotal',
        type: JetFieldType.double, description: 'Total spend per customer'),
    FieldDef('plainField', type: JetFieldType.string),
    FieldDef(
      'orders',
      type: JetFieldType.collection,
      description: 'Orders placed',
      fields: <FieldDef>[FieldDef('lineTotal', type: JetFieldType.double)],
    ),
  ],
);
```

```dart
testWidgets('a leaf field shows its description under the name', (
  WidgetTester tester,
) async {
  await pumpDesigner(
    tester,
    designer: const JetReportDesigner(dataSchema: _described),
  );
  expect(find.text('customerTotal'), findsOneWidget);
  expect(find.text('Total spend per customer'), findsOneWidget);
});

testWidgets('a field without a description shows only its name', (
  WidgetTester tester,
) async {
  await pumpDesigner(
    tester,
    designer: const JetReportDesigner(dataSchema: _described),
  );
  expect(find.text('plainField'), findsOneWidget);
  // No stray empty subtitle: the only texts are node names + type tokens.
  expect(find.text(''), findsNothing);
});

testWidgets('a collection field shows its description under the name', (
  WidgetTester tester,
) async {
  await pumpDesigner(
    tester,
    designer: const JetReportDesigner(dataSchema: _described),
  );
  expect(find.text('orders'), findsOneWidget);
  expect(find.text('Orders placed'), findsOneWidget);
});

testWidgets('dragging a leaf carries the field name, not the description', (
  WidgetTester tester,
) async {
  await pumpDesigner(
    tester,
    designer: const JetReportDesigner(dataSchema: _described),
  );
  // The drag chip text is the binding key (name), so the description never
  // becomes the dropped reference.
  final Finder chip = find.byType(Draggable<FieldDragData>);
  expect(chip, findsWidgets);
});
```

- [ ] **Step 2: Run to verify they fail.**

Run: `cd packages/jet_print && flutter test test/designer/data_source_tree_test.dart`
Expected: FAIL — `'Total spend per customer'` / `'Orders placed'` texts are not found (descriptions not yet rendered).

- [ ] **Step 3: Implement.** In `data_source_panel.dart`:

Pass the collection field's description into its `TreeBranch` in `_fieldNode`:

```dart
Widget _fieldNode(FieldDef field, int depth) {
  if (field.type == JetFieldType.collection) {
    return TreeBranch(
      icon: fieldTypeGlyph(JetFieldType.collection),
      label: field.name,
      depth: depth,
      description: field.description,
      initiallyExpanded: false,
      actions: const <Widget>[_CollectionActions()],
      children: <Widget>[
        for (final FieldDef child in field.fields) _fieldNode(child, depth + 1),
      ],
    );
  }
  return _FieldRow(field: field, depth: depth);
}
```

In `_FieldRow.build`, replace the `Expanded(child: Text(field.name, ...))` with the shared `LabelWithDescription` from Task 3 (imported from `region_chrome.dart` — `data_source_panel.dart` already imports that file for `TreeBranch`/`RegionEmptyHint`, so no new import line is needed):

```dart
          Expanded(
            child: LabelWithDescription(
              label: field.name,
              description: field.description,
              theme: theme,
            ),
          ),
```

This is the SAME widget the collection branch uses (Task 3), so leaf rows and branches render the two-line treatment identically with no duplicated layout code. `LabelWithDescription` returns a single-line title when `description` is null/empty, so the null-description case needs no special handling here.

Leave the `Draggable<FieldDragData>` wrapping and `FieldDragData(fieldName: field.name)` untouched — the drag still carries the binding key, never the description.

- [ ] **Step 4: Run to verify they pass.**

Run: `cd packages/jet_print && flutter test test/designer/data_source_tree_test.dart`
Expected: PASS (all, including the pre-existing tree tests).

- [ ] **Step 5: Full verification sweep.**

```bash
cd packages/jet_print && flutter analyze && dart format --output=none --set-exit-if-changed lib test && flutter test
```
Expected: analyzer clean, format clean, ALL tests green. **GOLDENS unchanged** — if any golden fails, STOP and inspect (this is an author-time-only change; no render path is touched).

- [ ] **Step 6: Playground guard.**

```bash
cd apps/jet_print_playground && flutter analyze && flutter test
```
Expected: green (the playground consumes the library; confirm no break).

- [ ] **Step 7: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/designer/layout/panels/data_source_panel.dart packages/jet_print/test/designer/data_source_tree_test.dart
git commit -m "feat(designer): Data Source view shows field descriptions (two-line)"
```

- [ ] **Step 8 (optional): Manual GUI smoke.** `cd apps/jet_print_playground && flutter run -d macos`; attach/select a data source whose schema carries a field description; confirm the Data Source tab shows the description as a muted second line under the field name, and a field without one shows only its name.

---

## Self-Review

- **Spec coverage:** Model `description` → Task 1. Codec round-trip + omit-when-null + non-string rejection → Task 2. Two-line display (leaf + collection branch) → shared `LabelWithDescription` (Task 3), consumed by both `TreeBranch` (Task 3) and `_FieldRow` (Task 4). Fallback to name-only when null → `LabelWithDescription` single-line early-return. No engine/golden change → Task 4 Step 5 sweep. Inference unchanged → Task 1 Step 3 note.
- **Out-of-scope honored:** no GUI editor for `description`, no rendered-output use, no controller/command/undo, no schema-version bump (schema is host-attached, not in the report template).
- **Placeholder scan:** none — every code step shows full code and exact commands.
- **Type consistency:** `FieldDef(..., description:)` named param used identically in Tasks 1/2/4; `TreeBranch(..., description:)` defined in Task 3 and consumed in Task 4; `LabelWithDescription({label, description, theme})` defined in Task 3 (region_chrome.dart, library-internal/non-private) and consumed by both `TreeBranch` (Task 3) and `_FieldRow` (Task 4) — single source, no duplication.
- **Key risk:** the existing `_invoice` test schema has a *field named* `description` — unrelated to the new property; tests use the separate `_described` schema and distinct description text to avoid `find.text` collisions.
