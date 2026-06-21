# Designer Demo-Switch Slowdown on Web — CanvasKit Font-Registration Leak — Design

**Status:** draft (2026-06-21) — awaiting user review
**Parent roadmap:** [2026-06-20-production-readiness-roadmap-design.md](./2026-06-20-production-readiness-roadmap-design.md)
**Relates to:** E4 (web support — this is a web-only defect E4's verification did
not exercise), the playground demo shell shipped across specs 024–036.
**Surface:** `flutter run -d chrome` (CanvasKit) playground; reproduces in any
web consumer of `JetReportWorkspace`/`JetReportDesigner`.

---

## 1. Summary

Switching demo tabs in the playground on **web** takes "more than 3 seconds with
no visual feedback," and **gets worse the longer you use the app**. Profiling
proved the cost is **GPU-side and unbounded**: it grows ~linearly with the number
of tab switches and never recovers.

Root cause: a **CanvasKit font-registration leak**. Every time the design canvas
records its frame, it constructs a fresh `CanvasPainter` whose "already-loaded
fonts" guard is empty, so it calls `ui.loadFontFromList` for every font variant
again. CanvasKit **appends** (never dedupes) each registration into its font
collection, so the collection bloats without bound and text rasterization slows
on every record. A second defect — the playground's tab shell **remounts the
designer on every switch** — is what makes a record fire on every switch,
turning a hot-path defect into a visible, ever-worsening freeze.

Three defects surfaced. Two are in the **library** (they bite any web consumer,
including on every drag-preview frame); one is in the **playground** (it also
silently discards in-progress edits on a tab switch).

This is **verify + fix**, not a redesign. The fixes are localized; goldens stay
byte-identical.

---

## 2. Evidence (profiling)

A temporary probe printed each slow frame's UI-thread vs GPU-thread split
(`SchedulerBinding.addTimingsCallback`), each `recordFrame` run (a per-`State`
counter), and a cumulative `ui.loadFontFromList` call count.

**Finding 1 — GPU-bound, and unbounded.** Bouncing between **two** tabs
(`Fatura` ⇄ `Bordro`), `build(UI)` stays flat (~55–60ms early, plateaus ~440ms);
`raster(GPU)` climbs without a ceiling and never recovers:

```
raster(GPU) ms: 776 → 854 → 950 → … → 1468 → 1936 → 2527 → 3038 …   (still climbing)
```

A shader/cold-paint cost would be one-time per tab and then warm. This is not
that — it is accumulation.

**Finding 2 — the designer remounts on every switch.** The `recordFrame` counter
is a per-`State` instance field and prints **`#1` every switch, twice per switch**
— i.e. a brand-new canvas `State` each time (counter resets), for both the
entering and the leaving tab. The keep-alive is defeated; the designer is torn
down and rebuilt on each switch.

**Finding 3 — font registrations and raster climb in lockstep.** The cumulative
`loadFontFromList` count rises **+4 every switch** (2 remounts × 2 variants,
`Default__bold` + `Default__normal`), in exact correlation with raster:

```
loadFontFromList total: 22 → 26 → 30 → 34 → 38 → 42 → 46 → 50 → 54 → 58 → 62 → 66 …
raster(GPU) ms:        810 → 916 →1028→1186→1245→1381→1442→1529→1638→1753→1851→2027 …
```

The same variant (`Default__bold`) is re-registered indefinitely. This is the
accumulator.

**Why web-only / why E4 missed it:** native engines deduplicate / GC font and
image handles differently; the cost is invisible on desktop and mobile, and E4's
web pass exercised rendering correctness, not a long-running edit/switch session.

---

## 3. Root cause

```
tab switch
  └─ ShadTabs wraps ONLY the selected tab's content in `Expanded`
       (shadcn_ui tabs.dart: expandContent → Expanded(child) when selected)
  └─ flipping `Expanded` on/off changes the widget *type* at that Column slot
  └─ Flutter unmounts the old element subtree, mounts a new one
       (the GlobalKey on `tab.content` does not save it across the type flip)
  └─ fresh DesignCanvas State  →  fresh recordFrame  (counter == #1, every switch)
        └─ fresh CanvasPainter, `_loadedFamilies` empty
             └─ _ensureFont → ui.loadFontFromList(...) for every variant, AGAIN
                  └─ CanvasKit APPENDS to its font collection (no dedupe)
                       └─ font collection grows unbounded
                            └─ text shaping/raster walks a bigger collection each frame
                                 └─ raster(GPU) climbs ~linearly, forever
```

Two layers, each independently a bug:

- **Accumulator (library):** `CanvasPainter` re-registers fonts on **every**
  `recordFrame`. This fires not only on tab switch but on **every drag-preview
  frame** (a drag ticks `frameVersion`, which re-records), so even a single
  consumer dragging an element bloats the engine font collection mid-drag.
- **Trigger (playground):** the demo shell remounts the designer per switch, so a
  record fires on every switch (and in-progress edits are discarded with the old
  `State`).

---

## 4. Defects & fixes

| # | Layer | Defect | File |
|---|---|---|---|
| **LIB-A** | library | `ui.loadFontFromList` re-runs on every record → CanvasKit font-collection bloat (the unbounded growth) | [canvas_painter.dart:51-59](../../../packages/jet_print/lib/src/rendering/paint/canvas_painter.dart#L51-L59) |
| **LIB-B** | library | `_decoded` `ui.Image`s are never `.dispose()`d → leaked Skia GPU textures on every record (image reports / drag) | [canvas_painter.dart:36,44-48,110-121](../../../packages/jet_print/lib/src/rendering/paint/canvas_painter.dart#L36) |
| **APP-C** | playground | `expandContent` defeats `maintainState` → designer remounts per switch → wasted re-record **+ silent edit-loss** | [main.dart](../../../apps/jet_print_playground/lib/main.dart) |

LIB-A is the direct cause of the observed 3s and the most fundamental (it also
fixes the drag hot path). LIB-B is a genuine GPU leak on the same per-record
pattern (not triggered by these two image-less tabs, but real for the menu demo
and any consumer with an `ImageElement`). APP-C is the playground correctness/UX
completion: instant switches **and** edits that survive a switch.

### 4.1 LIB-A — register each engine font variant once per process

Engine font registration is **process-global** state. The guard against
re-registering must therefore live at process scope, not per-`CanvasPainter`.

**Design:** introduce a shared, injectable "already-registered" set. The default
is a single library-global instance; tests pass a fresh set for isolation.

```dart
class CanvasPainter implements ReportPainter {
  CanvasPainter(
    this._canvas,
    this._registry, {
    FontLoader? fontLoader,
    Set<String>? registeredFamilies,         // NEW — defaults to the shared set
  })  : _loadFont = fontLoader ?? ui.loadFontFromList,
        _registered = registeredFamilies ?? _engineRegisteredFamilies;

  /// Process-global: every uiFamily ever registered into the engine.
  static final Set<String> _engineRegisteredFamilies = <String>{};

  /// Test seam: reset the shared registry between tests.
  @visibleForTesting
  static void debugResetEngineFonts() => _engineRegisteredFamilies.clear();

  final Set<String> _registered;

  Future<void> _ensureFont(String family, JetFontWeight weight, bool italic) async {
    final String uiFamily = uiFontFamily(family, weight, italic);
    if (_registered.contains(uiFamily)) return;     // global guard
    final Uint8List bytes = _registry.bytesFor(family, weight: weight, italic: italic);
    await _loadFont(bytes, fontFamily: uiFamily);
    _registered.add(uiFamily);
  }
}
```

- Keying on `uiFamily` (`family + weight + italic`) matches how the engine itself
  names the registration, so the guard is exactly as granular as the engine's
  identity for a typeface.
- The `FontLoader` seam is preserved; existing injection points are unaffected.
- **No public API change** — `CanvasPainter` is under `src/`.

### 4.2 LIB-B — dispose decoded images after recording

After `PictureRecorder.endRecording()`, the recorded `ui.Picture` holds its own
reference to anything drawn into it, so the `_decoded` `ui.Image` handles are no
longer needed and must be disposed to free their GPU textures.

**Design:** give `CanvasPainter` a `dispose()` that disposes its decoded images,
and have `DesignTimeFrameBuilder.recordFrame` call it after `endRecording`:

```dart
// CanvasPainter
void dispose() {
  for (final ui.Image img in _decoded.values) {
    img.dispose();
  }
  _decoded.clear();
}

// DesignTimeFrameBuilder.recordFrame
final CanvasPainter painter = CanvasPainter(ui.Canvas(recorder), fonts);
await paintFrame(frame, painter);
final ui.Picture picture = recorder.endRecording();
painter.dispose();          // free decoded image textures; picture keeps its own refs
return picture;
```

Verified-by-test that the returned picture still paints after the painter is
disposed (the picture retains what it needs; only the redundant handles are
released).

### 4.3 APP-C — stop the per-switch remount (stable `IndexedStack`)

Replace "ShadTabs hosts 8 live designers via `expandContent`" with "a tab strip
*selects*, and a structurally-stable `IndexedStack` *hosts* the 8 designers."

**Design:**
- `_PlaygroundHomeState` owns the selected demo (via a `ShadTabsController` so the
  strip keeps its shadcn look, or plain `int` state).
- The tab strip (`ShadTabs` used as a selector, with lightweight/empty content, or
  an equivalent segmented strip) only changes the selected index.
- The 8 designer bodies are rendered once in
  `Expanded(child: IndexedStack(index: selected, sizing: StackFit.expand, children: [...]))`.
  The children list is constant; only `index` changes → **no widget-type flip →
  no remount.** State (and thus each `JetReportDesignerController` + its edit
  history) is preserved across switches.
- Remove the `_FillTabHeight` workaround — `IndexedStack` with `StackFit.expand`
  gives every child a bounded height, so the offstage-unbounded-height hack is no
  longer needed.
- Preserve existing behaviors: the scrollable strip, the narrow/wide
  theme+locale cluster layout, the `_narrowWidth` breakpoint, and per-tab
  identity across the narrow⇄wide swap.

**Consequence (the bonus correctness win):** because the designer no longer
remounts, an edit made on one tab survives switching away and back — the behavior
the original `maintainState` comment *claimed* but did not deliver.

---

## 5. Why each fix is independently justified

- **LIB-A** stops the unbounded growth at its source and fixes the drag hot path
  for every web consumer. With LIB-A alone, the observed 3s is gone even if the
  playground keeps remounting (font loads become no-ops after the first).
- **LIB-B** fixes a real GPU texture leak on the same per-record pattern,
  independent of tabs (it bites image reports during drag).
- **APP-C** makes switches *instant* (cached-picture blit, ~8ms) and fixes the
  silent edit-loss. LIB-A caps the per-switch cost; only APP-C removes the
  per-switch re-record entirely and preserves edits.

All three ship together: LIB-A+B are the library correctness fixes; APP-C is the
playground completion.

---

## 6. Architecture & layering

- `canvas_painter.dart` remains the single `dart:ui`-touching rendering file
  (Constitution II). LIB-A/B keep that boundary — no new `dart:ui` import
  elsewhere.
- The font-registry guard is a static on `CanvasPainter`; it models genuinely
  global engine state and is injectable for tests, so it does not introduce
  hidden global coupling into pure layers.
- APP-C touches only the playground (`apps/jet_print_playground`); the library's
  `JetReportWorkspace`/`JetReportDesigner` are unchanged.

---

## 7. Testing strategy (TDD — Constitution III)

**LIB-A (unit, library):**
- Record the same frame twice sharing the default registry with a counting
  `FontLoader`; assert each variant is loaded **once total** (not per record).
- Record with a freshly-injected `registeredFamilies` set; assert it loads again
  (proves the guard is the registry, not hidden state).
- `debugResetEngineFonts()` restores first-load behavior.

**LIB-B (unit, library):**
- Record a frame containing an `ImagePrimitive`; after `recordFrame`, assert the
  painter's decoded `ui.Image`s report `debugDisposed == true`.
- Draw the returned `Picture` after disposal; assert it paints without throwing
  (the picture retained its references).

**Regression (library):**
- Full golden suite **byte-identical** — fonts are still registered (once) and
  images still drawn, so output is unchanged.

**APP-C (widget, playground):**
- Mutate a controller (e.g. move/select an element) on tab A, switch to B, switch
  back; assert the edit is still present (proves no remount / state preserved).
- Assert switching does not recreate the designer `State` (e.g. an `initState` /
  record counter does not increment per switch).

**Manual web verification (the reproduction, after fix):**
- Re-run the same probes; bouncing two tabs ≥30×: `loadFontFromList total` **caps**
  at the distinct-variant count and does **not** climb; `raster(GPU)` per switch
  stays **flat**; steady-state switch < 150ms total; an edit survives a switch.
- Then **remove all probes** (see §9).

---

## 8. Acceptance criteria

1. Bouncing two tabs 30×: cumulative `loadFontFromList` count is bounded by the
   number of distinct `(family,weight,italic)` variants used — it does not grow
   with switches.
2. `raster(GPU)` per switch does not climb monotonically; steady-state demo switch
   completes in < 150ms total (cached-picture blit).
3. Decoded `ui.Image`s are disposed after each record (no GPU texture leak);
   recorded pictures still paint correctly.
4. An in-progress edit on one demo tab survives switching to another tab and back.
5. All existing library + playground tests pass; **goldens byte-identical**.
6. `flutter analyze` clean; new code has dartdoc; **all temporary probes removed**.

---

## 9. Temporary probes to remove on completion

Three diagnostic probes were added during investigation and **must be stripped**
before merge (acceptance #6):

- `apps/jet_print_playground/lib/main.dart` — the `SchedulerBinding`
  `addTimingsCallback` JANK printer (+ its `dart:ui`/`scheduler`/`debugPrint`
  imports).
- `packages/jet_print/lib/src/designer/canvas/design_canvas.dart` — the
  `_recordCount` field and `recordFrame run #…` `debugPrint`.
- `packages/jet_print/lib/src/rendering/paint/canvas_painter.dart` — the
  `debugFontLoadCount` static, its `debugPrint`, and the
  `package:flutter/foundation.dart` probe import.

---

## 10. Risks & mitigations

- **Global font-guard collision:** two reports defining the same
  `(family,weight,italic)` name with *different* bytes would share the
  first-registered typeface. Not present today (the built-in `Default` and the
  Google-Fonts catalog are canonical per app). Mitigation: key on `uiFamily`
  (engine-identity granularity); document the assumption. If divergent same-name
  fonts ever ship, the registry key gains a content hash.
- **Disposing images after record:** if a backend needed the live handle
  post-record, disposal would break it. Mitigated by the §7 test that paints the
  picture after disposal. Only the design-time `recordFrame` path is changed; the
  export (`pdf_painter`) and page-rasterizer paths are untouched.
- **`IndexedStack` lays out all 8 designers:** all bodies are laid out at startup.
  This already happens today (offstage tabs are laid out), so it is not a new
  cost; only paint is deferred to selection. If startup ever needs trimming,
  lazy-mounting is a separate, later optimization (YAGNI now).
- **Selector behavior parity:** the tab strip must keep its scrollable,
  keyboard-navigable, themed behavior. Covered by reusing `ShadTabs` as the
  selector and a widget test on selection.

---

## 11. Out of scope

- Shader/SkSL warmup or pre-warming tabs — the slowdown is a leak, not cold
  shaders; warmup would mask nothing here.
- Caching decoded images *across* records (we dispose instead; cross-record image
  caching is a separate perf idea, not needed to fix the leak — YAGNI).
- Any other epic (E2b streaming, etc.).
- Bundle IDs / printing SPM gaps (tracked under E6/E7).

---

## 12. Process

- **Branch:** a new `039-canvaskit-font-leak` feature branch off local `main`
  (specs run through `038`; `039` is next).
- **Method:** SDD/TDD per Constitution III — each fix Red→Green. LIB-A and LIB-B
  are independent and land first (they fix the leak and pass on their own);
  APP-C lands last (it depends on nothing but completes the UX/correctness story).
- **Verification gate:** the §7 manual web re-measurement is the closing check;
  probes are removed only after it passes.
