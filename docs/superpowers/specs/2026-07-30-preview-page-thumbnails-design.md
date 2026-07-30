# Preview Page Thumbnails — Design

**Date:** 2026-07-30
**Status:** Approved (design), pending implementation plan

## Problem

The report preview (`JetReportPreview`) navigates pages only through the
toolbar: prev/next buttons, a "Page X of N" dropdown with First/Last/"Go to
page", and the left/right arrow keys. Picking page 7 of 20 means either
clicking next six times or typing a number — with no way to *see* which page
holds the content you want. Every mainstream document viewer (Acrobat, macOS
Preview, Chrome's PDF viewer) solves this with a thumbnail rail.

The user asked for a page-thumbnail list on the preview screen, plus a toolbar
toggle to show and hide it.

## Decision

A **left thumbnail rail** inside the preview's body, above which the existing
toolbar stays full width. The rail lists every page as a scaled-down painted
thumbnail with a page-number caption; clicking one navigates. A new leading
toolbar action toggles it. The rail is **shown by default** on desktop-class
viewports and auto-hidden below a 700 px body width.

## Approach (chosen: A — standalone `PageThumbnailRail` widget)

`packages/jet_print/lib/src/designer/preview/page_thumbnail_rail.dart` — a new
package-internal `StatefulWidget` owning its own scroll controller, picture
cache, and record lifecycle. `JetReportPreview` keeps only the toggle state,
the toolbar button, and the `Row` that places the rail beside the existing page
area (≈40 added lines in a file already at 566).

Rejected:

- **B — inline in `jet_report_preview.dart`.** Pushes that file to ~830 lines
  and tangles a multi-picture LRU cache with the existing single-picture
  `_record()` / `_recordSeq` lifecycle. The file already carries fit-mode,
  zoom, keyboard and toolbar concerns; this is exactly the god-file growth the
  designer split program removed elsewhere.
- **C — extract a shared `PagePictureCache` used by the main view and the
  rail.** Cleanest in theory, but the main view records exactly one picture
  guarded by its own sequence counter and works today. Unifying is a refactor
  of working code with no user-visible gain (YAGNI). Revisit only if a third
  consumer appears.

## Architecture

```
JetReportPreview (Column)
├─ UnifiedTopBar          ← full width, unchanged; gains a leading toggle action
├─ ShadSeparator.horizontal
└─ Expanded → Row
   ├─ PageThumbnailRail   ← 144 px, only when visible
   ├─ ShadSeparator.vertical
   └─ Expanded            ← the existing LayoutBuilder page area, unchanged
```

The page area's fit math needs no change: its `LayoutBuilder` already reads
live constraints, and the existing `viewportChanged` handshake re-fits when the
rail opens or closes and the body narrows/widens by 145 px.

### Rail widget

```dart
class PageThumbnailRail extends StatefulWidget {
  const PageThumbnailRail({
    super.key,
    required this.report,        // RenderedReport
    required this.currentIndex,  // selected page
    required this.onSelect,      // ValueChanged<int>
  });
}
```

Package-internal — **not** exported. The only public-API change is the new
`JetReportPreview.showThumbnails` parameter.

- **List** — `ListView.builder(itemExtent: _tileExtent, itemCount:
  report.pageCount)`. A fixed extent keeps scrolling O(visible) even for the
  ~20 000-row Defter demo's page count, and makes scroll-to-index pure
  arithmetic (`index * _tileExtent`) instead of `Scrollable.ensureVisible` plus
  per-tile `GlobalKey`s.
- **Extent** — derived from page 0's aspect ratio (thumbnail width 128 px plus
  caption and padding). Each tile still paints *its own* page contained within
  the slot, so a differently-sized page renders correctly rather than stretched.
- **Tile** — white sheet (matching the main view's light/dark sheet colours) +
  border; the selected tile gets a 2 px primary-coloured border. Content is
  `CustomPaint(FrameCustomPainter(picture: …, scale: 128 / page.width,
  revision: index))`. A page-number caption sits below, emphasized for the
  current page. The whole tile is a tap target wrapped in
  `Semantics(button: true, selected: …, label: <page N>)`.
- **Not-yet-recorded tile** — empty sheet plus caption, no spinner. This
  matches the main view, which also shows a bare sheet while its record is
  in-flight.

### Painting

A thumbnail is the **same** `ui.Picture` the main view would record, blitted at
a smaller scale — `ui.Picture` is a resolution-independent display list and
`FrameCustomPainter` already applies `canvas.scale()` at blit time. So the rail
records through the identical shared `paintFrame` → `CanvasPainter` pipeline
(Constitution IV: no preview-specific element drawing code) with no separate
low-resolution path.

The rail does **not** reuse the main view's picture. Two owners of one
`ui.Picture` means the main view's `_record()` can dispose it while the rail is
still blitting → use-after-dispose. The rail owns every picture it holds.

### Cache

`LinkedHashMap<int, ui.Picture>` capped at 24 entries, LRU: re-access moves an
entry to the end, eviction calls `.dispose()`, and `State.dispose()` drains the
map. Undisposed `ui.Picture`s leak on web/CanvasKit, so eviction disposal is a
correctness requirement, not an optimization.

`Set<int> _inFlight` coalesces duplicate record requests for the same index — a
fast scroll can request page 7 several times before the first `await` returns.
A completed record is dropped (and disposed) if the widget unmounted meanwhile.

`@visibleForTesting int get debugCachedCount` exposes the cache size so the cap
is testable.

Note on memory: `RenderedReport.pageAt(i)` caches built frames forever by
design (FR-021), so scrolling the rail through a long report materializes the
frames it passes. That is the engine's existing contract; the rail bounds only
what it itself owns (pictures), not the engine's frame cache.

### Auto-scroll

When `currentIndex` changes from outside (toolbar buttons, arrow keys,
"Go to page"), `didUpdateWidget` scrolls the tile into view only if it is not
already visible: `animateTo` a centred offset, ~180 ms, guarded on
`controller.hasClients`.

## Toolbar toggle

- Leading action in `_toolbarActions`, before the page-navigation group,
  followed by a `_Divider`.
- Key `jet_print.preview.thumbnails`; icon `LucideIcons.panelLeft`.
- On-state uses `ShadIconButton.secondary`, off-state `ShadIconButton.ghost` —
  shadcn has no toggle icon button, and the filled variant reads as pressed.
- Tooltip + accessible name switch with state, so two new l10n keys are needed
  rather than one.

## Public API

One new parameter:

```dart
const JetReportPreview({..., this.showThumbnails = true});
```

**Initial value only**, documented exactly like `initialPage`:
`didUpdateWidget` does not re-seed it, so a host rebuild never yanks the rail
back from under the user. No `onThumbnailsChanged` callback — no host needs to
persist the preference yet (YAGNI).

### Narrow-viewport default

Effective first-open visibility resolves **once**, on first layout, reusing the
existing `_defaultZoomResolved` one-shot pattern in the same widget: body width
< 700 px starts hidden. The breakpoint can only *hide* — `showThumbnails:
false` opens hidden at every width. Every explicit toggle afterwards is
honoured at any width; the breakpoint picks a default, it does not veto the
user.

The 700 px threshold sits above the 600 px golden-test surfaces (below) and
below the toolbar's existing 880 px scroll breakpoint.

## Localization

Two keys — `previewShowThumbnails` ("Show page thumbnails") and
`previewHideThumbnails` ("Hide page thumbnails") — added to **both** the three
`.arb` files (en/de/tr) and the hand-written
`jet_print_localizations{,_en,_de,_tr}.dart`, including the abstract getters
and doc comments. A previous spec shipped keys in the generated Dart only; both
sides land together here.

## Testing

New widget tests for the rail and the toggle:

1. Rail renders one tile per page and captions them.
2. Tapping a tile navigates the main view to that page.
3. Toggle hides, then re-shows, the rail.
4. `showThumbnails: false` opens without the rail; toggle still shows it.
5. Narrow viewport (< 700 px) opens hidden; wide opens shown.
6. Toolbar next/prev scrolls the rail's selected tile into view.
7. Cache stays at or below its cap while scrolling a many-page report
   (`debugCachedCount`).

Expected fix-ups in existing tests, because the rail is now visible at their
surface sizes:

- `test/designer/preview/preview_localization_*.dart` — 800×600.
- `apps/jet_print_playground/test/rendered_invoice_example_test.dart` — 900×700.

Finders such as bare `find.text('1')` may go ambiguous against the new page
captions; they get scoped to a descendant of the page area or the rail.

The four preview goldens render at 600×560 (`rendered_invoice_*`) and 600×840
(`chart_preview_light`) — below the 700 px breakpoint, so the rail auto-hides
and they are expected to stay byte-identical. This is *verified by running the
suite*, not asserted; if the Skia glyph cache drifts from the new toolbar
button, the goldens are regenerated deliberately and the diff inspected.

`public_api_test` covers the new `showThumbnails` parameter; `PageThumbnailRail`
itself stays unexported.

## Out of scope

- Keyboard focus traversal and arrow-key selection *within* the rail (arrow
  keys keep driving the main view, as today).
- User-resizable rail width.
- Multi-column / grid thumbnail view.
- Drag-to-reorder or any editing affordance — the preview is read-only.
