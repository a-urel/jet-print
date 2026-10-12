# 0005 — On iOS and Android, 1.x claims viewing and export; the designer waits for a device pass

**Status:** Accepted — 2026-10-13 (P4)

Supersedes [`0003`](0003-mobile-in-1-0-scope.md).

## Context

[`0003`](0003-mobile-in-1-0-scope.md) claimed all six Flutter platforms for
`1.0.0`, for rendering and export *and* for the interactive designer, and made
the designer half of that claim conditional on three deliverables: named
acceptance criteria for touch authoring, widget tests that check them at phone
width, and a manual pass on a real iOS device and a real Android device. It
also said what to do if P4 did not produce all three: narrow the claim, by a
record that supersedes it, rather than ship it.

Two of the three exist. [`../touch-authoring.md`](../touch-authoring.md) states
nine criteria, T1 to T9, and
`test/designer/canvas/phone_touch_authoring_test.dart` checks each at 390 × 844
with touch pointers, on the macOS, Ubuntu and Windows legs. Both merged with
#118, and writing them found three defects and one gap that no desktop run had
shown: a drag hit-tested about 18 pixels from where the finger went down, a
resize that trailed the finger by about 36, handle targets that covered a small
element's whole body, and no way to multi-select without a shift key.

The third does not exist. The device table at the end of
[`../touch-authoring.md`](../touch-authoring.md) reads *not yet run* for both
rows, and the pass was not run. `1.0.0` was nonetheless published to pub.dev on
2026-10-12 from `da4befd`. What shipped with it claims more than 0003 allowed:

- the package README says, without qualification, "Runs on Android, iOS, web,
  macOS, Windows and Linux";
- the `1.0.0` changelog section says the version "is published only once the
  real-device pass on iOS and Android … is recorded", which is false.

So the condition 0003 provided for has occurred, after the publish rather than
before it.

## Decision

On iOS and Android, `jet_print` 1.x claims what runs without a designer:
`JetReportEngine`, `JetReportExporter` (PDF and PNG), `JetReportPrinter` and
`JetReportPreview`. `JetReportDesigner` and `JetReportWorkspace` are claimed on
macOS, Windows, Linux and the web.

On iOS and Android the designer still builds, runs and ships, and its touch
authoring stays covered by the phone-width tests. It is not claimed: the README
says so on its platform line and under *Platform notes*. A touch defect found
there is still fixed; what the claim no longer does is promise there are none.

The pubspec's `platforms:` block keeps all six. It describes where the package
builds and its claimed surface runs, which is still all six, and
`test/architecture/platform_claim_test.dart` keeps each one built in CI.

Widening the claim again is a new record that supersedes this one and cites a
device table on [`../touch-authoring.md`](../touch-authoring.md) with a passing
row for each platform.

## Consequences

**What is claimed on a phone no longer depends on a finger.** The engine and
the exporter run under both mobile platform overrides in
`test/rendering/export/mobile_render_export_test.dart`. The preview paints the
same recorded frame as every other surface, and its controls are buttons and a
scroll, with no canvas gesture to get wrong. The printer is a seam over
`package:printing`, whose mobile share sheet the README already qualifies. All
of it is built for both platforms in CI. The
designer's mobile behaviour has widget tests, which is real evidence, but [`../touch-authoring.md`](../touch-authoring.md),
*What the tests cannot see*, lists what they miss: the platform's own edge and
back gestures, a real finger's contact size and speed, the software keyboard
over the properties panel, and the share sheet. #118 showed this is not a
theoretical class: every defect it fixed was invisible until a finger-sized
pointer drove the canvas.

**The cost 0003 predicted is now paid, and it is paid in public.** 0003 called
a withdrawn platform claim expensive after `1.0.0`, because a user may have
chosen the package for it. That holds. It is paid as early as it could be, the
day after the publish, and it withdraws a promise, not code: no export, default
or output changes, so under [`0004`](0004-what-1-0-must-settle.md) this is not a
breaking change, and a host running the designer on a phone sees nothing
different.

**The published `1.0.0` text stays wrong until the next release.** pub.dev
serves the README and changelog inside the archive, and a published version
cannot be edited. The repository's README is corrected now; the correction
reaches pub.dev with the next release, whose changelog entry says what was
wrong in `1.0.0`. The `1.0.0` section itself is left as published.

**P4 closes on the narrower claim.** Its exit criterion, `1.0.0` on pub.dev
with all six platforms declared and green, is met; nothing in it is owed any
longer. The device pass becomes the condition for widening, not a debt of
`1.0.0`.

## What this does not decide

- **Nothing is removed.** No API, no platform from the pubspec, no CI leg, no
  test. The touch work is maintained as it is today.
- **When the device pass runs, or who runs it.** The procedure and the table
  stay on [`../touch-authoring.md`](../touch-authoring.md), unchanged.
- **Simulators and emulators.** 0003 accepted none in the device table, and
  this record does not relax that.
- **Tablets, and the print seam's mobile semantics.** Neither was gated by 0003,
  and the share sheet's best-effort cancel result is already documented in the
  package README.
