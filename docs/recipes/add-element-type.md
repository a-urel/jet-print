# Add an element type

The order to wire a new drawable report object in, and the steps whose absence nothing reports.

The rules this touches live in [`../../AGENTS.md`](../../AGENTS.md) and what a
renderer may emit is [page 04](../04-the-frame.md). This page is only the sequence.

## The sequence

Copy the shape of `test/rendering/elements/persisted_extension_test.dart` first;
[page 06](../06-round-tripping.md) says what it proves and what it does not.

1. **Domain class** — `lib/src/domain/elements/<name>_element.dart`, extending
   `ReportElement` with `ValueEquality`. Implement `typeKey`, the three
   polymorphic rewriters the base class declares (`withBounds`, `withName`,
   `withVisible`), and a `props` spreading `baseProps` first — as every built-in
   does, and as that test's `StarElement` does not. Never hand-roll `==`/`hashCode`;
   `domain/value_equality.dart`'s dartdoc gives the reason. `AGENTS.md`'s
   inward-dependency rule applies, per `test/architecture/layer_boundaries_test.dart`.
2. **Codec** — `lib/src/domain/serialization/<name>_element_codec.dart`,
   extending `ElementCodec<X>` with `fromJson` / `toJson`. Omit defaults rather
   than writing them, so an unset property stays absent from the JSON.
3. **Register the codec** — one `register('<key>', const XElementCodec())` line
   in `registerBuiltInElementCodecs`
   (`domain/serialization/built_in_element_codecs.dart`).
4. **Renderer** — `rendering/elements/renderers/<name>_element_renderer.dart`,
   extending `ElementRenderer<X>`: `measure` returns a size, `emit` appends
   primitives to the `FrameBuilder`. A third-party encoder falls under
   `AGENTS.md`'s third-party rule; its guard,
   `test/architecture/barcode_dependency_isolation_test.dart`, covers your
   package only once you add it there.
5. **Register the pair** — one `register<XElement>('<key>', const
   XElementCodec(), const XElementRenderer())` line in
   `registerBuiltInElementTypes`
   (`rendering/elements/built_in_element_renderers.dart`). Pass `X` explicitly;
   inference widens it and stops checking the pairing.

Steps 3 and 5 are both mandatory and they fail differently —
[page 06](../06-round-tripping.md), *Trap*, states both directions. The
operational point: the half a correct-looking canvas **cannot** rule out is the
codec registration. Run `test/architecture/built_in_element_registration_test.dart`,
whose failure names the half you missed.

6. **Fill-time resolution**, if the type reads data — an arm in
   `rendering/fill/element_resolver.dart` → `ElementResolver.resolve`. Without
   one the element renders its authored value on every row and reports nothing.
7. **Designer** — a `DesignerToolType` variant *and* its `kDefaultElementSize`
   entry in `designer/canvas/design_tunables.dart`; a `_ToolboxEntry` in
   `designer/layout/designer_toolbox.dart`; the two arms the compiler will
   demand, `buildDefaultElement`
   (`designer/controller/commands/create_element_command.dart`) and `_typeKeyFor`
   (`designer/controller/api/statics.dart`), the second assigning the id prefix;
   `elementGlyph` in `designer/element_glyph.dart`, whose icon the toolbox
   repeats with nothing linking the two lists; `elementTypeLabel` in
   `designer/l10n/element_type_label.dart`, plus its `elementType…` key in all
   three ARB files ([recipe](add-localized-string.md)) — skip that and the type
   reads as the generic fallback wherever a label appears. Last, an inspector arm
   in `designer/layout/panels/properties/inspectors/element_inspector.dart` for
   whatever the type adds beyond position and size.
8. **Export** the class from `lib/jet_print.dart` and add a `CHANGELOG.md` entry.

Then sweep. If the type carries an enum, `AGENTS.md`'s trap on exhaustive
switches applies unchanged — run the grep it prescribes. And `kDefaultElementSize`
is a `const` map read with `!`: a missing entry compiles and crashes on first drag.

## Verify

```bash
flutter test packages/jet_print/test/rendering/elements/persisted_extension_test.dart \
  packages/jet_print/test/architecture/ \
  packages/jet_print/test/domain/serialization/
```

Then the full gate from the repository root, as `AGENTS.md` specifies it. If a
golden moves and you touched no golden fixture, read [`update-goldens.md`](update-goldens.md).

## Next

[`add-expression-function.md`](add-expression-function.md) if the type needs a
function to bind against; [page 06](../06-round-tripping.md) for what an older build does with it.
