# Quickstart: Designer Edit Surface

**Feature**: `003-designer-edit-surface` | **Date**: 2026-06-08
**Audience**: developers running/validating the interactive designer · **Prereqs**: Flutter
≥ 3.6, the `jet_print` workspace resolved (`flutter pub get` at repo root).

This is the fastest path to *see and exercise* the interactive design surface, plus the commands
that gate a merge (Constitution III/VI).

---

## 1. Run the designer (playground app)

```bash
cd apps/jet_print_playground
flutter run -d macos          # desktop-first target (mouse + keyboard)
```

You should get the 002 shell — top bar, toolbox, surface, three-tab right panel — but now the
**surface is live**.

## 2. Drive the core loop (US1 → US3, the MVP)

1. **Place**: drag the **Text** entry from the toolbox onto the detail band → a text element
   appears at the drop point and is selected (handles show). Repeat for Shape / Image / Barcode.
2. **Select**: click an element → outline + 8 resize handles; click empty canvas → clears.
3. **Move**: drag the element → it follows the pointer; on release the model position updates and
   stays within the band/page.
4. **Resize**: drag a handle → live resize with a minimum-size floor; release commits size.
5. **Snap**: move one element near another's edge/center or a band boundary → it snaps and a guide
   line appears; hold **Alt/Option** to bypass snapping for that gesture.
6. **Undo/redo**: top bar undo (`⌘Z`) walks every edit back (model **and** selection); redo
   (`⇧⌘Z`) re-applies; a new edit after undo discards redo.
7. **Multi-edit**: marquee-drag to select several; arrow keys nudge (Shift = larger step);
   `⌘C`/`⌘V` copy/paste (offset); bring-forward/send-back changes draw order; align/distribute the
   group; `Delete` removes (undoable).
8. **Panels**: selecting on canvas highlights the **Outline** and fills **Properties** (x/y/w/h;
   text for a text element); selecting an Outline row selects on canvas and scrolls it into view;
   editing a Properties number updates the canvas and is undoable. Double-click a text element to
   edit its text inline.
9. **Zoom/pan**: zoom in/out (top bar or shortcuts), fit-to-page; a drop always lands at the
   pointer's page position at any zoom.

## 3. Open & save (US / FR-022)

- **Save** (top bar) → the playground app picks a path and writes the design as JSON via
  `JetReportFormat.encodeJson`.
- **Open** (top bar) → pick a `.json` design; the playground app loads it with
  `JetReportFormat.decodeJson` into the controller.
- **Verify lossless round-trip**: save a design, reopen it → it is identical (same elements,
  order, attributes). This is the human view of SC-002 (the machine view is the round-trip test).

## 4. Embed it yourself (consumer API)

```dart
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

final controller = JetReportDesignerController();   // blank default design

JetReportDesigner(
  controller: controller,
  onSaveRequested: (ReportTemplate t) => mySink.write(JetReportFormat.encodeJson(t)),
  onOpenRequested: () async {
    final json = await mySource.read();
    if (json != null) controller.open(JetReportFormat.decodeJson(json));
  },
);
```

You can also build a model in code and observe edits:

```dart
controller.addListener(() => print('elements: '
    '${controller.template.bands.expand((b) => b.elements).length}'));
controller.createElement(DesignerToolType.text, /* band */ ..., /* atPage */ ...);
controller.undo();
```

> The library performs **no filesystem I/O** — the consumer owns open/save (headless;
> research [D8](research.md#d8--persistence-seam-fr-022-keeping-the-library-headless)). The playground
> app adds a file-picker dependency to demonstrate it; the published package does not.

## 5. Tests & merge gates (run before claiming done)

```bash
# From repo root (workspace). Library is the product:
cd packages/jet_print

flutter gen-l10n                         # regenerate localizations after ARB edits
flutter analyze                          # MUST be zero warnings (Constitution VI)
dart format --output=none --set-exit-if-changed .   # formatting gate
flutter test                             # ALL tests green, no skips (Constitution III)

# Update goldens ONLY when a visual change is intended & reviewed (Constitution IV):
flutter test --update-goldens
```

What the suite proves (maps to Success Criteria):

| Check | Criterion |
|---|---|
| Controller editing + undo/redo unit tests | SC-003 (≤50 edits undo/redo exact) |
| `JetReportFormat` round-trip test | SC-002 (100% lossless) |
| Drop/placement zoom-accuracy test | SC-006 (lands at pointer, any zoom) |
| Cross-panel sync widget test | SC-005 (single-interaction reflect) |
| Snapping + guide widget test | SC-004 (snap within threshold, bypassable) |
| 200-element drag perf smoke | SC-007 (~60 fps / frame budget) |
| Localization en/de/tr + fallback | SC-008 (no blank/raw-key labels) |
| Design-surface goldens (light/dark) | Constitution IV (shared-render fidelity) |

## 6. Acceptance walkthrough (manual, mirrors spec scenarios)

Place a text element, move it, resize it, undo twice, redo twice → canvas + model return to each
intermediate state exactly (US1/US3). Marquee three elements, align-left, distribute, nudge with
arrows, duplicate, send-to-back → each acts on the whole selection and is undoable (US4). This is
the SC-009 first-run task.

---

**If `flutter run` shows the 002 static page** (empty A4 hint, no interaction), the interactive
canvas isn't wired yet — check that `DesignerSurface` hosts `DesignCanvas` and that the shell
provides the controller via the `InheritedNotifier`.
