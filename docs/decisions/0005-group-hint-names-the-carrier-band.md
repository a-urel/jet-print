# 0005 — The group hint names the band that actually carries the settings

**Status:** Accepted — 2026-09-21 — phase P3

Rules on issue #35, *Group hint points at a header band that may not exist
(footer-only groups)*.

## Context

Selecting a group row in the outline shows a read-only summary whose hint sends
the author to edit the group's settings "on the group header band". When the
group has no header band, that band does not exist and the hint names nothing
the author can click.

The code matches the issue's account. `_groupInspector` in
`designer/layout/panels/properties_panel.dart` renders
`l10n.propertiesGroupOnHeaderHint` unconditionally; it takes a group id and
never looks at which band carries the section. The carrier is chosen twice
elsewhere in the same file with the same fallback, `group.header?.id ??
group.footer?.id` — once where `_bandInspector` decides whether to append
`_groupSection`, and once in the outline path. The comment above that branch
states the intent: the settings live on the group's header band, or its footer
when the group has no header, so the section is never unreachable — a design
note dated 2026-06-14.

The string is `propertiesGroupOnHeaderHint`, present in all three locale files
under `designer/l10n/`: `jet_print_en.arb` ("Edit page & group settings on the
group header band."), `jet_print_de.arb` ("Seiten- und Gruppeneinstellungen am
Gruppenkopf-Band bearbeiten.") and `jet_print_tr.arb` ("Sayfa ve grup ayarlarını
grup başlığı bandında düzenleyin."), with the generated accessors in the
matching `jet_print_localizations_*.dart` files.

The issue's account of the test gap is also correct.
`test/designer/group_inspector_test.dart` carries a `_footerOnly` fixture and
asserts which band carries the flags — with no header, the footer carries them
so they stay reachable — but never reads the hint text. The two halves were free
to drift.

Two findings qualify the issue's framing.

**The fallback is not unmentioned — it is documented in the very entry whose
value contradicts it.** The `@propertiesGroupOnHeaderHint` description in
`jet_print_en.arb` already says the hint points at "the group's CARRIER band —
its header, or its footer when the group has no header". The developer-facing
metadata and the user-facing value disagree inside one file: PR #33 corrected
the descriptions and the surrounding comments, and the value was left behind.
That settles what the intended meaning is — the string is wrong against its own
spec, not ambiguous.

**There is a third case the issue does not consider: a group with neither
band.** `GroupLevel.header` and `GroupLevel.footer` are both nullable, and
`validate` requires neither — it slot-checks them only when non-null. A bandless
group is representable, valid, and reachable from the designer's own API:
`createGroup` in `designer/controller/api/groups_scopes.dart` constructs a
`GroupLevel` with no bands at all, and `removeBandFromTree` in
`designer/controller/band_walker.dart` clears a slot while keeping its owner, so
deleting a header-only group's header leaves the group behind. In that state the
carrier expression is null, *no* band carries the section, and the hint sends
the author to a band that does not exist and that nothing in the panel will
create. The `createGroupBoundToField` path always makes a header, so the common
route is safe, but the bad state is one `removeBand` away.

This is a product question, not a string fix: what the hint should say
determines how many keys there are.

The issue offers three options — two carrier-specific strings selected
conditionally, most precise but one new key across three languages;
carrier-neutral phrasing naming both bands, minimal localization work but less
helpful in the common case; or interpolating the actual band name or type, most
informative but needing a placeholder in all three ARBs.

**The cost difference is small, and that is what decides it.** German and
Turkish need re-translation either way. Carrier-neutral phrasing rewrites the
value in all three locales, so `de` and `tr` go back to a translator;
carrier-specific strings rewrite one value and add one key, so `de` and `tr` go
back to a translator with two short strings instead of one. The difference is a
single sentence per locale. Neither option is cheap enough to win on cost nor
expensive enough to lose on it, so correctness should decide.

## Decision

Two carrier-specific strings, chosen from the carrier the panel already
computes — plus a third for the bandless case.

`_groupInspector` takes the group's carrier, the same `group.header?.id ??
group.footer?.id` the rest of the panel uses, and selects the hint from it.
There are three states, so there are three strings: `propertiesGroupOnHeaderHint`
keeps its key and its current English value for the common case; a new
`propertiesGroupOnFooterHint` names the group footer band; and a new
`propertiesGroupNoBandHint` says the group has no header or footer band yet and
that adding one makes the settings editable. The third is the honest reading of
the code and costs one more short string in the same round trip to the
translator. Every variant uses the vocabulary the band labels already use —
`bandTypeGroupHeader` and `bandTypeGroupFooter`, resolved through `bandTypeLabel`
in `designer/l10n/band_type_label.dart` — so the hint and the band it points at
agree on what that band is called. The `@propertiesGroupOnHeaderHint`
description is corrected to describe the header-only meaning it now has, since
the carrier-band explanation moves into the new keys. Estimated at **1 day**.

**Carrier-neutral phrasing was rejected** because it is correct in every case
and helpful in none. "The group's header or footer band" makes the author check
which of the two exists — work the panel has already done and is refusing to
share. It is a worse hint than today's for the common case in exchange for being
merely not-wrong in the uncommon one, and the translation saving that was its
only advantage turns out not to exist.

**Interpolating the band was rejected** as more machinery for no more
information. The carrier states are known statically, so a placeholder buys
nothing a fixed string does not already say; interpolating the band *type*
reproduces this decision through an ICU placeholder in three ARBs. Interpolating
the band *name* is worse, because names are author-editable through `renameBand`
— a hint reading "Regional summary" tells an author less about where to click
than "group footer band" does, and the unnamed-band fallback would be the type
label anyway. Keep it for a hint that genuinely needs to name a specific object.

## Consequences

Two new localization keys and one changed description, across three ARB files
and their generated accessors. The `de` and `tr` values must come from a
translator; they are not to be machine-translated into the ARBs.

The hint becomes a function of the model rather than a constant, so
`_groupInspector` needs the group's bands and not just its id. It already
receives the controller, so no signature change reaches the caller.

The bandless case is now named in the UI. A state the designer can produce but
the panel previously papered over becomes visible to authors, which may read as
a new problem; it is an existing one surfacing.

Nothing in the model, the commands or the render path changes. This is a
panel-and-strings change, fully covered by widget and localization tests.

`group_inspector_test.dart` becomes the place where the hint and the carrier are
asserted together, which is what stops this drifting again.

## What this does not decide

Whether a bandless group should be creatable at all — whether `createGroup`
should be withdrawn in favour of `createGroupBoundToField`, or `validate` should
warn on a group with no bands. Either would be a model change and wants its own
record; this one only stops the panel lying about the state.

## Acceptance

Issue #35 is not closed until these tests exist and pass.

- `test/designer/group_inspector_test.dart` — with the existing both-bands
  fixture the group row shows the header hint; with the `_footerOnly` fixture it
  shows the footer hint; with a new bands-free fixture it shows the no-band
  hint.
- The same file — a test tying the hint to the carrier the panel computes rather
  than to the fixture shape: for each fixture, the band named by `group.header?.id
  ?? group.footer?.id` and the hint variant on screen agree. This is the
  regression guard the issue is really asking for.
- `test/designer/localization_de_test.dart` and
  `test/designer/localization_tr_test.dart` — all three hint keys resolve in
  `de` and `tr`, with no fallback to English.
- A key-parity assertion that the two new keys exist in `jet_print_en.arb`,
  `jet_print_de.arb` and `jet_print_tr.arb` with an `@` description on the
  English entries. `test/architecture/documented_claims_test.dart` already walks
  the `.arb` files and is the natural home for it.
- A test that a group with neither band renders no editable group section
  anywhere in the panel, pairing with the new hint so the two statements about
  that state cannot diverge.
