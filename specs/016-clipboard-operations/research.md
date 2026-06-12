# Phase 0 — Research: Clipboard Operations in the Designer UI

The spec is explicit that the **backend already exists**: the in-memory `Clipboard`, the
controller `copy()/cut()/paste()/duplicate()`, the `ClipboardCommand` (paste insert), fresh-id +
offset + band-clamp, and the keyboard shortcuts. The work is **two UI surfaces** (toolbar group +
canvas context menu) plus the minimum backend plumbing those surfaces need to be reactive. Each
decision below is grounded in the actual code (paths relative to repo root).

---

## D1 — Reactive Paste enablement: `copy()` must notify (the one backend gap)

**Decision**: Add `notifyListeners()` to
[`JetReportDesignerController.copy()`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L768).

**Why**: The toolbar and canvas rebuild because
[`DesignerScope`](../../packages/jet_print/lib/src/designer/designer_scope.dart#L11) is an
`InheritedNotifier<JetReportDesignerController>` — `DesignerScope.of(context)` registers a
dependency, so **every** `controller.notifyListeners()` rebuilds the top bar
([`designer_top_bar.dart:102`](../../packages/jet_print/lib/src/designer/layout/designer_top_bar.dart#L102))
and the canvas. `cut()`, `paste()`, and `duplicate()` already notify (they route through `_commit`,
which calls `notifyListeners`). But **`copy()` does not** — it only calls `_clipboard.set(...)`
(controller:768–771). So after a pure Copy, no notification fires, and a Paste control whose
`enabled` is bound to clipboard state would **not re-enable until the next unrelated rebuild**. A
Copy changes derived UI-enablement state (`canPaste` flips false→true), so it MUST notify — even
though it creates no *history* entry (FR-009: Copy is not undoable; notifying ≠ committing).

**Alternatives rejected**:
- *Make `Clipboard` a `ChangeNotifier` and listen to it separately* — more moving parts, a second
  notifier to wire into every surface, and `Clipboard` is a deliberately-dumb value holder
  ([`clipboard.dart`](../../packages/jet_print/lib/src/designer/controller/clipboard.dart)). The
  controller is already the single notifier the UI listens to; route through it.
- *Poll / rebuild on a timer* — never.

**Test-First (Red→Green)**: a controller unit test attaches a listener and asserts `copy()` fires
exactly one notification (and still creates no undo entry: `canUndo` unchanged). Today this fails.

---

## D2 — Public enablement getters: `canCopy` / `canPaste`

**Decision**: Add two getters to the controller, mirroring the existing
[`canUndo`/`canRedo`](../../packages/jet_print/lib/src/designer/controller/jet_report_designer_controller.dart#L77):

```dart
bool get canCopy  => _document.selection.ids.isNotEmpty; // Cut/Copy/Duplicate/Delete enablement
bool get canPaste => !_clipboard.isEmpty;                // Paste enablement
```

**Why**: `_clipboard` is **private** (controller:737) and `Clipboard.isEmpty` is the only state
read, so Paste enablement has no public path today — a getter is required, not optional. `canCopy`
derives from the already-public `selection`, but exposing it (a) keeps the toolbar and the context
menu reading the **same** predicate so they cannot diverge (FR-012), and (b) is the single
selection-based gate for Cut, Copy, Duplicate, and Delete (FR-004, FR-005a). Two getters is the
**minimal honest** surface and matches the `canUndo`/`canRedo` idiom reviewers already know.

**Public-API note (Constitution I)**: this adds two public symbols on an already-public class.
[`public_api_test.dart`](../../packages/jet_print/test/public_api_test.dart) must be updated to
record them — an expected, reviewed surface change, consistent with the existing `can*` getters.

**Alternatives rejected**: *Inline `controller.selection.ids.isNotEmpty` in each widget* — works for
Cut/Copy but still leaves Paste with no public clipboard predicate, and duplicates the rule across
two surfaces (divergence risk against FR-012). *Expose the `Clipboard` object* — leaks an internal
type into the public API for no benefit.

---

## D3 — Toolbar clipboard group: reuse `_IconButton`, place beside History

**Decision**: Add a fenced group — `_Divider()` + three
[`_IconButton`](../../packages/jet_print/lib/src/designer/layout/designer_top_bar.dart#L411)s (Cut,
Copy, Paste) — to `leftChildren` in
[`designer_top_bar.dart`](../../packages/jet_print/lib/src/designer/layout/designer_top_bar.dart#L120),
immediately **after** the History group (undo/redo) and before the Zoom group.

**Why**: `_IconButton` is the exact widget undo/redo use — it already wires tooltip + `Semantics`
label + ghost styling + `enabled` (null `onPressed` disables). Cut/Copy/Paste are structurally
identical to undo/redo (icon command, enabled-state-driven), so they reuse it verbatim:

```dart
_IconButton(
  buttonKey: const ValueKey<String>('jet_print.designer.action.cut'),
  icon: LucideIcons.scissors,
  tooltip: l10n.actionCutTooltip,        // includes the shortcut hint (FR-014)
  enabled: controller.canCopy,
  onPressed: controller.cut,
),
```

The `undo/redo | cut/copy/paste` adjacency is the conventional editing-command cluster and inherits
the bar's existing responsive/compact/scroll behavior for free (FR — "consistent with current
toolbar"). Icons: `LucideIcons.scissors` (Cut), `LucideIcons.copy` (Copy),
`LucideIcons.clipboard` (Paste) — all present in the Lucide set already in use.

**Alternatives rejected**: *Place clipboard next to Arrange* — less conventional; clipboard belongs
with undo/redo. *A new button widget* — `_IconButton` already covers the need.

---

## D4 — Canvas context menu: `ShadContextMenuRegion` (pointer-anchored) + `ShadContextMenuItem`

**Decision**: Surface the menu with **`ShadContextMenuRegion`** (ships in the pinned
`shadcn_ui ^0.54.0` —
`~/.pub-cache/hosted/pub.dev/shadcn_ui-0.54.0/lib/src/components/context_menu.dart`), wrapping the
canvas content. Its `items` are the same
[`ShadContextMenuItem`](../../packages/jet_print/lib/src/designer/layout/designer_top_bar.dart#L304)
widgets the Arrange menu already builds. Items, in order: **Cut, Copy, Paste, ──, Duplicate,
Delete** (FR-002).

**Why**: The canvas has **no** secondary-tap / context menu today (verified: no `onSecondaryTap`,
`MenuAnchor`, or `PopupMenuButton` anywhere under `designer/canvas` or `designer/interaction`), so
this is net-new. `ShadContextMenuRegion` is purpose-built for right-click-at-pointer positioning and
is **already a dependency** — no new package (Constitution: minimal deps). Reusing
`ShadContextMenuItem` keeps the menu visually and behaviorally consistent with Arrange (same
`leading` icon + `child` label pattern), and each item's `enabled` binds to the same
`canCopy`/`canPaste` predicates as the toolbar (FR-012).

**Alternatives rejected**: *Flutter `showMenu`/`MenuAnchor`* — would introduce Material-menu styling
foreign to the shadcn design system the package standardizes on. *Hand-rolled `Overlay`* —
re-implements positioning/dismissal that `ShadContextMenuRegion` already provides.

---

## D5 — Right-click selection semantics (FR-010): hit-test on `onSecondaryTapDown`, then open

**Decision**: Add an `onSecondaryTapDown` handler on the canvas gesture layer
([`design_canvas.dart:650`](../../packages/jet_print/lib/src/designer/canvas/design_canvas.dart#L650))
that, **before** the menu paints, resolves selection via the existing
[`hitTestElement`](../../packages/jet_print/lib/src/designer/canvas/hit_testing.dart#L23) helper:

1. Hit-test the tap's page point (`transform.screenToPage(...)`, already used by `_handleTapDown`).
2. **Hit an element NOT in the current selection** → select just that element (replace selection).
3. **Hit an element already in the selection** → keep the (possibly multi-) selection unchanged.
4. **Hit empty canvas space** → keep the current selection unchanged (clarified 2026-06-12:
   secondary-click never deselects).

**Why**: FR-010 demands *select-then-menu* ordering, so the selection mutation must happen on the
secondary **down** event — which fires before the region's menu opens — and the resulting
`notifyListeners()` rebuilds the menu's enabled states (`canCopy`) against the just-updated
selection. `hitTestElement` already encodes z-order and hit-slop (the same logic primary tap uses),
so the right-click selects exactly what a left-click would, keeping the two paths consistent.

**Alternatives rejected**: *Let `ShadContextMenuRegion` open without touching selection* — fails
FR-010 (right-clicking an unselected element wouldn't act on it) and FR-001/FR-005a (menu would act
on a stale selection). *Re-implement hit-testing* — `hitTestElement` is the single source of truth.

---

## D6 — Shortcut hints on labels (FR-014, FR-014a)

**Decision**: Compose the platform-appropriate modifier glyph in code, not in the ARB strings.
Detect Apple platforms via `defaultTargetPlatform` (→ `⌘`) vs others (→ `Ctrl+`), and render:

- **Toolbar tooltips (FR-014)**: `"$label ($shortcut)"`, e.g. `"Cut (⌘X)"` / `"Cut (Ctrl+X)"`.
- **Context-menu items (FR-014a)**: the localized label as `child`, the shortcut as a muted
  `trailing` (Cut ⌘X/Ctrl+X, Copy ⌘C, Paste ⌘V, Duplicate ⌘D, Delete — Delete has no modifier).

**Why**: The action letters (X/C/V/D) are **not** translated, and the ⌘-vs-Ctrl choice is a runtime
platform fact, not a locale fact — so keeping the glyph out of the ARB avoids 3× duplicated
near-identical strings and a platform combinatorial explosion. The localized **label** ("Cut") still
comes from the ARB (FR-013). This mirrors how the codebase already separates localized text from
structural composition.

**Alternatives rejected**: *Bake `⌘X` into each ARB value* — duplicates the modifier across locales
and can't vary by platform at runtime.

---

## D7 — Localization keys (FR-013)

**Decision**: Add to all three ARB files
([`jet_print_en.arb`](../../packages/jet_print/lib/src/designer/l10n/jet_print_en.arb),
`_de.arb`, `_tr.arb`) the label keys used by **both** surfaces:

| Key | en | Used by |
|-----|----|---------| 
| `actionCutTooltip` | "Cut" | toolbar tooltip + menu label |
| `actionCopyTooltip` | "Copy" | toolbar tooltip + menu label |
| `actionPasteTooltip` | "Paste" | toolbar tooltip + menu label |
| `menuDuplicate` | "Duplicate" | context-menu item |
| `menuDelete` | "Delete" | context-menu item |

Each English entry carries the `@key` `description` metadata block the file already uses. The
shortcut glyph is appended in code (D6), so one label key serves both the toolbar tooltip and the
menu label.

**Why**: jet-print uses Flutter `gen-l10n` with `en`/`de`/`tr` ARBs
([`l10n.yaml`](../../packages/jet_print/l10n.yaml)); a key absent from a locale fails generation, so
all three must be filled (FR-013, SC-004). Reusing one label key per action across both surfaces
keeps them identical (FR-012) and minimizes new strings.

---

## D8 — No model / render / serialization impact (FR-016, SC-006; Constitution IV & V)

**Decision**: Touch only the **designer** layer (controller getters + `copy()` notify, top-bar
widgets, canvas gesture + menu, l10n). Do **not** touch the domain model, the codec/`schemaVersion`,
or the shared render pipeline (`FrameCustomPainter`, preview, export).

**Why**: Every clipboard *operation* (`ClipboardCommand`, fresh-id, offset, band-clamp) already
exists and is unchanged; this feature only adds *invocation points*. Because nothing routes through
serialization or rendering, saved files and preview/export/print output are **byte-for-byte
unchanged** and all existing goldens stay green by construction — satisfying WYSIWYG (IV) and
backward-compatible serialization (V) trivially.

---

## Open questions

None. All spec `[NEEDS CLARIFICATION]` items were resolved in the 2026-06-12 clarification session
(empty-canvas selection preservation; shortcut hints on menu items). The two-surface scope, the
reuse targets (`_IconButton`, `ShadContextMenuRegion`, `ShadContextMenuItem`, `hitTestElement`), and
the single backend change (`copy()` notify + two getters) are all confirmed against the code.
