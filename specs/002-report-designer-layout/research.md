# Phase 0 Research: Report Designer Main Layout

**Feature**: `002-report-designer-layout` | **Date**: 2026-06-06

This document resolves every technical unknown for the layout shell. The spec is layout-only
with placeholder content; the open questions are *how* to compose the regions, *how* to honor
the resize/collapse behavior, and *how* to establish the localization seam — all using the
stack already fixed by the scaffold (feature 001).

---

## D1 — Where the designer shell lives (library vs. tester app)

- **Decision**: Implement the shell as a new **public library widget** `JetReportDesigner` in
  `packages/jet_print/lib/src/designer/`, exported from the single entry point
  `lib/jet_print.dart`. The tester app renders it as a consumer.
- **Rationale**: Constitution Principle I (Library-First) makes the library the product and
  every app a consumer that must exercise only the public API. A designer shell built inside
  the tester app would couple the product's core UI to a non-shipped consumer and violate that
  rule. Placing it in the `designer` seam matches Principle II's layering.
- **Alternatives considered**:
  - *Build the layout in the tester app* — rejected: the layout IS the product's designer
    chrome; it must ship in the library.
  - *New top-level seam for "layout"* — rejected: the `designer` seam already owns
    design-time UI per the scaffold; no new seam is warranted.

---

## D2 — Component palette (which shadcn_ui widgets compose the shell)

- **Decision**: Compose entirely from `shadcn_ui ^0.54.0` (already resolved, no new UI dep):
  - **Frame / regions**: `ShadCard` + `ShadSeparator` + plain layout widgets for the top bar,
    toolbox, surface, and panel chrome.
  - **Resizable splitters**: `ShadResizablePanelGroup` with `ShadResizablePanel` children
    (horizontal axis) for toolbox | surface | right panel.
  - **Right tabbed panel**: `ShadTabs<String>` with three `ShadTab`s (Data Source, Outline,
    Properties).
  - **Top-bar actions**: `ShadButton` / `ShadButton.ghost` (non-functional `onPressed`).
- **Rationale**: FR-008/FR-009 require 100% shadcn-based, theme-driven controls. All needed
  primitives exist in 0.54.0 (verified: `resizable.dart`, `tabs.dart`, `separator.dart`,
  `card.dart`, `button.dart` are exported). No additional dependency keeps Constitution §VI's
  "minimal/justified dependencies" intact.
- **Alternatives considered**:
  - *Flutter Material `TabBar`/`Drawer`* — rejected: would introduce non-shadcn, default-styled
    controls, failing SC-005.
  - *Hand-rolled splitter with `GestureDetector`* — rejected: `ShadResizablePanelGroup` already
    provides themed drag handles, min/max enforcement, and accessible hit targets.

---

## D3 — Resizable side regions with minimum widths (FR-013)

- **Decision**: Use `ShadResizablePanelGroup(axis: horizontal)` with three panels. Panel sizes
  are **fractions** of the group width (`defaultSize`, `minSize`, `maxSize` in 0..1). Wrap the
  group in a `LayoutBuilder` and convert the spec's pixel minimums to fractions at build time:
  `minFraction = minPanelPx / constraints.maxWidth`. Defaults (desktop): toolbox `defaultSize
  ≈ 0.18` (`minSize ≈ 220px→fraction`), surface `defaultSize ≈ 0.62`, right panel `defaultSize
  ≈ 0.20` (`minSize ≈ 240px→fraction`); the surface absorbs remaining space.
- **Rationale**: `ShadResizablePanel` enforces `minSize`/`maxSize` natively (verified in
  source: assertions on `minSize <= maxSize`, `defaultSize` within range). Computing the
  fraction from live constraints honors the spec's intent ("each side region honors a minimum
  width") without hardcoding a window size. Spec assumptions explicitly leave exact pixels to
  planning (~200px panels).
- **Alternatives considered**:
  - *Fixed pixel-width `SizedBox` regions* — rejected: not user-resizable (violates FR-013).
  - *Express min as a static fraction* — rejected: a fixed fraction breaks the px-minimum
    promise as the window grows/shrinks; LayoutBuilder conversion keeps the floor stable.

---

## D4 — Collapse/expand below the width breakpoint (FR-011 / FR-014)

- **Decision**: A stateful shell (`JetReportDesigner` → `StatefulWidget`) wraps the body in a
  `LayoutBuilder`. Define a **breakpoint of 1024 logical px**. At/above it, render the
  three-panel `ShadResizablePanelGroup` (D3). Below it, replace each side region with a narrow
  **icon rail** (≈48px) carrying a `ShadButton.ghost` toggle; tapping a rail expands that side
  as an **overlay panel** (drawn above the surface, e.g. a `ShadSheet`-style side panel or a
  positioned `ShadCard`) so the design surface stays usable. Collapse state for each side is
  held in widget state and is re-expandable via the rail affordance.
- **Rationale**: Satisfies the clarified narrow-window behavior (collapse to icon rail, never
  clip a region out of view, always re-expandable) and SC-004. `LayoutBuilder` is the idiomatic
  Flutter way to branch on available width without a global media query, keeping the widget
  self-contained (Principle I — no host state).
- **Alternatives considered**:
  - *Horizontal scroll when narrow* — rejected: spec edge case forbids clipping the surface;
    scrolling the whole frame hides regions.
  - *Permanent overlay drawers at all sizes* — rejected: at desktop width the spec wants all
    regions visible simultaneously (US1 / Acceptance 1).

---

## D5 — Right panel tabs and default selection (FR-004 / FR-005 / FR-006)

- **Decision**: `ShadTabs<String>` with `tabs: [dataSource, outline, properties]` in that fixed
  order; initial/default value = **Data Source** (per spec Assumptions). Each `ShadTab` body is
  a private placeholder panel widget. Active tab styling and show/hide are handled by `ShadTabs`.
- **Rationale**: `ShadTabs` natively renders exactly one active tab, highlights it, and hides
  the others — directly satisfying FR-005/FR-006 with a single shadcn component. Using `String`
  keys keeps it simple and avoids exporting an enum (keeps public surface minimal, D8).
- **Alternatives considered**:
  - *Custom segmented control + `IndexedStack`* — rejected: reimplements what `ShadTabs` gives
    for free and risks non-shadcn styling.

---

## D6 — Localization mechanism (FR-016 / FR-017 / FR-018)

- **Decision**: Use Flutter's first-party **`gen-l10n`** tooling. Add `flutter_localizations`
  (SDK) + `intl` to the library, set `flutter: generate: true`, and add `l10n.yaml` with:
  `arb-dir: lib/src/designer/l10n`, `template-arb-file: jet_print_en.arb`,
  `output-localization-file: jet_print_localizations.dart`,
  `output-class: JetPrintLocalizations`, **`synthetic-package: false`** (so generated files are
  real source under `lib/src/designer/l10n/` and can be re-exported). Ship ARB files for
  `en` (template + default/fallback), `de`, `tr`. Export `JetPrintLocalizations` plus its
  `.delegate` and `supportedLocales` from `lib/jet_print.dart`.
- **Fallback behavior**:
  - *Missing key for a locale* → gen-l10n falls back to the template (`en`) value
    automatically (no blank, no raw key) — satisfies FR-017.
  - *Unsupported active locale* → Flutter's locale resolution falls back to the first supported
    locale; with `en` listed first this resolves to English — satisfies FR-017 edge case.
- **Rationale**: This is the canonical, pub-publishable way for a package to ship its own
  translations and expose a delegate consumers add to `localizationsDelegates`. `intl` is
  first-party and standard, satisfying Constitution §VI's "minimal/justified" bar. ARB is the
  documented, human-inspectable format. `synthetic-package: false` is required so the generated
  delegate is exportable through the public entry point (Principle I).
- **Analyzer note**: gen-l10n output can trip strict lints (e.g. `directives_ordering`). If the
  zero-warning gate (SC/FR-009 from feature 001) flags generated files, add an
  `analyzer: exclude:` entry for `**/l10n/jet_print_localizations*.dart` in
  `analysis_options.yaml`. Hand-written ARB and wiring code stays fully linted.
- **Alternatives considered**:
  - *Hand-rolled `Map<Locale, Map<String,String>>` + custom delegate* — rejected: reinvents
    gen-l10n, lacks tooling/validation, and diverges from ecosystem expectations (§VI).
  - *`slang` or other 3rd-party i18n packages* — rejected: adds a non-first-party dependency
    when the SDK tool suffices for static chrome strings.

---

## D7 — Tester app language toggle (FR-018)

- **Decision**: The tester app's root holds a `Locale` in state (default `en`). It passes
  `locale`, `localizationsDelegates: [JetPrintLocalizations.delegate,
  GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate]`, and `supportedLocales:
  JetPrintLocalizations.supportedLocales` to `ShadApp`. A `ShadButton`/`ShadSelect` cycles
  en → de → tr, calling `setState` so the tree rebuilds and `JetReportDesigner`'s labels update
  live — no restart (analogous to the existing light/dark toggle).
- **Rationale**: Mirrors the established theme-toggle pattern in `main.dart`, satisfies FR-018
  and SC-007, and proves the exported delegate works for a real consumer (Principle I).
- **Alternatives considered**:
  - *OS-locale only (no in-app control)* — rejected: FR-018 requires a runtime control in the
    tester app.

---

## D8 — Public API surface delta (Principle I — minimal surface)

- **Decision**: Export exactly:
  - `JetReportDesigner` — the shell widget (const-constructible, no required params, no host
    state).
  - `JetPrintLocalizations` — the generated localizations class, with its static `delegate` and
    `supportedLocales`.
  Keep region sub-widgets, panel bodies, the right-tab key enum/strings, and the breakpoint
  constant **private** under `src/`. The existing `JetPrintPlaceholder` and `jetPrintVersion`
  exports are retained.
- **Rationale**: Constitution §I demands a deliberately minimal surface. A consumer needs only
  the shell widget and the localization delegate; everything else is implementation detail.
- **Alternatives considered**:
  - *Export region widgets individually* — rejected: enlarges the surface and leaks layout
    internals before they're stable.

---

## D9 — Test & golden strategy (Principle III / IV)

- **Decision** (tests written **before** implementation, Principle III):
  1. **Region presence** widget test — pump `JetReportDesigner` in a `ShadApp`; assert top bar,
     toolbox, surface, and right panel are all found; assert toolbox lists ≥ multiple element
     entries and panels show their shaped placeholder content (US1/US3).
  2. **Tabs** widget test — default tab = Data Source content shown; tapping Outline/Properties
     swaps content and marks the active tab (US2 / FR-005/006).
  3. **Responsive collapse** widget test — pump at a narrow width (< breakpoint) and assert side
     regions collapse to rails with an expand affordance; expand restores the panel (FR-014 /
     SC-004).
  4. **Localization** widget test — render with `en`/`de`/`tr` and assert captions match each
     language; render with an unsupported locale and a deliberately missing key and assert
     English fallback (no blank/raw key) (US4 / FR-016/017 / SC-007).
  5. **Golden** test — capture the shell in light and dark themes (SC-003), extending the
     WYSIWYG harness seeded in feature 001.
- **Rationale**: Covers every functional requirement and success criterion that is observable in
  a widget test; goldens guard the "no unthemed region" promise. The existing domain
  layer-boundary test is untouched and must stay green (the designer seam may use Flutter UI).
- **Alternatives considered**:
  - *Manual visual review only* — rejected: Principle III is non-negotiable; behavior must be
    test-enforced.
