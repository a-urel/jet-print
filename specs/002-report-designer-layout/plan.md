# Implementation Plan: Report Designer Main Layout

**Branch**: `002-report-designer-layout` | **Date**: 2026-06-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-report-designer-layout/spec.md`

## Summary

Build the **visual shell** of the report designer as a new public library widget,
`JetReportDesigner`, living in the library's `designer` seam and consumed by the tester app
exactly as an external consumer would. The shell arranges five regions — a top bar, a
left toolbox, a center design surface, and a right three-tab panel (Data Source / Outline /
Properties) inside an enclosing frame — using only `shadcn_ui` components already resolved in
the workspace (`ShadResizablePanelGroup` for draggable splitters, `ShadTabs` for the right
panel, `ShadCard`/`ShadSeparator`/`ShadButton` for chrome). All controls are **non-functional
placeholders**; the only interactions this iteration are tab switching, side-region resizing,
and collapse/expand below a width breakpoint.

In parallel, this feature establishes the **localization seam** the rest of the designer will
rely on: the library ships its own `flutter_localizations` + `intl` + ARB-based
`JetPrintLocalizations` delegate (en default/fallback, de, tr) covering the designer chrome,
exported through the single public entry point. The tester app gains a runtime language
toggle (analogous to the existing light/dark switch) that flips `ShadApp.locale` so every
visible designer label updates live. Layout-only: no data binding, element creation, property
editing, or persistence.

## Technical Context

**Language/Version**: Dart 3.12.0 / Flutter 3.44.0 (stable), sound null-safety (per scaffold)
**Primary Dependencies**: Flutter SDK; `shadcn_ui ^0.54.0` (already resolved — provides
`ShadResizablePanelGroup`, `ShadTabs`, `ShadSeparator`, `ShadCard`, `ShadButton`); NEW:
`flutter_localizations` (SDK) + `intl` for ARB-based localization
**Storage**: N/A (layout-only; no persistence/serialization this iteration — deferred per Constitution V)
**Testing**: `flutter test` — widget tests (regions present, tab switch, collapse at narrow
width, locale switch + English fallback); light/dark golden tests of the shell extending the
WYSIWYG harness; existing architecture (layer-boundary) test stays green
**Target Platform**: macOS desktop (tester app); library remains platform-agnostic
**Project Type**: Dart pub workspace monorepo — reusable library + sample/tester desktop app
**Performance Goals**: N/A (static placeholder chrome; no rendering pipeline). Layout must
render without horizontal scroll at default desktop window size (SC-004) and switch
theme/language without restart (SC-003/SC-007)
**Constraints**: All visible controls shadcn-based and theme-driven (no hardcoded colors,
FR-008/009); single public entry point preserved; domain seam stays UI-free (arch test);
zero analyzer warnings (generated l10n excluded from analysis if needed); minimal/justified deps
**Scale/Scope**: 1 new public widget (`JetReportDesigner`) + 1 exported localization delegate;
5 layout regions; 3 right-side tabs; 3 locales; ~5 placeholder content groups; widget + golden tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| # | Principle | Status | How this plan complies |
|---|-----------|--------|------------------------|
| I | Library-First & Clean Public API | ✅ PASS | The designer shell is a **library** widget (`JetReportDesigner`) in `lib/src/designer/`, exported from the single entry point `lib/jet_print.dart`; the tester app renders it as a consumer only. Localization is exposed as a public `JetPrintLocalizations.delegate` + `supportedLocales` so consumers opt in (FR-016/018). Internals stay under `src/`. |
| II | Layered & Extensible Architecture | ✅ PASS | Layout is presentation-only, confined to the `designer` seam (allowed to use Flutter UI). No domain/rendering coupling — placeholder content is static, not bound to a report model; the `domain` seam stays UI-free and the layer-boundary test remains green. Localized strings are a presentation resource, not a domain entity. |
| III | Test-First (NON-NEGOTIABLE) | ✅ PASS | Phase 2 tasks write widget tests (region presence, tab switching, collapse at narrow width, locale switch + en fallback) and shell goldens **before** implementation; suite must be green with no skips. |
| IV | Rendering Fidelity — WYSIWYG (NON-NEGOTIABLE) | 🟡 N/A this iteration (not violated) | This is designer **chrome**, not report-model rendering; no canvas/preview/print paths exist yet, so no parallel rendering is introduced. Light/dark golden tests of the shell **extend** the seeded WYSIWYG harness; full fidelity coverage arrives with real rendering. |
| V | Versioned & Backward-Compatible Serialization | 🟡 DEFERRED (not violated) | Layout-only; nothing is persisted or serialized. No schema introduced, so no version/migration obligation triggered. |
| VI | Documentation & Developer Experience | ✅ PASS | New public symbols (`JetReportDesigner`, `JetPrintLocalizations` + delegate) carry dartdoc; tester app stays runnable and gains the language toggle; `CHANGELOG.md` updated; `dart format` + strict `analysis_options` enforced (generated l10n excluded from analysis to keep the zero-warning gate). |

**Initial gate**: PASS. No unjustified complexity. The two non-applicable principles (IV, V)
are spec-sanctioned scope boundaries (layout-only, placeholders acceptable), not violations,
so the Complexity Tracking table stays empty. The one new dependency surface
(`flutter_localizations` + `intl`) is first-party/standard and justified by FR-016–FR-018.

**Post-Design re-check**: PASS. The Phase 1 design (one shell widget composed from existing
`shadcn_ui` components, region sub-widgets private under `src/designer/`, ARB-based delegate
exported from the public entry point, tester locale toggle) adds no structural complexity
beyond what the constitution's layering already mandates and introduces no new runtime
dependency beyond the standard localization packages. No new violations.

## Project Structure

### Documentation (this feature)

```text
specs/002-report-designer-layout/
├── plan.md              # This file (/speckit.plan output)
├── research.md          # Phase 0 output — decisions on layout widgets, resize/collapse, l10n
├── data-model.md        # Phase 1 output — layout regions + localized-string seam (visual model)
├── quickstart.md        # Phase 1 output — run the designer + switch theme/language
├── contracts/
│   ├── public-api.md           # (existing, feature 001)
│   └── designer-layout-api.md  # Phase 1 output — new exported surface for this feature
├── checklists/          # (existing)
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
jet-print/                                  # workspace root (unchanged structure)
├── analysis_options.yaml                   # may add `analyzer: exclude:` for generated l10n
├── packages/
│   └── jet_print/                          # THE LIBRARY (the product)
│       ├── pubspec.yaml                    # + flutter_localizations (sdk), + intl; flutter: generate: true
│       ├── l10n.yaml                       # NEW — gen-l10n config (synthetic-package: false)
│       ├── CHANGELOG.md                    # updated for this feature
│       ├── lib/
│       │   ├── jet_print.dart              # + export JetReportDesigner, JetPrintLocalizations (delegate + supportedLocales)
│       │   └── src/
│       │       ├── domain/                 # UNCHANGED — stays UI-free (arch test guards this)
│       │       ├── rendering/              # UNCHANGED
│       │       └── designer/
│       │           ├── designer.dart       # seam doc (existing)
│       │           ├── jet_print_placeholder.dart   # existing placeholder (kept)
│       │           ├── jet_report_designer.dart      # NEW — the public shell widget (JetReportDesigner)
│       │           ├── layout/             # NEW — private region sub-widgets
│       │           │   ├── designer_top_bar.dart      # top bar: title + placeholder actions (FR-015)
│       │           │   ├── designer_toolbox.dart      # left palette of element entries (FR-002)
│       │           │   ├── designer_surface.dart      # center page/canvas placeholder (FR-003)
│       │           │   ├── designer_right_panel.dart  # ShadTabs: Data Source/Outline/Properties (FR-004)
│       │           │   └── panels/                    # placeholder bodies for the 3 tabs (FR-007)
│       │           │       ├── data_source_panel.dart
│       │           │       ├── outline_panel.dart
│       │           │       └── properties_panel.dart
│       │           └── l10n/               # NEW — localization seam
│       │               ├── jet_print_en.arb           # template + English (default/fallback)
│       │               ├── jet_print_de.arb           # German
│       │               ├── jet_print_tr.arb           # Turkish
│       │               └── jet_print_localizations*.dart  # gen-l10n output (synthetic-package:false)
│       └── test/
│           └── designer/
│               ├── jet_report_designer_test.dart      # US1/US3: 5 regions present + placeholder content
│               ├── right_panel_tabs_test.dart         # US2/FR-005/FR-006: default tab + switching
│               ├── responsive_collapse_test.dart      # FR-011/FR-014/SC-004: collapse at narrow width
│               ├── localization_test.dart             # US4/FR-016/017: en/de/tr + English fallback
│               └── goldens/
│                   └── jet_report_designer_light_dark_test.dart  # SC-003 light/dark shell goldens
└── apps/
    └── jet_print_tester/                   # TESTER APP (consumer; macOS desktop)
        ├── pubspec.yaml                    # + flutter_localizations (sdk) for global delegates
        ├── lib/
        │   └── main.dart                   # hosts JetReportDesigner; wires l10n delegates + supportedLocales;
        │                                   #   adds runtime language toggle (en/de/tr) alongside theme toggle (FR-018)
        └── test/
            └── app_consumes_library_test.dart  # updated: root renders one JetReportDesigner inside ShadApp
```

**Structure Decision**: Keep the established Dart pub workspace monorepo. The new layout is a
single public widget (`JetReportDesigner`) in the library's `designer` seam, composed from
private region sub-widgets under `src/designer/layout/`. Localization lives in
`src/designer/l10n/` (ARB + gen-l10n output with `synthetic-package: false` so the generated
delegate is a real, exportable source file). The public entry point gains exactly the symbols
in `contracts/designer-layout-api.md`; everything else stays private. The tester app remains a
pure consumer: it imports only `package:jet_print/jet_print.dart`, renders `JetReportDesigner`,
and wires the exported localization delegate plus a language toggle.

## Complexity Tracking

> No entries — the Constitution Check passed with no unjustified violations. Principles IV and
> V are not-applicable/deferred by the spec's explicit layout-only, placeholder-acceptable
> scope, not complexity introduced by this design. The single new dependency surface
> (`flutter_localizations` + `intl`) is standard, first-party, and required by FR-016–FR-018.
