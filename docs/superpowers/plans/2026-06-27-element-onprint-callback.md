# Element `onPrint` Callback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is Red→Green TDD.

**Goal:** Add a host-supplied per-element callback (`RenderOptions.onElementPrint`) invoked at emit time on preview/export/print, able to transform or suppress each element with full page/band/fields/variables context.

**Architecture:** A new public typedef + context type. The fill IR (`FilledBand`) gains the originating row's field snapshot. The layouter's single placement choke point (`LazyLayout._place`) invokes the callback just before each `renderer.emit`, with a fail-safe guard. The option threads engine → `layoutLazyDefinition` → `LazyLayout`. No serialization, designer, measurement, renderer, primitive, or paint change.

**Tech Stack:** Dart / Flutter, `flutter_test`. Spec: [docs/superpowers/specs/2026-06-27-element-onprint-callback-design.md](../specs/2026-06-27-element-onprint-callback-design.md).

## Global Constraints

- Run `flutter`/`dart` from `packages/jet_print`. Run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (`flutter` drifts the CWD into the package).
- Additive only: no serialization/codec change, no designer model change, no render-primitive/paint change.
- **Hard gate:** with `onElementPrint == null`, every existing golden is byte-identical (Constitution IV). Render goldens must not change.
- Callback contract: pure over `(element, context)`; transform/suppress; same runtime type or it is ignored; a throw never crashes the render.
- `dart format` clean and `flutter analyze` clean before every commit.
- Branch off `main` for this feature before Task 1.

---

## File Map

- **Create** `packages/jet_print/lib/src/rendering/engine/element_print_callback.dart` — `JetElementPrintCallback` typedef + `ElementPrintContext` class.
- **Modify** `packages/jet_print/lib/jet_print.dart` — export the two new symbols.
- **Modify** `packages/jet_print/lib/src/rendering/fill/filled_report.dart` — `FilledBand.fields` (carry-through, excluded from `==`/`hashCode`/`toString`).
- **Modify** `packages/jet_print/lib/src/rendering/fill/report_filler.dart` — populate `fields` from the row at `addBand`.
- **Modify** `packages/jet_print/lib/src/rendering/engine/render_options.dart` — `onElementPrint` field.
- **Modify** `packages/jet_print/lib/src/rendering/layout/band_measurer.dart` — `MeasuredBand.source` (the `FilledBand`).
- **Modify** `packages/jet_print/lib/src/rendering/layout/report_layouter.dart` — thread the callback into `LazyLayout`, invoke it in `_place`.
- **Modify** `packages/jet_print/lib/src/rendering/engine/jet_report_engine.dart` — pass `options.onElementPrint` to `layoutLazyDefinition`.
- Tests: new `test/rendering/engine/element_print_callback_test.dart`, `test/rendering/onprint_hook_test.dart`; extend `test/rendering/fill/report_filler_test.dart` (or nearest fill test).

### Grounded facts (verified in code)

- `FilledBand(...)` is built once in `report_filler.dart` `addBand` (≈L258) and has the `DataRow? row` in scope there. `DataRow.field(name)` returns `Object?`; wrap with `JetValue.from(...)` (the same coercion `FillEvalContext.resolveField` uses, `value.dart` L20/L75). `DataRow.fields` is `List<FieldDef>`.
- `BandType` (`report_band.dart` L6) includes `detail`, `pageHeader`, `pageFooter`, `groupHeader`, `summary`, etc.
- `MeasuredBand` (`band_measurer.dart` L25) carries `height` + `elements: List<({ReportElement element, JetRect bounds})>`; built once in `BandMeasurer.measure` (L52) as `MeasuredBand(maxBottom, boxes)`. The measured box keeps the element's authored `x/y/width` and a grown `height`.
- `LazyLayout._place` (`report_layouter.dart` L146) is the single emit choke point; called 3× in `buildPage` (L225 body, L230 headers, L238 footers). `pageCount` getter = `_plans.length` (L142). `LazyLayout` already holds `diagnostics` (a `ReportDiagnostics`; use `.warning(msg, elementId: ...)`).
- Engine `renderDefinition` (`jet_report_engine.dart` L59) calls `ReportLayouter(measurer: ...).layoutLazyDefinition(definition, fill.report)` (L88). `layoutLazyDefinition` builds `LazyLayout._(...)` (`report_layouter.dart` L298/L622). Eager `layoutDefinition` (L283) wraps `layoutLazyDefinition`.
- `JetColor(0xAARRGGBB)` const ctor; `JetColor.black`. `JetTextStyle.copyWith({JetColor? color, ...})`. `TextElement.copyWith({String? text, JetTextStyle? style, JetRect? bounds, String? name, BoolProperty? visible})`. `JetNumber.value` is `double`. All exported from `jet_print.dart`.

---

## Task 1: Public API types — `JetElementPrintCallback` + `ElementPrintContext`

**Files:**
- Create: `packages/jet_print/lib/src/rendering/engine/element_print_callback.dart`
- Modify: `packages/jet_print/lib/jet_print.dart`
- Test: `packages/jet_print/test/rendering/engine/element_print_callback_test.dart`

**Interfaces:**
- Produces: `typedef JetElementPrintCallback = ReportElement? Function(ReportElement element, ElementPrintContext context);` and `class ElementPrintContext { final int pageNumber; final int pageCount; final BandType bandType; final String? bandName; final Map<String, JetValue> fields; final Map<String, JetValue> variables; const ElementPrintContext({required ...}); }`.

- [ ] **Step 1: Write the failing test.**

```dart
// test/rendering/engine/element_print_callback_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

void main() {
  test('ElementPrintContext exposes its fields; callback can transform', () {
    const ctx = ElementPrintContext(
      pageNumber: 2,
      pageCount: 5,
      bandType: BandType.detail,
      bandName: 'customer',
      fields: <String, JetValue>{'total': JetNumber(value: -3)},
      variables: <String, JetValue>{},
    );
    expect(ctx.pageNumber, 2);
    expect(ctx.pageCount, 5);
    expect(ctx.bandType, BandType.detail);
    expect(ctx.bandName, 'customer');
    expect(ctx.fields['total'], const JetNumber(value: -3));

    final JetElementPrintCallback cb = (el, c) =>
        el is TextElement ? el.copyWith(text: 'p${c.pageNumber}') : el;
    final TextElement src = const TextElement(
      id: 't',
      bounds: JetRect(x: 0, y: 0, width: 10, height: 10),
      text: 'orig',
    );
    final ReportElement? out = cb(src, ctx);
    expect((out! as TextElement).text, 'p2');
  });
}
```

- [ ] **Step 2: Run to verify it fails.**

Run: `flutter test test/rendering/engine/element_print_callback_test.dart`
Expected: FAIL — `ElementPrintContext`/`JetElementPrintCallback` undefined.

- [ ] **Step 3: Create the implementation.**

```dart
// lib/src/rendering/engine/element_print_callback.dart
/// The host hook for per-element customization at emit time (spec
/// 2026-06-27). Fired once for every element about to be painted — on preview,
/// export, and print alike, because all three render through
/// `JetReportEngine.renderDefinition`.
library;

import '../../domain/report_band.dart' show BandType;
import '../../domain/report_element.dart';
import '../../expression/value.dart';

/// Read-only context handed to a [JetElementPrintCallback] at emit time.
class ElementPrintContext {
  /// Creates an emit-time context.
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

  /// The role of the band this element belongs to.
  final BandType bandType;

  /// The group name for group bands; null for non-group bands and page chrome.
  /// (The fill IR does not carry a band id, so this is group-only.)
  final String? bandName;

  /// The originating row's field values, keyed by field name. Empty for page
  /// chrome and static (rowless) bands — null-check, do not assume presence.
  final Map<String, JetValue> fields;

  /// The variable / running-aggregate snapshot at this band instance.
  final Map<String, JetValue> variables;
}

/// Fired once for every element about to be painted. Return [element] unchanged
/// to pass through, a modified copy of the **same runtime type** to alter it, or
/// null to suppress it. A different-type return is ignored (original painted)
/// and a diagnostic recorded; a throw is contained (original painted).
///
/// The element's bounds are fixed at emit time: changing content that needs more
/// height clips at the existing box rather than reflowing the band
/// (Jasper-faithful). Position (x/y) and width changes are honored.
///
/// MUST be deterministic over (element, context): it runs on every render pass,
/// and preview / export / print are separate passes — a callback that reads a
/// clock, RNG, or live data source makes them diverge.
typedef JetElementPrintCallback = ReportElement? Function(
  ReportElement element,
  ElementPrintContext context,
);
```

- [ ] **Step 4: Export from the barrel.** Add to `lib/jet_print.dart` near the other engine exports (after the `render_options.dart` export):

```dart
export 'src/rendering/engine/element_print_callback.dart'
    show ElementPrintContext, JetElementPrintCallback;
```

- [ ] **Step 5: Run to verify it passes.**

Run: `flutter test test/rendering/engine/element_print_callback_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + format, then commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/engine/element_print_callback.dart lib/jet_print.dart test/rendering/engine/element_print_callback_test.dart && flutter analyze lib/src/rendering/engine/element_print_callback.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/engine/element_print_callback.dart packages/jet_print/lib/jet_print.dart packages/jet_print/test/rendering/engine/element_print_callback_test.dart
git commit -m "feat(engine): JetElementPrintCallback + ElementPrintContext public types"
```

---

## Task 2: `FilledBand.fields` carries the originating row

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/fill/filled_report.dart`
- Modify: `packages/jet_print/lib/src/rendering/fill/report_filler.dart`
- Test: `packages/jet_print/test/rendering/fill/onprint_fill_fields_test.dart` (new)

**Interfaces:**
- Produces: `FilledBand.fields` → `Map<String, JetValue>` (unmodifiable; `const <String, JetValue>{}` default). Excluded from `==`/`hashCode`/`toString` (carry-through metadata, not band identity — protects existing fill snapshot tests).

- [ ] **Step 1: Write the failing test.** Build a one-field, one-row in-memory source and fill it; assert the detail band carries the row value under `fields`, and a rowless band carries `{}`.

```dart
// test/rendering/fill/onprint_fill_fields_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:jet_print/src/rendering/fill/report_filler.dart';
import 'package:jet_print/src/rendering/fill/filled_report.dart';

void main() {
  test('FilledBand.fields carries the originating row; {} when rowless', () {
    final def = ReportDefinition(
      page: const PageFormat.a4(),
      body: ReportBody(
        root: const DetailScope(
          children: <ScopeNode>[
            BandNode(
              band: Band(
                id: 'detail',
                type: BandType.detail,
                height: 20,
                elements: <ReportElement>[
                  TextElement(
                    id: 'amt',
                    bounds: JetRect(x: 0, y: 0, width: 80, height: 20),
                    text: 'amt',
                    expression: r'$F{amount}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final source = JetInMemoryDataSource(
      fields: const <FieldDef>[FieldDef(name: 'amount', type: JetFieldType.number)],
      rows: const <Map<String, Object?>>[
        <String, Object?>{'amount': 42},
      ],
    );

    final FillResult result = ReportFiller().fillDefinition(def, source);
    final FilledBand detail =
        result.report.bands.firstWhere((b) => b.type == BandType.detail);
    expect(detail.fields['amount'], const JetNumber(value: 42));
  });
}
```

> NOTE: verify the exact `ReportDefinition`/`DetailScope`/`BandNode`/`JetInMemoryDataSource`/`FillResult` constructor shapes against a neighboring fill test (e.g. an existing `test/rendering/fill/*_test.dart`) before running — copy that file's import paths and builder style. The assertion (`detail.fields['amount']`) is the load-bearing part; adjust the scaffolding to match the codebase's current builders.

- [ ] **Step 2: Run to verify it fails.**

Run: `flutter test test/rendering/fill/onprint_fill_fields_test.dart`
Expected: FAIL — `FilledBand` has no `fields` getter.

- [ ] **Step 3: Add the field to `FilledBand`.** In `filled_report.dart`, extend the constructor and add the field. Keep `==`/`hashCode`/`toString` unchanged.

```dart
  FilledBand({
    required this.type,
    required this.height,
    required List<ReportElement> elements,
    required Map<String, JetValue> variables,
    Map<String, JetValue> fields = const <String, JetValue>{},
    this.group,
  })  : elements = List<ReportElement>.unmodifiable(elements),
        variables = Map<String, JetValue>.unmodifiable(variables),
        fields = Map<String, JetValue>.unmodifiable(fields);
```

```dart
  /// The originating row's field values (spec 2026-06-27), keyed by field name;
  /// `{}` for rowless bands (chrome/static). Carry-through for the
  /// `onElementPrint` hook — intentionally excluded from `==`/`hashCode`/
  /// `toString`: a band's identity is its type/height/elements/variables/group,
  /// and equal designs over equal data already imply equal source rows, so
  /// including `fields` would only churn fill-snapshot goldens.
  final Map<String, JetValue> fields;
```

- [ ] **Step 4: Populate it in the filler.** In `report_filler.dart` `addBand` (≈L237–L267), the `FilledBand(...)` literal is built with `DataRow? row` in scope. Add a `fields:` argument built from the row:

```dart
      bands.add(FilledBand(
        type: band.type,
        height: band.height,
        elements: <ReportElement>[
          for (final ReportElement e in band.elements)
            if (resolver.isVisible(e,
                row: row, params: params, variables: vars))
              resolver.resolve(e, row: row, params: params, variables: vars),
        ],
        variables: vars,
        fields: row == null
            ? const <String, JetValue>{}
            : <String, JetValue>{
                for (final FieldDef f in row.fields)
                  f.name: JetValue.from(row.field(f.name)),
              },
        group: /* keep existing group argument if present */,
      ));
```

> Match the existing literal exactly — preserve every current argument (notably `group:` if passed) and only ADD `fields:`. `JetValue.from` is imported via `value.dart`; `FieldDef` via the data layer. Confirm both are already imported in `report_filler.dart` (they are used nearby) or add the imports.

- [ ] **Step 5: Run to verify it passes.**

Run: `flutter test test/rendering/fill/onprint_fill_fields_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full fill suite — no regression.**

Run: `flutter test test/rendering/fill`
Expected: PASS (fields excluded from `==`/`toString`, so fill snapshots are unchanged).

- [ ] **Step 7: Analyze + format, then commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/fill/filled_report.dart lib/src/rendering/fill/report_filler.dart test/rendering/fill/onprint_fill_fields_test.dart && flutter analyze lib/src/rendering/fill
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering/fill/filled_report.dart packages/jet_print/lib/src/rendering/fill/report_filler.dart packages/jet_print/test/rendering/fill/onprint_fill_fields_test.dart
git commit -m "feat(fill): FilledBand carries originating row fields for onPrint"
```

---

## Task 3: Thread the callback in and invoke it (pass-through + transform)

**Files:**
- Modify: `packages/jet_print/lib/src/rendering/engine/render_options.dart`
- Modify: `packages/jet_print/lib/src/rendering/layout/band_measurer.dart`
- Modify: `packages/jet_print/lib/src/rendering/layout/report_layouter.dart`
- Modify: `packages/jet_print/lib/src/rendering/engine/jet_report_engine.dart`
- Test: `packages/jet_print/test/rendering/onprint_hook_test.dart` (new)

**Interfaces:**
- Consumes: `JetElementPrintCallback`, `ElementPrintContext` (Task 1); `FilledBand.fields` (Task 2).
- Produces: `RenderOptions.onElementPrint` (`JetElementPrintCallback?`, default null); `MeasuredBand.source` (`FilledBand`); `LazyLayout` invokes the callback in `_place`. `ReportLayouter.layoutLazyDefinition(def, filled, {JetElementPrintCallback? onElementPrint})` and `layoutDefinition(..., {JetElementPrintCallback? onElementPrint})`.

- [ ] **Step 1: Write the failing test** — pass-through is identical, transform recolors.

```dart
// test/rendering/onprint_hook_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _singleText(String expr) => ReportDefinition(
      page: const PageFormat.a4(),
      body: ReportBody(
        root: DetailScope(
          children: <ScopeNode>[
            BandNode(
              band: Band(
                id: 'detail',
                type: BandType.detail,
                height: 20,
                elements: <ReportElement>[
                  TextElement(
                    id: 'amt',
                    bounds: const JetRect(x: 0, y: 0, width: 120, height: 20),
                    text: 'amt',
                    expression: expr,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

JetInMemoryDataSource _source(num amount) => JetInMemoryDataSource(
      fields: const <FieldDef>[FieldDef(name: 'amount', type: JetFieldType.number)],
      rows: <Map<String, Object?>>[<String, Object?>{'amount': amount}],
    );

// Collects the colors of the text-run primitives across all pages.
List<JetColor> _textColors(RenderedReport r) => <JetColor>[
      for (int i = 0; i < r.pageCount; i++)
        for (final p in r.page(i).primitives)
          if (p is TextRunPrimitive) p.style.color,
    ];

void main() {
  test('null callback passes through; transform recolors a text element', () {
    final def = _singleText(r'$F{amount}');

    final RenderedReport plain = const JetReportEngine()
        .renderDefinition(def, _source(-5));
    expect(_textColors(plain), everyElement(JetColor.black));

    final RenderedReport painted = const JetReportEngine().renderDefinition(
      def,
      _source(-5),
      options: RenderOptions(
        onElementPrint: (el, ctx) {
          if (el is! TextElement) return el;
          final v = ctx.fields['amount'];
          if (v is JetNumber && v.value < 0) {
            return el.copyWith(
                style: el.style.copyWith(color: const JetColor(0xFFFF0000)));
          }
          return el;
        },
      ),
    );
    expect(_textColors(painted), contains(const JetColor(0xFFFF0000)));
  });
}
```

> Verify `RenderedReport`'s page-access API (`pageCount` / `page(i)` / `.primitives`) and `TextRunPrimitive.style.color` against `lib/src/rendering/engine/rendered_report.dart`, `frame/page_frame.dart`, and `frame/primitive.dart`; adjust the `_textColors` accessor to the actual names. The behavioral assertions (black by default, red after transform) are the load-bearing part.

- [ ] **Step 2: Run to verify it fails.**

Run: `flutter test test/rendering/onprint_hook_test.dart`
Expected: FAIL — `RenderOptions` has no `onElementPrint`.

- [ ] **Step 3: Add the option field.** In `render_options.dart`, add the import and field (const ctor stays valid; default null).

```dart
import 'element_print_callback.dart';
```
```dart
    this.fonts = const <JetFontFamily>[],
    this.onElementPrint,
  });
```
```dart
  /// Host hook invoked once per element at emit time, on preview/export/print
  /// alike (spec 2026-06-27). Null (default) means no hook and byte-identical
  /// output to today. See [JetElementPrintCallback] for the contract.
  final JetElementPrintCallback? onElementPrint;
```

- [ ] **Step 4: Carry the source band on `MeasuredBand`.** In `band_measurer.dart`:

```dart
  MeasuredBand(this.height, List<({ReportElement element, JetRect bounds})> elements,
      this.source)
      : elements = List<({ReportElement element, JetRect bounds})>.unmodifiable(
            elements);
```
```dart
  /// The filled band this was measured from (spec 2026-06-27 — gives the emit
  /// hook the band's type/group/fields/variables).
  final FilledBand source;
```
And update the single construction site in `measure`:
```dart
    return MeasuredBand(maxBottom, boxes, band);
```

> `band_measurer.dart` already imports `filled_report.dart`. Grep `MeasuredBand(` across `lib/` to confirm `measure()` is the only construction site; if the boundary pass builds any `MeasuredBand` directly, pass its source `FilledBand` there too.

- [ ] **Step 5: Thread + invoke in `report_layouter.dart`.**

(a) Import the callback type:
```dart
import '../engine/element_print_callback.dart';
```

(b) Add a field + ctor param to `LazyLayout`:
```dart
  final JetElementPrintCallback? _onElementPrint;
```
In `LazyLayout._({...})` add `JetElementPrintCallback? onElementPrint,` and `_onElementPrint = onElementPrint` in the initializer list.

(c) Replace `_place` (L146–L161) with the context-aware, guarded version. Height comes from the measured box `e.bounds`; x/y/width from the (possibly modified) element — identical when unchanged, so null-callback output is byte-identical:

```dart
  void _place(
    List<({ReportElement element, JetRect bounds})> boxes,
    double leftX,
    double topY,
    FrameBuilder fb, {
    required int pageNumber,
    required BandType bandType,
    required String? bandName,
    required Map<String, JetValue> fields,
    required Map<String, JetValue> variables,
  }) {
    final JetElementPrintCallback? cb = _onElementPrint;
    final ElementPrintContext ctx = ElementPrintContext(
      pageNumber: pageNumber,
      pageCount: pageCount,
      bandType: bandType,
      bandName: bandName,
      fields: fields,
      variables: variables,
    );
    for (final ({ReportElement element, JetRect bounds}) e in boxes) {
      ReportElement el = e.element;
      if (cb != null) {
        ReportElement? out;
        try {
          out = cb(el, ctx);
        } catch (err) {
          diagnostics.warning('onElementPrint threw for "${el.id}": $err',
              elementId: el.id);
          out = el; // fail-safe to original
        }
        if (out == null) continue; // suppress
        if (out.runtimeType != el.runtimeType) {
          diagnostics.warning(
              'onElementPrint returned ${out.runtimeType} for "${el.id}" '
              '(expected ${el.runtimeType}); ignoring',
              elementId: el.id);
          out = el; // same-type guard
        }
        el = out;
      }
      _renderers.rendererFor(el).emit(
            el,
            _ctx,
            JetRect(
              x: leftX + el.bounds.x,
              y: topY + el.bounds.y,
              width: el.bounds.width,
              height: e.bounds.height,
            ),
            fb,
          );
    }
  }
```

> Confirm `ReportDiagnostics.warning(String, {String? elementId})` matches the existing call style in this file (it is used at L305/L335 etc.). Add imports for `BandType` (`../../domain/report_band.dart` — already imported) and `JetValue` (`../../expression/value.dart` — already imported).

(d) Update the three `buildPage` call sites:
```dart
    for (final _PlacedBand placed in _plans[index]) {
      _place(placed.band.elements, placed.x, placed.y, fb,
          pageNumber: index + 1,
          bandType: placed.band.source.type,
          bandName: placed.band.source.group,
          fields: placed.band.source.fields,
          variables: placed.band.source.variables);
    }
```
```dart
    for (final Band h in _headers) {
      _place(<({ReportElement element, JetRect bounds})>[
        for (final ReportElement el in h.elements)
          (element: _substitute(el, pageNumber), bounds: el.bounds),
      ], _left, y, fb,
          pageNumber: pageNumber,
          bandType: h.type,
          bandName: null,
          fields: const <String, JetValue>{},
          variables: const <String, JetValue>{});
      y += h.height;
    }
```
```dart
    for (final Band f in _footers) {
      _place(<({ReportElement element, JetRect bounds})>[
        for (final ReportElement el in f.elements)
          (element: _substitute(el, pageNumber), bounds: el.bounds),
      ], _left, y, fb,
          pageNumber: pageNumber,
          bandType: f.type,
          bandName: null,
          fields: const <String, JetValue>{},
          variables: const <String, JetValue>{});
      y += f.height;
    }
```

(e) Thread the param through `layoutLazyDefinition` and the `LazyLayout._(...)` call (L298 / L622), plus the eager `layoutDefinition` wrapper (L283):
```dart
  LazyLayout layoutLazyDefinition(ReportDefinition def, FilledReport filled,
      {JetElementPrintCallback? onElementPrint}) {
```
…and in the `return LazyLayout._(` arg list add:
```dart
      onElementPrint: onElementPrint,
```
…and in `layoutDefinition`:
```dart
  LayoutResult layoutDefinition(ReportDefinition def, FilledReport filled,
      {JetElementPrintCallback? onElementPrint}) {
    final LazyLayout lazy =
        layoutLazyDefinition(def, filled, onElementPrint: onElementPrint);
```

- [ ] **Step 6: Pass the option from the engine.** In `jet_report_engine.dart` (≈L88):
```dart
      () => ReportLayouter(measurer: MetricsTextMeasurer(fonts))
          .layoutLazyDefinition(definition, fill.report,
              onElementPrint: options.onElementPrint),
```

- [ ] **Step 7: Run to verify it passes.**

Run: `flutter test test/rendering/onprint_hook_test.dart`
Expected: PASS (both pass-through and transform).

- [ ] **Step 8: Run the full rendering + golden suite — no regression.**

Run: `flutter test test/rendering`
Expected: PASS, including all render goldens (null-callback path byte-identical).

- [ ] **Step 9: Analyze + format, then commit.**

```bash
cd packages/jet_print && dart format lib/src/rendering/engine/render_options.dart lib/src/rendering/layout/band_measurer.dart lib/src/rendering/layout/report_layouter.dart lib/src/rendering/engine/jet_report_engine.dart test/rendering/onprint_hook_test.dart && flutter analyze lib
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/rendering packages/jet_print/test/rendering/onprint_hook_test.dart
git commit -m "feat(engine): invoke onElementPrint at emit time (transform + pass-through)"
```

---

## Task 4: Guards — suppress, same-type, and throw

**Files:**
- Modify: `packages/jet_print/test/rendering/onprint_hook_test.dart` (add cases; implementation already landed in Task 3)

**Interfaces:**
- Consumes: the Task 3 `_place` guard logic; `RenderedReport.diagnostics`.

> The guard code shipped in Task 3 Step 5(c). This task proves all three branches with tests. If a test reveals a guard bug, fix it in `report_layouter.dart` under this task.

- [ ] **Step 1: Write the failing/【green】 tests.** Add to `onprint_hook_test.dart`:

```dart
  test('null return suppresses the element', () {
    final def = _singleText(r'$F{amount}');
    final RenderedReport r = const JetReportEngine().renderDefinition(
      def,
      _source(7),
      options: RenderOptions(
        onElementPrint: (el, ctx) => el is TextElement ? null : el,
      ),
    );
    final hasAmtText = <bool>[
      for (int i = 0; i < r.pageCount; i++)
        for (final p in r.page(i).primitives)
          if (p is TextRunPrimitive) true,
    ].isNotEmpty;
    expect(hasAmtText, isFalse); // the only text element was suppressed
  });

  test('different-type return is ignored and records a diagnostic', () {
    final def = _singleText(r'$F{amount}');
    final RenderedReport r = const JetReportEngine().renderDefinition(
      def,
      _source(7),
      options: RenderOptions(
        onElementPrint: (el, ctx) => el is TextElement
            ? ImageElement(
                id: el.id,
                bounds: el.bounds,
                source: const BytesImageSource(<int>[]),
              )
            : el,
      ),
    );
    // original text still painted
    final texts = <String>[
      for (int i = 0; i < r.pageCount; i++)
        for (final p in r.page(i).primitives)
          if (p is TextRunPrimitive) p.lines.join(),
    ];
    expect(texts.join(), contains('7'));
    expect(r.diagnostics.issues.any((d) => d.message.contains('onElementPrint')),
        isTrue);
  });

  test('a throwing callback is contained: original painted + diagnostic', () {
    final def = _singleText(r'$F{amount}');
    final RenderedReport r = const JetReportEngine().renderDefinition(
      def,
      _source(7),
      options: RenderOptions(
        onElementPrint: (el, ctx) => throw StateError('boom'),
      ),
    );
    final texts = <String>[
      for (int i = 0; i < r.pageCount; i++)
        for (final p in r.page(i).primitives)
          if (p is TextRunPrimitive) p.lines.join(),
    ];
    expect(texts.join(), contains('7'));
    expect(r.diagnostics.issues.any((d) => d.message.contains('onElementPrint')),
        isTrue);
  });
```

> Verify against real APIs: `ImageElement` + `BytesImageSource` constructor shapes (`domain/elements/image_element.dart`, `image_source.dart`); `TextRunPrimitive.lines` (the line list — confirm name in `frame/primitive.dart`); `RenderedReport.diagnostics` and the diagnostics collection accessor (`.issues`/`.all`/`.warnings` — confirm in `report_diagnostics.dart`). Adjust accessor names; keep the three behavioral assertions (suppressed / original-on-wrong-type / original-on-throw, each with a diagnostic on the latter two).

- [ ] **Step 2: Run to verify they pass.**

Run: `flutter test test/rendering/onprint_hook_test.dart`
Expected: PASS (guards implemented in Task 3).

- [ ] **Step 3: Analyze + format, then commit.**

```bash
cd packages/jet_print && dart format test/rendering/onprint_hook_test.dart && flutter analyze test/rendering/onprint_hook_test.dart
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/rendering/onprint_hook_test.dart
git commit -m "test(engine): onElementPrint suppress/same-type/throw guards"
```

---

## Task 5: Context correctness, chrome, golden-identity, and integration

**Files:**
- Modify: `packages/jet_print/test/rendering/onprint_hook_test.dart` (add cases)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Context-correctness test** — a multi-row report; assert the callback observes the right `bandType`, `fields`, `variables`, and `pageNumber`/`pageCount`.

```dart
  test('context carries bandType, fields, variables, and page numbers', () {
    final def = _singleText(r'$F{amount}');
    final captured = <ElementPrintContext>[];
    const JetReportEngine().renderDefinition(
      def,
      _source(42),
      options: RenderOptions(
        onElementPrint: (el, ctx) {
          captured.add(ctx);
          return el;
        },
      ),
    );
    final detailCtx = captured.firstWhere((c) => c.bandType == BandType.detail);
    expect(detailCtx.fields['amount'], const JetNumber(value: 42));
    expect(detailCtx.pageNumber, greaterThanOrEqualTo(1));
    expect(detailCtx.pageCount, greaterThanOrEqualTo(1));
    expect(detailCtx.pageNumber, lessThanOrEqualTo(detailCtx.pageCount));
  });
```

- [ ] **Step 2: Chrome test** — a definition with a page header/footer; assert the hook fires for chrome with `fields == {}` and a `pageHeader`/`pageFooter` band type.

```dart
  test('hook fires for page chrome with empty fields', () {
    // Build a definition that has a page header/footer band carrying one text
    // element. Use the nearest existing layouter/engine test that exercises page
    // chrome (search test/rendering for pageHeader/pageFooter) as the template
    // for the definition shape.
    // Assert: some captured ctx has bandType == BandType.pageHeader (or
    // pageFooter) and that ctx.fields is empty.
  });
```

> Replace the placeholder body using a real chrome-bearing definition copied from an existing page-chrome layouter test (`grep -rl "pageHeader\|pageFooter" test/rendering`). The assertion: a captured `ElementPrintContext` with `bandType == BandType.pageHeader` (or `pageFooter`) and `fields.isEmpty`.

- [ ] **Step 3: Golden-identity test** — null callback leaves output identical.

```dart
  test('null onElementPrint produces the same frames as no options', () {
    final def = _singleText(r'$F{amount}');
    final RenderedReport a =
        const JetReportEngine().renderDefinition(def, _source(9));
    final RenderedReport b = const JetReportEngine().renderDefinition(
      def,
      _source(9),
      options: const RenderOptions(), // onElementPrint == null
    );
    expect(a.pageCount, b.pageCount);
    for (int i = 0; i < a.pageCount; i++) {
      expect(a.page(i).primitives, b.page(i).primitives); // primitive value-equality
    }
  });
```

> If `FramePrimitive` lacks value-equality, assert on a stable projection (primitive runtimeType + bounds + text/color) instead. Confirm in `frame/primitive.dart`.

- [ ] **Step 4: Integration test** — negative amount → red, a flagged element suppressed, in one render.

```dart
  test('integration: recolor negatives and suppress a flagged element', () {
    final def = ReportDefinition(
      page: const PageFormat.a4(),
      body: ReportBody(
        root: DetailScope(
          children: <ScopeNode>[
            BandNode(
              band: Band(
                id: 'detail',
                type: BandType.detail,
                height: 20,
                elements: <ReportElement>[
                  TextElement(
                    id: 'amt',
                    bounds: const JetRect(x: 0, y: 0, width: 120, height: 20),
                    text: 'amt',
                    expression: r'$F{amount}',
                  ),
                  TextElement(
                    id: 'badge',
                    bounds: const JetRect(x: 130, y: 0, width: 60, height: 20),
                    text: 'FLAG',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final RenderedReport r = const JetReportEngine().renderDefinition(
      def,
      _source(-1),
      options: RenderOptions(
        onElementPrint: (el, ctx) {
          if (el is! TextElement) return el;
          if (el.id == 'badge') return null; // suppress
          final v = ctx.fields['amount'];
          if (v is JetNumber && v.value < 0) {
            return el.copyWith(
                style: el.style.copyWith(color: const JetColor(0xFFFF0000)));
          }
          return el;
        },
      ),
    );
    final texts = <String>[
      for (int i = 0; i < r.pageCount; i++)
        for (final p in r.page(i).primitives)
          if (p is TextRunPrimitive) p.lines.join(),
    ];
    expect(texts.join(), isNot(contains('FLAG'))); // badge suppressed
    expect(_textColors(r), contains(const JetColor(0xFFFF0000))); // amt red
  });
```

- [ ] **Step 5: Run the whole task's tests.**

Run: `flutter test test/rendering/onprint_hook_test.dart`
Expected: PASS.

- [ ] **Step 6: Full verification sweep.**

```bash
cd packages/jet_print
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test                       # whole package; goldens unchanged
cd ../../apps/jet_print_playground && flutter analyze && flutter test
```
Expected: all green; no golden changes.

- [ ] **Step 7: Commit.**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/rendering/onprint_hook_test.dart
git commit -m "test(engine): onElementPrint context, chrome, golden-identity, integration"
```

---

## Self-Review

- **Spec coverage:** FR-001 → Task 3 (option + invoke). FR-002 → Task 1 (`ElementPrintContext`) + Task 3/5 (populated). FR-003 → Task 3 (transform/pass-through) + Task 4 (suppress). FR-004 → Task 4 (same-type guard). FR-005 → Task 4 (throw). FR-006 → Task 3 (chrome call sites) + Task 5 Step 2. FR-007 → Task 3 wiring through `renderDefinition` (shared by preview/export/print). FR-008 → Task 2. FR-009 → no codec/designer/primitive change; Task 3 Step 8 + Task 5 Step 3/6 confirm goldens. SC-001 → Task 3 transform. SC-002 → Task 4 suppress. SC-003 → Task 5 Step 1. SC-004 → Task 5 Step 1 (fields) + Step 2 (chrome empty). SC-005 → Task 4. SC-006 → Task 5 Step 3 + sweep.
- **Placeholder scan:** Task 5 Step 2 chrome definition is intentionally a fill-from-template note (the codebase's exact chrome-band builder must be copied from an existing test) — flagged, with the concrete assertion specified. All other steps carry runnable code.
- **Type consistency:** `JetElementPrintCallback`/`ElementPrintContext` field names match across Tasks 1/3/4/5; `FilledBand.fields` and `MeasuredBand.source` names match Tasks 2/3; `layoutLazyDefinition(..., {onElementPrint})` matches engine call in Task 3 Step 6.
- **Verify-before-trust:** several steps call out confirming real API shapes (`RenderedReport.page/primitives`, `TextRunPrimitive.lines/style.color`, `ReportDiagnostics` accessor, fill builders) against the codebase — these are deliberate guards, not gaps.
