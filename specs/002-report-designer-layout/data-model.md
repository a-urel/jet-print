# Phase 1 Data Model: Report Designer Main Layout

**Feature**: `002-report-designer-layout` | **Date**: 2026-06-06

> This is a **layout-only** feature. There is **no persisted/serializable data model** and no
> domain entities (Constitution §V is not triggered). The "entities" below are *visual
> structure* (widget composition) and one *presentation resource* (localized strings). They map
> the spec's Key Entities to concrete widgets and their non-functional placeholder content.

## Visual structure (widget composition)

```text
JetReportDesigner (public StatefulWidget — holds collapse state + active tab)
└── Designer Frame  (LayoutBuilder → breakpoint branch)
    ├── DesignerTopBar           (top strip)
    │   ├── report title         (placeholder, localized)
    │   └── action buttons       (placeholder, non-functional, localized labels/tooltips)
    └── Body
        ├── ≥ breakpoint (≥1024px): ShadResizablePanelGroup (horizontal)
        │   ├── DesignerToolbox        (ShadResizablePanel, minSize floor)
        │   ├── DesignerSurface        (ShadResizablePanel, largest — absorbs remainder)
        │   └── DesignerRightPanel     (ShadResizablePanel, minSize floor)
        └── < breakpoint: icon rails (collapsed) + overlay expand for each side region
```

## Entities (visual regions) → widgets

| Spec entity | Widget (privacy) | Role / placeholder content | Key requirements |
|-------------|------------------|----------------------------|------------------|
| Designer Frame | `JetReportDesigner` (**public**) | Enclosing arrangement; owns spacing, resizable splitters, collapse breakpoint, active-tab + collapse state, theme application. | FR-001, FR-008/009, FR-011, FR-012, FR-013, FR-014 |
| Top Bar | `DesignerTopBar` (private) | Horizontal strip: placeholder report title + ≥1 placeholder action control (e.g. Preview/Save/Export ghost buttons), non-functional. | FR-001, FR-015 |
| Toolbox | `DesignerToolbox` (private) | Left-docked vertical palette listing sample element entries: Label, Text, Table, Image (+ more), as a list/palette of placeholder rows. | FR-002, FR-007 |
| Design Surface | `DesignerSurface` (private) | Center primary area showing a bounded page/canvas placeholder distinct from chrome; never a blank void; scrolls independently. | FR-003, FR-007, FR-010 |
| Right Panel (tabbed) | `DesignerRightPanel` (private) | `ShadTabs<String>` hosting three panels; exactly one visible; default = Data Source; active tab highlighted. | FR-004, FR-005, FR-006 |
| Data Source Panel | `DataSourcePanel` (private) | Placeholder **field list** (sample field rows). | FR-007 |
| Outline Panel | `OutlinePanel` (private) | Placeholder hierarchical **element tree** (sample bands/elements). | FR-007 |
| Properties Panel | `PropertiesPanel` (private) | Placeholder **property rows** (sample name/value pairs). | FR-007 |
| Localized Strings | `JetPrintLocalizations` (**public** delegate) | Translatable chrome captions resolved per active locale (en/de/tr), English default + fallback. Presentation resource, not persisted. | FR-016, FR-017, FR-018 |

## Localized-string seam (presentation resource)

- **Source**: ARB files under `lib/src/designer/l10n/` — `jet_print_en.arb` (template + default/
  fallback), `jet_print_de.arb`, `jet_print_tr.arb`.
- **Generated**: `JetPrintLocalizations` (class) via `gen-l10n`, `synthetic-package: false`,
  exposing a static `delegate` (`LocalizationsDelegate<JetPrintLocalizations>`) and
  `supportedLocales` (`[Locale('en'), Locale('de'), Locale('tr')]`).
- **String keys** (chrome only — illustrative sample *values* like mock field names are NOT
  translated, per spec Localization scope):

  | Key (intent) | en (template) example |
  |--------------|------------------------|
  | `appTitle` / `reportTitlePlaceholder` | "Untitled report" |
  | `actionPreview`, `actionSave`, `actionExport` (+ tooltips) | "Preview", "Save", "Export" |
  | `tabDataSource`, `tabOutline`, `tabProperties` | "Data Source", "Outline", "Properties" |
  | `toolboxLabel`, `toolboxLabelEntry`, `toolboxTextEntry`, `toolboxTableEntry`, `toolboxImageEntry` | "Toolbox", "Label", "Text", "Table", "Image" |
  | `panelDataSourceHint`, `panelOutlineHint`, `panelPropertiesHint`, `surfaceEmptyHint` | placeholder captions |

  (Exact key set is finalized when tests are written in Phase 2; the table fixes intent and the
  three-locale coverage, not the final identifiers.)

## State (in-memory only — no persistence)

| State | Owner | Values | Drives |
|-------|-------|--------|--------|
| Active right-side tab | `JetReportDesigner` (or `ShadTabsController`) | `dataSource` (default) \| `outline` \| `properties` | FR-005/006 show/hide |
| Toolbox collapsed | `JetReportDesigner` | `bool` (default false at desktop width) | FR-014 collapse/expand |
| Right panel collapsed | `JetReportDesigner` | `bool` (default false at desktop width) | FR-014 collapse/expand |
| Panel split sizes | `ShadResizableController` | fractions ≥ per-panel `minSize` | FR-013 resize |
| Active locale | **playground app** (consumer), via `ShadApp.locale` | `en` (default) \| `de` \| `tr` | FR-018 live label switch |
| Theme mode | **playground app** (consumer), existing | light (default) \| dark | FR-009 theme |

> Locale and theme are owned by the **consumer** (playground app), not the library widget — the
> library reads the ambient `Localizations`/`ShadTheme`, keeping `JetReportDesigner` free of
> host state (Constitution §I).

## Validation / invariants (visual)

- Exactly one right-side tab is active at all times; Data Source on first load (FR-006).
- The design surface always renders its page placeholder, even with no content (edge case).
- Side regions never clip out of view: ≥ breakpoint they honor `minSize`; < breakpoint they
  collapse to rails and remain re-expandable (FR-011/FR-014).
- No region renders with default/unthemed styling — every color/text style comes from
  `ShadTheme.of(context)` (FR-008/009).
- No visible chrome label is a hard-coded literal; all come from `JetPrintLocalizations`, with
  English fallback for missing keys / unsupported locales (FR-016/017).
