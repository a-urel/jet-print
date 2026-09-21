# 0003 — Full mobile support, including the designer, is in 1.0 scope

**Status:** Accepted — 2026-09-21

## Context

E5 made the designer usable with a finger, over four commits on 2026-06-21: the
canvas tracks the active pointer kind (`821900fa`), resize handles and
scrollbars grow to finger size under touch (`de7efec6`), a long press opens the
context menu that a right-click opens on desktop (`748590f6`), and the shell's
minimum width dropped to 360 so a ~390pt phone lays out in the real narrow rail
layout rather than a horizontally scrolling desktop shell (`2251bf38`). CI grew
an iOS job and an Android job the same day (`721c97ff`).
`packages/jet_print/README.md`'s *Platform support* table has listed all six
targets since.

That is genuine work, and it is not the same thing as verification. What the
mobile legs of `.github/workflows/ci.yml` actually run is this:

```yaml
  android:
    name: android (apk)
    ...
      - name: Build the playground APK
        working-directory: apps/jet_print_playground
        run: flutter build apk --debug
```

The `ios` job has the same shape, ending in `flutter build ios --debug
--no-codesign`. Neither job has a test step at all. A build job proves the
native plugin toolchain links for that OS — which is worth having, and is
exactly what the README's table claims for those two rows ("APK build", "app
build (no codesign)"). It proves nothing about whether a gesture does the right
thing. The test suite runs on the macOS, Ubuntu and Windows legs and on the
Chrome leg; none of those is a phone.

The automated coverage that touches this at all, in full:

- `test/designer/phone_width_layout_test.dart` — one test. At 390 × 844 it
  asserts that the horizontal-scroll fallback shell is absent and the collapsed
  right-panel rail is present. No gesture is performed.
- `test/designer/canvas/long_press_menu_test.dart` — two tests, both at the
  default test surface rather than at phone width. A long press on an element
  opens the context menu (under a macOS platform override, because on mobile
  `ShadContextMenuRegion` enables long-press by default and the desktop case was
  the one at risk); and a press-hold-drag on the `bottomRight` handle enlarges
  the element instead of opening the menu, the handle owning the long press as
  the deepest detector.
- `test/rendering/export/mobile_render_export_test.dart` — render plus PDF and
  PNG export succeed under an iOS/Android platform override. Headless; no
  designer involved.

Read together: one touch-kind drag is covered, on one handle, at desktop size.
Nothing drives select, move or align by touch. Nothing drives any gesture at a
phone-sized viewport. The two facts the phone-width test and the long-press
tests each establish are never established *at the same time*.

There was manual verification. E5 ran three rounds of simulator and emulator
smoke (`d86c194e`, `99ad280f`, `f94cf7a4`), each of which caught and fixed real
issues — touch canvas pan and handle resize among them (`2b9eccb3`). Two things
to be honest about: those were simulators and emulators, not devices, and the
checklist that recorded them lived in `docs/superpowers/`, which
[`../workflow.md`](../workflow.md) makes working-document space, and is no
longer in the tree. A one-off manual pass whose record has been deleted is not a
gate; it is a memory.

## Decision

`1.0.0` claims all six Flutter platforms — macOS, Windows, Linux, web, iOS and
Android — for both rendering/export and the interactive designer.

## Consequences

**A designer built for a mouse is being promised on a phone, and nothing
currently verifies the promise.** That is the point of this record, so it is
stated without hedging. The interaction model was designed around a cursor with
hover, a right button and pixel-accurate positioning; the touch affordances are
adaptations of it. They have been smoke-tested by one person on simulators once,
three months ago, and the record of that pass no longer exists. Between then and
`1.0.0` the claim rests on nothing that runs.

**P4 must close that gap before the claim ships.** Three deliverables, all of
which must exist and pass:

1. **Named acceptance criteria for touch authoring**, written down before the
   tests are: for each of select, move, resize and align, at a phone-sized
   viewport, what a finger does and what must result — including the ones that
   are easy to get wrong, such as which gesture pans the canvas versus drags an
   element, what a long press does on an element against on empty canvas, and
   what the minimum hit target is for a resize handle.
2. **A widget-test or golden pass at phone width covering those gestures.**
   Phone-sized viewport, `PointerDeviceKind.touch`, driving select, move, resize
   and align end to end and asserting against the definition the controller
   produces — the combination that neither `phone_width_layout_test.dart` nor
   `long_press_menu_test.dart` covers today. It runs in the suite, on every
   push, on a leg that already runs tests.
3. **A manual pass on a real iOS device and a real Android device**, against the
   criteria from (1), recorded somewhere that is not git-ignored.

**If P4 does not produce all three, the honest move is to narrow the claim, not
to ship it.** See the alternative below.

**What it buys, if the work lands.** A report designer that is genuinely usable
on a tablet and survivable on a phone is a differentiator; almost nothing in
this category offers one. The library's own shape supports it — the core is pure
Dart and the rendering path carries no platform dependency, so the engine side
of the claim is cheap and already exercised headlessly under both platform
overrides.

**What it costs if it goes wrong.** A platform claim is the kind of promise that
is expensive to withdraw after `1.0.0`: dropping "supports iOS and Android" from
a published `1.x` is a breaking change to what users chose the package for, in a
way that dropping an export is not.

## The alternative, recorded so it can be chosen deliberately

**Narrow the claim to viewer-and-export on mobile.** `1.0.0` would promise
`JetReportEngine`, `JetReportExporter`, `JetReportPrinter` and
`JetReportPreview` on iOS and Android — all of which the headless mobile export
test already exercises under a platform override — and scope `JetReportDesigner`
to desktop and web. The README's *Platform support* table would say so per row,
rather than implying the whole library everywhere.

This is the fallback if P4's three deliverables are not met. It is a smaller
claim that is entirely true, which is better than a larger one that is partly
unverified, and it can be widened later by a minor release without breaking
anything.

Choosing it means **superseding this record** with a `0004` that says the
criteria were not met and states the narrower scope. It does not mean quietly
softening the README, or letting the claim erode into "well, it builds". If the
decision changes, the change is written down.

## What this does not decide

- **Not the designer's interaction model.** Whether touch authoring eventually
  needs its own gesture vocabulary rather than adapted desktop gestures is an
  open design question; this record only requires that whatever exists be
  verified.
- **Not tablet against phone.** The acceptance criteria are written at phone
  width because it is the hard case; a tablet is not separately gated.
- **Not the print seam's mobile semantics.** On iOS and Android the `printing`
  dependency presents the OS share sheet, and a user dismissal there may report
  as success — a known, documented behaviour, unchanged by this record.
- **Not CI's shape.** Whether the mobile legs eventually run tests, and on what,
  is P4's to decide; this record requires that the phone-width gesture tests run
  somewhere in CI, not that they run on an emulator.
