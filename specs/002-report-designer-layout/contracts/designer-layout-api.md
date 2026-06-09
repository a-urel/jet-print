# Public API Contract: Report Designer Layout

**Feature**: `002-report-designer-layout` | **Date**: 2026-06-06

This feature adds to the library's single public entry point. It does **not** change or remove
the surface defined in feature 001 (`JetPrintPlaceholder`, `jetPrintVersion`). As in 001, the
"interface contract" for this Flutter/Dart library is the set of symbols re-exported from:

```dart
import 'package:jet_print/jet_print.dart';
```

Importing any `package:jet_print/src/...` path remains a contract violation, guarded by the
existing encapsulation test.

## New exported symbols (this feature)

| Symbol | Kind | Purpose | Stability |
|--------|------|---------|-----------|
| `JetReportDesigner` | `Widget` (`StatefulWidget`) | The report designer **shell**: top bar + toolbox + design surface + three-tab right panel inside a resizable, collapsible frame. Layout-only; controls are non-functional placeholders. Reads `ShadTheme` and ambient `Localizations`. | Experimental (0.x) |
| `JetPrintLocalizations` | `class` (gen-l10n) | Localized chrome strings for the designer (en/de/tr; English default + fallback). | Experimental (0.x) |
| `JetPrintLocalizations.delegate` | `LocalizationsDelegate<JetPrintLocalizations>` | Delegate consumers add to `localizationsDelegates`. | Experimental (0.x) |
| `JetPrintLocalizations.supportedLocales` | `List<Locale>` | The locales the library ships: `[en, de, tr]`. | Experimental (0.x) |

> Exact symbol names are the contract intent; Phase 2 may refine identifiers, but the **shape**
> is fixed: one renderable, host-state-free designer shell widget + one exported localization
> delegate (with its `delegate`/`supportedLocales` statics). Region sub-widgets, panel bodies,
> tab keys, and the collapse breakpoint stay private under `src/`.

### `JetReportDesigner` contract

- MUST be a `StatefulWidget` (it owns active-tab and collapse state) with **no required
  parameters** and MUST build under a standard `ShadApp` shell.
- MUST NOT require host-application state, global singletons, or playground-app code (it reads the
  ambient `ShadTheme` and `Localizations` only).
- MUST render five regions — top bar, toolbox, design surface, right tabbed panel, enclosing
  frame — all simultaneously at default desktop width (FR-001, US1).
- MUST present the right panel with exactly three tabs in order **Data Source, Outline,
  Properties**, with Data Source active by default and exactly one visible at a time
  (FR-004/005/006).
- MUST support draggable resize of the side regions down to enforced minimum widths (FR-013)
  and collapse/expand of side regions below the width breakpoint (FR-014).
- MUST source every visible chrome caption from `JetPrintLocalizations` (no hard-coded
  literals) and visibly change appearance with `ShadTheme` (light/dark) (FR-008/009/016).
- MUST carry dartdoc describing purpose, usage, and that it is layout-only this iteration
  (Principle VI).

### `JetPrintLocalizations` contract

- MUST provide translations for **en (default/fallback), de, tr** covering the designer chrome
  (top bar title + action labels/tooltips, the three tab captions, toolbox entries, panel
  placeholder labels) (FR-016).
- For a missing key in a supported locale, or an unsupported active locale, resolution MUST
  fall back to English — never a blank label or a raw resource key (FR-017).
- MUST be wireable by a consumer via `localizationsDelegates: [JetPrintLocalizations.delegate,
  ...]` and `supportedLocales: JetPrintLocalizations.supportedLocales`.

## Consumer usage (the playground app, and any external consumer)

```dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

ShadApp(
  locale: activeLocale,                    // en | de | tr — switched at runtime
  localizationsDelegates: const [
    JetPrintLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: JetPrintLocalizations.supportedLocales,
  home: const JetReportDesigner(),         // the whole designer shell
);
```

## Non-goals (explicitly NOT in the public surface)

- No domain/report-model types (`lib/src/domain` stays private and UI-free).
- No rendering/serialization API (deferred; Constitution §V).
- No exported region sub-widgets, panel bodies, tab-key enum, or breakpoint constant.
- No data binding, element creation, property editing, drag-and-drop, or persistence behavior.

## Contract tests (Phase 1 → enforced test-first in Phase 2)

These assert the contract above and MUST be written before implementation (Principle III):

1. **Public-API import test** — imports *only* `package:jet_print/jet_print.dart` and references
   `JetReportDesigner` + `JetPrintLocalizations` (delegate + supportedLocales), proving the
   surface is sufficient.
2. **Encapsulation test** (existing) — no consumer file imports a `package:jet_print/src/` path.
3. **Region presence widget test** — pumps `JetReportDesigner` and asserts all five regions +
   representative placeholder content render (FR-001/002/003/007).
4. **Tabs widget test** — default tab Data Source; switching shows the selected panel and hides
   the others; active tab highlighted (FR-004/005/006).
5. **Responsive collapse widget test** — below breakpoint, side regions collapse to rails and
   are re-expandable (FR-011/014 / SC-004).
6. **Localization widget test** — en/de/tr captions render correctly; unsupported locale and
   missing key fall back to English (FR-016/017 / SC-007).
7. **Light/dark golden test** — the shell renders themed in both variants (SC-003).
