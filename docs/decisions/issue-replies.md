# Issue replies

Ready-to-post comments for the two issues ruled on in
[`0004`](0004-band-shrink-keeps-authored-geometry.md) and
[`0005`](0005-group-hint-names-the-carrier-band.md). Paste the body of each
section, below its rule, straight into the issue thread.

---

## Issue #32

Ruling: option 1, with the gap paid for by a diagnostic rather than by a clamp.
A band resize keeps element geometry exactly as authored, `SetBandHeightCommand`
stays a single-field change, and the resulting out-of-bounds state is detected
and shown to the author instead of being quietly repaired or prevented.

The principle behind it is that a report definition is a user's authored
document, and a resize gesture must not silently destroy authored content. That
rules out clamping on commit: `clampToBand` shrinks an oversized rect and
nothing remembers what it was, so shrink-then-grow loses the layout for good,
and a drag eight pixels too far is exactly the case nobody notices. Blocking the
drag destroys nothing, but it buys no invariant — the out-of-bounds state is
already reachable from a loaded definition, from an undo/redo replay and from
`setBandHeight`, so the engine has to tolerate it whatever the divider handle
does; all the option removes is the ordinary "shrink the band, then tidy the
elements into it" order of work, and splitting it between drags and commands
would let the properties panel's height field reach heights the handle cannot.
Two things in the code settle it. `_place` in `report_layouter.dart` offsets a
band-relative rect onto the page with no band clip anywhere in the frame or
paint path, so the real consequence of a shrink is that the element over-prints
the band below — a visible wrong-output condition that belongs in front of the
author. And the model already has the mechanism: `validate` is surfaced as the
controller's `diagnostics` getter, and `_validateColumns` already warns per
element when an element overflows a column cell, so band containment is the same
shape of thing rather than a new category.

The work is to add invariant I9 to `validate` — a warning per element whose
bounds extend past its band's height or past `bandContentWidth`, carrying its
`elementId` — and to surface it in `_bandInspector` as one de-duplicated,
localized row, following `_columnDiagnostics` and the `_InlineWarning` rendering
in `_columnLayoutSection`. Worth flagging: the `diagnostics` getter currently
has no consumer anywhere under `lib/src/designer/`, so the panel row is part of
this change and not a follow-up — a `validate` entry on its own would change
nothing an author can see. Also worth noting that the gap is already documented,
in the library doc of `element_bounds.dart` and in the chrome comment in
`selection_overlay.dart`; that prose should be reworded to state an intended
contract and point at I9.

Estimated at 2 days, phase P3. Not closed until:

- Shrinking a band below an element's bottom leaves that element's bounds
  unchanged, asserted for both `setBandHeight` and the
  `beginBandResize`/`updateBandResize`/`commitBandResize` sequence
  (`band_selection_resize_test.dart`).
- A shrink-then-grow cycle restores the original height with every element's
  bounds unchanged.
- A case in `clamp_semantics_test.dart` asserting `SetBandHeightCommand.apply`
  alters no element bounds, beside the existing move/resize cases.
- I9 in `report_validation_test.dart`: one warning per overflowing element, in
  document order, with the right `elementId`; nothing when all elements fit;
  fires on horizontal overflow too.
- `diagnostics` reports the overflow after a shrink and stops after an undo
  (`author_time_validation_test.dart`).
- A band-inspector widget test: one warning row for a band with overflowing
  elements, none for a clean band.
- The new string resolves in `de` and `tr` (`localization_de_test.dart`,
  `localization_tr_test.dart`).
- A layouter test pinning that an element past its band's bottom is emitted at
  its band-relative offset and is not clipped, so the over-printing behaviour
  this ruling rests on cannot change by accident.

---

## Issue #35

Ruling: option 1, two carrier-specific strings — plus a third for a case the
issue does not cover. `_groupInspector` will select the hint from the carrier
the panel already computes, `group.header?.id ?? group.footer?.id`, rather than
stating one unconditionally.

The translation cost is what makes this easy to decide. German and Turkish need
re-translation either way — carrier-neutral phrasing rewrites the value in all
three locales, carrier-specific strings rewrite one and add one — so the
difference is a single sentence per locale, and correctness should decide
instead of cost. On correctness the neutral phrasing loses: "the group's header
or footer band" is never wrong and never helpful, and it makes the author check
which band exists when the panel already knows. Interpolating the band is more
machinery for no more information, since the carrier states are known
statically; interpolating the *type* is option 1 through an ICU placeholder, and
interpolating the *name* is worse, because names are author-editable through
`renameBand` and a hint reading "Regional summary" tells an author less about
where to click than "group footer band" does.

Two corrections to the issue text. First, the fallback is not unmentioned — the
`@propertiesGroupOnHeaderHint` description in `jet_print_en.arb` already says
the hint points at "the group's CARRIER band — its header, or its footer when
the group has no header". The developer-facing metadata and the user-facing
value disagree inside one file, which looks like PR #33's correction landing on
the description and not on the string; that settles the intent, so this is a
string that is wrong against its own spec rather than an open question. Second,
and more importantly, there is a third state the issue does not consider.
`GroupLevel.header` and `GroupLevel.footer` are both nullable, `validate`
requires neither, and a bandless group is reachable from the designer's own API:
`createGroup` in `groups_scopes.dart` builds one with no bands, and
`removeBandFromTree` clears a slot while keeping its owner, so deleting a
header-only group's header leaves one behind. In that state the carrier is null,
*no* band carries the section, and the hint sends the author to a band that does
not exist and that the panel will not create. So the change is three strings,
not two: keep `propertiesGroupOnHeaderHint` for the common case, add
`propertiesGroupOnFooterHint`, and add `propertiesGroupNoBandHint`. The wording
should reuse the existing `bandTypeGroupHeader` and `bandTypeGroupFooter`
vocabulary so the hint and the band label agree.

Estimated at 1 day, phase P3. Not closed until:

- `group_inspector_test.dart` asserts the hint for all three fixtures: both
  bands present shows the header hint, the existing `_footerOnly` fixture shows
  the footer hint, and a new bands-free fixture shows the no-band hint.
- A test tying the hint to the carrier the panel computes rather than to the
  fixture shape — for each fixture, `group.header?.id ?? group.footer?.id` and
  the hint variant on screen agree. This is the guard that stops the two
  drifting again, which is what let the bug through.
- All three keys resolve in `de` and `tr` with no English fallback
  (`localization_de_test.dart`, `localization_tr_test.dart`).
- A key-parity assertion that the new keys exist in all three ARBs with an `@`
  description on the English entries; `documented_claims_test.dart` already
  walks the `.arb` files and is the natural home for it.
- A test that a group with neither band renders no editable group section
  anywhere in the panel, so that statement and the new hint cannot diverge.
- The `de` and `tr` values come from a translator, not from machine translation
  in the ARBs.
