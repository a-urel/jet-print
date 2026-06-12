# Quickstart: Format Properties — Font & Color Editors

**Feature**: `021-format-properties` — end-to-end manual walk once implemented.

## Run

```bash
# from repo root
flutter run -d macos --target apps/jet_print_playground/lib/main.dart
# or: cd apps/jet_print_playground && flutter run -d macos   (run git from repo root afterwards)
```

## 1. Style a text element (Story 1 / P1)

1. Drop a **text** element on the canvas; select it → Properties tab shows a **Font** section
   with family, size, B/I/U, color, and alignment bound to current values.
2. Family select lists the registered families (built-in `JetSans` today), each previewed in
   its own typeface — pick one; canvas re-renders immediately.
3. Size: type `36` + Enter → text grows. Type `500` → clamps to `144`. Type `abc` → rejected,
   previous value restored.
4. Toggle **B**, **I**, **U** — each press updates canvas instantly and shows active state.
5. Color: open the swatch popover → pick red, or type `#1E40AF` + Enter. Trigger shows the
   swatch + hex. Type `#zzz` → rejected with feedback, last color kept.
6. Alignment: click center/right segments → text re-aligns within its bounds (no justify
   segment — justified rendering is a follow-up).
7. Press **⌘Z** repeatedly — each committed change above steps back exactly once, and the
   editors track the restored values.

## 2. Style a shape (Story 2 / P2)

1. Select a **rectangle** → **Appearance** section: fill color, outline color, outline width.
2. Set fill to a color → interior paints. Choose **None** → outline-only box; editor shows
   the none state.
3. Set outline width to `3` → thicker border; set `0` → border disappears; set back to `2` →
   border returns **in its remembered color**.
4. Select a **line** shape → only outline color + width appear (no fill control).
5. Set fill *and* outline to None → the shape stays selectable on canvas via the design-time
   placeholder affordance.

## 3. Barcode color (Story 3 / P3)

1. Select a **barcode** → a color editor shows the current bar color (black).
2. Pick navy → the placeholder tint updates on canvas. Undo restores black.

## 4. Verify WYSIWYG + persistence (FR-014/FR-015)

1. With styled text + shapes + barcode on the page, open **Preview** → identical styling.
2. Export **PDF** and **PNG** → family, size, bold/italic/**underline**, color (incl. a
   translucent one), alignment, fill/stroke/none states all match the canvas.
3. **Save** the report, reopen it → every style (alpha, none states, underline) reloads
   exactly; an old pre-feature report still opens and re-saves unchanged.

## Test suite

```bash
# from repo root — full gate: analyze, format, tests incl. new goldens
flutter analyze && dart format --output=none --set-exit-if-changed packages apps && flutter test packages/jet_print
```

Key suites: `domain/styles/*` (underline, copyWith), `domain/serialization/*` (round-trips,
pre-feature byte-compare), `designer/controller/*_command_test.dart` (single-undo/no-op),
`designer/properties_editor_test.dart` (C1–C9 gating/commit/validation),
`rendering/**` (underline parity, stroke-width-0, goldens).
