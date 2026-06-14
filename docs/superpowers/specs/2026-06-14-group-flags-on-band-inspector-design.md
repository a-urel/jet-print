# Editing group flags from the band you see — design note

**Date:** 2026-06-14
**Status:** Proposed
**Relates to:** [2026-06-13-band-model-reification-design.md](2026-06-13-band-model-reification-design.md) (spec 024)

## Problem

Spec 024 reified the band model: a group is now a first-class `GroupLevel`
that owns its header/footer bands and holds the pagination flags
(`keepTogether`, `reprintHeaderOnEachPage`, `startNewPage`) in **one place**.
This fixed a real wart — the old flat model surfaced the same flag on both the
group-header and group-footer band, with no authoritative home.

But the migration moved the *editing affordance* with the data: today those
flags are reachable **only** by selecting the abstract group row (e.g.
`invoice`) in the Outline → Properties shows `_groupInspector`. Selecting the
**Grup Başlığı** (group-header) band — the thing the author actually looks at
on the canvas — shows a height-only `_bandInspector`. So "make this group start
on a new page" now requires hunting for an abstract node instead of clicking the
header you see. That is the intuitiveness regression the reification introduced.

The question raised: *was the old (band-anchored) approach better?* Answer: the
old **data model** was not better (ambiguous dual-flag), but the old **UX
placement** (set it on the header) was more intuitive — and that is
recoverable without reverting the model.

## How the industry does it (model vs. designer UX)

| Engine | Where group identity lives | Where the flags live | In the **designer**, selecting the group band shows the flags? |
|---|---|---|---|
| **JasperReports / Jaspersoft Studio** (OSS reference) | `JRGroup` — named, first-class, owns header/footer | `isStartNewPage`, `isReprintHeaderOnEachPage`, `keepTogether` → **on the group object** | **Yes.** Selecting the group-header band (Outline or Design view) makes the *group's* properties appear in the Properties view. |
| **DevExpress XtraReports** | `GroupHeaderBand.GroupFields` → on the band | `Band.PageBreak` (None/BeforeBand/**AfterBand**), `GroupBand.RepeatEveryPage` → on the band | Yes — they are band properties; the band's property grid shows them. |
| **Crystal / Telerik** | First-class Group object (Group Expert / `Groups`) | "New Page Before/After", keep-together → on the section/band | Yes — set on the section you select. |

Two takeaways:

1. **Spec 024's data model = JasperReports**, the most mature OSS engine. The
   reification was the right call; do **not** revert to band-anchored storage.
2. **Every tool lets you edit the flags by selecting the band you see** — even
   JasperReports, which stores them on a separate group object. The data home
   and the editing affordance are deliberately decoupled. Spec 024 ported the
   data model faithfully but left the editing affordance only on the abstract
   node. We close that gap.

## Decision

Keep the reified `GroupLevel` model unchanged. **Edit the group's key + flags
from the band you see — its group-*header* band** — and remove the standalone
group inspector. The flags still write to the one `GroupLevel` (single source of
truth); we move the editing affordance from the abstract group node to the
header band the author actually looks at, which is the Jaspersoft Studio
behaviour (data home and editing affordance decoupled).

Decided with the user (2026-06-14): **header band only** (the footer shows just
its height), and the **group inspector is removed** (selecting the abstract
group row no longer edits flags).

### Behaviour

- **Group-header band selected** → the band inspector keeps the band's own
  **Height** field, then appends a labelled **"Grup · {name}"** section showing
  the owning group's **key** + the three flag switches (`keepTogether`,
  `reprintHeaderOnEachPage`, `startNewPage`), editing that `GroupLevel`.
- **Group-footer band selected** → **Height only** (no group section), in the
  normal case where the group has a header.
- **Reachability fallback (derived):** `GroupLevel.header` is nullable. So the
  rule is precisely "the group section lives on the group's **header** band, or
  on its **footer** band when the group has no header" — exactly one band per
  group carries it, and the flags are never unreachable. In the common case
  (header present) this is the header, matching the decision; the footer carries
  it only for an otherwise headerless group.
- The owning group is resolved with the existing
  `findGroupOfBand(definition, bandId)` ([band_walker.dart:252](../../packages/jet_print/lib/src/designer/controller/band_walker.dart));
  the carrier check compares the band id against `group.header?.id` (or
  `group.footer?.id` when `group.header == null`).
- **Group-row selection (`selection.groupId`)** → a minimal, read-only summary:
  the **"Grup · {name}"** header plus a one-line hint pointing the author to the
  group-header band for page/group settings. No editable flags here. The old
  flag-editing `_groupInspector` is gone.
- The key + flag widgets are extracted into a shared `_groupSection(groupId)`
  helper, now used only by `_bandInspector` (on the carrier band).

### Out of scope (deliberately)

- **Richer `PageBreak` (Before/After) semantics** à la DevExpress — a single
  `startNewPage` bool covers the common case; revisit only if asked.
- **Group create/delete affordances** in the Outline — a separate gap (the
  controller already has `createGroup`/`deleteGroup`; no UI caller yet). Not
  part of this note.
- Any change to non-group bands' inspectors.

## Impact

- **UI-only.** No change to domain types, serialization, the v1→v2 migration,
  or the renderer. Render goldens are unaffected (no `--update-goldens`).
- **Tests (TDD):**
  - selecting a group-**header** band surfaces the flag switches (keyed
    `groupNewPage`, `groupKeepTogether`, `groupReprintHeader`) + the `groupKey`
    field, and toggling one edits the underlying `GroupLevel`;
  - selecting the group-**footer** band of a group that *has* a header shows
    **height only** (no flag switches);
  - a **headerless** group surfaces the section on its footer (reachability
    fallback);
  - selecting the **group row** shows the read-only summary, **no** flag
    switches.
  - The existing group-inspector test (T025) is rewritten to the header-band
    affordance (the flag-editing `_groupInspector` no longer exists).
- **CHANGELOG:** the spec-024 entry currently reads "Edited via the first-class
  Group inspector"; update it to "edited by selecting the group's header band".
- **l10n:** a new hint string for the group-row summary (en/de/tr).

## Follow-up decisions (2026-06-14, with the user, post-implementation)

Two refinements landed right after the above, in the same TDD pass:

1. **Only `startNewPage` is surfaced in the group section.** `keepTogether` and
   `reprintHeaderOnEachPage` are fully implemented in the layouter and
   golden-tested ([report_layouter.dart](../../packages/jet_print/lib/src/rendering/layout/report_layouter.dart) —
   `keepExtent` and header reprint), but they are **hidden from the UI for now**
   as a minimalism choice (not because they're unimplemented, unlike the
   reserved band types). The controller setters and the `GroupLevel` fields are
   retained, so this is a one-line restore. The group section now shows the
   group key + the *Start on new page* switch only.

2. **The group node is removed from the Outline (Jasper-style).** Jaspersoft
   Studio surfaces a group through its **header/footer bands** (greyed when
   absent), not a separate abstract node — confirmed by their docs. So the
   Outline no longer renders a "Group · {name}" node; a scope shows, in document
   order, its **group headers (outer→inner) → children → group footers
   (inner→outer)**, with each group band sitting directly under the scope. The
   `+addHeader`/`+addFooter` affordances (which lived on the removed node) move
   into the scope's **"+" menu**: *add detail band* / *add a missing group
   header* / *add a missing group footer* (group-named when the scope has more
   than one group). The group-row read-only summary remains as **latent**
   behaviour reachable only programmatically (`selectGroup`), since there is no
   longer a node to select.

   *Note on provenance:* this was **not** mandated by spec 024 — the spec calls
   groups "first-class, addressable entities with their own inspector." Removing
   the node is a **new** decision, consistent with having moved flag-editing onto
   the header band (decision above), which made the abstract node redundant.
