# Multi-Level Inline Aggregates — Designer Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Depends on the engine plan** (`plan-engine.md`): this plan consumes `resolveAggregatePath` / `AggregatePath` from `packages/jet_print/lib/src/data/aggregate_path.dart` (engine Task 1). Land the engine milestone first, or at minimum engine Task 1.

**Goal:** Make the designer's author-time resolution aggregate-operand-aware so a deep leaf is **Valid** as the operand of an aggregate (`{SUM([lineTotal])}` at the customer footer) and **Unresolved** when referenced bare (`[lineTotal]`), and offer descendant leaf fields in the fx field palette, visually marked as deeper-collection.

**Architecture:** A small engine helper (`Expression.aggregateOperandFields`) walks the AST to report which `$F{}` refs are aggregate operands. The designer's binding-resolution seam gains `descendantOperandNamesForBand` (leaf names with a unique descend path from the band's own scope, via `resolveAggregatePath`) and `descendantFieldChoicesForBand` (those leaves as `FieldDef`s for the palette). The fx editor's pure `statusFor` and the Properties panel's `_unresolved` become aggregate-operand-aware: a ref is resolvable when it is a normal in-scope name, **or** it is an aggregate operand and a descendant operand. The fx palette renders descendant leaves with a distinct marker, inserting the plain `[field]` token (the author wraps it in a function).

**Tech Stack:** Dart (Flutter workspace). Package: `packages/jet_print`. Tests run with `flutter test` **from `packages/jet_print`**. UI uses `shadcn_ui`. Localization is hand-written per-locale (`en`/`de`/`tr`) behind an abstract `JetPrintLocalizations`.

## Global Constraints

- **A bare deep reference stays Unresolved** (FR-006): a descendant leaf is legal **only** as an aggregate operand; `[lineTotal]` alone at a higher band has no row to bind to and must read **Unresolved / Field not found** — unchanged behavior on the record-blind path.
- **Same-scope wins** (FR-001): the resolver short-circuits to `SameScope` for a non-collection field at the band's own scope; only `DescendPath` operands are offered/accepted as descendant operands. **Ambiguous** descendant operands are **not** offered and **not** treated as resolvable (they are an author-time error, surfaced via engine `validate(def, schema:)`).
- **Palette inserts the plain token** (FR-007): a descendant field button inserts `[field]` (not a pre-wrapped `SUM([field])`) — the author chooses the function. The marker is purely visual.
- Aggregate vocabulary stays single-sourced (`aggregate_functions.dart`); never re-list `SUM`/`AVG`/`COUNT`/`MIN`/`MAX`.
- No new serialization fields or grammar tokens.

---

## File Structure

**Modify:**
- `packages/jet_print/lib/src/expression/expression.dart` — add `Set<String> get aggregateOperandFields` (AST walk).
- `packages/jet_print/lib/src/designer/controller/binding_resolution.dart` — add `descendantOperandNamesForBand` + `descendantFieldChoicesForBand`.
- `packages/jet_print/lib/src/designer/layout/panels/expression_editor_dialog.dart` — make `statusFor` aggregate-operand-aware; thread `descendantOperands` + marked descendant fields through `showExpressionEditor` / `_ExpressionEditorDialog`; mark descendant field buttons.
- `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart` — make `_unresolved` aggregate-operand-aware; pass descendant operands + fields into the value field / fx editor.
- `packages/jet_print/lib/src/designer/l10n/jet_print_localizations.dart` (+ `_en.dart`, `_de.dart`, `_tr.dart`) — one new label for the descendant-field marker tooltip.

**Test files** mirror each (see tasks).

---

### Task 1: `Expression.aggregateOperandFields` (engine helper)

Report which `$F{}` references are operands of an aggregate call (`SUM`/`AVG`/`COUNT`/`MIN`/`MAX`), anywhere in the expression — so the designer can distinguish an aggregate operand from a bare reference.

**Files:**
- Modify: `packages/jet_print/lib/src/expression/expression.dart`
- Test: `packages/jet_print/test/expression/aggregate_operand_fields_test.dart` (create)

**Interfaces:**
- Consumes: AST node types (`CallExpr`, `FieldRefExpr`, etc. from `ast.dart`), `aggregateCalculationFor` (from `aggregate/aggregate_functions.dart`).
- Produces: `Set<String> get aggregateOperandFields` on `Expression`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/expression/aggregate_operand_fields_test.dart`:

```dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/expression/expression.dart';

void main() {
  test('reports the operand of a top-level aggregate', () {
    expect(Expression.parse(r'SUM($F{lineTotal})').aggregateOperandFields,
        <String>{'lineTotal'});
  });

  test('reports operands of aggregate sub-terms in a compound expression', () {
    expect(
      Expression.parse(r'SUM($F{lineTotal}) + COUNT($F{orderNo})')
          .aggregateOperandFields,
      <String>{'lineTotal', 'orderNo'},
    );
  });

  test('a bare field reference is not an aggregate operand', () {
    expect(Expression.parse(r'$F{lineTotal}').aggregateOperandFields, isEmpty);
  });

  test('a non-aggregate call argument is not an aggregate operand', () {
    expect(Expression.parse(r'UPPER($F{name})').aggregateOperandFields, isEmpty);
  });

  test('a field used both bare and as an operand is reported (operand wins)',
      () {
    expect(
      Expression.parse(r'SUM($F{x}) + $F{x}').aggregateOperandFields,
      <String>{'x'},
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/expression/aggregate_operand_fields_test.dart`
Expected: FAIL — `aggregateOperandFields` is not defined on `Expression`.

- [ ] **Step 3: Implement the getter**

In `expression.dart`, add `import 'aggregate/aggregate_functions.dart';` and add this getter to the `Expression` class (after `references`):

```dart
  /// The `$F{}` field names that appear as the operand of an aggregate call
  /// (`SUM`/`AVG`/`COUNT`/`MIN`/`MAX`) anywhere in this expression — including
  /// aggregate sub-terms of a compound expression (`SUM($F{x}) + 1`). A field
  /// referenced only outside an aggregate is NOT reported. Used by the designer
  /// to accept a descendant leaf as a valid aggregate operand while still
  /// flagging the same leaf when referenced bare (spec 033, FR-006/FR-007).
  Set<String> get aggregateOperandFields {
    final Set<String> operands = <String>{};
    void collectFields(Expr node) {
      switch (node) {
        case FieldRefExpr(name: final String n):
          operands.add(n);
        case UnaryExpr(operand: final Expr o):
          collectFields(o);
        case BinaryExpr(left: final Expr l, right: final Expr r):
          collectFields(l);
          collectFields(r);
        case ConditionalExpr(
            condition: final Expr c,
            thenBranch: final Expr t,
            elseBranch: final Expr e
          ):
          collectFields(c);
          collectFields(t);
          collectFields(e);
        case CallExpr(arguments: final List<Expr> args):
          for (final Expr a in args) {
            collectFields(a);
          }
        case LiteralExpr():
        case ParamRefExpr():
        case VariableRefExpr():
          break;
      }
    }

    void walk(Expr node) {
      if (node is CallExpr && aggregateCalculationFor(node.name) != null) {
        for (final Expr a in node.arguments) {
          collectFields(a);
        }
        return; // operands of this aggregate collected; don't double-walk them
      }
      switch (node) {
        case UnaryExpr(operand: final Expr o):
          walk(o);
        case BinaryExpr(left: final Expr l, right: final Expr r):
          walk(l);
          walk(r);
        case ConditionalExpr(
            condition: final Expr c,
            thenBranch: final Expr t,
            elseBranch: final Expr e
          ):
          walk(c);
          walk(t);
          walk(e);
        case CallExpr(arguments: final List<Expr> args):
          for (final Expr a in args) {
            walk(a);
          }
        case LiteralExpr():
        case FieldRefExpr():
        case ParamRefExpr():
        case VariableRefExpr():
          break;
      }
    }

    walk(_root);
    return operands;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run (from `packages/jet_print`): `flutter test test/expression/aggregate_operand_fields_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/expression/expression.dart packages/jet_print/test/expression/aggregate_operand_fields_test.dart
git commit -m "feat(033): Expression.aggregateOperandFields (AST walk over aggregate operands)"
```

---

### Task 2: Descendant operand names + field choices (binding resolution)

Add author-time helpers that report, for a band, the descendant leaf names valid as aggregate operands (unique descend path from the band's own scope) and the matching `FieldDef`s for the palette.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/controller/binding_resolution.dart`
- Test: `packages/jet_print/test/designer/controller/binding_resolution_descendant_test.dart` (create)

**Interfaces:**
- Consumes: `resolveAggregatePath` / `DescendPath` (engine Task 1), `fieldsInScopeForChain` (`data/binding_scope.dart`), `scopePathToBand` (`band_walker.dart`), `FieldDef`, `JetFieldType`.
- Produces:
  ```dart
  Set<String> descendantOperandNamesForBand(ReportDefinition def, JetDataSchema schema, String bandId);
  List<FieldDef> descendantFieldChoicesForBand(ReportDefinition def, JetDataSchema schema, String bandId);
  ```
  Both resolve against the band's **own** scope chain (`scopePathToBand`) — an aggregate folds over the band's own scope subtree, so operands descend from there (a nested footer uses its own scope, not the parent union that `resolvableNamesForBand` adds for same-scope binding). A name is included only when `resolveAggregatePath` returns `DescendPath` (excludes same-scope names — already offered as normal fields — and ambiguous names).

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/controller/binding_resolution_descendant_test.dart`. Build a Customer ▸ Order ▸ Line `ReportDefinition` (master = customers; a `customer` root group with a footer band id `cf`; the summary band id `summary`) and the matching `JetDataSchema` (root: `customerCode`, `orders`[collection: `orderNo`, `lines`[collection: `lineTotal`]]). Assert:
- `descendantOperandNamesForBand(def, schema, 'summary')` contains `lineTotal` and `orderNo` (both uniquely reachable) and **not** `customerCode` (same-scope) or `orders`/`lines` (collections);
- `descendantOperandNamesForBand(def, schema, 'cf')` (root group footer, root scope) is the same set;
- `descendantFieldChoicesForBand(def, schema, 'summary')` returns `FieldDef`s whose names are exactly that set;
- for a schema with two sibling collections sharing a leaf name, the ambiguous name is **absent** from both results.

- [ ] **Step 2: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/designer/controller/binding_resolution_descendant_test.dart`
Expected: FAIL — the two functions don't exist.

- [ ] **Step 3: Implement the helpers**

In `binding_resolution.dart`, add imports `import '../../data/aggregate_path.dart';` (the file already imports `binding_scope.dart`, `data_schema.dart`, `field_def.dart`, `detail_scope.dart`, `report_definition.dart`, `band_walker.dart`). Append:

```dart
/// The descendant leaf names valid as inline-aggregate operands in band
/// [bandId]: every non-collection leaf uniquely reachable (a [DescendPath]) by
/// descending the collection subtree of the band's OWN scope. Excludes
/// same-scope names (already offered as normal fields) and ambiguous names (an
/// author-time error). The author writes these only inside an aggregate;
/// referenced bare they remain unresolved (FR-006).
Set<String> descendantOperandNamesForBand(
    ReportDefinition def, JetDataSchema schema, String bandId) {
  final List<DetailScope> chain = scopePathToBand(def, bandId);
  final List<FieldDef> scopeFields = fieldsInScopeForChain(schema, chain);
  final Set<String> out = <String>{};
  void collectLeaves(List<FieldDef> fields) {
    for (final FieldDef f in fields) {
      if (f.type == JetFieldType.collection) {
        collectLeaves(f.fields);
      } else {
        if (resolveAggregatePath(scopeFields, f.name) is DescendPath) {
          out.add(f.name);
        }
      }
    }
  }

  // Only leaves inside collections can be descendant operands; walk each
  // collection field's subtree.
  for (final FieldDef f in scopeFields) {
    if (f.type == JetFieldType.collection) collectLeaves(f.fields);
  }
  return out;
}

/// The fx field-palette choices for descendant operands in band [bandId]: a
/// synthetic [FieldDef] per name from [descendantOperandNamesForBand], typed
/// [JetFieldType.unknown] (the palette inserts the plain `[name]` token). These
/// are rendered marked as deeper-collection fields, distinct from in-scope
/// fields (FR-007).
List<FieldDef> descendantFieldChoicesForBand(
    ReportDefinition def, JetDataSchema schema, String bandId) {
  return <FieldDef>[
    for (final String name in descendantOperandNamesForBand(def, schema, bandId))
      FieldDef(name),
  ];
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run (from `packages/jet_print`): `flutter test test/designer/controller/binding_resolution_descendant_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/designer/controller/binding_resolution.dart packages/jet_print/test/designer/controller/binding_resolution_descendant_test.dart
git commit -m "feat(033): descendant operand names + field choices for a band"
```

---

### Task 3: Aggregate-operand-aware `statusFor`

Make the fx editor's pure status function accept descendant operands: a `$F{}` ref is resolvable when it is in `names`, or when it is an aggregate operand **and** a descendant operand. A bare descendant ref is still Unresolved.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/expression_editor_dialog.dart`
- Test: `packages/jet_print/test/designer/expression_editor_status_descendant_test.dart` (create)

**Interfaces:**
- Consumes: `Expression.aggregateOperandFields` (Task 1), `fieldRefsIn` (`data/binding_scope.dart`), `parseValueField` / `BindingValue` (existing).
- Produces: new `statusFor` signature `EditorStatus statusFor(String text, Set<String> names, {Set<String> descendantOperands = const <String>{}})`.

- [ ] **Step 1: Write the failing test**

Create `packages/jet_print/test/designer/expression_editor_status_descendant_test.dart`:

```dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/designer/layout/panels/expression_editor_dialog.dart';

void main() {
  const Set<String> names = <String>{'customerCode'}; // in-scope at this band
  const Set<String> deep = <String>{'lineTotal'}; // descendant operand

  test('a descendant leaf as an aggregate operand is Valid', () {
    expect(statusFor('{SUM([lineTotal])}', names, descendantOperands: deep),
        isA<StatusValid>());
  });

  test('a bare descendant leaf is Unresolved', () {
    final EditorStatus s =
        statusFor('[lineTotal]', names, descendantOperands: deep);
    expect(s, isA<StatusUnresolved>());
    expect((s as StatusUnresolved).name, 'lineTotal');
  });

  test('an in-scope field stays Valid', () {
    expect(statusFor('[customerCode]', names, descendantOperands: deep),
        isA<StatusValid>());
  });

  test('an unknown operand is Unresolved', () {
    final EditorStatus s =
        statusFor('{SUM([nope])}', names, descendantOperands: deep);
    expect(s, isA<StatusUnresolved>());
    expect((s as StatusUnresolved).name, 'nope');
  });

  test('a compound aggregate with a descendant operand is Valid', () {
    expect(
        statusFor('{SUM([lineTotal]) * 1.1}', names, descendantOperands: deep),
        isA<StatusValid>());
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/designer/expression_editor_status_descendant_test.dart`
Expected: FAIL — `statusFor` has no `descendantOperands` parameter (the descendant-operand and bare cases both currently return `StatusUnresolved`/compile-error).

- [ ] **Step 3: Update `statusFor`**

In `expression_editor_dialog.dart`, add `import '../../../expression/expression.dart';` and replace `statusFor` with:

```dart
/// Pure status computation, unit-testable independent of the widget.
/// - A binding (`{…}` / `[field]`): every `$F{}` ref must resolve — it is
///   resolvable when it is in [names], or when it is an aggregate operand and a
///   [descendantOperands] leaf (spec 033). A bare descendant ref (not an
///   aggregate operand) stays unresolved (FR-006). First out-of-scope ref →
///   unresolved(that name).
/// - A `{…}`-wrapped value that does NOT parse to a binding → syntax error.
/// - Plain literal text → valid.
EditorStatus statusFor(String text, Set<String> names,
    {Set<String> descendantOperands = const <String>{}}) {
  final ValueParse parse = parseValueField(text);
  if (parse is BindingValue) {
    Set<String> operandRefs;
    try {
      operandRefs = Expression.parse(parse.expression).aggregateOperandFields;
    } on Object {
      operandRefs = const <String>{};
    }
    for (final String ref in fieldRefsIn(parse.expression)) {
      if (names.contains(ref)) continue;
      if (operandRefs.contains(ref) && descendantOperands.contains(ref)) {
        continue;
      }
      return StatusUnresolved(ref);
    }
    return const StatusValid();
  }
  final String t = text.trim();
  if (t.length >= 2 && t.startsWith('{') && t.endsWith('}')) {
    return const StatusSyntaxError();
  }
  return const StatusValid();
}
```

- [ ] **Step 4: Run the new test + the existing fx editor tests**

Run (from `packages/jet_print`): `flutter test test/designer/expression_editor_status_descendant_test.dart test/designer/value_field_fx_test.dart`
Expected: PASS — new descendant cases pass; existing `value_field_fx_test.dart` (no `descendantOperands` arg → defaults empty → unchanged behavior) stays green.

- [ ] **Step 5: Commit**

```bash
git add packages/jet_print/lib/src/designer/layout/panels/expression_editor_dialog.dart packages/jet_print/test/designer/expression_editor_status_descendant_test.dart
git commit -m "feat(033): aggregate-operand-aware fx status (descendant operand Valid, bare Unresolved)"
```

---

### Task 4: Localization for the descendant-field marker

Add one label used as the tooltip/marker for descendant field buttons in the fx palette.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/l10n/jet_print_localizations.dart` (abstract), `..._en.dart`, `..._de.dart`, `..._tr.dart`

- [ ] **Step 1: Add the abstract getter**

In `jet_print_localizations.dart`, near `exprEditorFieldsLabel` (line ~522), add:

```dart
  /// Tooltip/marker shown on a fx-palette field button that belongs to a deeper
  /// (descendant) collection — valid only inside an aggregate (spec 033).
  String get exprEditorDeeperFieldHint;
```

- [ ] **Step 2: Add the per-locale strings**

- In `..._en.dart` (near line 220): `String get exprEditorDeeperFieldHint => 'From a nested collection — use inside an aggregate (e.g. SUM)';`
- In `..._de.dart`: `String get exprEditorDeeperFieldHint => 'Aus einer verschachtelten Sammlung — nur innerhalb einer Aggregatfunktion (z. B. SUM)';`
- In `..._tr.dart`: `String get exprEditorDeeperFieldHint => 'İç içe bir koleksiyondan — yalnızca bir toplama işlevi içinde (örn. SUM)';`

- [ ] **Step 3: Verify it compiles**

Run (from `packages/jet_print`): `flutter analyze lib/src/designer/l10n`
Expected: no errors (every locale implements the new abstract getter).

- [ ] **Step 4: Commit**

```bash
git add packages/jet_print/lib/src/designer/l10n/
git commit -m "feat(033): l10n for the fx descendant-field marker (en/de/tr)"
```

---

### Task 5: Wire the Properties panel + fx palette

Thread descendant operands and descendant field choices through the value field, the fx editor, and the unresolved hint, and render descendant field buttons marked.

**Files:**
- Modify: `packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart`
- Modify: `packages/jet_print/lib/src/designer/layout/panels/expression_editor_dialog.dart`
- Test: `packages/jet_print/test/designer/value_field_descendant_test.dart` (create)

**Interfaces:**
- Consumes: `descendantOperandNamesForBand` / `descendantFieldChoicesForBand` (Task 2), the aggregate-aware `statusFor` (Task 3), `Expression.aggregateOperandFields` (Task 1), `exprEditorDeeperFieldHint` (Task 4).
- Produces: extended `showExpressionEditor` / `_ExpressionEditorDialog` / `_ValueField` signatures carrying `descendantOperands` + `descendantFields`.

**Wiring steps (no behavior change when no schema is attached):**

1. **Properties panel — compute the new sets.** Add two helpers beside `_resolvableNames` (lines ~555–564), mirroring its null-guards:
   ```dart
   Set<String> _descendantOperands(JetDataSchema? schema,
       JetReportDesignerController controller, String elementId) {
     if (schema == null) return const <String>{};
     final Band? band = findBandOfElement(controller.definition, elementId);
     if (band == null) return const <String>{};
     return descendantOperandNamesForBand(controller.definition, schema, band.id);
   }

   List<FieldDef> _descendantFields(JetDataSchema? schema,
       JetReportDesignerController controller, String elementId) {
     if (schema == null) return const <FieldDef>[];
     final Band? band = findBandOfElement(controller.definition, elementId);
     if (band == null) return const <FieldDef>[];
     return descendantFieldChoicesForBand(controller.definition, schema, band.id);
   }
   ```
   Add `import '../../controller/binding_resolution.dart';` if not already importing those symbols (the panel already calls `resolvableNamesForBand`/`resolvableFieldChoices`, so the import exists).

2. **Properties panel — make `_unresolved` aggregate-operand-aware.** Replace the `expression` branch of `_unresolved` (line ~547) so a descendant operand inside an aggregate is not flagged:
   ```dart
   if (expression != null) {
     final Set<String> deep =
         descendantOperandNamesForBand(controller.definition, schema, band.id);
     return !_resolvesAggregateAware(names, deep, expression);
   }
   ```
   Add a private helper in the same class:
   ```dart
   /// True when every `$F{}` ref in [expression] is in [names], or is an
   /// aggregate operand and a descendant operand (spec 033). Mirrors the fx
   /// editor's statusFor resolution for the inline Unresolved hint.
   bool _resolvesAggregateAware(
       Set<String> names, Set<String> deep, String expression) {
     Set<String> operandRefs;
     try {
       operandRefs = Expression.parse(expression).aggregateOperandFields;
     } on Object {
       operandRefs = const <String>{};
     }
     for (final String ref in fieldRefsIn(expression)) {
       if (names.contains(ref)) continue;
       if (operandRefs.contains(ref) && deep.contains(ref)) continue;
       return false;
     }
     return true;
   }
   ```
   Add imports `import '../../../expression/expression.dart';` and ensure `fieldRefsIn` (from `data/binding_scope.dart`) is imported (the panel already uses `expressionResolvesNames`, so `binding_scope.dart` is imported).

3. **Properties panel — pass the new data to `_ValueField`.** In the `_ValueField(...)` construction (lines ~228–240), add:
   ```dart
   descendantOperands: _descendantOperands(schema, controller, id),
   descendantFields: _descendantFields(schema, controller, id),
   ```

4. **`_ValueField` — carry the new fields and forward to the fx editor.** Add `final Set<String> descendantOperands;` and `final List<FieldDef> descendantFields;` (with defaults `const <String>{}` / `const <FieldDef>[]`) to `_ValueField` and its constructor (lines ~1800–1835). In `_openFx` (line ~1884), pass them on:
   ```dart
   final String? result = await showExpressionEditor(
     context,
     initialText: widget.display.text,
     resolvableNames: widget.resolvableNames,
     fields: widget.fields,
     descendantOperands: widget.descendantOperands,
     descendantFields: widget.descendantFields,
   );
   ```

5. **fx editor — accept and use the new inputs.** In `expression_editor_dialog.dart`:
   - Extend `showExpressionEditor` and `_ExpressionEditorDialog` with `Set<String> descendantOperands = const <String>{}` and `List<FieldDef> descendantFields = const <FieldDef>[]`.
   - Pass `descendantOperands: widget.descendantOperands` into the two `statusFor(...)` calls (init + `_onChange`).
   - In the build method's fields `Wrap` (lines ~171–184), after the in-scope field buttons, render the descendant field buttons marked — wrap each in a `Tooltip` with `l10n.exprEditorDeeperFieldHint`, use a distinct key prefix and a muted/italic style so they read as "deeper":
     ```dart
     for (final FieldDef f in widget.descendantFields)
       Tooltip(
         message: l10n.exprEditorDeeperFieldHint,
         child: ShadButton.ghost(
           key: ValueKey<String>('$_k.deepField.${f.name}'),
           size: ShadButtonSize.sm,
           onPressed: () => _insertAtCaret('[${f.name}]', '[${f.name}]'.length),
           child: Text('↳ ${f.name}',
               style: const TextStyle(fontStyle: FontStyle.italic)),
         ),
       ),
     ```

- [ ] **Step 1: Write the failing widget test**

Create `packages/jet_print/test/designer/value_field_descendant_test.dart`. Pump the designer (or the Properties panel) with the Customer ▸ Order ▸ Line definition + schema, select the summary element whose value is `{SUM([lineTotal])}`, and assert:
- the inline Unresolved hint (`_UnresolvedHint`, keyed text `bindingUnresolved`) is **not** shown for `{SUM([lineTotal])}`;
- it **is** shown when the value is `[lineTotal]` (bare);
- opening the fx editor shows a descendant field button keyed `jet_print.designer.exprEditor.deepField.lineTotal`, and the status line reads Valid for `{SUM([lineTotal])}`.

Model the pump/select harness on the existing fx widget test `test/designer/value_field_fx_test.dart`.

- [ ] **Step 2: Run the test to verify it fails**

Run (from `packages/jet_print`): `flutter test test/designer/value_field_descendant_test.dart`
Expected: FAIL — descendant button absent and/or the Unresolved hint shows for `{SUM([lineTotal])}` before wiring.

- [ ] **Step 3: Apply the wiring (steps 1–5 above)**

- [ ] **Step 4: Run the new test + the designer suite**

Run (from `packages/jet_print`): `flutter test test/designer/`
Expected: PASS — new descendant widget test passes; existing designer/fx/properties tests stay green (defaults preserve current behavior with no schema).

- [ ] **Step 5: Run full suite + analyze**

Run (from `packages/jet_print`): `flutter test` then `flutter analyze`
Expected: full suite green; `flutter analyze` clean (no unused imports, no missing l10n overrides).

- [ ] **Step 6: Commit**

```bash
git add packages/jet_print/lib/src/designer/layout/panels/properties_panel.dart packages/jet_print/lib/src/designer/layout/panels/expression_editor_dialog.dart packages/jet_print/test/designer/value_field_descendant_test.dart
git commit -m "feat(033): designer surfaces descendant operands — Valid status, unflagged hint, marked palette"
```

---

## Self-Review (designer)

**Spec coverage:**
- FR-007 (aggregate-operand-aware `statusFor`, `_unresolved`, value-field choices; palette offers descendant leaves, marked, inserting `[field]`) → Tasks 3, 5 (+ Task 1 helper, Task 2 sets, Task 4 marker label).
- FR-006 (bare deep ref stays Unresolved) → Tasks 3, 5 tests (the bare-`[lineTotal]` case).
- SC-002 (fx editor shows Valid for `{SUM([lineTotal])}` at the customer footer and Unresolved for bare `[lineTotal]`) → Tasks 3, 5 tests.
- FR-001 same-scope/ambiguous handling → Task 2 (only `DescendPath` names offered/accepted; ambiguous excluded, errored by engine `validate(def, schema:)`).
- US2 (designer accepts the deep aggregate; palette lists `lineTotal` marked) → Task 5.

**Placeholder scan:** none — `statusFor`, the binding-resolution helpers, the AST walk, and every wiring edit ship complete code. The two widget-test tasks (Task 5) describe the pump/select harness by reference to the existing `value_field_fx_test.dart` rather than re-inlining it; assertions and widget keys are fully specified.

**Type consistency:** `descendantOperands: Set<String>` and `descendantFields: List<FieldDef>` are named identically across `_ValueField`, `showExpressionEditor`, `_ExpressionEditorDialog`, and the `statusFor` parameter. `descendantOperandNamesForBand`/`descendantFieldChoicesForBand` (Task 2) are consumed verbatim by the panel helpers (Task 5). `Expression.aggregateOperandFields` (Task 1) is used identically in `statusFor` (Task 3) and `_resolvesAggregateAware` (Task 5). The fx-editor descendant button key prefix `jet_print.designer.exprEditor.deepField.<name>` matches between the implementation (Task 5 step 5) and the widget test (Task 5 step 1).

**Dependency:** Tasks 2–5 require engine Task 1 (`resolveAggregatePath`). Task 1 here (the AST helper) is self-contained and can land first.
