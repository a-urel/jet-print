# Changelog

All notable changes to the `jet_print` library are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Report model foundation (spec 003 Part 1): pure-Dart geometry value types
  (`JetSize`/`JetOffset`/`JetEdgeInsets`/`JetRect`), `PageFormat`, the element
  model (`ReportElement`, `TextElement`, `UnknownElement`), `ReportBand`/
  `BandType`/`ReportTemplate`, an `ElementCodecRegistry` extension point, and
  versioned JSON serialization with a forward-migration framework
  (`encodeTemplate`/`decodeTemplate`, `schemaVersion`, `SchemaMigration`).
- `JetReportDesigner` — the report designer **shell** widget: a top command bar,
  a left element toolbox (a compact icon toolbar with tooltips), a center design
  surface (a bounded paper page), and a right three-tab context panel
  (Data Source / Outline / Properties) in a theme-driven frame. Layout-only this
  iteration — every control is a non-functional placeholder; the live
  interactions are tab switching, splitter resize of the right panel (down to its
  minimum width), and collapse/expand of the right panel to an icon rail below
  the 1024px width breakpoint. The icon toolbox stays visible at every width.
- `JetPrintLocalizations` — the library's own gen-l10n localization delegate
  covering the designer chrome in English (default/fallback), German, and Turkish,
  exported with its `delegate` and `supportedLocales` so consumers can wire it
  into their app shell. Unsupported locales and missing keys fall back to English.
- Visual model completion (spec 003 Part 2): style value types (`JetColor`
  with hex serialization, `JetTextStyle`, `JetBoxStyle`); text styling on
  `TextElement` (sparse-serialized); new element types `ShapeElement`
  (line/rectangle), `ImageElement` (url/field/base64-bytes sources, `JetBoxFit`),
  and `BarcodeElement` (QR / Code128 / EAN-13 / Data Matrix); and
  `registerBuiltInElementCodecs` to wire all four built-in element codecs.

## 0.1.0

Initial scaffold release.

### Added

- Single public entry point `package:jet_print/jet_print.dart`.
- `JetPrintPlaceholder` — a `const`, theme-aware placeholder widget that reflects
  the active `shadcn_ui` theme.
- `jetPrintVersion` — the library's declared version string, establishing the
  SemVer baseline.
- Three internal layer seams (`domain`, `rendering`, `designer`) under `lib/src/`
  with an inward-only dependency rule enforced by an architecture test.
