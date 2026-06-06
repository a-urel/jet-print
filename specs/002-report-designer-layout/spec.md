# Feature Specification: Report Designer Main Layout

**Feature Branch**: `002-report-designer-layout`  
**Created**: 2026-06-06  
**Status**: Draft  
**Input**: User description: "create main layout of report designer including: left: toolbox, right 3 tabs: data source, report explorer (or find a better name for this), properties, client area: design surface. always use shadcn widgets. not functional, just layout. placeholder content acceptable."

## Overview

This feature establishes the **visual shell** of the report designer: the arrangement of
its primary work regions so the rest of the designer can be built into a stable frame. It is
a **layout-only** deliverable — regions are present, labeled, and visually correct, but the
controls inside them are non-functional placeholders. No data binding, no element creation,
no property editing, and no persistence are in scope.

> **Naming decision** — The requested "report explorer" panel is named **"Outline"** in this
> spec. It presents the hierarchical structure (bands/sections/elements) of the report being
> designed, mirroring the well-understood "Outline" convention used by document and design
> tools. Alternatives considered: *Report Tree*, *Structure*, *Report Explorer*. "Outline" is
> the shortest unambiguous label and avoids collision with the separate *Data Source* panel.
> See Assumptions if the team prefers a different label — it changes one tab caption only.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the full designer workspace at a glance (Priority: P1)

A report author opens the report designer and immediately sees a familiar three-zone
workspace: a tool palette on the left, a large central canvas to design on, and a stack of
context panels on the right. The layout communicates "this is where I build a report" without
any explanation, even though nothing is interactive yet.

**Why this priority**: This is the entire deliverable. The layout is the foundation every
later feature (toolbox drag, canvas editing, property binding) attaches to. Without the shell
correctly arranged, nothing else can be demonstrated. It is independently valuable as the
visual skeleton the team and stakeholders review and sign off on.

**Independent Test**: Launch the tester app, open the designer screen, and visually confirm
all four regions (left toolbox, center design surface, right tabbed panel, and an enclosing
frame) are present, correctly positioned, and styled with the shadcn theme in both light and
dark mode. Delivers value as a reviewable, demoable workspace skeleton.

**Acceptance Scenarios**:

1. **Given** the tester app is running, **When** the report designer screen is shown, **Then** a left toolbox region, a center design surface, and a right panel region are all visible simultaneously without scrolling on a standard desktop window.
2. **Given** the designer is shown, **When** the user observes the layout, **Then** the center design surface occupies the largest share of horizontal space, with the toolbox and right panel flanking it.
3. **Given** the active theme is toggled between light and dark, **When** the designer re-renders, **Then** every region adopts the corresponding shadcn theme colors with no unstyled or default-look elements.

---

### User Story 2 - Switch between the three right-side context panels (Priority: P2)

The author uses the tabbed panel on the right to switch among **Data Source**, **Outline**,
and **Properties** views. Selecting a tab reveals that panel's placeholder content; the other
two are hidden. The selected tab is visually distinct.

**Why this priority**: Tab switching is the one interaction included so reviewers can confirm
all three named panels exist and are reachable. It is secondary to the overall arrangement
(US1) but still independently demonstrable. Beyond tab selection, the panels remain
non-functional.

**Independent Test**: With the designer shown, click each of the three right-side tabs in
turn and confirm the correct placeholder panel appears and the active tab is highlighted.

**Acceptance Scenarios**:

1. **Given** the right panel is visible, **When** the designer first loads, **Then** exactly one tab is active by default and its placeholder content is shown.
2. **Given** the Data Source tab is active, **When** the user selects the Outline tab, **Then** the Outline placeholder is shown, the Data Source placeholder is hidden, and the Outline tab is marked active.
3. **Given** any tab is active, **When** the user reads the tab strip, **Then** all three tab captions — Data Source, Outline, Properties — are legible and in a consistent order.

---

### User Story 3 - Recognize the purpose of each region from placeholder content (Priority: P3)

Each region shows representative placeholder content so reviewers understand its intended
role: the toolbox shows a list of sample report-element entries (e.g., Label, Text, Table,
Image), the Outline shows a sample element tree, Data Source shows a sample field list, and
Properties shows sample property rows. The design surface shows an empty page placeholder.

**Why this priority**: Placeholder content turns an empty frame into a self-explanatory mock,
improving stakeholder review quality. It is lowest priority because it is illustrative only
and carries no behavior.

**Independent Test**: Inspect each region and confirm it contains theme-consistent
placeholder content that plausibly represents its future purpose, with no empty gaps that
misrepresent the region's role.

**Acceptance Scenarios**:

1. **Given** the toolbox is visible, **When** the user scans it, **Then** it lists multiple sample report-element entries arranged as a palette.
2. **Given** the design surface is visible, **When** the user views it, **Then** it presents a clearly bounded page/canvas placeholder distinct from the surrounding chrome.
3. **Given** any right-side tab is active, **When** the user views its body, **Then** it shows placeholder content shaped like that panel's intended future content (field list / element tree / property rows).

---

### Edge Cases

- **Narrow window**: When the window is resized narrower than the comfortable minimum, the layout MUST keep all three regions reachable (e.g., side panels retain a minimum width and the center surface scrolls or shrinks) rather than clipping a region out of view.
- **Very tall content**: When a panel's placeholder list is longer than its height, that panel MUST scroll independently without pushing other regions off-screen.
- **Theme with no explicit selection**: When the app starts without a user theme choice, the designer MUST render with a sensible default theme (matching the tester app's default) rather than an unstyled fallback.
- **Empty design surface**: The design surface with no report content MUST still render its page/canvas placeholder, not a blank void.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The designer MUST present a single screen composed of four visual regions: a left **toolbox**, a center **design surface**, a right **tabbed panel**, and an enclosing layout frame that positions them.
- **FR-002**: The left toolbox region MUST be docked to the left edge and display a vertical palette of placeholder report-element entries.
- **FR-003**: The center design surface MUST occupy the primary (largest) area between the toolbox and the right panel and display a bounded page/canvas placeholder.
- **FR-004**: The right region MUST present a tab strip with exactly three tabs in this order: **Data Source**, **Outline**, **Properties**.
- **FR-005**: Selecting a right-side tab MUST show that tab's placeholder panel and hide the other two; the active tab MUST be visually distinguished.
- **FR-006**: Exactly one right-side tab MUST be active on initial load (default selection).
- **FR-007**: Each region MUST contain placeholder content representative of its intended role (toolbox = element palette, Data Source = field list, Outline = element tree, Properties = property rows, design surface = empty page).
- **FR-008**: All visible controls MUST be rendered using the project's shadcn-based component library and MUST respect the active shadcn theme.
- **FR-009**: The layout MUST adopt both light and dark theme variants correctly, with no region falling back to an unthemed default appearance.
- **FR-010**: Each panel and the design surface MUST scroll independently when their content exceeds the available space, without displacing sibling regions.
- **FR-011**: The layout MUST keep all four regions present and reachable across a reasonable range of desktop window sizes, honoring sensible minimum widths for the side regions.
- **FR-012**: Except for switching the active right-side tab, the controls MUST be non-functional placeholders (no data binding, element creation, property editing, or persistence) in this iteration.

### Key Entities *(layout regions — visual only, no data model)*

- **Designer Frame**: The enclosing arrangement that positions the three working regions; owns overall spacing, dividers, and theme application.
- **Toolbox**: Left-docked palette listing report-element types as placeholder entries.
- **Design Surface**: Central canvas region showing an empty report page placeholder; the primary work area.
- **Right Panel (tabbed)**: A three-tab container hosting the Data Source, Outline, and Properties placeholder panels, of which one is visible at a time.
- **Data Source Panel**: Placeholder field-list view (one of the three tabs).
- **Outline Panel**: Placeholder hierarchical element-tree view of the report (renamed from "report explorer"; one of the three tabs).
- **Properties Panel**: Placeholder property-row view (one of the three tabs).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first-time reviewer can identify all four regions (toolbox, design surface, right tabbed panel, frame) and correctly state each region's purpose within 15 seconds of seeing the screen, without guidance.
- **SC-002**: All three right-side tabs are reachable, and switching to any tab shows its placeholder and hides the others in 100% of attempts.
- **SC-003**: The layout renders correctly with no unthemed or visually broken regions in both light and dark themes (2 of 2 theme variants pass visual review).
- **SC-004**: The full layout is visible without horizontal scrolling at the tester app's default desktop window size, and remains usable (all regions reachable) when the window is resized down to a defined minimum.
- **SC-005**: 100% of visible controls are shadcn-based components themed consistently — zero default-styled or platform-native-looking controls appear in review.
- **SC-006**: Stakeholders can approve the workspace arrangement from the layout alone (no functional features required), confirming the shell is ready for subsequent feature work.

## Assumptions

- **shadcn = Flutter `shadcn_ui`**: "shadcn widgets" refers to the project's adopted `shadcn_ui` Flutter component library (per the established scaffold), not the React/TypeScript shadcn/ui. Components such as the tabbed panel, cards, list rows, and resizable dividers come from that library.
- **Tab label "Outline"**: The "report explorer" panel is labeled **Outline**. If the team prefers *Report Tree*, *Structure*, or the original *Report Explorer*, it is a single caption change with no structural impact.
- **Desktop-first**: The designer targets the macOS desktop tester app (per the current scaffold). Touch/mobile layouts are out of scope this iteration.
- **Optional header strip**: A thin top region (title / placeholder action bar) MAY be included as part of the enclosing frame for visual completeness, but no toolbar actions are functional. The four named regions remain the focus.
- **Default tab**: The Data Source tab is the default-active right-side tab on load (any single default is acceptable for review).
- **Placeholder content is illustrative**: Sample entries (element types, fields, properties) are static and chosen to communicate intent; they are not wired to any real report model.
- **Non-functional by design**: Drag-and-drop, selection, editing, and saving are explicitly deferred; only tab switching is interactive.
