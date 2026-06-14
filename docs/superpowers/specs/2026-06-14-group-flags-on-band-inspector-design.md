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

Keep the reified `GroupLevel` model unchanged. **Surface the owning group's
flags on the band inspector when a group-header or group-footer band is
selected** — the Jaspersoft Studio behaviour. The flags still write to the one
`GroupLevel` (single source of truth); we only add a second, more discoverable
place to edit them.

### Behaviour

- Selecting a band whose type is `groupHeader` or `groupFooter`:
  - the band inspector keeps the band's own **Height** field, then
  - appends a labelled **"Grup · {name}"** section showing the owning group's
    **key** + the three flag switches, editing that `GroupLevel`.
- Both the header and the footer band of a group surface the same section
  (symmetric; matches Jaspersoft Studio — the flags belong to the group, not to
  one band).
- The owning group is resolved with the existing
  `findGroupOfBand(definition, bandId)` ([band_walker.dart:252](../../packages/jet_print/lib/src/designer/controller/band_walker.dart)).
- The standalone group inspector (select the group row → `_groupInspector`) is
  **retained** as a second entry point. Redundant editing paths are fine and
  also match the reference tools.
- The key + flag widgets are extracted into a shared `_groupSection(groupId)`
  helper used by both `_groupInspector` and `_bandInspector`. Because the
  selection is always *either* a band *or* a group (never both at once), the
  existing `ValueKey`s (`groupKey`, `groupKeepTogether`, `groupReprintHeader`,
  `groupNewPage`) can be reused without collision.

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
- **Tests (TDD):** a widget test asserting that selecting a group-header band
  surfaces the group flag switches (keyed `groupNewPage` etc.) and that toggling
  one edits the underlying `GroupLevel`; a parallel check for the footer band.
  The existing `_groupInspector` test stays green.
