# Quickstart: Vertical & Horizontal Canvas Rulers

## For the end user (designer)

Open the report designer. **Rulers are on by default**: a horizontal ruler runs along the top of the
canvas and a vertical ruler down the left, both in **millimetres** measured from the page's top-left
corner (0,0).

- **Read positions/sizes**: the marks show where things sit on the sheet in mm. Move the pointer over
  the canvas and a thin marker tracks your position on both rulers. Select an element (or several, or
  a band) and its overall extent is highlighted on each ruler — left→right on top, top→bottom on the
  left.
- **Zoom & pan**: the rulers stay locked to the page. Zoom in for finer marks, out for coarser ones —
  labels never crowd or disappear.
- **Hide/show**: click the **ruler** toggle in the top bar (next to grid and snap). Off → the rulers
  disappear and the canvas reclaims the space. On → they come back. The toggle highlights when rulers
  are visible, just like grid and snap.

## For the host developer (the one public touchpoint)

**Nothing to wire.** Rulers ship inside `JetReportDesigner` and are controlled entirely by the
existing top-bar toggle. There is no new required parameter, no host callback, no setup:

```dart
// Unchanged — rulers are present and on by default.
const JetReportDesigner();
```

If a host drives the designer through the controller, two methods are available (mirroring the
existing grid/snap pair):

```dart
controller.rulersEnabled;            // bool — currently visible? (default true)
controller.setRulersEnabled(false);  // hide; setRulersEnabled(true) to show
```

Ruler visibility is a **session view preference** — it is *not* saved in the report template, exactly
like `gridEnabled` and `snapEnabled`. Saved reports, preview, and export are completely unaffected by
rulers (they are a design-time aid only).

## For the contributor (where things live)

- **Measurement math (pure, test-first)**: `lib/src/designer/canvas/ruler_scale.dart`
  (`RulerScale`/`RulerTick`) and `ruler_metrics.dart` (`pointsToMm`/`mmToPoints`, `selectionExtent`).
  No Flutter import → unit-tested directly.
- **The strips**: `lib/src/designer/canvas/ruler_overlay.dart` (the H/V ruler widgets + painters),
  integrated into `design_canvas.dart` as fixed edge overlays beside the scrollbars, with the
  viewport inset by `kRulerThickness` when enabled.
- **Visibility**: `rulersEnabled`/`setRulersEnabled` on `jet_report_designer_controller.dart`; the
  toggle in `designer_top_bar.dart`.
- **Tunables**: `design_tunables.dart` (`kRulerThickness`, `kRulerMinLabelGapPx`, `kRulerStepLadderMm`).

Run the tests:

```bash
flutter test packages/jet_print
```

Key invariants the tests pin: ruler marks align with page positions at every zoom + scroll
(`ruler_alignment_test.dart`), labels never overlap and at least one is always shown
(`ruler_scale_test.dart`), the selection highlight is the union of whatever is selected
(`ruler_metrics_test.dart` / `ruler_tracking_test.dart`), and existing canvas/preview/export goldens
are unchanged (rulers add no rendered output).
