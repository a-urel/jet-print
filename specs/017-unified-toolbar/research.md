# Phase 0 Research: Unified Context-Switching Toolbar

All NEEDS CLARIFICATION from Technical Context are resolved below. Each decision is grounded in the
existing codebase (file:line) and the spec's recorded clarifications.

---

## D1 — One shared toolbar shell, composed by both modes

**Decision**: Extract a private `unified_top_bar.dart` shell widget with three regions — **left**
(file icon + report name + inline-rename affordance), **center** (Designer|Preview switch), **right**
(an actions slot the caller fills). `DesignerTopBar` and the preview toolbar both *compose* it,
passing their mode-specific groups into the right slot.

**Rationale**: The two bars are already the same height (`DesignerTopBar` `_height = 52`,
`jet_report_preview.dart` `_toolbarHeight = 52`) and visually styled to match — but the left/center
markup is duplicated and free to drift. FR-001 and SC-003 demand the left + center regions be
*positionally identical* in both modes. The only structural guarantee of that is a **single widget**
rendering them; a shared shell makes divergence impossible rather than a thing tests must police.

**Alternatives considered**:
- *Keep two bars, add the switch to each independently* — rejected: duplicates the rename + name +
  switch markup twice, and SC-003 parity becomes a perpetual review burden instead of a structural fact.
- *One mega-toolbar widget that internally branches on mode and owns the canvas/preview swap* —
  rejected: that pulls mode ownership into the library, contradicting the clarification that the
  **host** owns mode, and couples the toolbar to both the canvas and the renderer.

---

## D2 — The mode switch reuses `onPreviewRequested` / `onBack` as switch-request events

**Decision**: The center switch emits a "switch requested" event by calling existing callbacks:
from the designer, selecting **Preview** calls `JetReportDesigner.onPreviewRequested`
([jet_report_designer.dart:97](../../packages/jet_print/lib/src/designer/jet_report_designer.dart#L97));
from preview, selecting **Designer** calls `JetReportPreview.onBack`
([jet_report_preview.dart:78](../../packages/jet_print/lib/src/designer/preview/jet_report_preview.dart#L78)).
No new mode/onModeChanged API is added. The active segment is the current mode (Designer in the
designer shell, Preview in the preview shell); the inactive segment is enabled only when its callback
is wired.

**Rationale**: The recorded clarification is explicit — *"Host owns it — the toolbar emits a 'switch
requested' event and the host performs the actual switch; the toolbar reflects the active mode it is
given."* The host already performs the swap: the playground pushes a preview route on
`onPreviewRequested` and pops on `onBack` (`apps/jet_print_playground/lib/main.dart`). Those two
callbacks already *are* the switch-request events the clarification describes; reusing them keeps the
public surface minimal (Constitution I) and means existing hosts get the switch for free.

**Alternatives considered**:
- *Add `WorkspaceMode mode` + `ValueChanged<WorkspaceMode> onModeChanged` to both widgets* —
  rejected: a parallel public API for a state the host already owns and already toggles via the two
  callbacks; more surface, no behavior gained.
- *Library owns mode and renders both designer + preview in one widget, toggling internally* —
  rejected: contradicts the clarification and couples the toolbar to the render/canvas layers (II).

---

## D3 — Rename is one undoable controller op built from one command

**Decision**: Add `void rename(String name)` to `JetReportDesignerController`, implemented as
`_commit(SetTemplateNameCommand(name))`. The new `SetTemplateNameCommand` applies
`before.template.copyWith(name: name)` via `DesignerDocument.withTemplate`. Rename is a single
undo/redo step and notifies listeners once, exactly like every other mutator.

**Rationale**: `ReportTemplate.name` already exists
([report_template.dart:25](../../packages/jet_print/lib/src/domain/report_template.dart#L25)) with a
`copyWith(name:)`, and `DesignerDocument.withTemplate`
([designer_document.dart:28](../../packages/jet_print/lib/src/designer/controller/designer_document.dart#L28))
already exists. The controller funnels **every** edit through `_commit`
([jet_report_designer_controller.dart:937](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L937)),
which pushes history and notifies. Following that path gives rename undo/redo and host-surfacing
(`controller.template.name`) for free and keeps it consistent with the codebase (the 016 plan used
the same command/`_commit` idiom). FR-008 ("update the template's name field … expose the change so
the host can persist it") is satisfied because `controller.template` is the value the host saves.

**Alternatives considered**:
- *Mutate `template.name` directly / a non-undoable setter* — rejected: the model is immutable and
  bypassing `_commit` would skip undo/redo and the notify, breaking FR-005/Principle III consistency.
- *A non-history "metadata" channel for the name* — rejected: renaming is a user edit users expect to
  undo; splitting it out adds a second mutation path for no benefit.

---

## D4 — Inline edit: Enter/blur commit, Escape cancel, empty → placeholder

**Decision**: Activating the edit affordance turns the name into a focused `ShadInput` pre-filled
with the current name. Commit rules:
- **Enter** → commit the typed value (including empty/whitespace, which is stored as `''`).
- **Blur** → commit **only when the trimmed value is non-empty**; an empty blur cancels (keeps prior).
- **Escape** → cancel, restore prior name.
The displayed name renders the localized placeholder whenever the stored name is empty/whitespace.

**Rationale**: Directly encodes the clarifications and acceptance scenarios. Clarification: *"Blur
confirms — clicking away commits the typed name (if non-empty); Escape still cancels."* Scenario
US2.6: *"confirms an empty or whitespace-only name → the report falls back to the placeholder state
rather than showing a blank name."* So an explicit empty Enter is allowed and resolves to the
placeholder via the existing display fallback, while an empty *blur* must not silently wipe the name.
The placeholder fallback already exists in both bars (designer reads `reportTitlePlaceholder`;
preview falls back to the localized "Preview" label at
[jet_report_preview.dart:221](../../packages/jet_print/lib/src/designer/preview/jet_report_preview.dart#L221)).

**Alternatives considered**:
- *Reject empty on Enter too (revert)* — rejected: contradicts US2.6, which explicitly defines the
  empty-confirm → placeholder outcome.
- *Commit on every keystroke* — rejected: no confirm/cancel semantics, breaks Escape (US2.3) and the
  blur-only-when-non-empty rule.

---

## D5 — Preview holds a local "displayed name" for immediate feedback

**Decision**: The preview shell seeds its displayed name from `RenderedReport.title` and keeps a
local override updated on rename commit, while always calling `onRename(newName)` so the host owns
persistence. Designer mode needs no override — it reads `controller.template.name` reactively.

**Rationale**: FR-008 requires the new name to *immediately* appear. In designer the controller
notify handles that. In preview the name source is `RenderedReport.title`
([rendered_report.dart:53](../../packages/jet_print/lib/src/rendering/engine/rendered_report.dart#L53)),
which is immutable and only changes when the host re-renders — a different cadence than "typed now".
A small local override bridges the two without forcing a re-render inside the library (keeping
Principle IV's render path untouched). `onRename` is the host-wired idiom the preview already uses for
`onExportPdf`/`onPrint` ([jet_report_preview.dart:86](../../packages/jet_print/lib/src/designer/preview/jet_report_preview.dart#L86)).

**Alternatives considered**:
- *Give preview the controller and read `template.name`* — rejected: enlarges `JetReportPreview`'s
  contract (it is a read-only viewer over a `RenderedReport`) and couples it to the designer
  controller; the callback is the lighter, consistent seam.
- *Require the host to re-render to see the new name* — rejected: violates FR-008's "immediately".

---

## D6 — Localization keys

**Decision**: Add to `jet_print_en.arb` / `_de.arb` / `_tr.arb`:
- `modeDesigner` — the **Designer** segment label.
- `modePreview` — the **Preview** segment label.
- `actionRenameTooltip` — tooltip / accessible name for the edit affordance.
- `renameFieldLabel` — accessible label for the inline edit field.
Each with an `@`-description, following the established convention
(`reportTitlePlaceholder`, `actionPreview`, `action*Tooltip`, `toggle*`) in the existing ARBs.

**Rationale**: FR-013 requires all new chrome to be localizable and consistent with the existing
multi-language support (en/de/tr, English-first fallback, verified by `public_api_test`). Reusing the
existing key style keeps the ARB coherent. Existing `actionPreview` ("Preview") can back the Preview
segment label, but a dedicated `modePreview`/`modeDesigner` pair reads more clearly as a paired
switch and avoids overloading the action label's meaning.

**Alternatives considered**:
- *Reuse `actionPreview` for the segment and hardcode "Designer"* — rejected: hardcoding breaks
  FR-013; an unpaired label is inconsistent.

---

## D7 — Zero render / serialization impact (confirming the no-ops)

**Decision**: No change to the render pipeline, `PageFrame`, `RenderedReport` shape, the codec, or
`kReportSchemaVersion` (stays **1**). The only model interaction is *editing* the already-serialized
`name`.

**Rationale**: This feature is toolbar chrome plus a name edit. `name` is already encoded in
`report_codec.dart` (always written), so a renamed template serializes losslessly with no migration
(Principle V). Preview keeps painting through the shared `paintFrame` → `FrameCustomPainter` pipeline
unchanged (Principle IV), so every existing report golden stays green by construction. The only new
goldens/widget assertions concern the *toolbar's* appearance (region parity, SC-003).

**Alternatives considered**: none — this is a verification decision, recorded so review can confirm
the no-ops rather than re-derive them.

---

## Resolved unknowns summary

| Unknown | Resolution |
|--------|------------|
| Who owns mode / how does the switch happen? | Host owns it; switch reuses `onPreviewRequested`/`onBack` (D2). |
| Where does the name live; how does rename propagate? | `ReportTemplate.name` (already serialized); new `controller.rename` + preview `onRename` (D3, D5). |
| Inline-edit commit/cancel semantics? | Enter/blur(non-empty) commit, Escape cancel, empty→placeholder (D4). |
| New dependencies? | None (D1 — existing shadcn_ui + flutter widgets). |
| Serialization / schema change? | None; `schemaVersion` stays 1 (D7). |
| New public API surface? | Two symbols: `controller.rename`, `JetReportPreview.onRename` (D2, D3, D5). |
