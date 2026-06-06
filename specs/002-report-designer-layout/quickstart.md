# Quickstart: Report Designer Main Layout

**Feature**: `002-report-designer-layout` | **Date**: 2026-06-06

How to run the designer shell, exercise its three interactions (tab switch, resize, collapse),
and verify theme + language switching. Assumes the feature-001 scaffold is already running
(see `specs/001-flutter-library-scaffold/quickstart.md` for clone → `flutter pub get`).

## 1. Get dependencies (adds localization packages)

```bash
# from the workspace root
flutter pub get
```

This resolves the new `flutter_localizations` (SDK) + `intl` deps and triggers gen-l10n
(`flutter: generate: true` + `l10n.yaml`) to produce `JetPrintLocalizations` from the ARB
files under `packages/jet_print/lib/src/designer/l10n/`.

## 2. Run the tester app (macOS desktop)

```bash
cd apps/jet_print_tester
flutter run -d macos
```

You should see the **report designer shell**:

- a **top bar** with a placeholder report title and non-functional action buttons,
- a left **toolbox** listing sample element entries (Label, Text, Table, Image, …),
- a large center **design surface** showing a bounded empty-page placeholder,
- a right **tabbed panel** with **Data Source / Outline / Properties** (Data Source active).

## 3. Exercise the three interactions

| Interaction | How | Expected |
|-------------|-----|----------|
| **Switch tabs** | Click Outline, then Properties | The selected panel's placeholder shows; the others hide; the active tab is highlighted (FR-005/006). |
| **Resize side regions** | Drag the splitter between the toolbox/surface or surface/right panel | The side region resizes down to its minimum width; the surface absorbs the rest (FR-013). |
| **Collapse / expand** | Resize the window narrower than ~1024px | Side regions collapse to icon rails; click a rail to expand it back over the surface (FR-014 / SC-004). |

## 4. Switch theme (light/dark)

Use the existing theme toggle in the tester app. Every region adopts the corresponding shadcn
theme colors with no unstyled element (FR-008/009 / SC-003).

## 5. Switch language (en / de / tr)

Use the new **language toggle** in the tester app to cycle English → German → Turkish. Every
visible designer label (top bar title + actions, the three tab captions, toolbox entries, panel
placeholder labels) updates **without a restart** (FR-018 / SC-007). Selecting an unsupported
locale falls back to English (no blank or raw-key captions, FR-017).

## 6. Run the test suite (test-first; all green, no skips)

```bash
# from the workspace root
flutter test
flutter analyze        # zero warnings (Constitution §VI / FR-009)
dart format --output=none --set-exit-if-changed .
```

Tests for this feature live under `packages/jet_print/test/designer/`:

- `jet_report_designer_test.dart` — five regions + placeholder content present (US1/US3)
- `right_panel_tabs_test.dart` — default tab + switching (US2 / FR-005/006)
- `responsive_collapse_test.dart` — collapse/expand below breakpoint (FR-014 / SC-004)
- `localization_test.dart` — en/de/tr + English fallback (US4 / FR-016/017 / SC-007)
- `goldens/jet_report_designer_light_dark_test.dart` — light/dark shell goldens (SC-003)

To (re)generate goldens after an intentional visual change:

```bash
flutter test --update-goldens
```

## What is intentionally NOT here

Layout-only this iteration: no data binding, element creation, property editing,
drag-and-drop, or persistence. Toolbox entries, field/element/property rows, and the page are
static placeholders that communicate intent only.
