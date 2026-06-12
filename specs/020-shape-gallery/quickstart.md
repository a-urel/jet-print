# Quickstart: Shape Gallery in Properties Pane

An end-to-end walk a reviewer (or the playground) can follow to confirm the feature. Assumes the
designer is open in `apps/jet_print_playground`.

## 1. Pick a form from the gallery (P1)

1. Drag a **Shape** from the toolbox onto a band. It starts as a rectangle (unchanged default).
2. With the shape selected, open the **Properties** tab. A new **Shape** section shows eight
   thumbnails: line, rectangle, ellipse, triangle, diamond, pentagon, hexagon, star. The **rectangle**
   thumbnail is highlighted.
3. Click the **hexagon** thumbnail. The shape on the canvas immediately becomes a hexagon, keeping its
   exact position, size, and stroke/fill. The hexagon thumbnail is now highlighted.
4. Click the **star** thumbnail → the shape becomes a star, same bounds and styling.
5. Click the **star** thumbnail again (the active one) → nothing happens, and Undo is **not** armed for
   this click (no-op).
6. Select a **text** element → the Shape section is gone. Click empty canvas (no selection) → still gone.

## 2. Undo / redo (P2)

1. With the star shape, press **Undo** → it returns to a hexagon in one step.
2. Press **Undo** again → back to a rectangle.
3. Press **Redo** → hexagon; **Redo** again → star. Each step is exactly one form change.

## 3. Persistence + WYSIWYG across preview/export (P3)

1. Set one shape to **hexagon** and another to **triangle**. Fill them (e.g. a stroke + fill color).
2. **Save** the report, then **reload** it → both shapes return as hexagon and triangle, styling intact.
3. Switch to **Preview** → the hexagon and triangle look identical to the canvas.
4. **Export** to PDF and PNG → the shapes match the canvas and preview exactly (same geometry, fill,
   stroke).
5. Open a **pre-feature** report (only lines/rectangles) → it loads unchanged.

## 4. Line coherence + degenerate bounds (edge cases)

1. Take a filled rectangle, switch it to **line** → it renders as a diagonal stroke (no fill error).
   The flip-diagonal option applies. Switch back to **rectangle** → it is fillable again.
2. Resize a shape to a very thin / ~1×1 box and cycle through forms → each renders (or collapses)
   without an error.

## 5. Forward-compat round-trip (FR-009) — via test/inspection

1. Hand-author (or load a fixture with) a shape whose `kind` is an unrecognized value, e.g. `octagon`.
2. Open the report → it loads without error and renders as a **rectangle**.
3. Save the report → inspect the JSON: the shape's `kind` is still `octagon` (lossless; the original
   form name was preserved via `unknownForm`).
4. Now deliberately pick **star** in the gallery and save → the JSON `kind` is `star` (the unknown was
   intentionally replaced).

## 6. Accessibility / localization

1. Tab through the gallery with the keyboard → each thumbnail is focusable and activatable; a screen
   reader announces its form name and button role.
2. Switch the app locale to **German** then **Turkish** → the **Shape** section label and the eight
   form names are translated.

## Verify (commands)

```bash
# from repo root
flutter test packages/jet_print            # full suite incl. new geometry/codec/command/widget/golden tests
flutter analyze packages/jet_print         # zero warnings
dart format --output=none --set-exit-if-changed packages/jet_print
```

All green, analyzer clean, formatting unchanged → the feature meets its contracts.
