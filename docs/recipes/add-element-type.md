# Add an element type

The order to wire a new drawable report object in, and the two edits that look redundant and are not.

The rules this touches live in [`../../AGENTS.md`](../../AGENTS.md); what a
renderer may emit is [page 04](../04-the-frame.md); why registration is split in
two is [page 06](../06-round-tripping.md), *Trap*. This page is only the sequence.

## The sequence

Start from `test/rendering/elements/persisted_extension_test.dart`, which defines
an element, a codec and a renderer entirely in test code and proves the round
trip and the draw. Copy its shape first — it is also the proof that nothing below
is needed to make a type *work*; the steps are what make it a built-in.

1. **Domain class** — `lib/src/domain/elements/<name>_element.dart`, extending
   `ReportElement`. Implement `typeKey` and the three polymorphic rewriters the
   base class declares (`withBounds`, `withName`, `withVisible`), plus `==` and
   `hashCode`. Keep it Flutter-free, per `AGENTS.md`'s inward-dependency rule;
   `test/architecture/layer_boundaries_test.dart` is what stops you otherwise.
2. **Codec** — `lib/src/domain/serialization/<name>_element_codec.dart`,
   extending `ElementCodec<X>` with `fromJson` / `toJson`. Omit defaults rather
   than writing them, so an unset property stays absent from the JSON.
3. **Register the codec** — one `register('<key>', const XElementCodec())` line
   in `registerBuiltInElementCodecs`
   (`domain/serialization/built_in_element_codecs.dart`).
4. **Renderer** — `rendering/elements/renderers/<name>_element_renderer.dart`,
   extending `ElementRenderer<X>`: `measure` returns a size, `emit` appends
   primitives to the `FrameBuilder`. If the type needs a third-party encoder,
   the vendor import belongs in one adapter file and nowhere else — the file
   `AGENTS.md`'s third-party rule names is the worked example, and its guard,
   `test/architecture/barcode_dependency_isolation_test.dart`, covers your
   package only once you add it there.
5. **Register the pair** — one `register<XElement>('<key>', const
   XElementCodec(), const XElementRenderer())` line in
   `registerBuiltInElementTypes`
   (`rendering/elements/built_in_element_renderers.dart`). Pass `X` explicitly;
   inference widens it and stops checking the pairing.

Steps 3 and 5 are both mandatory. A type present in one list only still draws
correctly on the canvas, so **a correct-looking canvas is not confirmation that
you registered it**; run
`test/architecture/built_in_element_registration_test.dart`, whose failure names
the half you missed.

6. **Designer** — a `DesignerToolType` variant *and* its `kDefaultElementSize`
   entry in `designer/canvas/design_tunables.dart`; a `_ToolboxEntry` in
   `designer/layout/designer_toolbox.dart`; `buildDefaultElement` in
   `designer/controller/commands/create_element_command.dart`, the one arm the
   compiler will demand; `elementGlyph` in `designer/element_glyph.dart`, whose
   icon the toolbox repeats with nothing linking the two lists; `elementTypeLabel`
   in `designer/l10n/element_type_label.dart`, plus its `elementType…` key in all
   three ARB files ([recipe](add-localized-string.md)) — skip that and the type
   reads as the generic fallback wherever a label appears. Last, an inspector arm
   in `designer/layout/panels/properties/inspectors/element_inspector.dart` for
   whatever the type adds beyond position and size.
7. **Export** the class from `lib/jet_print.dart` and add a `CHANGELOG.md` entry.

Then sweep. If the type carries an enum of its own, `AGENTS.md`'s trap on
exhaustive switches applies unchanged — run the grep it prescribes. And check
`kDefaultElementSize`: a plain `const` map read with `!`, so a missing entry
compiles and crashes the first time someone drags the tool.

## Verify

```bash
flutter test packages/jet_print/test/rendering/elements/persisted_extension_test.dart \
  packages/jet_print/test/architecture/ \
  packages/jet_print/test/domain/serialization/
```

Then the full gate from the repository root, as `AGENTS.md` specifies it. If a
golden moves and you did not touch a golden fixture, stop and read
[`update-goldens.md`](update-goldens.md).

## Next

[`add-expression-function.md`](add-expression-function.md) if the type needs a
function to bind against; [page 06](../06-round-tripping.md) for what an older
build does with your type.
