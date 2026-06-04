# Changelog

All notable changes to the `jet_print` library are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
