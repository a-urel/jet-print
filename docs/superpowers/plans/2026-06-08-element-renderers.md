# Element Renderers (Spec 007a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the rendering-side element extension point — `ElementRenderer<E>` (measure + emit) paired with the existing `ElementCodec<E>` via one `register<E>` call — plus built-in renderers for text, shape, image, and barcode/unknown placeholders, proving a custom element type round-trips through JSON *and* renders with zero core edits.

**Architecture:** Renderers render the element handed to them (the "resolved-element" seam — 007b's Fill swaps in resolved copies later, so renderers never change). A `RenderContext` carries only the `TextMeasurer`. `ElementTypeRegistry` *composes* the domain `ElementCodecRegistry` (consumed by `report_codec`) with a new `ElementRendererRegistry`. One 006 amendment — `MeasuredText.fontFamily` — makes the measurer the single authority for the font family, so the renderer cannot pick a family the measurer didn't measure.

**Tech Stack:** Dart (pub workspace monorepo), Flutter test harness. Pure-Dart `rendering/elements/` seam (no `dart:ui` — enforced by the layer-boundary test). Sealed/`final` value types, `covariant ReportElement` for registry storage (mirroring the codec seam), TDD with `flutter test`.

**Spec:** `docs/superpowers/specs/2026-06-08-element-renderers-design.md`.

**Conventions for every task:**
- Run all commands from `packages/jet_print/`. Test command form: `flutter test test/<path> -r expanded`.
- After each task the analyzer gate must stay green: `flutter analyze` prints `No issues found!` (the root `analysis_options.yaml` promotes `unused_import`/`unused_local_variable`/`unused_element`/`unused_field`/`dead_code` to **errors**).
- `lib/` files use **relative** imports, ordered `dart:` → `package:` → relative, each group alphabetized (`directives_ordering` + `prefer_relative_imports`). The new `rendering/elements/` files use relative imports only.
- Test files use white-box `package:jet_print/src/...` imports (allowlisted for `/test/rendering/` and `/test/domain/`).
- New `src/` types are **not** exported from `jet_print.dart` (deferred to the 011 facade).
- Commit messages end with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (omitted from the commands below for brevity).
- Branch is already `007a-element-renderers`.

---

## File Structure

**Modify:**
- `lib/src/domain/geometry.dart` — add `JetConstraints`.
- `lib/src/rendering/text/text_measurer.dart` — add required `MeasuredText.fontFamily`.
- `lib/src/rendering/text/metrics_text_measurer.dart` — populate `fontFamily`.
- `test/rendering/text/text_measurer_types_test.dart` — update the `MeasuredText(...)` construction.
- `docs/superpowers/specs/2026-06-07-frame-text-paint-design.md` — record the `fontFamily` amendment.
- `test/architecture/layer_boundaries_test.dart` — add an `elements/` Flutter-free assertion.
- `CHANGELOG.md` — 007a entry.

**Create (lib):**
- `lib/src/rendering/elements/render_context.dart` — `RenderContext` (holds the `TextMeasurer`).
- `lib/src/rendering/elements/element_renderer.dart` — `ElementRenderer<E>` interface.
- `lib/src/rendering/elements/placeholder.dart` — `emitPlaceholder` helper.
- `lib/src/rendering/elements/renderers/text_element_renderer.dart`
- `lib/src/rendering/elements/renderers/shape_element_renderer.dart`
- `lib/src/rendering/elements/renderers/image_element_renderer.dart`
- `lib/src/rendering/elements/renderers/barcode_element_renderer.dart`
- `lib/src/rendering/elements/renderers/unknown_element_renderer.dart`
- `lib/src/rendering/elements/element_renderer_registry.dart` — `ElementRendererRegistry`.
- `lib/src/rendering/elements/element_type_registry.dart` — `ElementTypeRegistry`.
- `lib/src/rendering/elements/built_in_element_renderers.dart` — `registerBuiltInElementTypes`.

**Create (test):**
- `test/domain/geometry_constraints_test.dart`
- `test/rendering/text/measured_text_font_family_test.dart`
- `test/rendering/elements/element_renderer_test.dart`
- `test/rendering/elements/placeholder_test.dart`
- `test/rendering/elements/text_element_renderer_test.dart`
- `test/rendering/elements/shape_element_renderer_test.dart`
- `test/rendering/elements/image_element_renderer_test.dart`
- `test/rendering/elements/barcode_element_renderer_test.dart`
- `test/rendering/elements/unknown_element_renderer_test.dart`
- `test/rendering/elements/element_renderer_registry_test.dart`
- `test/rendering/elements/element_type_registry_test.dart`
- `test/rendering/elements/persisted_extension_test.dart`

---

## Task 1: `MeasuredText.fontFamily` (006 amendment — single font authority)

**Files:**
- Modify: `lib/src/rendering/text/text_measurer.dart`
- Modify: `lib/src/rendering/text/metrics_text_measurer.dart`
- Modify: `test/rendering/text/text_measurer_types_test.dart`
- Modify: `docs/superpowers/specs/2026-06-07-frame-text-paint-design.md`
- Test: `test/rendering/text/measured_text_font_family_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/text/measured_text_font_family_test.dart`:

```dart
// MeasuredText.fontFamily reports the resolved base family (007a / 006 amendment).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/styles/text_style.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  test('measure reports the default family when the style names none', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final MetricsTextMeasurer m = MetricsTextMeasurer(reg);
    expect(m.measure('A', JetTextStyle.fallback).fontFamily, 'JetSans');
  });

  test('measure reports a registered custom family', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    reg.register('Custom', reg.bytesFor(null)); // reuse default bytes under a new name
    final MetricsTextMeasurer m = MetricsTextMeasurer(reg);
    expect(
      m.measure('A', const JetTextStyle(fontFamily: 'Custom')).fontFamily,
      'Custom',
    );
  });

  test('an unregistered family falls back to the default family', () {
    final FontRegistry reg = FontRegistry()..registerDefault();
    final MetricsTextMeasurer m = MetricsTextMeasurer(reg);
    expect(
      m.measure('A', const JetTextStyle(fontFamily: 'Nope')).fontFamily,
      'JetSans',
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/text/measured_text_font_family_test.dart -r expanded`
Expected: FAIL — compile error, `MeasuredText` has no `fontFamily` getter.

- [ ] **Step 3: Add the field to `MeasuredText`**

In `lib/src/rendering/text/text_measurer.dart`, replace the `MeasuredText` constructor + doc block (the `const MeasuredText({...})` through the `firstAscent` field) so it reads:

```dart
/// The result of [TextMeasurer.measure]: laid-out [lines] and the wrapped block
/// [size]. [firstAscent] is the baseline offset of the first line. [fontFamily]
/// is the registry-resolved base family the measurer actually measured with —
/// the painter renders the same family, so measurement and rendering cannot pick
/// different families (006 amendment for 007a).
class MeasuredText {
  /// Creates a measured-text result.
  const MeasuredText({
    required this.lines,
    required this.size,
    required this.firstAscent,
    required this.fontFamily,
  });

  /// The laid-out lines, top to bottom.
  final List<TextLine> lines;

  /// The wrapped block size (max line width × total height), in points.
  final JetSize size;

  /// Baseline offset of the first line from the block top, in points.
  final double firstAscent;

  /// The registry-resolved base font family used for measurement.
  final String fontFamily;
}
```

- [ ] **Step 4: Populate it in `MetricsTextMeasurer`**

In `lib/src/rendering/text/metrics_text_measurer.dart`, change the returned `MeasuredText(...)` (currently `lines/size/firstAscent`) to add `fontFamily`:

```dart
    return MeasuredText(
      lines: lines,
      size: JetSize(maxW, lines.length * lineHeight),
      firstAscent: lineAscent,
      fontFamily: _registry.resolveFamily(style.fontFamily,
          weight: style.weight, italic: style.italic),
    );
```

- [ ] **Step 5: Fix the existing construction site**

In `test/rendering/text/text_measurer_types_test.dart`, the `MeasuredText(...)` in the second test currently omits `fontFamily`. Update it and add an assertion:

```dart
  test('MeasuredText carries lines, size, firstAscent, and fontFamily', () {
    const TextLine l = TextLine(
        text: 'A', width: 6.39, top: 0, baseline: 10.69, height: 13.62);
    const MeasuredText m = MeasuredText(
        lines: <TextLine>[l],
        size: JetSize(6.39, 13.62),
        firstAscent: 10.69,
        fontFamily: 'JetSans');
    expect(m.lines.single, l);
    expect(m.size, const JetSize(6.39, 13.62));
    expect(m.firstAscent, 10.69);
    expect(m.fontFamily, 'JetSans');
  });
```

- [ ] **Step 6: Run the tests + analyzer**

Run: `flutter test test/rendering/text/ -r expanded && flutter analyze`
Expected: all text tests PASS; analyzer prints `No issues found!`. (No other `lib`/`test` site constructs `MeasuredText` — verified by `grep -rn 'MeasuredText(' lib test`.)

- [ ] **Step 7: Record the 006 amendment in the spec**

Append to `docs/superpowers/specs/2026-06-07-frame-text-paint-design.md` (end of file):

```markdown

## Amendment (2026-06-08, for spec 007a)

`MeasuredText` gains a required `String fontFamily` — the registry-resolved base family the
measurer measured with (`FontRegistry.resolveFamily(...)`). This makes the measurer the single
authority for the font family: the element renderer (007a) reads `MeasuredText.fontFamily` for
`TextRunPrimitive.fontFamily`, so a measured run and its painted run cannot choose different
families. The measurer↔painter parity still requires a shared `FontRegistry` instance (011 wiring);
this amendment removes only the renderer-side divergence.
```

- [ ] **Step 8: Commit**

```bash
git add lib/src/rendering/text/text_measurer.dart lib/src/rendering/text/metrics_text_measurer.dart \
  test/rendering/text/measured_text_font_family_test.dart test/rendering/text/text_measurer_types_test.dart \
  docs/superpowers/specs/2026-06-07-frame-text-paint-design.md
git commit -m "feat(rendering): add MeasuredText.fontFamily (006 amendment for 007a)"
```

---

## Task 2: `JetConstraints` geometry type

**Files:**
- Modify: `lib/src/domain/geometry.dart`
- Test: `test/domain/geometry_constraints_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/domain/geometry_constraints_test.dart`:

```dart
// JetConstraints: a max-width/height sizing bound for ElementRenderer.measure (007a).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';

void main() {
  test('defaults are unbounded (infinity) and constrain is a no-op', () {
    const JetConstraints c = JetConstraints();
    expect(c.maxWidth, double.infinity);
    expect(c.maxHeight, double.infinity);
    expect(c.constrain(const JetSize(40, 12)), const JetSize(40, 12));
  });

  test('constrain clamps each axis independently to the max', () {
    const JetConstraints c = JetConstraints(maxWidth: 30, maxHeight: 10);
    expect(c.constrain(const JetSize(40, 8)), const JetSize(30, 8));
    expect(c.constrain(const JetSize(20, 25)), const JetSize(20, 10));
  });

  test('value equality and toString', () {
    expect(const JetConstraints(maxWidth: 5, maxHeight: 7),
        const JetConstraints(maxWidth: 5, maxHeight: 7));
    expect(const JetConstraints(maxWidth: 5, maxHeight: 7),
        isNot(const JetConstraints(maxWidth: 5, maxHeight: 8)));
    expect(const JetConstraints(maxWidth: 5, maxHeight: 7).toString(),
        'JetConstraints(maxWidth: 5.0, maxHeight: 7.0)');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/domain/geometry_constraints_test.dart -r expanded`
Expected: FAIL — `JetConstraints` is undefined.

- [ ] **Step 3: Implement `JetConstraints`**

Append to `lib/src/domain/geometry.dart` (after `JetRect`):

```dart

/// Immutable sizing bounds for `ElementRenderer.measure`: a maximum [maxWidth]
/// and [maxHeight] in logical points. Either may be [double.infinity]
/// (unbounded). Pure-Dart; mirrors the role of a layout constraint without any
/// `dart:ui` dependency.
class JetConstraints {
  /// Creates constraints; both axes default to unbounded.
  const JetConstraints({
    this.maxWidth = double.infinity,
    this.maxHeight = double.infinity,
  });

  /// Maximum width, in points (may be [double.infinity]).
  final double maxWidth;

  /// Maximum height, in points (may be [double.infinity]).
  final double maxHeight;

  /// Returns [size] with each axis clamped down to the corresponding max.
  JetSize constrain(JetSize size) => JetSize(
        size.width < maxWidth ? size.width : maxWidth,
        size.height < maxHeight ? size.height : maxHeight,
      );

  @override
  bool operator ==(Object other) =>
      other is JetConstraints &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight;

  @override
  int get hashCode => Object.hash(maxWidth, maxHeight);

  @override
  String toString() =>
      'JetConstraints(maxWidth: $maxWidth, maxHeight: $maxHeight)';
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/domain/geometry_constraints_test.dart -r expanded && flutter analyze`
Expected: PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/domain/geometry.dart test/domain/geometry_constraints_test.dart
git commit -m "feat(domain): add JetConstraints sizing bounds (007a)"
```

---

## Task 3: Render contract — `RenderContext` + `ElementRenderer<E>`

**Files:**
- Create: `lib/src/rendering/elements/render_context.dart`
- Create: `lib/src/rendering/elements/element_renderer.dart`
- Test: `test/rendering/elements/element_renderer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/elements/element_renderer_test.dart`:

```dart
// The render contract: RenderContext (measurer holder) + ElementRenderer<E>.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/element_renderer.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';
import 'package:jet_print/src/rendering/text/text_measurer.dart';

/// A minimal concrete renderer proving the contract compiles and dispatches.
class _StubRenderer extends ElementRenderer<TextElement> {
  const _StubRenderer();
  @override
  JetSize measure(TextElement el, RenderContext ctx, JetConstraints c) =>
      JetSize(el.bounds.width, el.bounds.height);
  @override
  void emit(TextElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) =>
      out.add(RectPrimitive(bounds: bounds, elementId: el.id));
}

void main() {
  final RenderContext ctx =
      RenderContext(measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));

  test('RenderContext exposes its measurer', () {
    expect(ctx.measurer, isA<TextMeasurer>());
  });

  test('a renderer measures to the authored size and emits a primitive', () {
    const TextElement el = TextElement(
        id: 'x', bounds: JetRect(x: 0, y: 0, width: 30, height: 10), text: 'hi');
    expect(const _StubRenderer().measure(el, ctx, const JetConstraints()),
        const JetSize(30, 10));
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    const _StubRenderer()
        .emit(el, ctx, const JetRect(x: 1, y: 2, width: 30, height: 10), out);
    final RectPrimitive prim =
        out.build().primitives.single as RectPrimitive;
    expect(prim.elementId, 'x');
    expect(prim.bounds, const JetRect(x: 1, y: 2, width: 30, height: 10));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/elements/element_renderer_test.dart -r expanded`
Expected: FAIL — `RenderContext`/`ElementRenderer` are undefined.

- [ ] **Step 3: Implement `RenderContext`**

Create `lib/src/rendering/elements/render_context.dart`:

```dart
/// The environment passed to an [ElementRenderer]'s measure/emit (spec 007a).
///
/// In 007a it carries only the [TextMeasurer]; a diagnostics sink is added here
/// in 007b without changing renderer signatures. It deliberately exposes neither
/// resolved values (renderers render the element they are handed — the
/// resolved-element seam) nor a separate `FontRegistry` (the measurer is the
/// single font authority via `MeasuredText.fontFamily`).
library;

import '../text/text_measurer.dart';

/// Carries the shared text-measurement environment for a render pass.
class RenderContext {
  /// Creates a context over [measurer].
  const RenderContext({required this.measurer});

  /// Lays out text into lines (and reports the resolved font family).
  final TextMeasurer measurer;
}
```

- [ ] **Step 4: Implement `ElementRenderer<E>`**

Create `lib/src/rendering/elements/element_renderer.dart`:

```dart
/// The rendering-side element extension point (spec 007a): measures an element
/// and emits frame primitives for it. Paired with the domain-side `ElementCodec`
/// through `ElementTypeRegistry.register`.
library;

import '../../domain/geometry.dart';
import '../../domain/report_element.dart';
import '../frame/frame_builder.dart';
import 'render_context.dart';

/// Measures and emits primitives for one element type [E].
///
/// `measure`/`emit` take a `covariant ReportElement` (not `E`) for the same
/// reason `ElementCodec` does: it keeps `ElementRenderer<E>` a subtype of
/// `ElementRenderer<ReportElement>` so the registry can hold it. The registry
/// only dispatches after matching the element's `typeKey`, so the implicit
/// narrowing in each concrete renderer is always sound.
abstract class ElementRenderer<E extends ReportElement> {
  /// Const base constructor.
  const ElementRenderer();

  /// The element's desired size within [constraints] (no side effects).
  JetSize measure(
      covariant ReportElement element, RenderContext ctx, JetConstraints constraints);

  /// Appends this element's primitives to [out], positioned within [bounds].
  void emit(covariant ReportElement element, RenderContext ctx, JetRect bounds,
      FrameBuilder out);
}
```

- [ ] **Step 5: Run the test + analyzer**

Run: `flutter test test/rendering/elements/element_renderer_test.dart -r expanded && flutter analyze`
Expected: PASS; `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/rendering/elements/render_context.dart lib/src/rendering/elements/element_renderer.dart \
  test/rendering/elements/element_renderer_test.dart
git commit -m "feat(rendering): ElementRenderer contract + RenderContext (007a)"
```

---

## Task 4: `emitPlaceholder` helper (render-don't-crash)

**Files:**
- Create: `lib/src/rendering/elements/placeholder.dart`
- Test: `test/rendering/elements/placeholder_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/elements/placeholder_test.dart`:

```dart
// emitPlaceholder: an outline rect + a measured label, for render-don't-crash.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/placeholder.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx =
      RenderContext(measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));

  test('emits an outline rect then a label text run, both tagged', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    emitPlaceholder(out, const JetRect(x: 2, y: 3, width: 40, height: 20),
        'image', ctx, elementId: 'img1');
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims.length, 2);

    final RectPrimitive rect = prims[0] as RectPrimitive;
    expect(rect.bounds, const JetRect(x: 2, y: 3, width: 40, height: 20));
    expect(rect.stroke, isNotNull);
    expect(rect.fill, isNull);
    expect(rect.elementId, 'img1');

    final TextRunPrimitive label = prims[1] as TextRunPrimitive;
    expect(label.lines.single.text, 'image');
    expect(label.fontFamily, 'JetSans');
    expect(label.elementId, 'img1');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/elements/placeholder_test.dart -r expanded`
Expected: FAIL — `emitPlaceholder` is undefined.

- [ ] **Step 3: Implement the helper**

Create `lib/src/rendering/elements/placeholder.dart`:

```dart
/// A shared visible-placeholder primitive (spec 007a): an outline rect plus a
/// small label. Backs the image-missing, barcode, and unknown-element cases so a
/// renderer never leaves an element blank (render-don't-crash).
library;

import '../../domain/geometry.dart';
import '../../domain/styles/color.dart';
import '../../domain/styles/text_style.dart';
import '../frame/frame_builder.dart';
import '../frame/primitive.dart';
import '../text/text_measurer.dart';
import 'render_context.dart';

/// A muted grey for placeholder outlines and labels.
const JetColor _placeholderColor = JetColor(0xFF999999);

/// The label style: small, muted, left-aligned.
const JetTextStyle _placeholderStyle =
    JetTextStyle(fontSize: 8, color: _placeholderColor);

/// Appends an outline [RectPrimitive] over [bounds] followed by a measured
/// [label] [TextRunPrimitive], both tagged with [elementId].
void emitPlaceholder(
  FrameBuilder out,
  JetRect bounds,
  String label,
  RenderContext ctx, {
  String? elementId,
}) {
  out.add(RectPrimitive(
    bounds: bounds,
    stroke: _placeholderColor,
    elementId: elementId,
  ));
  final MeasuredText m =
      ctx.measurer.measure(label, _placeholderStyle, maxWidth: bounds.width);
  out.add(TextRunPrimitive(
    bounds: bounds,
    lines: m.lines,
    style: _placeholderStyle,
    fontFamily: m.fontFamily,
    elementId: elementId,
  ));
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/rendering/elements/placeholder_test.dart -r expanded && flutter analyze`
Expected: PASS; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/elements/placeholder.dart test/rendering/elements/placeholder_test.dart
git commit -m "feat(rendering): shared emitPlaceholder helper (007a)"
```

---

## Task 5: `TextElementRenderer` (+ local wrap-width determinism)

**Files:**
- Create: `lib/src/rendering/elements/renderers/text_element_renderer.dart`
- Test: `test/rendering/elements/text_element_renderer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/elements/text_element_renderer_test.dart`:

```dart
// TextElementRenderer: measure/emit + the §7.1 local wrap-width invariant.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/text_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final MetricsTextMeasurer measurer =
      MetricsTextMeasurer(FontRegistry()..registerDefault());
  final RenderContext ctx = RenderContext(measurer: measurer);
  const TextElementRenderer renderer = TextElementRenderer();

  const TextElement el = TextElement(
    id: 't',
    bounds: JetRect(x: 0, y: 0, width: 40, height: 100),
    text: 'the quick brown fox',
  );

  test('emit produces one TextRunPrimitive carrying the resolved family', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, const JetRect(x: 5, y: 5, width: 40, height: 100), out);
    final TextRunPrimitive run =
        out.build().primitives.single as TextRunPrimitive;
    expect(run.fontFamily, 'JetSans');
    expect(run.style, el.style);
    expect(run.elementId, 't');
    expect(run.bounds, const JetRect(x: 5, y: 5, width: 40, height: 100));
  });

  test('measure wraps at the authored width, ignoring the constraint', () {
    final JetSize size =
        renderer.measure(el, ctx, const JetConstraints(maxWidth: 9999));
    final JetSize expected =
        measurer.measure(el.text, el.style, maxWidth: 40).size;
    expect(size, expected);
  });

  test('emit wraps at the authored width, not the passed bounds width', () {
    final List<String> authored = measurer
        .measure(el.text, el.style, maxWidth: 40)
        .lines
        .map((l) => l.text)
        .toList();
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    // Deliberately WIDER emit bounds: wrapping must still use the authored 40.
    renderer.emit(el, ctx, const JetRect(x: 5, y: 5, width: 9999, height: 100), out);
    final TextRunPrimitive run =
        out.build().primitives.single as TextRunPrimitive;
    expect(run.lines.map((l) => l.text).toList(), authored);
    expect(run.lines.length, greaterThan(1)); // sanity: the text actually wrapped at 40
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/elements/text_element_renderer_test.dart -r expanded`
Expected: FAIL — `TextElementRenderer` is undefined.

- [ ] **Step 3: Implement the renderer**

Create `lib/src/rendering/elements/renderers/text_element_renderer.dart`:

```dart
/// Renders a [TextElement] as one pre-broken [TextRunPrimitive] (spec 007a).
///
/// Wraps at the element's own authored width (`el.bounds.width`) in BOTH measure
/// and emit — a local determinism invariant that does not depend on the caller
/// passing a particular constraint or bounds width (text grows in height only).
library;

import '../../../domain/elements/text_element.dart';
import '../../../domain/geometry.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../../text/text_measurer.dart';
import '../element_renderer.dart';
import '../render_context.dart';

/// The built-in renderer for `text` elements.
class TextElementRenderer extends ElementRenderer<TextElement> {
  /// Const constructor.
  const TextElementRenderer();

  @override
  JetSize measure(TextElement el, RenderContext ctx, JetConstraints constraints) =>
      ctx.measurer.measure(el.text, el.style, maxWidth: el.bounds.width).size;

  @override
  void emit(TextElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    final MeasuredText m =
        ctx.measurer.measure(el.text, el.style, maxWidth: el.bounds.width);
    out.add(TextRunPrimitive(
      bounds: bounds,
      lines: m.lines,
      style: el.style,
      fontFamily: m.fontFamily,
      elementId: el.id,
    ));
  }
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/rendering/elements/text_element_renderer_test.dart -r expanded && flutter analyze`
Expected: PASS (3 tests); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/elements/renderers/text_element_renderer.dart \
  test/rendering/elements/text_element_renderer_test.dart
git commit -m "feat(rendering): TextElementRenderer with local wrap-width invariant (007a)"
```

---

## Task 6: `ShapeElementRenderer` (line + rectangle)

**Files:**
- Create: `lib/src/rendering/elements/renderers/shape_element_renderer.dart`
- Test: `test/rendering/elements/shape_element_renderer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/elements/shape_element_renderer_test.dart`:

```dart
// ShapeElementRenderer: rectangle -> RectPrimitive; line -> diagonal LinePrimitive.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/styles/box_style.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/shape_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx =
      RenderContext(measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const ShapeElementRenderer renderer = ShapeElementRenderer();
  const JetRect bounds = JetRect(x: 10, y: 20, width: 40, height: 30);

  test('measure returns the authored box size', () {
    const ShapeElement el = ShapeElement(
        id: 'r', bounds: bounds, kind: ShapeKind.rectangle);
    expect(renderer.measure(el, ctx, const JetConstraints()),
        const JetSize(40, 30));
  });

  test('rectangle emits a RectPrimitive carrying the box style', () {
    const ShapeElement el = ShapeElement(
      id: 'r',
      bounds: bounds,
      kind: ShapeKind.rectangle,
      style: JetBoxStyle(fill: JetColor.black, stroke: JetColor.black, strokeWidth: 2),
    );
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final RectPrimitive p = out.build().primitives.single as RectPrimitive;
    expect(p.bounds, bounds);
    expect(p.fill, JetColor.black);
    expect(p.stroke, JetColor.black);
    expect(p.strokeWidth, 2);
    expect(p.elementId, 'r');
  });

  test('line emits the top-left -> bottom-right diagonal by default', () {
    const ShapeElement el =
        ShapeElement(id: 'l', bounds: bounds, kind: ShapeKind.line);
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final LinePrimitive p = out.build().primitives.single as LinePrimitive;
    expect(p.start, const JetOffset(10, 20));
    expect(p.end, const JetOffset(50, 50));
    expect(p.color, JetColor.black); // default when style has no stroke
    expect(p.elementId, 'l');
  });

  test('flipDiagonal line emits bottom-left -> top-right', () {
    const ShapeElement el = ShapeElement(
        id: 'l', bounds: bounds, kind: ShapeKind.line, flipDiagonal: true);
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final LinePrimitive p = out.build().primitives.single as LinePrimitive;
    expect(p.start, const JetOffset(10, 50));
    expect(p.end, const JetOffset(50, 20));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/elements/shape_element_renderer_test.dart -r expanded`
Expected: FAIL — `ShapeElementRenderer` is undefined.

- [ ] **Step 3: Implement the renderer**

Create `lib/src/rendering/elements/renderers/shape_element_renderer.dart`:

```dart
/// Renders a [ShapeElement] (spec 007a): a rectangle fills its box as a
/// [RectPrimitive]; a line draws across the box diagonal as a [LinePrimitive].
library;

import '../../../domain/elements/shape_element.dart';
import '../../../domain/geometry.dart';
import '../../../domain/styles/color.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../element_renderer.dart';
import '../render_context.dart';

/// The built-in renderer for `shape` elements.
class ShapeElementRenderer extends ElementRenderer<ShapeElement> {
  /// Const constructor.
  const ShapeElementRenderer();

  @override
  JetSize measure(ShapeElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(ShapeElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    switch (el.kind) {
      case ShapeKind.rectangle:
        out.add(RectPrimitive(
          bounds: bounds,
          fill: el.style.fill,
          stroke: el.style.stroke,
          strokeWidth: el.style.strokeWidth,
          elementId: el.id,
        ));
      case ShapeKind.line:
        final double left = bounds.x;
        final double top = bounds.y;
        final double right = bounds.x + bounds.width;
        final double bottom = bounds.y + bounds.height;
        final JetOffset start = el.flipDiagonal
            ? JetOffset(left, bottom)
            : JetOffset(left, top);
        final JetOffset end =
            el.flipDiagonal ? JetOffset(right, top) : JetOffset(right, bottom);
        out.add(LinePrimitive(
          bounds: bounds,
          start: start,
          end: end,
          color: el.style.stroke ?? JetColor.black,
          strokeWidth: el.style.strokeWidth,
          elementId: el.id,
        ));
    }
  }
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/rendering/elements/shape_element_renderer_test.dart -r expanded && flutter analyze`
Expected: PASS (4 tests); `No issues found!`. (The `switch` over `ShapeKind` is exhaustive — no `default`.)

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/elements/renderers/shape_element_renderer.dart \
  test/rendering/elements/shape_element_renderer_test.dart
git commit -m "feat(rendering): ShapeElementRenderer (line + rect) (007a)"
```

---

## Task 7: `ImageElementRenderer` (embedded bytes + placeholder fallback)

**Files:**
- Create: `lib/src/rendering/elements/renderers/image_element_renderer.dart`
- Test: `test/rendering/elements/image_element_renderer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/elements/image_element_renderer_test.dart`:

```dart
// ImageElementRenderer: BytesImageSource -> ImagePrimitive; url/field -> placeholder.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/image_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx =
      RenderContext(measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const ImageElementRenderer renderer = ImageElementRenderer();
  const JetRect bounds = JetRect(x: 0, y: 0, width: 50, height: 40);

  test('measure returns the authored box size', () {
    final ImageElement el = ImageElement(
        id: 'i', bounds: bounds, source: BytesImageSource(Uint8List(0)));
    expect(renderer.measure(el, ctx, const JetConstraints()),
        const JetSize(50, 40));
  });

  test('embedded bytes emit an ImagePrimitive with the element fit', () {
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final ImageElement el = ImageElement(
        id: 'i', bounds: bounds, source: BytesImageSource(bytes), fit: JetBoxFit.cover);
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final ImagePrimitive p = out.build().primitives.single as ImagePrimitive;
    expect(p.bytes, bytes);
    expect(p.fit, JetBoxFit.cover);
    expect(p.bounds, bounds);
    expect(p.elementId, 'i');
  });

  test('a url source (unresolved in 007a) emits a placeholder', () {
    const ImageElement el = ImageElement(
        id: 'i', bounds: bounds, source: UrlImageSource('https://x/y.png'));
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims[0], isA<RectPrimitive>());
    expect((prims[1] as TextRunPrimitive).lines.single.text, 'image');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/elements/image_element_renderer_test.dart -r expanded`
Expected: FAIL — `ImageElementRenderer` is undefined.

- [ ] **Step 3: Implement the renderer**

Create `lib/src/rendering/elements/renderers/image_element_renderer.dart`:

```dart
/// Renders an [ImageElement] (spec 007a). Embedded [BytesImageSource] becomes an
/// [ImagePrimitive]; a not-yet-resolved url/field source renders a placeholder
/// (byte resolution for those sources is a 007b / paint-prep concern).
library;

import '../../../domain/elements/image_element.dart';
import '../../../domain/elements/image_source.dart';
import '../../../domain/geometry.dart';
import '../../frame/frame_builder.dart';
import '../../frame/primitive.dart';
import '../element_renderer.dart';
import '../placeholder.dart';
import '../render_context.dart';

/// The built-in renderer for `image` elements.
class ImageElementRenderer extends ElementRenderer<ImageElement> {
  /// Const constructor.
  const ImageElementRenderer();

  @override
  JetSize measure(ImageElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(ImageElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    final JetImageSource source = el.source;
    if (source is BytesImageSource) {
      out.add(ImagePrimitive(
        bounds: bounds,
        bytes: source.bytes,
        fit: el.fit,
        elementId: el.id,
      ));
    } else {
      emitPlaceholder(out, bounds, 'image', ctx, elementId: el.id);
    }
  }
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/rendering/elements/image_element_renderer_test.dart -r expanded && flutter analyze`
Expected: PASS (3 tests); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/elements/renderers/image_element_renderer.dart \
  test/rendering/elements/image_element_renderer_test.dart
git commit -m "feat(rendering): ImageElementRenderer (embedded bytes + placeholder) (007a)"
```

---

## Task 8: `BarcodeElementRenderer` (placeholder for now)

**Files:**
- Create: `lib/src/rendering/elements/renderers/barcode_element_renderer.dart`
- Test: `test/rendering/elements/barcode_element_renderer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/elements/barcode_element_renderer_test.dart`:

```dart
// BarcodeElementRenderer: a labeled placeholder (real symbology is a later spec).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/barcode_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx =
      RenderContext(measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const BarcodeElementRenderer renderer = BarcodeElementRenderer();
  const JetRect bounds = JetRect(x: 0, y: 0, width: 80, height: 30);

  test('measure returns the authored box size', () {
    const BarcodeElement el = BarcodeElement(
        id: 'b', bounds: bounds, symbology: BarcodeSymbology.code128, data: '123');
    expect(renderer.measure(el, ctx, const JetConstraints()),
        const JetSize(80, 30));
  });

  test('emits a placeholder labeled with the symbology name', () {
    const BarcodeElement el = BarcodeElement(
        id: 'b', bounds: bounds, symbology: BarcodeSymbology.qrCode, data: 'X');
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    renderer.emit(el, ctx, bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims[0], isA<RectPrimitive>());
    expect((prims[1] as TextRunPrimitive).lines.single.text, 'qrCode');
    expect(prims[1].elementId, 'b');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/elements/barcode_element_renderer_test.dart -r expanded`
Expected: FAIL — `BarcodeElementRenderer` is undefined.

- [ ] **Step 3: Implement the renderer**

Create `lib/src/rendering/elements/renderers/barcode_element_renderer.dart`:

```dart
/// Renders a [BarcodeElement] (spec 007a) as a labeled placeholder. Real
/// symbology (Code128/EAN/QR/DataMatrix) is deferred to a dedicated later spec.
library;

import '../../../domain/elements/barcode_element.dart';
import '../../../domain/geometry.dart';
import '../../frame/frame_builder.dart';
import '../element_renderer.dart';
import '../placeholder.dart';
import '../render_context.dart';

/// The built-in renderer for `barcode` elements (placeholder).
class BarcodeElementRenderer extends ElementRenderer<BarcodeElement> {
  /// Const constructor.
  const BarcodeElementRenderer();

  @override
  JetSize measure(BarcodeElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(BarcodeElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    emitPlaceholder(out, bounds, el.symbology.name, ctx, elementId: el.id);
  }
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/rendering/elements/barcode_element_renderer_test.dart -r expanded && flutter analyze`
Expected: PASS (2 tests); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/elements/renderers/barcode_element_renderer.dart \
  test/rendering/elements/barcode_element_renderer_test.dart
git commit -m "feat(rendering): BarcodeElementRenderer placeholder (007a)"
```

---

## Task 9: `UnknownElementRenderer` (preserved-type placeholder)

**Files:**
- Create: `lib/src/rendering/elements/renderers/unknown_element_renderer.dart`
- Test: `test/rendering/elements/unknown_element_renderer_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/elements/unknown_element_renderer_test.dart`:

```dart
// UnknownElementRenderer: a placeholder labeled with the unrecognized typeKey.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/unknown_element.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/elements/renderers/unknown_element_renderer.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

void main() {
  final RenderContext ctx =
      RenderContext(measurer: MetricsTextMeasurer(FontRegistry()..registerDefault()));
  const UnknownElementRenderer renderer = UnknownElementRenderer();

  UnknownElement makeUnknown() => UnknownElement(
        typeKey: 'gizmo',
        rawJson: <String, Object?>{
          'type': 'gizmo',
          'id': 'g1',
          'bounds': <String, Object?>{'x': 0, 'y': 0, 'w': 25, 'h': 15},
        },
      );

  test('measure returns the best-effort bounds from the preserved JSON', () {
    expect(renderer.measure(makeUnknown(), ctx, const JetConstraints()),
        const JetSize(25, 15));
  });

  test('emits a placeholder labeled with the unknown typeKey', () {
    final FrameBuilder out = FrameBuilder(PageFormat.a4Portrait);
    final UnknownElement el = makeUnknown();
    renderer.emit(el, ctx, el.bounds, out);
    final List<FramePrimitive> prims = out.build().primitives;
    expect(prims[0], isA<RectPrimitive>());
    expect((prims[1] as TextRunPrimitive).lines.single.text, 'Unknown: gizmo');
    expect(prims[1].elementId, 'g1');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/elements/unknown_element_renderer_test.dart -r expanded`
Expected: FAIL — `UnknownElementRenderer` is undefined.

- [ ] **Step 3: Implement the renderer**

Create `lib/src/rendering/elements/renderers/unknown_element_renderer.dart`:

```dart
/// Renders any element whose type-key is not registered (spec 007a): a visible
/// placeholder labeled with the preserved type-key. The registry returns this
/// for every unregistered type, including a round-tripped `UnknownElement`.
library;

import '../../../domain/geometry.dart';
import '../../../domain/report_element.dart';
import '../../frame/frame_builder.dart';
import '../element_renderer.dart';
import '../placeholder.dart';
import '../render_context.dart';

/// The built-in fallback renderer for unregistered element types.
class UnknownElementRenderer extends ElementRenderer<ReportElement> {
  /// Const constructor.
  const UnknownElementRenderer();

  @override
  JetSize measure(ReportElement el, RenderContext ctx, JetConstraints constraints) =>
      JetSize(el.bounds.width, el.bounds.height);

  @override
  void emit(ReportElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) {
    emitPlaceholder(out, bounds, 'Unknown: ${el.typeKey}', ctx, elementId: el.id);
  }
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/rendering/elements/unknown_element_renderer_test.dart -r expanded && flutter analyze`
Expected: PASS (2 tests); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/elements/renderers/unknown_element_renderer.dart \
  test/rendering/elements/unknown_element_renderer_test.dart
git commit -m "feat(rendering): UnknownElementRenderer placeholder (007a)"
```

---

## Task 10: `ElementRendererRegistry` (dispatch + unknown fallback + last-write-wins)

**Files:**
- Create: `lib/src/rendering/elements/element_renderer_registry.dart`
- Test: `test/rendering/elements/element_renderer_registry_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/elements/element_renderer_registry_test.dart`:

```dart
// ElementRendererRegistry: typeKey dispatch, unknown fallback, last-write-wins.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/unknown_element.dart';
import 'package:jet_print/src/rendering/elements/element_renderer_registry.dart';
import 'package:jet_print/src/rendering/elements/renderers/text_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/unknown_element_renderer.dart';

void main() {
  test('rendererFor returns the registered renderer by typeKey', () {
    final ElementRendererRegistry reg = ElementRendererRegistry()
      ..register('text', const TextElementRenderer());
    const TextElement el = TextElement(
        id: 't', bounds: JetRect(x: 0, y: 0, width: 1, height: 1), text: 'x');
    expect(reg.rendererFor(el), isA<TextElementRenderer>());
  });

  test('rendererFor falls back to the Unknown renderer for an unregistered type',
      () {
    final ElementRendererRegistry reg = ElementRendererRegistry();
    final UnknownElement el = UnknownElement(
        typeKey: 'gizmo', rawJson: <String, Object?>{'type': 'gizmo'});
    expect(reg.rendererFor(el), isA<UnknownElementRenderer>());
  });

  test('register is last-write-wins (built-in override)', () {
    final ElementRendererRegistry reg = ElementRendererRegistry()
      ..register('text', const UnknownElementRenderer())
      ..register('text', const TextElementRenderer());
    const TextElement el = TextElement(
        id: 't', bounds: JetRect(x: 0, y: 0, width: 1, height: 1), text: 'x');
    expect(reg.rendererFor(el), isA<TextElementRenderer>());
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/elements/element_renderer_registry_test.dart -r expanded`
Expected: FAIL — `ElementRendererRegistry` is undefined.

- [ ] **Step 3: Implement the registry**

Create `lib/src/rendering/elements/element_renderer_registry.dart`:

```dart
/// Maps element `type` keys to their [ElementRenderer]s and dispatches (007a).
/// Unregistered types (including a round-tripped `UnknownElement`) resolve to the
/// built-in [UnknownElementRenderer] placeholder. Registration is last-write-wins
/// (matching `ElementCodecRegistry`), so a consumer can override a built-in.
library;

import '../../domain/report_element.dart';
import 'element_renderer.dart';
import 'renderers/unknown_element_renderer.dart';

/// A registry of element renderers keyed by `typeKey`.
class ElementRendererRegistry {
  final Map<String, ElementRenderer<ReportElement>> _renderers =
      <String, ElementRenderer<ReportElement>>{};

  static const ElementRenderer<ReportElement> _unknown =
      UnknownElementRenderer();

  /// Registers [renderer] for elements whose `typeKey` equals [typeKey]
  /// (last-write-wins).
  void register(String typeKey, ElementRenderer<ReportElement> renderer) {
    _renderers[typeKey] = renderer;
  }

  /// The renderer for [element]'s `typeKey`, or the Unknown placeholder renderer
  /// when no renderer is registered for it.
  ElementRenderer<ReportElement> rendererFor(ReportElement element) =>
      _renderers[element.typeKey] ?? _unknown;
}
```

- [ ] **Step 4: Run the test + analyzer**

Run: `flutter test test/rendering/elements/element_renderer_registry_test.dart -r expanded && flutter analyze`
Expected: PASS (3 tests); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/src/rendering/elements/element_renderer_registry.dart \
  test/rendering/elements/element_renderer_registry_test.dart
git commit -m "feat(rendering): ElementRendererRegistry with unknown fallback (007a)"
```

---

## Task 11: `ElementTypeRegistry` + `registerBuiltInElementTypes`

**Files:**
- Create: `lib/src/rendering/elements/element_type_registry.dart`
- Create: `lib/src/rendering/elements/built_in_element_renderers.dart`
- Test: `test/rendering/elements/element_type_registry_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/rendering/elements/element_type_registry_test.dart`:

```dart
// ElementTypeRegistry: pairs codec + renderer; composes the codec registry;
// registerBuiltInElementTypes wires text/shape/image/barcode; last-write-wins.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/elements/barcode_element.dart';
import 'package:jet_print/src/domain/elements/image_element.dart';
import 'package:jet_print/src/domain/elements/image_source.dart';
import 'package:jet_print/src/domain/elements/shape_element.dart';
import 'package:jet_print/src/domain/elements/text_element.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/rendering/elements/built_in_element_renderers.dart';
import 'package:jet_print/src/rendering/elements/element_type_registry.dart';
import 'package:jet_print/src/rendering/elements/renderers/barcode_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/image_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/shape_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/text_element_renderer.dart';
import 'package:jet_print/src/rendering/elements/renderers/unknown_element_renderer.dart';

void main() {
  const JetRect r = JetRect(x: 0, y: 0, width: 1, height: 1);

  test('built-ins register both a codec and a renderer per type', () {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);

    const TextElement text = TextElement(id: 't', bounds: r, text: 'x');
    expect(reg.renderers.rendererFor(text), isA<TextElementRenderer>());

    // The codec half drives serialization: encode produces a typed map.
    expect(reg.codecs.encode(text)['type'], 'text');
  });

  test('renderers for all built-in types are wired (direct instances)', () {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    expect(
        reg.renderers.rendererFor(
            const ShapeElement(id: 's', bounds: r, kind: ShapeKind.rectangle)),
        isA<ShapeElementRenderer>());
    expect(
        reg.renderers.rendererFor(
            ImageElement(id: 'i', bounds: r, source: BytesImageSource(Uint8List(0)))),
        isA<ImageElementRenderer>());
    expect(
        reg.renderers.rendererFor(const BarcodeElement(
            id: 'b', bounds: r, symbology: BarcodeSymbology.code128, data: '1')),
        isA<BarcodeElementRenderer>());
  });

  test('register is last-write-wins (built-in override)', () {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    // Override 'text' with a different renderer. Widening E to ReportElement is
    // the documented covariance path (UnknownElementRenderer is
    // ElementRenderer<ReportElement>, not <TextElement>).
    reg.register<ReportElement>(
        'text', const TextElementCodec(), const UnknownElementRenderer());
    const TextElement text = TextElement(id: 't', bounds: r, text: 'x');
    expect(reg.renderers.rendererFor(text), isA<UnknownElementRenderer>());
  });
}
```

Add these imports to the test's import block (the override test references `ReportElement` and `TextElementCodec`):
```dart
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/serialization/text_element_codec.dart';
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/rendering/elements/element_type_registry_test.dart -r expanded`
Expected: FAIL — `ElementTypeRegistry`/`registerBuiltInElementTypes` are undefined.

- [ ] **Step 3: Implement `ElementTypeRegistry`**

Create `lib/src/rendering/elements/element_type_registry.dart`:

```dart
/// The unified element-type extension point (spec 007a): binds an element type's
/// codec (persist) and renderer (draw) under one `typeKey`. COMPOSES — does not
/// replace — the domain `ElementCodecRegistry` ([codecs]), which `report_codec`
/// consumes for save/load; [renderers] is used for render-time dispatch.
library;

import '../../domain/report_element.dart';
import '../../domain/serialization/element_codec.dart';
import 'element_renderer.dart';
import 'element_renderer_registry.dart';

/// Pairs codec and renderer registries behind one typed `register` call.
class ElementTypeRegistry {
  /// Creates a registry, defaulting each half to a fresh empty registry.
  ElementTypeRegistry({
    ElementCodecRegistry? codecs,
    ElementRendererRegistry? renderers,
  })  : codecs = codecs ?? ElementCodecRegistry(),
        renderers = renderers ?? ElementRendererRegistry();

  /// The codec registry (consumed by `encodeTemplate`/`decodeTemplate`).
  final ElementCodecRegistry codecs;

  /// The renderer registry (consumed by render-time dispatch).
  final ElementRendererRegistry renderers;

  /// Registers [codec] and [renderer] for [typeKey] (last-write-wins on both).
  ///
  /// The shared type parameter [E] pairs the two; passing an explicit type
  /// argument (as the built-ins do) rejects a mismatched pair. Dart's covariant
  /// generics allow an *inferred* call to widen [E] to `ReportElement` and
  /// compile a mismatch, so this enforces pairing, it does not fully prevent it
  /// — the same trade-off `ElementCodec`'s `covariant ReportElement` documents.
  void register<E extends ReportElement>(
    String typeKey,
    ElementCodec<E> codec,
    ElementRenderer<E> renderer,
  ) {
    codecs.register(typeKey, codec);
    renderers.register(typeKey, renderer);
  }
}
```

- [ ] **Step 4: Implement `registerBuiltInElementTypes`**

Create `lib/src/rendering/elements/built_in_element_renderers.dart`:

```dart
/// Registers the built-in element types (codec + renderer) shipped with the
/// library, through the single paired `ElementTypeRegistry.register` call so each
/// built-in flows the same path a custom type does (spec 007a). Consumers add
/// their own types with further `register(...)` calls.
library;

import '../../domain/elements/barcode_element.dart';
import '../../domain/elements/image_element.dart';
import '../../domain/elements/shape_element.dart';
import '../../domain/elements/text_element.dart';
import '../../domain/serialization/barcode_element_codec.dart';
import '../../domain/serialization/image_element_codec.dart';
import '../../domain/serialization/shape_element_codec.dart';
import '../../domain/serialization/text_element_codec.dart';
import 'element_type_registry.dart';
import 'renderers/barcode_element_renderer.dart';
import 'renderers/image_element_renderer.dart';
import 'renderers/shape_element_renderer.dart';
import 'renderers/text_element_renderer.dart';

/// Registers `text`, `shape`, `image`, and `barcode` (each codec paired with its
/// renderer) into [registry].
void registerBuiltInElementTypes(ElementTypeRegistry registry) {
  registry
    ..register<TextElement>(
        'text', const TextElementCodec(), const TextElementRenderer())
    ..register<ShapeElement>(
        'shape', const ShapeElementCodec(), const ShapeElementRenderer())
    ..register<ImageElement>(
        'image', const ImageElementCodec(), const ImageElementRenderer())
    ..register<BarcodeElement>(
        'barcode', const BarcodeElementCodec(), const BarcodeElementRenderer());
}
```

- [ ] **Step 5: Run the test + analyzer**

Run: `flutter test test/rendering/elements/element_type_registry_test.dart -r expanded && flutter analyze`
Expected: PASS (2 tests); `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/rendering/elements/element_type_registry.dart \
  lib/src/rendering/elements/built_in_element_renderers.dart \
  test/rendering/elements/element_type_registry_test.dart
git commit -m "feat(rendering): ElementTypeRegistry + built-in element types (007a)"
```

---

## Task 12: Flagship persisted-extension test (Constitution-II proof)

**Files:**
- Test: `test/rendering/elements/persisted_extension_test.dart`

- [ ] **Step 1: Write the test (no library change — this proves zero core edits)**

Create `test/rendering/elements/persisted_extension_test.dart`:

```dart
// FLAGSHIP: a custom element type round-trips through report_codec AND renders,
// with zero edits to library src/ (Constitution II — persistence + rendering).
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/src/domain/geometry.dart';
import 'package:jet_print/src/domain/page_format.dart';
import 'package:jet_print/src/domain/report_band.dart';
import 'package:jet_print/src/domain/report_element.dart';
import 'package:jet_print/src/domain/report_template.dart';
import 'package:jet_print/src/domain/serialization/element_codec.dart';
import 'package:jet_print/src/domain/serialization/report_codec.dart';
import 'package:jet_print/src/domain/styles/color.dart';
import 'package:jet_print/src/rendering/elements/built_in_element_renderers.dart';
import 'package:jet_print/src/rendering/elements/element_renderer.dart';
import 'package:jet_print/src/rendering/elements/element_type_registry.dart';
import 'package:jet_print/src/rendering/elements/render_context.dart';
import 'package:jet_print/src/rendering/frame/frame_builder.dart';
import 'package:jet_print/src/rendering/frame/primitive.dart';
import 'package:jet_print/src/rendering/text/font_registry.dart';
import 'package:jet_print/src/rendering/text/metrics_text_measurer.dart';

/// A custom element type defined ENTIRELY in test code.
class StarElement extends ReportElement {
  const StarElement({required super.id, required super.bounds, required this.points});
  final int points;
  @override
  String get typeKey => 'star';
  @override
  bool operator ==(Object other) =>
      other is StarElement &&
      other.id == id &&
      other.bounds == bounds &&
      other.points == points;
  @override
  int get hashCode => Object.hash(id, bounds, points);
}

class StarCodec extends ElementCodec<StarElement> {
  const StarCodec();
  @override
  StarElement fromJson(Map<String, Object?> json) => StarElement(
        id: json['id']! as String,
        bounds: JetRect.fromJson((json['bounds']! as Map).cast<String, Object?>()),
        points: (json['points']! as num).toInt(),
      );
  @override
  Map<String, Object?> toJson(StarElement element) => <String, Object?>{
        'id': element.id,
        'bounds': element.bounds.toJson(),
        'points': element.points,
      };
}

class StarRenderer extends ElementRenderer<StarElement> {
  const StarRenderer();
  @override
  JetSize measure(StarElement el, RenderContext ctx, JetConstraints c) =>
      JetSize(el.bounds.width, el.bounds.height);
  @override
  void emit(StarElement el, RenderContext ctx, JetRect bounds, FrameBuilder out) =>
      out.add(RectPrimitive(bounds: bounds, stroke: JetColor.black, elementId: el.id));
}

void main() {
  test('custom type round-trips through report_codec AND renders, zero core edits',
      () {
    final ElementTypeRegistry reg = ElementTypeRegistry();
    registerBuiltInElementTypes(reg);
    reg.register<StarElement>('star', const StarCodec(), const StarRenderer());

    const StarElement star = StarElement(
        id: 's1', bounds: JetRect(x: 10, y: 20, width: 30, height: 30), points: 5);
    final ReportTemplate template = ReportTemplate(
      name: 'demo',
      page: PageFormat.a4Portrait,
      bands: <ReportBand>[
        ReportBand(
            type: BandType.detail, height: 50, elements: <ReportElement>[star]),
      ],
    );

    // (a) Persist through the REAL codec path: encode -> decode -> re-encode.
    final Map<String, Object?> json = encodeTemplate(template, reg.codecs);
    final ReportTemplate decoded = decodeTemplate(json, reg.codecs);
    expect(encodeTemplate(decoded, reg.codecs), json); // deep map equality
    expect(decoded.bands.single.elements.single, star); // typed, value-equal

    // (b) Render through the registered renderer.
    final FrameBuilder out = FrameBuilder(template.page);
    reg.renderers.rendererFor(star).emit(
          star,
          RenderContext(
              measurer: MetricsTextMeasurer(FontRegistry()..registerDefault())),
          star.bounds,
          out,
        );
    final FramePrimitive prim = out.build().primitives.single;
    expect(prim, isA<RectPrimitive>());
    expect((prim as RectPrimitive).elementId, 's1');
  });
}
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/rendering/elements/persisted_extension_test.dart -r expanded`
Expected: PASS — proves a never-before-seen type both persists (through `encodeTemplate`/`decodeTemplate`) and renders, with no edits under `lib/`.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add test/rendering/elements/persisted_extension_test.dart
git commit -m "test(rendering): flagship persisted-extension proof (round-trip + render) (007a)"
```

---

## Task 13: Layer-boundary assertion + CHANGELOG

**Files:**
- Modify: `test/architecture/layer_boundaries_test.dart`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add the failing boundary assertion**

In `test/architecture/layer_boundaries_test.dart`, inside the `group('layer boundaries — rendering seam', ...)` block, add a new test after the existing `'only paint/canvas_painter.dart imports dart:ui / Flutter UI'` test (before the group's closing `});`):

```dart
    test('the elements/ seam exists and stays Flutter-free', () {
      final Directory elementsDir = Directory(
          '${root.path}/packages/jet_print/lib/src/rendering/elements');
      expect(elementsDir.existsSync(), isTrue,
          reason: 'Missing ${elementsDir.path}');
      final List<File> elementsFiles = elementsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((FileSystemEntity f) => f.path.endsWith('.dart'))
          .toList();
      expect(elementsFiles, isNotEmpty);
      final List<String> violations = <String>[];
      for (final File file in elementsFiles) {
        for (final String uri in _directive
            .allMatches(file.readAsStringSync())
            .map((Match m) => m.group(1)!)) {
          if (_isFlutterUi(uri)) violations.add('${file.path} -> $uri');
        }
      }
      expect(violations, isEmpty,
          reason: 'rendering/elements must stay headless (no dart:ui/Flutter):\n'
              '${violations.join('\n')}');
    });
```

- [ ] **Step 2: Run the boundary test**

Run: `flutter test test/architecture/layer_boundaries_test.dart -r expanded`
Expected: PASS — all `rendering/elements/` files are headless (the seam imports only domain/expression/frame/text).

- [ ] **Step 3: Update the CHANGELOG**

In `CHANGELOG.md`, under the current unreleased section, add:

```markdown
- **Element renderers (spec 007a).** `ElementRenderer<E>` (measure + emit) paired with
  `ElementCodec<E>` via `ElementTypeRegistry.register`; built-in renderers for text, shape, image,
  and barcode/unknown placeholders; `RenderContext`; `JetConstraints`. `MeasuredText` gains a
  resolved `fontFamily` (006 amendment). Custom element types round-trip through JSON *and* render
  with zero core edits.
```

- [ ] **Step 4: Run the full suite + analyzer**

Run: `flutter test -r expanded && flutter analyze`
Expected: every test PASSES (the prior 365+ plus the new 007a tests); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add test/architecture/layer_boundaries_test.dart CHANGELOG.md
git commit -m "test(rendering): pin elements/ seam headless; changelog (007a)"
```

---

## Done

All of spec 007a is implemented: the render contract, five built-in renderers, both registries, the unified registration, the `MeasuredText.fontFamily` amendment, and the flagship persisted-extension proof. After Task 13, dispatch a final holistic code review over the whole 007a change set, then use `superpowers:finishing-a-development-branch` to merge `007a-element-renderers` into `main`.
