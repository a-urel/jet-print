# Phase 1 Data Model: Designer Edit Surface

**Feature**: `003-designer-edit-surface` | **Date**: 2026-06-08
**Input**: [spec.md](spec.md) · [research.md](research.md) · [plan.md](plan.md)

This feature adds an **editing state layer** in the designer seam over the **existing immutable
domain model**. It introduces almost no new *persisted* data — the on-disk artifact stays the
`ReportTemplate` JSON of Constitution V. What is new is the **in-memory edit state** (selection,
history, clipboard, interaction) and a handful of **additive domain helpers** for producing
modified copies.

Legend: **(existing)** = already in the codebase, reused; **(new)** = introduced here;
**(domain+)** = small additive change to an existing domain type.

---

## 1. Edited artifact (existing domain — the source of truth)

These are reused unchanged as the model the surface mutates and serializes (FR-003, FR-025). They
are immutable, value-equal, and JSON-round-tripping.

| Entity | Source | Role in this feature |
|---|---|---|
| `ReportTemplate` | `domain/report_template.dart` | The design being edited; `name`, `page`, `bands` (+ parameters/variables/groups carried through losslessly). |
| `PageFormat` | `domain/page_format.dart` | Page size + margins; the placement bounds and design-canvas page (read-only structure, FR-021). |
| `ReportBand` / `BandType` | `domain/report_band.dart` | Placement containers shown as context; elements live in `band.elements`; list order = z-order. |
| `ReportElement` (abstract) | `domain/report_element.dart` | Base: `id`, `bounds` (`JetRect`), `typeKey`. |
| `TextElement`, `ShapeElement`/`ShapeKind`, `ImageElement`/`JetBoxFit`/`JetImageSource`, `BarcodeElement`/`BarcodeSymbology`, `UnknownElement` | `domain/elements/*` | The four creatable types (FR-002) + lossless passthrough of unknown types. |
| `JetRect`, `JetSize`, `JetOffset`, `JetEdgeInsets` | `domain/geometry.dart` | Geometry of bounds, deltas, page margins. |
| `JetTextStyle`, `JetBoxStyle`, `JetColor` | `domain/styles/*` | Default appearance for created elements. |

### 1a. Additive domain helpers **(domain+)** — required by editing, test-first

Editing an immutable model means producing modified copies. These additions are minimal,
non-breaking, and unit-tested (Constitution III):

- `ReportElement.withBounds(JetRect bounds) → ReportElement` *(abstract; each subtype implements)*
  — the polymorphic move/resize primitive. Returns a copy of the same concrete type with new
  `bounds`, all other fields preserved.
- `TextElement.copyWith({String? text, JetTextStyle? style, JetRect? bounds}) → TextElement`
  — supports inline text editing (FR-019).
- `ReportBand.copyWith({BandType? type, double? height, List<ReportElement>? elements, String? group}) → ReportBand`
  — replace a band's element list when an edit touches one band.
- `ReportTemplate.copyWith({String? name, PageFormat? page, List<ReportBand>? bands, ...}) → ReportTemplate`
  — replace the bands list / rename, preserving parameters/variables/groups.

**Invariants preserved by every helper**: value equality holds (a copy with identical fields
`==` the original); unedited fields are referentially preserved (FR-025 non-destructiveness);
`UnknownElement` is never rewritten — it round-trips byte-for-byte (`element_codec.dart`).

---

## 2. Serialization facade **(new public)** — the file-format contract

| Entity | Definition | Role |
|---|---|---|
| `JetReportFormat` | `domain/serialization/report_format.dart` **(new)** | Public facade over `encodeTemplate`/`decodeTemplate` (`report_codec.dart`) with built-in element codecs + migrations pre-wired. |

**API shape**:
- `Map<String,Object?> encode(ReportTemplate)` — stamps `schemaVersion = kReportSchemaVersion`.
- `ReportTemplate decode(Map<String,Object?>)` — validates version, runs migrations, decodes
  (unknown element types → `UnknownElement`, unknown band fields preserved).
- `String encodeJson(ReportTemplate)` / `ReportTemplate decodeJson(String)` — UTF-8 JSON text.

**Validation rules** (inherited from `report_codec.dart`): missing/non-int `schemaVersion` →
`ReportFormatException`; version newer than build → `ReportFormatException`; older version →
forward migration; malformed band/element → typed `ReportFormatException`.

**Round-trip invariant (FR-003 / SC-002)**: `decode(encode(t)) == t` for every reachable template,
including unknown element types and the full parameter/variable/group payload.

---

## 3. Editing state **(new, designer seam)** — the in-memory edit layer

### 3.1 `JetReportDesignerController` *(new, public — `ChangeNotifier`)*

The single state seam shared by the canvas and the panels (FR-018). Holds:

| Field | Type | Notes |
|---|---|---|
| `template` | `ReportTemplate` (existing) | Current document model; the value to save (FR-022). |
| `selection` | `Selection` (new) | Current selected element ids. |
| `canUndo` / `canRedo` | `bool` | Drive top bar enablement (FR-017, US3.4). |
| `gridEnabled` / `snapEnabled` | `bool` | Top-bar toggles (FR-011, US2.4); consulted by snapping; default on (view state, not in history). |
| *(internal)* `EditHistory` | new | Undo/redo snapshot stacks. |
| *(internal)* `Clipboard` | new | Cut/copied elements for paste. |
| *(internal)* `_seq` | `int` | Monotonic id counter (FR-004). |
| *(internal)* `_interaction` | `Interaction?` | Live drag/resize coalescing state (D3/D5). |

**Behavioral methods** (each emits one history entry unless noted): `open(ReportTemplate)` (resets
history, seeds `_seq`), `select`/`addToSelection`/`toggle`/`selectAll`/`clearSelection` (no
history — selection-only, but undo restores selection too), `createElement(type, bandId, atPage)`,
`moveBy`/`resizeTo` (committed forms), `beginInteraction`/`updateInteraction`/`commitInteraction`/
`cancelInteraction` (one entry per committed gesture), `delete`, `cut`/`copy`/`paste`/`duplicate`,
`bringForward`/`sendBackward`/`bringToFront`/`sendToBack`, `align(...)`/`distribute(...)`,
`setGeometry(...)`, `setText(...)`, `nudge(dx,dy)`, `undo()`, `redo()`.

**Invariants**: `template` is always a valid, serializable model; element `id`s are unique;
selection only references existing ids; every mutating method leaves `canUndo == true`.

### 3.2 `DesignerDocument` *(new, private)*

Immutable snapshot = the unit of history. `{ ReportTemplate template; Selection selection }`.
Value-equal. Because both members are immutable, a snapshot is O(1) to capture and exact to
restore (FR-017).

### 3.3 `Selection` *(new)*

Immutable set of selected element `id`s (order-stable for predictable align/distribute anchors).
Helpers: `isEmpty`, `contains(id)`, `single` (the lone element, for Properties), `with(id)`,
`without(id)`, `toggled(id)`. Resolved against `template` to yield elements/bounds on demand.

### 3.4 `EditCommand` *(new, private)* + concrete commands

`abstract EditCommand { String get label; DesignerDocument apply(DesignerDocument before); }`.
One concrete command per editing FR:

| Command | FR | Effect |
|---|---|---|
| `CreateElementCommand` | FR-001/002/004 | Insert a typed element (default size + attrs, fresh id) into a band at a page point; selects it. |
| `MoveCommand` / `ResizeCommand` | FR-008/009/010 | New bounds (via `withBounds`), clamped to band+page; multi-element for Move. |
| `SetGeometryCommand` | FR-019 | Set x/y/w/h numerically from Properties. |
| `SetTextCommand` | FR-019 | Set a text element's `text` (inline / Properties). |
| `DeleteCommand` | FR-014 | Remove selected elements from their bands. |
| `ReorderCommand` | FR-013 | Move element(s) within `band.elements` (forward/back/to-front/to-back). |
| `ClipboardCommand` (paste/duplicate) | FR-015 | Insert offset copies with fresh ids; select them. |
| `AlignCommand` / `DistributeCommand` | FR-012 | Reposition a multi-selection. |
| `NudgeCommand` | FR-016 | Move selection by the nudge step. |

Every command returns a *new* `DesignerDocument`; none mutates in place. Each is independently
unit-testable against a fixture template.

### 3.5 `EditHistory` *(new, private)*

Two `List<DesignerDocument>` stacks (undo, redo), unbounded within a session (FR-017). `push(prev)`
on each edit clears redo; `undo()`/`redo()` move the current document across stacks. Tracks a
`revision` int (bumped per change) used by the canvas's `shouldRepaint` (D5).

### 3.6 `Clipboard` *(new, private)*

In-memory `List<ReportElement>` from the last cut/copy (FR-015). Paste deep-copies with fresh ids
and the paste offset (D7). Session-scoped; not persisted; not the OS clipboard.

### 3.7 `Interaction` *(new, private)* — live gesture state (no history until commit)

Captured on `beginInteraction`: the gesture kind (`move` | `resize` | `marquee` | `create-drag`),
the affected element ids, the start page point, and (for resize) the active handle. Live deltas
update a transient preview the overlay paints (D5); `commit` folds the delta into one command,
`cancel` discards it.

---

## 4. Canvas/view value types **(new, private — presentation, not persisted)**

| Type | Role |
|---|---|
| `DesignerToolType` (enum: `text`, `shape`, `image`, `barcode`) | Toolbox→canvas drag payload; maps to a default element factory (FR-001/002). |
| `CanvasViewTransform` | `{ double scale; JetOffset pan }` + `pageToScreen`/`screenToPage`; zoom/pan + pointer-accurate mapping (FR-020 / SC-006). |
| `DesignTimeLayout` | Computed map: element `id` → absolute page `JetRect` + owning band; band → page rect. Feeds hit-testing (D4) and the design-time frame (D1). |
| `Handle` (enum: 8 positions) + `HandleHit` | Resize-handle geometry with hit-area ≥ visual (FR-009, tiny-element edge case). |
| `SnapResult` | `{ JetOffset adjusted; List<SnapGuide> guides }` from grid/sibling/band/page snapping (FR-011 / SC-004). |
| `SnapGuide` | A transient guide line (orientation + position) drawn during manipulation (FR-023). |
| `DropTarget` | The band a pending drop will land in, or "nearest valid" / rejected (FR-023, drop edge case). |

These are ephemeral UI state — never serialized, never in history (except as derived from the
committed model + transient interaction).

---

## 5. State transitions (selection & history)

```
            create / move / resize / delete / reorder / paste / setText / setGeometry / align / nudge
  (model) ───────────────────────────────────────────────────────────────────────► (model')
      │                         push prior DesignerDocument to undo; clear redo
      │
  undo │ pop undo → current ; push current → redo            redo │ pop redo → current ; push current → undo
      ▼                                                            ▼
  (restores BOTH template and selection — FR-017)        (re-applies in order — US3.2)

  new edit after undo  ⇒  redo stack discarded (US3.3)
  history at end + undo/redo ⇒ no-op; canUndo/canRedo = false (US3.4)
```

Selection-only actions (click, marquee, shift-click, select-all, Esc) do **not** push history, but
because every history `DesignerDocument` *includes* the selection, undoing a model edit restores
the selection that existed before it (coherent-selection guarantee, FR-017 + edge case
"Undo and selection").

---

## 6. Relationships

```
JetReportDesignerController (ChangeNotifier, public)
 ├─ template : ReportTemplate ──────────► bands : ReportBand[] ──► elements : ReportElement[]
 ├─ selection : Selection ──────────────► (ids referencing elements)
 ├─ history : EditHistory ──────────────► DesignerDocument[]  (each = {template, selection})
 ├─ clipboard : Clipboard ──────────────► ReportElement[]
 └─ commands : EditCommand* ────────────► produce next DesignerDocument

DesignCanvas (widget)
 ├─ reads controller.template ──► DesignTimeLayout ──► design-time PageFrame (reuses ElementRenderer.emit + CanvasPainter)
 ├─ reads controller.selection ─► handles / overlay
 └─ CanvasViewTransform ────────► page ↔ screen (hit-test, placement, zoom/pan)

Outline / Properties panels  ──(InheritedNotifier)──►  same controller  (FR-018 two-way sync)

JetReportFormat  ◄──save/open──  controller.template   (consumer drives file I/O — D8)
```

---

## 7. Validation & constraints (from requirements)

- **Identity** (FR-004): every element `id` unique within the template; controller-assigned,
  collision-free across open/paste/duplicate.
- **Containment** (FR-010): committed bounds ⊆ owning band ∩ page content area; no off-page state.
- **Min size** (FR-009): resize clamps to ≥ 4×4 pt (lines excepted on one axis).
- **Lossless round-trip** (FR-003 / SC-002): `JetReportFormat.decode(encode(t)) == t`, incl.
  unknown elements + parameters/variables/groups, with no reordering.
- **Non-destructiveness** (FR-025): an edit to element A leaves every other element, the band
  structure, and report settings referentially unchanged.
- **History fidelity** (FR-017 / SC-003): any sequence of ≤50 edits fully undoes to origin and
  redoes to final, model + selection matching at each step.
- **Pointer accuracy** (FR-020 / SC-006): drop/placement lands within tolerance of the pointer's
  page position at every zoom level.
