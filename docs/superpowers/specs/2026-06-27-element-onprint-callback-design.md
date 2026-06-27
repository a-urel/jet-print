# Element `onPrint` Callback — Design

**Date:** 2026-06-27
**Status:** Design approved, pending spec review → plan.
**Type:** Additive public API + a single fill-IR field. No serialization change, no designer model change, no breaking change.

## 1. Problem

Hosts need to customize report output per element at render time using logic that lives in their own Dart code — conditional fore-color, dynamic text, suppression — based on the underlying data, the band, running aggregates, and the page. JasperReports solves this with element-level `onPrint` scriptlet events. jet_print today exposes no element-level hook: the only callbacks are UI-layer (`JetReportWorkspace.onSave/onOpen/onPrint`, `JetReportPreview.onPrint`) and they receive the finished `RenderedReport`, with no way to intercept or alter an individual element.

## 2. Goal

A host-supplied Dart callback, invoked once for every element about to be painted, that may return a modified copy of the element, return it unchanged, or suppress it. It runs identically on preview, export, and print, because all three render through `JetReportEngine.renderDefinition(...)`.

**Non-goals (YAGNI):**
- No band / page / report lifecycle events — element-level only.
- No authored, serialized expression properties (no `printWhenExpression` in the template). This is host code, not template data.
- No custom expression functions, no visitor API.

## 3. Decisions (from brainstorming)

| Decision | Choice | Consequence |
|---|---|---|
| Mechanism | **Host Dart callback** | Logic in app code, not in the `.json` template. Designer cannot run it; preview/export/print can (they have the host's `RenderOptions`). |
| Capability | **Transform + suppress** | Return modified copy, `null` to suppress, or same to pass through. Plus free side-effects. |
| Scope | **Per-element only** | One callback, fired per element. Host branches on `element.id`/type itself. |
| Context | **fields + band + variables + page#/count** | All four coexist only at emit time (post-pagination). |
| Seam | **Emit-time** (`LazyLayout.buildPage` → `_place`) | Page number available; element size already fixed. |
| Mutable scope | **Any field, same runtime type** | Type swap rejected (diagnostic + fall back to original). |

### 3.1 The seam ↔ fixed-size coupling

Wanting `pageNumber`/`pageCount` forces firing **after** pagination, which is **after** measurement. So a returned element whose content needs more height does **not** reflow — it clips at the element's existing bounds. This is faithful to Jasper's `onPrint` (the element is already positioned and sized when the event fires) and is a documented contract, not a defect. Position (bounds x/y) changes are honored; height changes clip/overlap.

## 4. Public API

New exports from `lib/jet_print.dart`:

```dart
/// Fired once for every element about to be painted, on preview, export, and
/// print alike. Return [element] unchanged to pass through, a modified copy
/// (same runtime type) to alter it, or null to suppress it.
///
/// The element's bounds are already fixed at emit time: changing content that
/// needs more height clips at the existing box rather than reflowing the band
/// (Jasper-faithful). Position changes are honored.
///
/// MUST be deterministic over (element, context): the callback runs on every
/// render pass, and preview / export / print are separate passes — a callback
/// that reads a clock, RNG, or live data source makes them diverge.
typedef JetElementPrintCallback = ReportElement? Function(
  ReportElement element,
  ElementPrintContext context,
);

/// Read-only context handed to [JetElementPrintCallback] at emit time.
class ElementPrintContext {
  const ElementPrintContext({
    required this.pageNumber,
    required this.pageCount,
    required this.bandType,
    required this.bandName,
    required this.fields,
    required this.variables,
  });

  /// 1-based page index the element is printing on.
  final int pageNumber;

  /// Total resolved page count.
  final int pageCount;

  /// The role of the band this element belongs to (detail / groupHeader /
  /// summary / pageHeader / ...).
  final BandType bandType;

  /// The group name for group bands (from the fill IR's `group`); null for
  /// non-group bands. (The fill IR does not carry a band id today, so this is
  /// group-only; adding a band id would be a separate IR field.)
  final String? bandName;

  /// The current row's field values, keyed by field name. Empty for page
  /// chrome and static bands (host must null-check, not assume presence).
  final Map<String, JetValue> fields;

  /// The variable / running-aggregate snapshot as of this band instance.
  final Map<String, JetValue> variables;
}
```

Wired via one new field on the existing `RenderOptions` (const class, neutral default):

```dart
/// Host hook invoked per element at emit time, on preview/export/print alike.
/// Null (default) means no hook and byte-identical output to today (SC-006).
final JetElementPrintCallback? onElementPrint;
```

`JetReportWorkspace` / `JetReportPreview` gain a matching pass-through parameter so the playground and designer-driven previews can wire it into the `RenderOptions` they build.

`ReportElement`, `BandType`, `JetValue` are already public. `JetElementPrintCallback` and `ElementPrintContext` are the only new symbols.

### 4.1 Host usage

```dart
RenderOptions(
  onElementPrint: (el, ctx) {
    if (el is! TextElement || el.id != 'amount') return el;     // narrow first
    final total = ctx.fields['total'];                          // raw row value
    if (total is JetNumber && total.value < 0) {
      return el.copyWith(style: el.style.copyWith(color: JetColor.red));
    }
    return el;
  },
)
```

`ctx.fields['total']` is the **raw** `JetValue`; `el.text` is the already-formatted display string. Host branches on the raw data, may rewrite either layer.

## 5. Pipeline changes

Dependencies point inward; no layer above is touched beyond the new option field.

1. **Fill IR — row fields snapshot.**
   `FilledBand` gains `final Map<String, JetValue> fields` (defensively frozen, like `variables`). `ReportFiller` populates it from the current `DataRow` for per-row bands; `{}` for chrome/static bands. This is the only fill-layer change — the row is not on the IR today. `MeasuredBand` already carries its `FilledBand`, so `fields` reaches layout for free.

2. **Emit-time invocation** in `LazyLayout._place` (the single choke point both body bands and page chrome flow through). Before `renderer.emit(el, ...)`:
   - Build `ElementPrintContext` from the `buildPage` index (+1), the resolved `pageCount`, and the band's `type` / `group` / `fields` / `variables`.
   - Call the callback inside a guard:
     ```dart
     ReportElement? out = el;
     final cb = _onElementPrint;
     if (cb != null) {
       try {
         out = cb(el, ctx);
       } catch (e, st) {
         _diagnostics.warn('onElementPrint threw for ${el.id}: $e');
         out = el;                                  // fail-safe to original
       }
       if (out == null) continue;                  // suppress: skip emit
       if (out.runtimeType != el.runtimeType) {
         _diagnostics.warn('onElementPrint returned a different type for '
             '${el.id}; ignoring');
         out = el;                                  // same-type guard
       }
     }
     _renderers.rendererFor(out).emit(out, _ctx, bounds, fb);
     ```
   `_onElementPrint` and the diagnostics sink are carried as `LazyLayout` fields, threaded from `JetReportEngine.renderDefinition` via `RenderOptions`.

3. **Page chrome** flows through the same `_place`, so the hook fires for header/footer elements too, with `fields: {}` and `bandType: pageHeader/pageFooter`.

4. **Fail-safe** (above): a throwing or wrong-type callback never crashes the render — it falls back to the original element and records a diagnostic, mirroring the `visible` fail-safe.

**Untouched:** serialization/codecs, designer model & commands, measurement, renderers, frame primitives, paint backends (Canvas/PDF/PNG).

## 6. Edge cases & contracts

- **Determinism** (documented, not enforced): hook must be pure over `(element, context)`; non-deterministic hooks make preview ≠ export ≠ print. Dartdoc warns.
- **Page caching**: `RenderedReport` caches built page frames; the hook fires when a page is first built, not on re-request of a cached page. Consistent under the determinism contract.
- **Suppression**: `null` drops only the paint; the band keeps its reserved height (no reflow).
- **Empty fields**: chrome / static bands pass `fields: {}`; host must null-check.
- **`null` callback**: zero overhead, byte-identical output to today.
- **Position vs size**: returned bounds x/y honored; width/height changes clip/overlap because measurement is fixed.

## 7. Testing

- **Unit (fill):** `FilledBand.fields` populated from the row; `{}` for chrome.
- **Unit (emit seam):** pass-through (same → identical frame), transform (color/text change reflected in the emitted primitive), suppress (`null` → element absent), same-type guard (wrong type → original + diagnostic), throw (→ original + diagnostic).
- **Context correctness:** `pageNumber` / `pageCount` / `bandType` / `bandName` / `fields` / `variables` carry expected values across a multi-page grouped report (chrome band → empty fields).
- **Golden safety (hard gate):** `onElementPrint == null` → every existing golden byte-identical (Constitution IV).
- **Integration:** one report driven through `renderDefinition` — negative amount → red fore-color; a flagged row's badge suppressed — asserted on the resulting frame.
- **Playground (optional):** a demo wiring `onElementPrint` to prove the host ergonomics end-to-end.

## 8. Requirements

- **FR-001** A host may supply `RenderOptions.onElementPrint`, invoked once per element about to be painted.
- **FR-002** The callback receives the resolved element and an `ElementPrintContext` (`pageNumber`, `pageCount`, `bandType`, `bandName` = group name or null, `fields`, `variables`).
- **FR-003** Returning a same-type modified copy alters the painted element; returning the same element passes through; returning `null` suppresses it.
- **FR-004** A returned element of a different runtime type is ignored (original painted) and a diagnostic recorded.
- **FR-005** A callback that throws is contained: the original element is painted and a diagnostic recorded; the render does not crash.
- **FR-006** The hook fires for body bands and page chrome alike; chrome passes `fields: {}`.
- **FR-007** The hook runs on preview, export, and print via the shared `renderDefinition` path.
- **FR-008** `FilledBand` carries the originating row's field values; `{}` for non-row bands.
- **FR-009** No serialization, designer model, or render-primitive change; element size/measurement is fixed at emit time.

## 9. Success criteria

- **SC-001** A callback recoloring a `TextElement` on a negative value produces a frame whose text-run primitive carries the new color.
- **SC-002** A callback returning `null` for a flagged element produces a frame missing that element; the band height is unchanged.
- **SC-003** `pageNumber`/`pageCount` observed by the callback match the page the element prints on, across a multi-page report.
- **SC-004** `fields` matches the originating row for detail bands and is empty for page chrome.
- **SC-005** A throwing / wrong-type callback yields the unmodified element plus a diagnostic, never a crash.
- **SC-006** `onElementPrint == null` leaves every existing golden byte-identical.
