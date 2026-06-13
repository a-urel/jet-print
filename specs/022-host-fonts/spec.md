# Feature Specification: Host & System Fonts in Font Pickers

**Feature Branch**: `022-host-fonts`
**Created**: 2026-06-13
**Status**: Draft
**Input**: User description: "list system/host fonts in font pickers"

## Context & Motivation

The report designer already lets a user choose a font family for a text element from a
picker, and whatever family is chosen renders identically on the design canvas, in print
preview, and in exported documents (spec 021). Today, however, that picker only ever lists
the **three fonts bundled with the library** (the built-in sans, serif, and mono families).
There is no supported way for the application that embeds the report designer (the **host
application** — e.g. an invoicing product, a label-printing tool) to make *its own* brand or
document fonts selectable. Designers are therefore stuck formatting reports in fonts that may
not match the rest of the host product or the customer's brand.

This feature gives the host application a supported way to contribute fonts to the report
engine so they appear in **every** font picker in the designer and render with full fidelity
everywhere a report is shown or produced. A secondary, optional capability lets the host
surface fonts already installed on the end user's operating system, with the portability
trade-offs that entails.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Host application contributes its own fonts (Priority: P1)

The team building a host product registers their brand/document fonts with the report engine
once, at startup. From then on, every designer running inside that product lists those font
families in the text font-family picker — previewed in their own typeface — alongside the
built-in families. A report designer picks one, and the text renders in that font on the
canvas, in preview, and in every exported PDF/PNG, byte-for-byte the same.

**Why this priority**: This is the core of the request and the only part that is
architecturally safe by construction: the same registered font data drives measurement and
every render path, so picking a host font can never break the design-equals-output guarantee.
It is independently valuable and shippable on its own — without it, the picker is limited to
three fonts forever. Everything else in this feature builds on this capability.

**Independent Test**: Register one additional font family with the engine, open the designer,
confirm the family appears in the font-family picker previewed in its own typeface, apply it
to a text element, and confirm the rendered glyphs are identical across canvas, preview, and a
PDF/PNG export.

**Acceptance Scenarios**:

1. **Given** the host has registered a font family "Acme Brand" before the designer is shown,
   **When** a designer opens the font-family picker for a selected text element, **Then**
   "Acme Brand" appears in the list, previewed in its own typeface, alongside the built-in
   families.
2. **Given** "Acme Brand" is registered, **When** a designer applies it to a text element,
   **Then** the canvas re-renders the text in that font immediately and the choice persists in
   the saved report.
3. **Given** a text element uses "Acme Brand", **When** the report is shown in print preview
   and exported to PDF and PNG, **Then** the text appears in "Acme Brand" identically in all
   three, and the exported PDF contains the font so the text stays selectable/searchable.
4. **Given** the host registers a family providing only a regular face, **When** a designer
   applies bold or italic to text in that family, **Then** the system renders the closest
   available face following the existing fallback rules, without error.
5. **Given** the host has registered several families, **When** any font-family picker in the
   designer is opened, **Then** all registered families are listed (not only the built-in
   three), in a stable, predictable order.

---

### User Story 2 - Reports stay readable when a font is not registered (Priority: P2)

A report authored in one session (where "Acme Brand" was registered) is later opened in a
session where that font is **not** registered — a different machine, a viewer that did not
register the same fonts, or an exported template shared with a third party. The report still
opens, the missing font's name is preserved and shown as unavailable in the picker (never
silently swapped), and the text renders in a fallback font without data loss.

**Why this priority**: Host-registered fonts are contributed at runtime, so any given session
may not have the same set. Reports must never become unreadable or silently re-styled because a
font is absent. This extends the existing "unavailable family" behavior (spec 021) to cover
host-contributed fonts and is essential for portability, but it is a graceful-degradation
guarantee rather than the headline capability, so it is P2.

**Independent Test**: Author a report using a registered font, then load that report in a
session where the font is not registered; confirm it opens without error, the stored family
name is shown as unavailable in the picker, the value is preserved on save, and the text
renders in a fallback font.

**Acceptance Scenarios**:

1. **Given** a report whose text uses "Acme Brand", **When** it is opened where "Acme Brand"
   is not registered, **Then** the report opens without error and the text renders in a
   fallback font.
2. **Given** such a report is open, **When** the designer inspects the text's font-family
   picker, **Then** the stored name "Acme Brand" is shown and marked as unavailable, and it is
   preserved if the report is saved without changing the family.
3. **Given** such a report is exported, **When** the export is produced, **Then** it succeeds
   using the fallback font and does not fail or block on the missing font.

---

> **Operating-system ("system") font discovery is deferred to a future feature** — see the
> "Resolved Scope Decision" section below. This feature delivers User Stories 1–2 (the
> host-registration core). The requirements are written so that a later OS-font feature can
> layer on without rework: the unavailable-font handling (User Story 2) already covers any
> font that is not present in a session, OS-sourced or otherwise.

### Edge Cases

- **Duplicate registration**: The host registers a family name that already exists (a built-in
  name, or the same custom name twice). The system MUST resolve this deterministically (last
  registration wins for that family/face, or first wins) — see FR-009 — and never end up with
  an ambiguous or doubled picker entry.
- **Partial faces**: A family is registered with some faces missing (e.g. regular + bold but no
  italic). Applying a missing face falls back per existing rules; the picker still lists the
  family once.
- **Invalid or empty font data**: The host attempts to register a family with unreadable or
  empty font data. The system MUST reject that registration in a way the host can detect,
  without corrupting the picker or crashing the designer.
- **Registration after the designer is already shown**: Fonts are registered (or an OS-font
  option toggled) while a designer is already on screen. The behavior MUST be defined — either
  pickers reflect the change, or the documented contract is that registration happens before
  the designer is built.
- **Empty registration set**: The host registers nothing. The picker still lists the built-in
  families and works exactly as today.
- **Very large font sets** (relevant to User Story 3): An OS exposes hundreds of font families.
  The picker MUST remain usable (e.g. scannable/scrollable, not visibly degraded).
- **Report shared as a template file**: A saved report carries the font *name* it references,
  not the font itself. Re-opening it elsewhere relies on that font being registered/available
  there; otherwise User Story 2 applies. (Exported PDFs embed the faces they use and are
  unaffected.)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a supported, documented way for a host application to
  register one or more named font families with the report engine, supplying the font data for
  each family's faces (at minimum a regular face; optionally bold, italic, and bold-italic).
- **FR-002**: Registered font families MUST appear in every font-family picker in the designer,
  listed alongside the built-in families and previewed in their own typeface where possible.
- **FR-003**: A font family applied to a text element MUST render identically on the design
  canvas, in print preview, and in exported output (the design-equals-output guarantee), for
  host-registered fonts exactly as for built-in fonts — driven by the same registered font data
  with no separate or divergent font handling per path.
- **FR-004**: Exported documents that use a registered font MUST embed that font so the text
  remains real, selectable/searchable text (not an image), consistent with existing export
  behavior, embedding each used face once per document.
- **FR-005**: When a text element's font requires a face the registered family does not provide
  (e.g. italic of a regular-only family), the system MUST fall back per the existing variant
  rules without error and without losing the stored family choice.
- **FR-006**: Registration MUST be additive — host fonts supplement, never remove, the built-in
  families; the built-in default family MUST always remain available as the ultimate fallback.
- **FR-007**: When a report references a font family that is not available in the current
  session, the system MUST preserve the stored family name, show it in the picker marked as
  unavailable, render the text in a fallback font, and keep the stored value intact on save —
  for host-registered and OS fonts alike (consistent with spec 021).
- **FR-008**: Font pickers MUST present available families in a stable, predictable order
  across sessions (e.g. built-in families first, then host-registered families in the order the
  host registered them), so the list does not reshuffle unexpectedly between openings.
- **FR-009**: The system MUST resolve duplicate or repeated registrations of the same family
  name deterministically and document the rule, yielding exactly one picker entry per family
  name.
- **FR-010**: The system MUST reject a registration whose font data is missing, empty, or
  unreadable in a way the host can detect, without corrupting other registrations or the picker.
- **FR-011**: The library MUST NOT enumerate or load fonts from the end user's operating system;
  the set of available fonts is exactly the built-in families plus whatever the host explicitly
  registers. (Operating-system font discovery is out of scope for this feature — see "Resolved
  Scope Decision".)
- **FR-012**: All new host-facing capabilities (font registration) MUST be documented for host
  developers, and the bundled example/sample app MUST demonstrate registering at least one
  custom font that then appears in the picker and renders end-to-end across canvas, preview, and
  export.

### Key Entities *(include if feature involves data)*

- **Font family**: A named typeface available to the report (e.g. "Acme Brand"). Has a display
  name used in pickers and stored in reports, and one or more faces. Sources: built-in
  (bundled), host-registered, or — if in scope — OS-provided.
- **Font face**: A specific variant of a family — regular, bold, italic, bold-italic — carrying
  the actual glyph/measurement data used to render and measure text.
- **Font registry (conceptual)**: The single, authoritative set of families/faces the engine
  knows about in a session. What every picker lists and what every render path (canvas,
  preview, export) draws from — they are necessarily the same set, which is what makes
  design-equals-output hold.
- **Report font reference**: The family *name* a text element stores. Travels with the saved
  report; resolves against whatever is registered/available when the report is opened
  (otherwise the unavailable-font behavior applies).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A host developer can make a custom font appear in every designer font picker and
  render it identically across canvas, preview, and export by performing a single, documented
  registration step before showing the designer — demonstrated by the sample app.
- **SC-002**: For any host-registered font applied to text, the rendered output is visually
  identical across canvas, print preview, and exported PDF/PNG (verified by snapshot/parity
  checks at 100% — no per-path divergence).
- **SC-003**: A report that uses a host-registered font opens with **zero errors** in a session
  where that font is not registered, preserves the stored font name, and renders text in a
  fallback font; saving does not lose the original font name.
- **SC-004**: Every font picker in the designer lists the complete available set (built-in +
  host-registered, plus OS fonts only when the host opted in) — never a stale subset — with
  each family previewed in its own typeface.
- **SC-005**: With no host registration and no OS opt-in, the designer behaves exactly as it
  does today (built-in families only), confirming the capability is purely additive and the
  library remains self-contained by default.
- **SC-006**: A host developer can determine programmatically when a registration was rejected
  (invalid/empty font data) rather than discovering it as a silent missing entry.

## Assumptions

- This feature builds on the existing font-rendering and font-picker capabilities (spec 021):
  the engine can already render and measure any *available* font identically across canvas,
  preview, and export, and the picker already lists "available" families and handles
  unavailable ones. The gap this feature closes is that there is currently no *supported,
  public* way for a host to change which fonts are available beyond the bundled three.
- "Host application" means the application embedding the report designer/engine as a library;
  the library remains self-contained and does not depend on host code (Constitution Principle
  I). Font registration is a capability the host calls, not a dependency the library takes on.
- Fonts are registered as data the host provides (font files/bytes the host has the right to
  use); licensing of host-supplied or OS fonts is the host's responsibility, not the library's.
- Saved reports continue to store a font *reference* (name), not embedded font data; portability
  of a shared template depends on the same font being available where it is opened. Exported
  PDFs embed the faces they actually use (existing behavior) and are self-contained.
- The serialized report schema does **not** need a new version for this feature: text elements
  already store a font-family name, and that storage is unchanged. (To be confirmed in planning;
  no schema change is anticipated.)
- Default behavior is conservative: OS-font surfacing, if built at all, is **off** unless the
  host explicitly opts in, preserving the design-equals-output guarantee by default.

## Resolved Scope Decision

**Scope of "system" fonts.** The request said "system/host fonts." *Host* fonts (User Stories
1–2) are unambiguous, safe, and the clear core. *System* (operating-system) fonts are in tension
with two project principles: design-equals-output / WYSIWYG (arbitrary OS-installed fonts cannot
be guaranteed to render identically across machines or in headless export) and
library-self-containment (the engine would have to reach into the OS environment). Spec 021
already explicitly excluded OS-level font discovery.

**Decision (2026-06-13): this feature delivers host-registered fonts only; operating-system
font discovery is deferred to a separate future feature.** Rationale: the host-registration core
is fully valuable on its own, preserves every project guarantee by construction, and is what
unblocks brand/document fonts in the picker. OS discovery, if pursued later, can build on this
foundation — the unavailable-font behavior (User Story 2) already handles any font absent from a
session, so a future OS-font feature layers on cleanly. Should OS discovery be wanted, it should
be opt-in, off by default, and ship with an explicit reduced-portability indication; that is
captured for the future feature, not this one.

## Out of Scope

- **Operating-system ("system") font discovery** — deferred to a future feature (see "Resolved
  Scope Decision"). This feature is host-registered fonts only.
- Toolbar/quick-format font controls (Properties-panel pickers only, consistent with spec 021).
- Font **management UI** inside the designer (uploading, deleting, or organizing fonts through
  the designer's own interface) — fonts are contributed by the host programmatically, not
  managed by the end user in-app.
- Embedding host fonts into the saved **template/JSON** so the template file is self-carrying —
  templates continue to reference fonts by name. (Exported PDFs remain self-contained.)
- Any change to how text is measured, laid out, or styled beyond *which* fonts are selectable.
