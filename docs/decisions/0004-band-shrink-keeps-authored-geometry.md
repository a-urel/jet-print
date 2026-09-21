# 0004 — A band shrink keeps authored element geometry

**Status:** Accepted — 2026-09-21 — phase P3

Rules on issue #32, *Shrinking a band leaves its elements outside it (no
re-clamp on band resize)*.

## Context

Shrinking a band below the bottom edge of one of its elements leaves that
element's band-relative bounds unchanged, so the element hangs past the band's
new bottom until some element-geometry command re-clamps it. The issue's account
of the code path is accurate, and was verified end to end before this record.

`_bandHandle` in `designer/canvas/selection_overlay.dart` drives the drag; its
`onPanEnd` and `onLongPressEnd` call `commitBandResize`. `updateBandResize` in
`designer/controller/api/resize.dart` applies one clamp to the live preview —
`kMinBandHeight` from `designer/canvas/design_tunables.dart`, 8 pt as of this
date — to the band's own height. `commitBandResize` hands that preview to
`_applyBandHeight` in `designer/controller/jet_report_designer_controller.dart`,
which re-applies the same floor and commits `SetBandHeightCommand`. That
command's `apply` is `b.copyWith(height: height)` and never touches
`band.elements`. Nothing on the path reaches `clampToBand`, `clampResizeToBand`
or `_commitBounds`. The numeric path is the same code: `setBandHeight` in
`designer/controller/api/bands.dart` routes through `_applyBandHeight` too.

The gap is already written down twice, which is why it reads as an oversight but
is not one. The library doc of `designer/controller/element_bounds.dart` states
that the containment guarantee is scoped to commands that move an *element*,
that changing a *band* is not one, and that shrinking a band can leave an
element hanging past its new bottom. The comment above `rectFor` in
`selection_overlay.dart` repeats it for the selection chrome. What is missing is
not the knowledge but a decision and a test.

Two facts found in the code bear on the ruling and are not in the issue.

**The layouter does not clip an element to its band.** `_place` in
`rendering/layout/report_layouter.dart` translates a band-relative rect to the
page by adding the band's origin and emits it at that rectangle; there is no
band clip anywhere in the frame or paint path. The consequence of a shrink is
therefore that the element *over-prints the band below it*, not that it
disappears — a visible wrong-output condition, which argues for putting it in
front of the author rather than hiding it.

**The model already permits the state by other routes.** A loaded definition, an
undo/redo replay and a programmatic `setBandHeight` all reach an out-of-bounds
element with no drag involved. Whatever the gesture does, the engine must
tolerate the state.

The model also already has the right mechanism. `validate` in
`domain/report_validation.dart` returns non-throwing `Diagnostic`s for
invariants I1–I8 and is exposed to the designer as the `diagnostics` getter on
`JetReportDesignerController`, recomputed on read so the designer can surface
problems live while holding a transient invalid state. There is a direct
precedent for a *geometry* diagnostic there: `_validateColumns` already warns,
per element, when an element overflows its column cell and will be clipped. And
there is a precedent for presenting one: `_columnDiagnostics` in
`designer/layout/panels/properties_panel.dart` is derived from the same geometry
`validate` checks but localized and de-duplicated, rendered through the existing
`_InlineWarning` and `_UnresolvedHint` rows in `_columnLayoutSection`.

One caveat, verified: the `diagnostics` getter has no consumer anywhere under
`packages/jet_print/lib/src/designer/`. A `validate` entry alone would change
nothing an author can see.

**The principle.** A report definition is a user's authored document, and a
resize gesture must not silently destroy authored content. Geometry an author
placed deliberately is content; the band height is one property of the
container, and changing it is not consent to rewrite everything inside it.

The issue offers three options: accept and document; clamp on commit via
`clampToBand`, at the cost of the original layout on a later grow and of storing
the full element set in the command; or block the drag at the lowest element's
bottom edge, which is non-destructive but demands the elements move first. The
issue's author prefers the third for drags and the first for commands.

## Decision

Take the first option as the contract, and pay for the gap with a diagnostic.

`SetBandHeightCommand` stays a single-field change: a band resize, dragged or
programmatic, never rewrites element bounds, and the out-of-bounds state is a
permitted, representable, round-trippable state of the model. `validate` gains
invariant **I9, element containment** — a warning per element whose bounds
extend past its band's height or past `bandContentWidth`, carrying its
`elementId`, in document order, worded to say the element will print over the
band below. `_bandInspector` surfaces it the way `_columnLayoutSection` surfaces
column overflow: one localized, de-duplicated `_InlineWarning` for the selected
band, next to the height field that caused it. The drag is not blocked and the
preview is not re-clamped; `kMinBandHeight` remains the only floor. Estimated at
**2 days**.

**Clamping on commit was rejected** because it destroys authored geometry
irreversibly by the gesture that caused it. `clampToBand` shrinks an oversized
rect and nothing remembers what it was, so shrink-then-grow leaves the elements
squashed at the top for good, and a drag eight pixels too far is exactly the
case an author does not notice. It also breaks the shape `SetBandHeightCommand`
documents for itself — a band has only a height, so a band resize is a
single-field change — by requiring the command to carry every element so redo
reproduces it.

**Blocking the drag was rejected** for a weaker but sufficient reason: it buys
no invariant. The out-of-bounds state stays reachable from deserialization, undo
and `setBandHeight`, so no other code may assume containment and the tolerant
behaviour is needed anyway. All the option removes is the ordinary "shrink the
band, then tidy the elements into it" order of work, with no explanation at the
moment the drag stops moving. Splitting it — blocking drags but not commands —
would make the properties panel's own height field reach heights the divider
handle cannot, for no stated benefit. The cited analogy to element edge-pinning
does not carry: there one element is resized against a container that is not
moving, and here the container is the thing being resized, against many
elements at once.

## Consequences

The model gains a valid-but-flagged state. This matches how `validate` already
treats column overflow and the I7 representable-but-not-yet-rendered shapes, so
it adds no new category.

A shrink-then-grow cycle is lossless. That is the main thing clamping would have
cost, and it is worth stating plainly.

Authors can produce a report that over-prints, and will be told at author time
rather than at print time. Nothing forces them to fix it — deliberately; the
definition is theirs.

The `diagnostics` getter gets its first in-designer consumer, so the panel row
is part of this change and not a follow-up. Later work on a general problems
surface should fold the band inspector's row into it rather than grow a second
path.

Hosts calling `validate` will see new warnings on definitions that previously
validated clean. No engine behaviour changes, but the diagnostic output does,
and that belongs in the release notes.

The prose in `element_bounds.dart` and `selection_overlay.dart` becomes the
statement of an intended contract rather than the note of a gap, and should be
reworded to point at I9 and at this record.

## What this does not decide

Whether the designer gets a general problems panel, and whether `validate`'s
developer-facing strings are ever localized wholesale rather than mirrored
per-inspector as `_columnDiagnostics` does today.

## Acceptance

Issue #32 is not closed until these tests exist and pass.

- `test/designer/controller/band_selection_resize_test.dart` — shrinking a band
  below an element's bottom leaves that element's bounds unchanged, asserted for
  both entry points: `setBandHeight`, and the `beginBandResize` /
  `updateBandResize` / `commitBandResize` sequence.
- The same file — a shrink-then-grow cycle returns the band to its original
  height with every element's bounds unchanged.
- `test/designer/controller/clamp_semantics_test.dart` — a case asserting
  `SetBandHeightCommand.apply` alters no element bounds, beside the existing
  move/resize cases that pin the clamp split.
- `test/domain/report_validation_test.dart` — I9 emits one warning per
  overflowing element, in document order, each carrying the right `elementId`;
  emits nothing when every element fits; fires on horizontal overflow as well as
  vertical.
- `test/designer/author_time_validation_test.dart` — `diagnostics` reports the
  overflow immediately after a band shrink and stops reporting it after an undo.
- A band-inspector widget test, beside the existing height-field coverage in
  `test/designer/properties_editor_test.dart` — a band with one or more
  overflowing elements renders exactly one warning row; a clean band renders
  none.
- `test/designer/localization_de_test.dart` and
  `test/designer/localization_tr_test.dart` — the new string resolves in `de`
  and `tr`.
- `test/rendering/layout/report_layouter_test.dart` — an element whose bounds
  extend past its band's height is emitted at its band-relative offset and is
  not clipped, pinning the over-printing behaviour this record's reasoning
  depends on.
