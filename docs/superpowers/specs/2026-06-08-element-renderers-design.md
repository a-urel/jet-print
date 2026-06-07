# Spec 007a — Element Renderers · Design

**Status:** approved-pending-review · **Date:** 2026-06-08 · **Depends on:** 003 (domain
elements, geometry, styles, codecs), 006 (frame primitives, `FrameBuilder`, `TextMeasurer`,
`FontRegistry`). Uses 005 (`JetValue`/`jetStringify`) only transitively. · **Layer:**
`rendering/elements/` (inward DAG: `rendering → domain, data, expression`; never Flutter).

007a is the **first half** of blueprint spec 007 (Element Types + Fill), split — like 005a/005b —
into **007a Element Renderers** (this spec) and **007b Fill**. 007a delivers the rendering-side
extension point and the built-in renderers over *authored* element content. 007b adds the data
pass (`FilledReport`, expression resolution, group sequencing, deferred placeholders, diagnostics).

---

## 1. Purpose & the Principle-II proof

Deliver `ElementRenderer<E>` (measure + emit) and a registry that pairs it with the existing
domain-side `ElementCodec<E>` through one `register<E>(typeKey, codec, renderer)` call — so a
custom element type is **both persistable and renderable with zero core edits**. Ship built-in
renderers for `text`, `shape` (line/rect), `image`, and a `barcode` *placeholder*, plus an
`unknown` placeholder renderer.

The flagship test registers a **test-only** `StarElement` (`+ StarCodec + StarRenderer`, defined
entirely in test code) and asserts it **(a)** round-trips through JSON unchanged *and* **(b)**
emits its expected primitive — with no edits to library `src/`. That single test is the
Constitution-II proof for persistence *and* rendering.

## 2. Scope & boundary

**In scope (007a):** the render contract (`JetConstraints`, `RenderContext`, `ElementRenderer`),
`ElementRendererRegistry`, `ElementTypeRegistry` (the unified registration), five built-in
renderers, a shared visible-placeholder helper, and one **006 contract amendment**
(`MeasuredText.fontFamily`).

**Domain footprint:** exactly one additive value type — `JetConstraints` joins
`domain/geometry.dart` (the blueprint names it beside `JetSize`/`JetRect`). No model or
serialization change. **No** text-`expression` field — that is added in 007b, where Fill consumes
it.

**Out of scope → 007b/later (named, not silent):** the text `expression` field and its evaluation,
`FilledReport`, dataset iteration, group header/footer sequencing, deferred page-scoped
placeholders, a diagnostics sink on the context, and real `FieldImageSource`/`UrlImageSource` byte
resolution → **007b**. Real barcode symbology (Code128/EAN/QR/DataMatrix) → its own later spec.

## 3. The resolved-element contract (the 007a↔007b seam)

007a renderers **render the element they are handed** — there is no resolved-value side-channel.
Dynamic data reaches a renderer because **007b's Fill produces a *resolved copy* of each element,
per band instance**, and Layout (008) calls the renderer on that copy.

A **resolved element** is defined tightly, so 007b cannot grow into a parallel element hierarchy:

> A resolved element is the **same concrete type** as its authored element, with **identical**
> `typeKey`, `id`, `bounds`, and **all authored style/layout fields preserved**. Only
> **data-bearing fields** are substituted with their resolved values.

| Element | Data-bearing field(s) substituted | Preserved as authored |
|---|---|---|
| `TextElement` | `text` (← evaluated expression; an unbound element keeps its literal `text`) | `id`, `bounds`, `style` |
| `BarcodeElement` | `data` | `id`, `bounds`, `symbology`, `color` |
| `ImageElement` | `source` (→ `BytesImageSource(resolvedBytes)`) | `id`, `bounds`, `fit` |
| `ShapeElement` | *(none — purely static)* | all; resolved copy == authored |
| `UnknownElement` | *(none — rendered as placeholder)* | preserved verbatim |

**Consequences (why this shape was chosen over a value channel):**
- *No null sentinel.* A binding that resolves to null yields `text: ''` (blank), distinct from an
  unbound element that keeps its literal — no presence/value ambiguity.
- *No heterogeneous carrier.* Resolved image bytes live in the element's own typed
  `BytesImageSource`, not in a `Map<id, JetValue>` (which cannot hold bytes — `JetValue.from` in
  `expression/value.dart` maps `Uint8List` to a `JetError`).
- *No lookup-key ambiguity.* One authored element repeated across rows becomes **one resolved copy
  per band instance**; the renderer never indexes a shared map by id.

Renderers authored in 007a therefore need **zero changes** in 007b: Fill swaps in resolved copies
and the renderer never learns it happened. The *mechanism* that produces copies (a per-type resolve
hook vs. `copyWith`) is a 007b decision; 007a pins only the contract above.

## 4. The render contract

```dart
// domain/geometry.dart  (additive)
class JetConstraints {
  const JetConstraints({this.maxWidth = double.infinity,
                        this.maxHeight = double.infinity});
  final double maxWidth;
  final double maxHeight;
  JetSize constrain(JetSize size); // clamps each axis to the max; value-equal; toString
}
```

```dart
// rendering/elements/render_context.dart
/// The environment passed to a renderer's measure/emit. In 007a it carries only
/// the text measurer; 007b adds a diagnostics sink here without touching renderer
/// signatures. It deliberately does NOT expose resolved values (§3) or a separate
/// FontRegistry (§5).
class RenderContext {
  const RenderContext({required this.measurer});
  final TextMeasurer measurer;
}
```

```dart
// rendering/elements/element_renderer.dart
/// Measures and emits primitives for one element type [E].
///
/// `measure`/`emit` take a `covariant ReportElement` (not `E`) for the same
/// reason `ElementCodec` does: it keeps `ElementRenderer<E>` a subtype of
/// `ElementRenderer<ReportElement>` so the registry can hold it; the registry
/// only dispatches after matching `typeKey`, so the cast is always sound.
abstract class ElementRenderer<E extends ReportElement> {
  const ElementRenderer();
  JetSize measure(covariant ReportElement el, RenderContext ctx, JetConstraints c);
  void emit(covariant ReportElement el, RenderContext ctx, JetRect bounds, FrameBuilder out);
}
```

The blueprint's illustrative `MeasureContext`/`FillContext` are **formalized as one
`RenderContext`** — they carry identical data in v1 and the only foreseen divergence (a diagnostics
sink) arrives with Fill/Layout. The blueprint labels those signatures "illustrative, formalized per
spec," so this is a sanctioned formalization, recorded in §11, not a blueprint amendment.

## 5. 006 contract amendment — `MeasuredText.fontFamily`

To keep line layout and font-family resolution from drifting apart (two authorities → measure with
one fallback set, paint with another), the **measurer becomes the single source of truth** for
both. This is a real change to the 006 text seam, handled as a formal 006 amendment (parallel to
§15.6), not a 007 footnote:

- `MeasuredText` (`rendering/text/text_measurer.dart`) gains a **required `String fontFamily`** —
  the registry-resolved base family the measurer actually measured
  (`registry.resolveFamily(style.fontFamily, weight:, italic:)`).
- `MetricsTextMeasurer` (`rendering/text/metrics_text_measurer.dart`) populates it; its existing
  internal `metricsFor` resolution already determines the variant.
- The 006 design doc and every `MeasuredText(...)` construction site (measurer + tests) are updated.

The text renderer reads `m.fontFamily` for `TextRunPrimitive.fontFamily`; the painter combines that
base family with `style.weight`/`italic` into its synthetic `_uiFamily` exactly as in 006. The
`RenderContext` therefore needs **no** `FontRegistry`, and the measured family and the rendered
family cannot diverge.

## 6. Registries & unified registration

```dart
// rendering/elements/element_renderer_registry.dart
class ElementRendererRegistry {
  void register(String typeKey, ElementRenderer<ReportElement> renderer);
  /// The renderer for [element]'s typeKey, or the built-in Unknown placeholder
  /// renderer for any unregistered key (including a preserved UnknownElement).
  ElementRenderer<ReportElement> rendererFor(ReportElement element);
}
```

```dart
// rendering/elements/element_type_registry.dart  (lives in rendering → may import domain)
/// Binds an element type's codec (persist) and renderer (draw) under one key.
/// COMPOSES — does not replace — the existing ElementCodecRegistry.
class ElementTypeRegistry {
  ElementTypeRegistry({ElementCodecRegistry? codecs, ElementRendererRegistry? renderers});
  final ElementCodecRegistry codecs;       // consumed by encodeTemplate/decodeTemplate
  final ElementRendererRegistry renderers; // consumed by renderer lookup
  void register<E extends ReportElement>(
      String typeKey, ElementCodec<E> codec, ElementRenderer<E> renderer) {
    codecs.register(typeKey, codec);
    renderers.register(typeKey, renderer);
  }
}
void registerBuiltInElementTypes(ElementTypeRegistry r); // text, shape, image, barcode (paired)
```

- **Composition, not replacement.** `encodeTemplate`/`decodeTemplate`
  (`domain/serialization/report_codec.dart`) keep taking an injected `ElementCodecRegistry`; that
  registry **is** `typeRegistry.codecs`. The
  existing `registerBuiltInElementCodecs` stays valid (codec-only contexts). The 011 engine will own
  one `ElementTypeRegistry`; nothing in serialization changes.
- **`register<E>` generic — with an honest caveat.** The type parameter pairs codec and renderer,
  and the built-in registrations pass **explicit** type arguments
  (`r.register<TextElement>('text', …)`) which *do* reject a mismatched pair. But Dart class generics
  are covariant, so an **inferred** call can widen `E` to the common supertype `ReportElement` and
  compile a mismatch; Dart offers no exact-type bound to forbid this. The spec documents this rather
  than overclaiming compile-time prevention — the same covariance trade-off the codec seam already
  documents in `domain/serialization/element_codec.dart` (the `covariant ReportElement` note).

## 7. Built-in renderers (`rendering/elements/renderers/`)

All `measure` results clamp to nothing in 007a beyond the rules below; Layout (008) owns growth and
placement. Text growth is **vertical only** — a text element's width is invariant (§7.1).

| Renderer (`E`) | `measure` | `emit` |
|---|---|---|
| **Text** (`TextElement`) | `measurer.measure(el.text, el.style, maxWidth: c.maxWidth).size` | `TextRunPrimitive(bounds, lines: m.lines, style: el.style, fontFamily: m.fontFamily, elementId: el.id)` where `m = measurer.measure(el.text, el.style, maxWidth: bounds.width)` |
| **Shape** (`ShapeElement`) | `JetSize(el.bounds.width, el.bounds.height)` (non-growing) | rectangle → `RectPrimitive(fill: style.fill, stroke: style.stroke, strokeWidth: style.strokeWidth)`; line → `LinePrimitive` across the box diagonal (TL→BR, or BL→TR when `flipDiagonal`), `color: style.stroke ?? JetColor.black`, `strokeWidth: style.strokeWidth` |
| **Image** (`ImageElement`) | `JetSize(el.bounds.width, el.bounds.height)` | `el.source` is `BytesImageSource` → `ImagePrimitive(bytes, fit: el.fit, elementId)`; otherwise (URL/field — unresolved in 007a) → placeholder box labeled `image` |
| **Barcode** (`BarcodeElement`) | `JetSize(el.bounds.width, el.bounds.height)` | **placeholder box** labeled with `el.symbology.name` (real symbology deferred) |
| **Unknown** (`ReportElement`) | best-effort `JetSize(el.bounds.width, el.bounds.height)` | placeholder box labeled `Unknown: ${el.typeKey}` |

### 7.1 Authoritative wrap width (preserves 006 determinism)

A text element's **width never changes** between measure and emit — it grows in height only. Both
calls wrap at the **element box width**: `measure` is called with `c.maxWidth == el.bounds.width`
and `emit` wraps at `bounds.width == el.bounds.width`. Identical width in ⇒ identical line breaks
out, so the 006 line-break-determinism guarantee holds across the two calls. The spec states this as
a hard contract: **Layout MUST pass the text element's box width as `maxWidth` to `measure`, and
the emitted bounds preserve that width.**

### 7.2 Placeholder helper (render-don't-crash)

```dart
// rendering/elements/placeholder.dart
/// Emits a visible placeholder: an outline RectPrimitive over [bounds] plus a
/// measured [label] text run. Backs the image-missing, barcode, and unknown cases.
void emitPlaceholder(FrameBuilder out, JetRect bounds, String label,
                     RenderContext ctx, {String? elementId});
```

One helper, three callers — every "can't render the real thing" path produces something paintable
(a live designer canvas must never blank out an element).

## 8. Error handling

007a has no diagnostics sink (that arrives in 007b). Its render-don't-crash behaviors:

| Case | 007a behavior |
|---|---|
| Image source not yet resolvable (URL/field) | placeholder box labeled `image` |
| Barcode (symbology unimplemented) | placeholder box labeled with the symbology name |
| Unregistered / unknown element type | `rendererFor` returns the Unknown renderer → placeholder box labeled `Unknown: <typeKey>` |
| Text with empty string | one empty `TextLine` (006 measurer behavior) → empty run; no crash |

## 9. Testing (data-goldens + emit asserts)

- **Per-renderer measure/emit unit tests** — assert emitted **primitive structure**, not pixels:
  text → one `TextRunPrimitive` with the expected line count + resolved `fontFamily`; shape-line →
  `LinePrimitive` with the correct diagonal endpoints; shape-rect → `RectPrimitive` carrying the box
  style; image-bytes → `ImagePrimitive`; image-url / barcode / unknown → placeholder
  `RectPrimitive` + label `TextRunPrimitive`. Headless, deterministic.
- **`MeasuredText.fontFamily`** — a 006-level test asserts the measurer reports the resolved base
  family (default `JetSans`; a registered custom family when present).
- **Flagship persisted-extension test** — `StarElement`/`StarCodec`/`StarRenderer` in test code;
  assert round-trip through `typeRegistry.codecs.encode`→JSON→`decode` is unchanged **and**
  `rendererFor(star).emit(...)` produces the expected primitive — **zero edits to library `src/`**.
- **Layer-boundary** — extend the existing rendering-seam test to assert `rendering/elements/`
  imports no `dart:ui`/Flutter (the existing "only `paint/canvas_painter.dart` imports dart:ui"
  whitelist already enforces this; an explicit assertion documents intent).

White-box tests import `package:jet_print/src/...` (the deferred-export convention; `/test/rendering/`
is already allowlisted in the encapsulation test).

## 10. Public API & exports

Nothing new is exported from `jet_print.dart` in 007a — the public facade (`JetReportEngine`,
public `registerElementType`) is spec 011. The 011 engine will own one `ElementTypeRegistry` and
expose registration publicly; until then the types live in `src/` and are exercised white-box.

## 11. Design decisions & deviations (auditable)

1. **Resolved-element model over a resolved-value channel** (§3) — chosen after review showed a
   `Map<id, JetValue>` channel cannot carry image bytes and conflates presence with value. Resolved
   data lives in each element's own typed fields.
2. **One `RenderContext`** formalizes the blueprint's illustrative `MeasureContext`/`FillContext`
   (§4) — identical data in v1; diagnostics divergence deferred to 007b.
3. **`MeasuredText.fontFamily`** — formal 006 amendment (§5), single font authority.
4. **`register<E>` generic with documented covariance caveat** (§6) — mirrors the codec seam.
5. **Barcode placeholder, not symbology** — per the approved fork; the blueprint's `barcode⊕`
   (third-party lib) is anticipated for the future symbology spec.

## 12. File plan

- **Modify:** `domain/geometry.dart` (+`JetConstraints`);
  `rendering/text/text_measurer.dart` (+`MeasuredText.fontFamily`);
  `rendering/text/metrics_text_measurer.dart` (populate it);
  006 design doc + 006 measurer tests; `test/architecture/layer_boundaries_test.dart`;
  `CHANGELOG.md`.
- **Create:** `rendering/elements/{render_context, element_renderer, element_renderer_registry,
  element_type_registry, built_in_element_renderers, placeholder}.dart`;
  `rendering/elements/renderers/{text, shape, image, barcode, unknown}_element_renderer.dart`;
  `test/rendering/elements/*` (per-renderer + registry + persisted-extension).

## 13. Review history

Three pre-write review rounds (GitHub Copilot), folded in:
- **R1 (design):** null sentinel unsafe; `JetValue` too narrow for images; `register` pairing;
  one authoritative wrap width; two font authorities. → drove the **resolved-element pivot** (§3),
  the **`MeasuredText.fontFamily`** single-authority fix (§5), the **invariant wrap width** (§7.1),
  and the **generic-`register` caveat** (§6). `ElementTypeRegistry` **composes** the codec registry
  (§6, Open-Q1); resolved data is keyed by band instance, not id (§3, Open-Q2).
- **R2 (refinements):** pin "resolved element" tightly (§3 field-partition table); treat
  `MeasuredText.fontFamily` as a real 006 amendment (§5); reuse the codec seam's covariance
  rationale verbatim (§6).
