# Public API Contract: Designer Edit Surface

**Feature**: `003-designer-edit-surface` | **Date**: 2026-06-08

This feature extends the library's single public entry point:

```dart
import 'package:jet_print/jet_print.dart';
```

Importing any `package:jet_print/src/...` path remains a contract violation, guarded by the
existing encapsulation test (`test/encapsulation_test.dart`).

It **supersedes the 002 non-goal** "No domain/report-model types … No rendering/serialization
API." Hosting, mutating, and round-tripping a design (FR-003, FR-022) is impossible without a
public model + format, so this iteration exposes them (research [D2](../research.md#d2--public-api-expansion-model--serialization-constitution-i--v)).
The 002 surface (`JetReportDesigner`, `JetPrintLocalizations`, `JetPrintPlaceholder`,
`jetPrintVersion`) is **preserved**; `JetReportDesigner` gains **optional** parameters only, so
existing const-construction (`const JetReportDesigner()`) keeps compiling.

---

## 1. New / changed exported symbols

| Symbol | Kind | Purpose | Stability |
|---|---|---|---|
| `JetReportDesigner` *(changed)* | `StatefulWidget` | Now interactive; gains optional `controller`, `initialReport`, `onSaveRequested`, `onOpenRequested`. Still const-constructible with no args. | Experimental (0.x) |
| `JetReportDesignerController` | `class extends ChangeNotifier` | The edit-state seam: holds `template`, `selection`, undo/redo, clipboard; exposes all editing operations. | Experimental (0.x) |
| `JetReportFormat` | `class` (static facade) | Encode/decode a `ReportTemplate` to/from the versioned JSON file format. | Experimental (0.x) |
| `ReportTemplate`, `ReportBand`, `BandType`, `PageFormat` | model | The report definition being edited + serialized. | Experimental (0.x) |
| `ReportElement`, `TextElement`, `ShapeElement`, `ShapeKind`, `ImageElement`, `JetBoxFit`, `JetImageSource` (+ concrete sources), `BarcodeElement`, `BarcodeSymbology`, `UnknownElement` | model | The element hierarchy (four creatable types + lossless unknown passthrough). | Experimental (0.x) |
| `JetRect`, `JetSize`, `JetOffset`, `JetEdgeInsets` | model | Geometry value types. | Experimental (0.x) |
| `JetTextStyle`, `JetBoxStyle`, `JetColor` (+ enums they expose) | model | Element appearance value types. | Experimental (0.x) |
| `ReportParameter`, `ReportVariable`, `ReportGroup` | model | Carried by a template; exported so a loaded design round-trips losslessly (not edited this spec). | Experimental (0.x) |

> Exact identifiers are the contract *intent*; Phase 2 may refine names, but the **shape** is
> fixed: one interactive designer widget + one controller + one serialization facade + the
> `ReportTemplate`-reachable model graph. Internal canvas/command/layout/render types stay private.

---

## 2. `JetReportDesigner` contract (changed)

- MUST remain const-constructible with **no required parameters** (`const JetReportDesigner()`),
  preserving the 002 public-API + golden tests. With no `controller`/`initialReport` it creates an
  internal controller over a **default blank template** (a sensible default band structure, per the
  spec assumption), so the widget is still drop-in.
- MUST accept an optional `controller` (`JetReportDesignerController`) so a consumer can own the
  model, observe changes, and drive save/open. When both `controller` and `initialReport` are
  given, `controller` wins (and `initialReport` is ignored).
- MUST accept optional `onSaveRequested(ReportTemplate current)` and
  `onOpenRequested()` hooks wired to the top bar Save/Open actions (FR-022); the library performs
  **no filesystem I/O** itself (research [D8](../research.md#d8--persistence-seam-fr-022-keeping-the-library-headless)).
- MUST make the center surface an interactive WYSIWYG canvas: create-by-drop, select, move,
  resize, marquee, multi-select, snapping + guides, z-order, clipboard, keyboard, undo/redo,
  zoom/pan, inline text edit (FR-001–FR-020).
- MUST keep cross-panel selection sync: canvas ↔ Outline ↔ Properties via the controller
  (FR-018); the Data Source panel is unchanged (Out of Scope).
- MUST render element appearance through the **shared** rendering pipeline (Constitution IV) — no
  divergent per-element drawing (research [D1](../research.md#d1--design-time-rendering-reuse-constitution-iv-gate)).
- MUST keep all chrome localized (en/de/tr, English fallback) and theme-driven, continuing 002
  (FR-024). New affordances expose accessible names/roles and are keyboard-operable (FR-024 / SC-008).
- MUST carry dartdoc covering the new parameters and that property editing is geometry + text only
  this iteration (Principle VI).

## 3. `JetReportDesignerController` contract

- MUST be a `ChangeNotifier`; notifying on every change to `template`, `selection`, or undo/redo
  availability, so panels and the top bar rebuild reactively (FR-018, FR-017).
- MUST expose, at minimum: `ReportTemplate get template`; `Selection get selection`;
  `bool get canUndo` / `bool get canRedo`; `void open(ReportTemplate)`; and editing operations
  covering every state-changing FR (create, move, resize, setGeometry, setText, delete, reorder,
  cut/copy/paste/duplicate, align, distribute, nudge), each undoable/redoable (FR-017).
- MUST assign every created/pasted/duplicated element an `id` unique within the template (FR-004),
  collision-free across `open` (FR-004).
- MUST constrain committed geometry to the owning band + page content area (FR-010) and enforce the
  minimum element size on resize (FR-009).
- MUST coalesce a live drag/resize gesture into a **single** history entry committed on release
  (FR-017, US1.3/US2.1), via begin/update/commit/cancel interaction methods.
- MUST restore **both** model and selection on undo/redo (FR-017).
- MUST NOT perform filesystem or platform I/O (headless; Constitution Technology Standards).

## 4. `JetReportFormat` contract

- MUST encode any `ReportTemplate` to a JSON-safe `Map` stamped with `schemaVersion`, and decode it
  back, with built-in element codecs and schema migrations pre-wired (no registry setup by the
  consumer).
- MUST round-trip losslessly: `decode(encode(t)) == t` for every template — including unknown
  element types (preserved via `UnknownElement`) and the full parameter/variable/group payload —
  with no attribute loss or reordering (FR-003 / SC-002).
- MUST provide JSON-string conveniences (`encodeJson` / `decodeJson`).
- MUST throw a typed `ReportFormatException` on a missing/invalid `schemaVersion`, a version newer
  than the build, or malformed structure (existing codec behavior), so consumers can report load
  errors. *(Whether `ReportFormatException` itself is exported is a Phase-2 refinement; the throw
  behavior is contracted.)*

---

## 5. Consumer usage (the playground app, and any external consumer)

```dart
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

final controller = JetReportDesignerController(); // blank default design

ShadApp(
  localizationsDelegates: JetPrintLocalizations.localizationsDelegates,
  supportedLocales: JetPrintLocalizations.supportedLocales,
  home: JetReportDesigner(
    controller: controller,
    onSaveRequested: (ReportTemplate current) async {
      final String json = JetReportFormat.encodeJson(current);
      await myFilePicker.writeText(json);          // consumer owns file I/O
    },
    onOpenRequested: () async {
      final String? json = await myFilePicker.readText();
      if (json != null) controller.open(JetReportFormat.decodeJson(json));
    },
  ),
);
```

---

## 6. Non-goals (explicitly NOT in the public surface this iteration)

- No rendering/layout/paint, expression-engine, fill, or data-source types (stay private).
- No per-type property editors beyond geometry + text (Out of Scope; full suite deferred).
- No data-field binding API, band/section structure editing, expression editor, or rendered/export
  preview (deferred to later specs / engine 009).
- No filesystem API inside the library; no recent-files / new-blank / templates gallery.

---

## 7. Contract tests (Phase 1 → enforced test-first in Phase 2, Constitution III)

These assert the contract and MUST be written before implementation:

1. **Public-API import test** *(extends existing)* — importing only the entry point, reference
   `JetReportDesignerController`, `JetReportFormat`, `ReportTemplate`, the four element types, and
   geometry/style types; prove the surface is sufficient to build, mutate, and serialize a design.
2. **Encapsulation test** *(existing)* — no consumer file imports `package:jet_print/src/`.
3. **Backward-compat construction** — `const JetReportDesigner()` still constructs (002 contract).
4. **`JetReportFormat` round-trip** — `decode(encode(t)) == t` across a fixture incl. unknown
   element + parameters/variables/groups (FR-003 / SC-002).
5. **Controller editing + undo/redo** — each operation mutates `template` as specified and is
   fully undoable/redoable with selection restored (FR-017 / SC-003); ids stay unique (FR-004);
   geometry is constrained (FR-009/FR-010).
6. **Designer interaction widget tests** — drop-create, click-select + handles, drag-move,
   handle-resize, marquee multi-select, snapping + guide, z-order, delete, copy/paste/duplicate,
   keyboard nudge (canvas-focus-only), inline text edit; each reflected on canvas + undoable
   (FR-001–FR-019).
7. **Cross-panel sync widget test** — canvas↔Outline↔Properties selection + Properties geometry
   edit reflects on canvas and is undoable (FR-018/FR-019 / SC-005).
8. **Zoom-accuracy test** — a drop lands at the pointer's page position across zoom levels
   (FR-020 / SC-006).
9. **Localization tests** *(extend existing)* — new affordance strings render en/de/tr with
   English fallback (FR-024 / SC-008).
10. **Goldens** — design surface with representative elements selected, in light/dark, reusing the
    shared rendering pipeline (Constitution IV; extends the WYSIWYG golden harness).
11. **Performance smoke** — a 200-element design drives a 20-element drag within the frame budget
    with no exceptions (SC-007).
