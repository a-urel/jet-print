# Touch authoring

A finger can select, move, resize and align report elements in the designer on a
phone. That claim is nine criteria, written below as what a finger does and what
must result. Each is a widget test in
`packages/jet_print/test/designer/canvas/phone_touch_authoring_test.dart`, which
CI runs on every pull request and every push to `main`. The real-device record
at the end of this page holds each device's result for all nine.
[`decisions/0003`](decisions/0003-mobile-in-1-0-scope.md) requires all three,
criteria, tests and a device pass, before `1.0.0` claims the designer on iOS
and Android. `1.0.0` was published on 2026-10-12 with the first two in place;
the device pass is still owed.

## The viewport the criteria assume

A phone in portrait: **390 × 844** logical pixels, the designer's default zoom,
and nothing but `PointerDeviceKind.touch`. At that width the default zoom is
fit-to-width, which clamps at the 25% floor, so an element 200 points wide is
50 pixels on screen and one 60 points tall is 15. That is the hard case on
purpose: a criterion that holds there holds at any zoom a user picks.

## The criteria

| # | A finger… | …and the result must be |
|---|---|---|
| T1 | taps an element | that element alone is selected; a tap on another replaces it. A tap on empty band space selects the band |
| T2 | drags an element, selected or not | the element moves with the finger, measured from where the finger went down, as one undo step. A drag on an element's body moves that element and never grabs a handle, neither its own nor a selected neighbour's |
| T3 | drags empty canvas | the page scrolls with the finger. Nothing is selected and the report is unchanged: under touch there is no marquee |
| T4 | drags a resize handle, an element's or a band's | the element or band resizes by the full distance the finger moved, anchored at the opposite edge |
| T5 | aims at a resize handle | the target is 44 × 44 pixels, although the drawn square stays 8. It leans out of the element and reaches past the paper's edge, where it still grabs; only element bodies take precedence over it |
| T6 | long-presses | on an element: it is selected, or with multi-select on, added, and the context menu opens for the selection. On empty canvas: the menu opens and the selection is kept |
| T7 | presses the canvas at all | a multi-select toggle, 44 pixels square, appears in the canvas's bottom-left corner. It is absent until the first finger press, and goes away, switched off, when a mouse presses anywhere on the canvas, the toggle included |
| T8 | taps elements with the toggle on | each tap adds or removes that element, as shift-click does. An empty tap keeps the selection, and a drag on a selected element moves all of them |
| T9 | selects two elements that way, then picks **Arrange → Align left** | both share the leftmost x, and nothing else moves. At phone width the top bar scrolls sideways to reach Arrange |

The test names carry the same numbers. When a criterion changes, its test and
its row here change in the same commit.

## Why the gestures are these

**Which gesture pans and which drags.** A drag that starts on an element moves
it, and one that starts on empty canvas scrolls the page. On a desktop the same
empty-canvas drag draws a marquee. A phone has no wheel and no trackpad, and a
scrollbar is too thin to grab, so dragging is the only way to scroll.

**Why there is a toggle.** Align needs two elements selected. A finger has no
shift key, and its empty-canvas drag scrolls rather than drawing a marquee, so
until this toggle existed align was unreachable by touch. A long-press-then-drag
marquee was considered and rejected. It is hard to discover, and it collides
with the long press that opens the context menu on empty canvas. The toggle
shows only under touch. A mouse already has shift-click and marquee, and the
designer goldens, which never simulate touch, stay as they were.

**Two bugs the criteria found.** Both were invisible on a desktop, because a
mouse's drag slop is a pixel or two and a finger's is about 18, and a mouse's
16-pixel handle targets leave a body free:

- **Drag start.** The canvas and handle detectors reported a drag from where it
  cleared the slop, not from where the finger went down
  (`DragStartBehavior.start`, Flutter's default). A drag on a 15-pixel element
  was hit-tested off it and scrolled the page. A handle resize trailed the
  finger by about 36 pixels. Both detectors now use `DragStartBehavior.down`.
- **Handle targets.** Centred on a small element, the 44-pixel touch targets
  covered its whole body, so once an element was selected, a finger could
  resize it but not move it. Under touch the rule is now that **bodies come
  first**: a press on any element's body misses every handle and reaches the
  canvas, which selects or moves that element. A handle's target takes the
  gaps around bodies, plus its own drawn square. Each target leans out of its
  element, into those gaps, and the selection chrome is laid over the page,
  reaching 44 pixels past it, rather than inside it. A page box clips hit
  tests at its edge, and an element flush with the margin, the first column
  of most tables, would otherwise keep a corner target of about 13 pixels.
  See `selection_overlay.dart` → `_handle`, `_BodiesFirst`, and
  `design_canvas/build_helpers.dart` → `_selectionOverlay`.

**What is not a criterion.** Pinch-to-zoom: the canvas does not handle it, and
zoom is reached from the top bar. Decision 0003 names select, move, resize and
align, so pinch is not part of the 1.0 claim. Adding it later is additive.

## What the tests cannot see

A widget test drives synthetic pointers through the same recognizers a device
does, but it cannot see:

- the platform's own gestures: the iOS edge swipe and the Android back
  gesture;
- real finger contact size and drag speed;
- the software keyboard covering the properties panel;
- the share sheet that printing opens on mobile.

The device pass below is for those.

## The real-device pass

Run the playground on each device, from the repository root:

```bash
cd apps/jet_print_playground
flutter run -d <device-id>   # `flutter devices` lists the ids
```

Open any sample, switch to the designer, and work T1 to T9 in order with a
finger. Then check the four items above that the tests cannot see. A criterion
passes only if it behaves as its row says without a second attempt. Record one
row per device. A failure gets a line under the table naming the criterion and
what happened.

| Date | Device | OS | Commit | T1–T9 | Not seen by tests | By |
|---|---|---|---|---|---|---|
| — | real iOS device | — | — | not yet run | — | — |
| — | real Android device | — | — | not yet run | — | — |

Decision 0003 accepts no simulator or emulator in this table. Those already ran
in June 2026 and are what it calls a memory rather than a gate.

## Run it

```bash
flutter test packages/jet_print/test/designer/canvas/phone_touch_authoring_test.dart
```

## Next

[`08-the-canvas.md`](08-the-canvas.md) for how the canvas hit-tests a press, and
[`roadmap.md`](roadmap.md), P4, for where the device pass stands against the
published `1.0.0`.
