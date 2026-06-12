# JetReportWorkspace — keep-alive designer↔preview with loading feedback

**Date**: 2026-06-12
**Status**: Design (awaiting review)
**Branch context**: builds on `017-unified-toolbar` (the shared `UnifiedTopBar` + `WorkspaceModeSwitch`)

## Problem

Switching between the designer and the preview is slow and gives no visual
feedback. Two distinct costs, with different fixes:

1. **Back to design is slow.** The designer canvas is a *cached* `ui.Picture`
   (recorded once per model change by `DesignTimeFrameBuilder.recordFrame`,
   blitted cheaply by `FrameCustomPainter`). When a host **unmounts** the
   designer on switch (an in-place swap, as in the consuming app), returning
   re-runs `initState` → first build → an **async** re-record. During that gap
   the canvas paints blank and the toolbox/right panel rebuild — that is the
   stutter. The cost is *not* data-proportional; it is the remount + re-record.

2. **Into preview is slow for large datasources.** `JetReportEngine.render()`
   runs two synchronous, data-proportional passes on the calling thread —
   `ReportFiller.fill` (every expression, all master/detail rows) and
   `ReportLayouter.layoutLazy` (a boundary pass over the whole filled report to
   resolve the exact page count). Only per-page frame building is lazy. So the
   first render of a large dataset blocks one UI frame, with no spinner able to
   paint (the frame never yields).

## Goal

Make mode switching feel instant, and give visible feedback for the one cost
that remains.

- **Keep both views mounted** so switching is a pure visibility toggle — zero
  rebuild, zero re-record, instant in both directions. This fully fixes (1) and
  reduces (2) to a **one-time** first render.
- **Render the preview behind a loading indicator** so that first large-data
  render shows feedback instead of a silent freeze.

Out of scope (explicit): moving `render()` off the UI thread (isolate / chunked
yielding). The `renderReport` callback's `FutureOr` return keeps that path open
for later without an API change.

## Approach

A single new **public** widget, `JetReportWorkspace`, that owns the workspace
mode and composes the existing `JetReportDesigner` and `JetReportPreview`. It
lives in the library (`packages/jet_print`) so it can reuse the private shell
widgets (`UnifiedTopBar`, `WorkspaceModeSwitch`, `WorkspaceMode`) built in 017.

No change to `JetReportDesigner`, `JetReportPreview`, the render engine, or
serialization — the workspace only *composes* them.

### Public surface (additive — one symbol)

```dart
JetReportWorkspace({
  Key? key,
  required JetReportDesignerController controller,
  required FutureOr<RenderedReport> Function(ReportTemplate template) renderReport,
  JetDataSchema? dataSchema,
  ReportSaveRequestedCallback? onSaveRequested,
  ReportOpenRequestedCallback? onOpenRequested,
  ValueChanged<RenderedReport>? onExportPdf,
  ValueChanged<RenderedReport>? onPrint,
  WidgetBuilder? loadingBuilder,
});
```

- `renderReport` is the host's render policy (the playground's `renderInvoice`).
  `FutureOr` lets a host that already renders off-thread plug in unchanged,
  while a plain synchronous `JetReportEngine().render(...)` still works.
- `onExportPdf` / `onPrint` receive the **current** `RenderedReport` (the
  workspace owns it now, so the host no longer closes over a `_report` field).
  The host still performs all I/O.
- `WorkspaceMode` **stays private** — the workspace always opens in designer
  mode, so no enum is exported.
- **Net new public symbols: exactly `JetReportWorkspace`.** The callback
  typedefs (`ReportSaveRequestedCallback`, `ReportOpenRequestedCallback`) are
  reused; `ValueChanged` / `FutureOr` / `WidgetBuilder` are platform types.

This deliberately expands the 017 minimal-surface stance by one widget, chosen
so consumers get keep-alive + feedback for free rather than re-implementing the
host composition.

### Structure (keep-alive)

```
IndexedStack(index: mode == designer ? 0 : 1)
 ├─ 0: JetReportDesigner(controller, dataSchema, onSaveRequested, onOpenRequested,
 │        onPreviewRequested: _enterPreview)        ← always mounted; cached picture retained
 └─ 1: preview slot
        report == null (first render in flight) → _LoadingScaffold:
              UnifiedTopBar(leadingIcon, name, center: WorkspaceModeSwitch(
                  mode: preview, onSwitchRequested: _enterDesigner), actions: none)
              + body: indeterminate ShadProgress pinned under the toolbar
        report != null → JetReportPreview(report, onBack: _enterDesigner,
              onExportPdf: () => onExportPdf?.call(report),
              onPrint:     () => onPrint?.call(report))
```

`IndexedStack` keeps both children's `State` alive, so returning to design
re-blits the cached `ui.Picture` in one frame — no `initState`, no re-record,
no panel rebuild. The designer's selection and scroll position survive the
round trip (a direct consequence of the same `State` instance).

The loading scaffold reuses the private `UnifiedTopBar` + `WorkspaceModeSwitch`
so the **switch-back affordance is present while loading** and the bar stays
positionally identical to both modes (017 FR-001). Its `name` comes from
`controller.template.name` (the live name, same source the designer's bar uses). The indicator is an
indeterminate `ShadProgress` (shadcn_ui has no circular spinner) placed as a
thin bar directly under the toolbar; `loadingBuilder` overrides it.

### Render + feedback flow

State held by the workspace: `WorkspaceMode _mode` (starts `designer`),
`RenderedReport? _report`, `ReportTemplate? _lastRendered`, `bool _rendering`.

`_enterPreview(ReportTemplate template)`:
1. `setState(_mode = preview)`.
2. If `_report != null && identical(template, _lastRendered)` → reuse cached
   report instantly (no render). Return.
3. Else enter loading: `setState(_rendering = true)`. Schedule the render
   **deferred** (a microtask / post-frame callback) so the loading scaffold
   paints at least one frame before the synchronous render runs.
4. `final report = await renderReport(template);` then, if still mounted,
   `setState(_report = report; _lastRendered = template; _rendering = false)`.

`_enterDesigner()`: `setState(_mode = designer)`. Never renders.

Because `ReportTemplate` is immutable and replaced on every edit, the
`identical(template, _lastRendered)` check is an exact "did the design change
since I last rendered" test: an **unedited** round trip into preview is free; an
**edited** one re-renders.

Re-render while an old report is showing (edited, re-entering preview): keep the
old `JetReportPreview` visible with a loading overlay (an indeterminate
`ShadProgress` over the existing pages) — no blank flash, feedback that work is
in flight, and the new pages swap in on completion.

Guard: a stale render must not overwrite a newer one. Tag each render with an
incrementing sequence (mirrors `JetReportPreview._recordSeq`); ignore a result
whose sequence is no longer current.

### What is intentionally untouched

- The render engine: `render()` stays synchronous; the workspace only defers
  *when* it is called. (The async-engine path is left open behind `FutureOr`.)
- Serialization: no field, no `schemaVersion` change.
- `JetReportDesigner` / `JetReportPreview`: unchanged; the workspace passes the
  existing `onPreviewRequested` / `onBack` switch events to its own mode setters.
- Report goldens: this is chrome/composition only; no paint path changes.

### Playground

The playground is **refactored** to use `JetReportWorkspace` as the reference
demo: it drops the `Navigator.push` preview route and the `_report` field in
`RenderedInvoiceExample`, supplying `controller`, `dataSchema`, `renderReport:
(t) => renderInvoice(template: t)`, and the save/open/export/print callbacks.
This both proves the abstraction is complete and documents the recommended
consumer shape.

## Testing

Widget tests (`jet_report_workspace_test.dart`):
- designer→preview shows the loading scaffold (mode switch present, preview
  active), then the rendered preview once `renderReport` completes;
- switch back to designer is immediate and the **same** designer `State`
  survives (selection / scroll preserved) — the keep-alive proof;
- unedited re-entry into preview reuses the report (`renderReport` fired once);
- editing the template then re-entering preview triggers exactly one re-render;
- a slow/in-flight render that is superseded does not overwrite the newer report
  (sequence guard);
- `onExportPdf` / `onPrint` fire with the current `RenderedReport`;
- `loadingBuilder` overrides the default indicator when supplied.

Regression: existing designer / preview / top-bar / codec / golden suites stay
green (nothing they cover changes). `public_api_test.dart` updated for the one
new symbol. Playground test updated for the workspace wiring.

## Risks / notes

- The first large-data render still blocks one UI frame; the indeterminate
  `ShadProgress` will have painted before it, but it freezes during that frame.
  Accepted per the chosen scope; the `FutureOr` seam allows an off-thread render
  later with no API change.
- `ShadProgress` is a linear indeterminate bar, not a circular spinner — a
  deliberate choice to stay within shadcn_ui and avoid pulling Material in for a
  spinner. `loadingBuilder` is the escape hatch for hosts that want something
  else.
