# Quickstart: Editable Paper Type & Margins

End-to-end walk proving the feature, for a reviewer or the playground. Run the designer
(`apps/jet_print_playground`) and open a report; the Properties panel's **PAGE** section is now editable and
shows an **Office-style page sample**.

## The round-trip

1. **See the current paper named.** Open Properties with nothing selected. PAGE shows **A4** (not `595 × 842`),
   **Portrait**, margin preset **Normal**, and a small page-sample thumbnail with margin guides.
2. **Change the paper type.** Open the paper picker → choose **Letter**. The canvas page resizes to 612 × 792
   immediately; the sample thumbnail re-proportions; existing elements keep their top-left positions.
3. **Rotate it.** Toggle **Landscape**. Width/height swap (792 × 612); the thumbnail flips to landscape.
4. **Apply a margin preset.** Choose **Narrow** — all four side fields become `14`; the content guides in the
   thumbnail move outward. The margin label reads **Narrow**.
5. **Tweak one side.** Set **Left** to `50`. Only Left changes; the preset label flips to **Custom**; the
   thumbnail’s left guide shifts.
6. **Go Custom.** Set paper type to **Custom**; the Width/Height fields appear. Enter `300 × 500`; the page
   adopts it exactly. Enter `0` for height → it clamps to the minimum (no unusable page).
7. **Confirm WYSIWYG.** Switch to **Preview** and **Export** — both show the same page size and content area as
   the canvas (SC-003).
8. **Undo everything.** Press Undo repeatedly: each step reverts one change (margin side, margins, orientation,
   paper type) back to A4 portrait. Redo re-applies them.
9. **Persist.** Set Letter + landscape + Narrow, Save, reopen — the page comes back exactly. Open a report
   saved **before** this feature — it loads unchanged.

## Host wiring

**None.** The designer already owns the controller via `DesignerScope`; the rebuilt PAGE section calls
`controller.setPageFormat(...)` internally. No new constructor params, callbacks, or exports for the host —
the only new public symbols are `setPageFormat`, `PageFormat.copyWith`, and `JetEdgeInsets.copyWith`.

## How a control commits (pattern)

Each PAGE control composes the next `PageFormat` from the live one and hands it to the controller, which
clamps and commits as one undo step:

```dart
final page = controller.template.page;

// paper preset (preserve current margins, honor current orientation)
controller.setPageFormat(applyPaper(letter, landscape: isLandscape(page))
    .copyWith(margins: page.margins));

// orientation toggle
controller.setPageFormat(page.copyWith(width: page.height, height: page.width));

// margin preset
controller.setPageFormat(page.copyWith(margins: JetEdgeInsets.all(narrow.value)));

// one side
controller.setPageFormat(page.copyWith(margins: page.margins.copyWith(left: 50)));

// custom dimension
controller.setPageFormat(page.copyWith(width: 300, height: 500));
```

## Verify (from repo root)

```bash
flutter test packages/jet_print            # unit + widget + golden
flutter analyze packages/jet_print         # zero warnings
dart format --output=none --set-exit-if-changed packages/jet_print
# regenerate goldens only after a deliberate, reviewed visual change:
# flutter test packages/jet_print --update-goldens
```
