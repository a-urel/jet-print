# `visible` Property for Report Objects — Design

**Date:** 2026-06-26
**Status:** Approved (brainstorming) → ready for implementation plan
**Scope:** Conditional visibility for elements **and** bands, driven by a static bool or a boolean expression.

## Goal

Let report authors hide any element (text/image/shape/barcode) or any band (furniture, group header/footer, detail, summary, nested-scope footer) either by a static toggle or by a per-row boolean expression. Invisible elements are not painted; invisible bands collapse (the report flows up). Fully back-compatible: existing reports render byte-identical.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Which objects? | **Elements + Bands** |
| Value model | A reusable serializable **`BoolProperty { value, expression }`** value type, one field `visible` per object |
| Precedence | **Expression wins when present**: `expression != null ? eval(expression) : value` |
| Error / non-boolean | **Fail-safe to visible** + record a diagnostic (never silently drop content) |
| Designer UI (first cut) | **Properties panel only**: a "Visible" checkbox + optional fx-editor expression field, undoable commands |

## Architecture

The fill pipeline produces a `FilledBand` stream that the layouter merely stacks. Visibility is therefore a **fill-time filter**, not a paint-time skip — an invisible object literally never enters the `FilledReport` IR. This keeps the layouter/painter unchanged and keeps the IR golden-testable.

### 1. `BoolProperty` — pure, serializable, reusable

`lib/src/domain/bool_property.dart` (new):

```dart
class BoolProperty {
  const BoolProperty({this.value = true, this.expression});

  /// Static fallback used when [expression] is null.
  final bool value;

  /// When non-null, governs visibility (takes precedence over [value]).
  final String? expression;

  bool get hasExpression => expression != null;

  /// Resolves the effective boolean. Precedence lives here; the actual
  /// expression evaluation is INJECTED so this domain type never depends on
  /// the expression engine (Constitution II — layered architecture).
  bool getValue(bool Function(String expr) evaluate) =>
      expression != null ? evaluate(expression!) : value;

  /// [expression] uses the thunk pattern (mirrors barcode_element.dart's
  /// `dataField: () => null`) so callers can DISTINGUISH "keep" from "clear".
  BoolProperty copyWith({bool? value, String Function()? expression});

  Map<String, Object?> toJson();        // omit-when-default (see Serialization)
  factory BoolProperty.fromJson(Map<String, Object?> json);

  @override bool operator ==(Object other);
  @override int get hashCode;
}
```

`const BoolProperty()` (value=true, expression=null) is the default "always visible".

### 2. Model fields

- `ReportElement` (base) gains `final BoolProperty visible` (default `const BoolProperty()`), threaded through every concrete subtype's constructor, `copyWith`, `withBounds`, `withName`, `==`, `hashCode`. `UnknownElement` is a passthrough (its preserved JSON is inert — never rewritten).
- `Band` gains `final BoolProperty visible` (default `const BoolProperty()`) + `copyWith`/`==`/`hashCode`.

One field per object (not two) minimizes the rebuilder surface.

### 3. Fill-time evaluation

Shared helper (fill layer, owns the evaluator + diagnostics):

```dart
// resolveVisibility(prop, ctx, diagnostics, id) -> bool
bool resolveVisibility(BoolProperty prop, FillEvalContext ctx,
    ReportDiagnostics diagnostics, String id) {
  return prop.getValue((expr) {
    // parse + eval + coerce-truthy; on parse error, eval error, or
    // non-boolean result -> record a diagnostic and return TRUE (fail-safe).
  });
}
```

- **Element:** in `report_filler.dart` `addBand`, filter elements whose `resolveVisibility` is false out of the resolved list → absent from `FilledBand.elements` → not painted. Absolute layout means the gap remains (by design; collapsing absolute elements is out of scope).
- **Band:** in `addBand` / `emitOnce`, if the band's `resolveVisibility` is false, do not emit the `FilledBand` → following bands flow up = collapse, with no layouter change.
- Context: the same as a text `expression` — row + params + variables. Page-scoped variables are **not** available in a visible expression (same rule text expressions follow).
- Error contract: parse failure / eval error → `diagnostics.error` + visible; non-boolean result → `diagnostics.warning` + visible.

### 4. Serialization (additive, no schema bump)

`BoolProperty.toJson` is compact and omit-by-default:
- default (`value==true && expression==null`) → the owner omits the `visible` key entirely.
- else → `{ "value": false }` and/or `{ "expression": "..." }` (only non-default sub-keys written).

Owners:
- Each element codec (text/shape/image/barcode): `if (el.visible != const BoolProperty()) 'visible': el.visible.toJson()`; read with `json['visible'] == null ? const BoolProperty() : BoolProperty.fromJson(...)`.
- Band `_encodeBand`/`_decodeBand`: same single pair of sites.

Existing report JSON is unchanged (old files decode to the default → visible). No `reportFormatVersion` bump (follows the `name`-field precedent).

### 5. Designer UI (Properties panel only)

- A "Visible" checkbox bound to `BoolProperty.value`, plus an optional expression field reusing the spec-032 fx editor bound to `BoolProperty.expression`. Shown for the selected element or band.
- Two undoable controller commands: `SetVisibleCommand` (element + band) carrying the new `BoolProperty`, following the existing `set_*_command` pattern. (Single command taking a whole `BoolProperty` is simpler than separate value/expression commands.)
- Properties wiring uses existing band/element lookup (`findBandOfElement`, `scopePathToBand`).

## Risk: the rebuilder sweep (primary risk)

Adding a base field to `ReportElement` historically caused **silent data loss**: a rebuilder that constructs a subtype directly (not via `copyWith`) drops the new field ([[spec-031-designer-total-resolution-status]] dropped a field in 5 scope-rebuilders; [[rename-report-objects-status]] dropped `name` in 5 commands). Mitigation, enforced in the plan:

1. `grep` every **direct constructor** of each element subtype (`TextElement(`, `ShapeElement(`, `ImageElement(`, `BarcodeElement(`) and `Band(` across `lib/` — not just `copyWith` sites.
2. Note `element_resolver.dart` constructs fresh `TextElement(...)` on parse-error / unresolved-field / page-ref branches — those resolved copies must carry `visible` forward (or it is intentionally irrelevant post-fill, since visibility was already applied; document the choice).
3. Final opus review specifically auditing field preservation across all rebuilders.

## Testing

- `bool_property_test.dart`: precedence (expression wins), `getValue` with injected evaluator, JSON round-trip incl. default omission, `copyWith` keep-vs-clear thunk.
- Domain: each element subtype + `Band` — `copyWith`/`withName`/`withBounds`/`==`/`hashCode` preserve `visible`.
- Codec: round-trip + old-JSON-without-key → default visible (back-compat).
- Fill: invisible element omitted; invisible band collapses; expression true/false; parse-error / eval-error / non-boolean → visible + correct diagnostic; static `value:false`.
- Designer: command undo/redo; Properties panel toggles + expression wiring.
- Goldens: unchanged for all-visible reports.

## Out of scope (first cut)

- Outline tree hidden-indicator (eye-off icon / dimming).
- Page-scoped variables inside a visible expression.
- Collapsing the gap left by an invisible **element** (absolute layout keeps it).
- Reusing `BoolProperty` for other properties (it is built reusable, but no other property is migrated now).

## Files (anticipated)

**New**
- `lib/src/domain/bool_property.dart`
- `test/domain/bool_property_test.dart`

**Modified — domain**
- `report_element.dart`, `band.dart`, `elements/{text,shape,image,barcode}_element.dart`, `unknown_element.dart`

**Modified — serialization**
- `serialization/{text,shape,image,barcode}_element_codec.dart`, `serialization/report_definition_codec.dart`

**Modified — fill**
- `rendering/fill/element_resolver.dart` (or a new `visibility.dart` helper), `rendering/fill/report_filler.dart`

**Modified — designer**
- `designer/layout/panels/properties_panel.dart`, new `designer/controller/commands/set_visible_command.dart`, command registration

**Tests** as listed under Testing.
