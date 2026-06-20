# T052 — Acceptance record (format properties, spec 021)

**Closed:** 2026-06-20, via Epic 1 (release hygiene), "automate + waive".

## Automated coverage (replaces the automatable quickstart steps)
- Style models + sentinel copyWith: `test/domain/styles/*`, and the
  `JetTextStyle`/`JetBoxStyle`/`setBarcodeColor` cases in `public_api_test.dart`.
- Single-undo / no-op command semantics: `test/designer/controller/*_command_test.dart`.
- Properties-editor gating/commit/validation (C1–C9): `test/designer/properties_editor_test.dart`.
- All-three-kinds save→reload parity (quickstart §4.3):
  `test/domain/serialization/styled_elements_roundtrip_test.dart`.

## Human-verified, then waived from per-release manual repetition
Visual/interaction steps the harness cannot assert; verified once by inspection
in the macOS playground and waived going forward:
- Canvas re-renders instantly on each font/color/alignment change.
- Color swatch popover and `#hex` entry (incl. reject-and-restore on bad input).
- `⌘Z` steps back exactly one committed change and the editors track the
  restored values.
- Preview + exported PDF/PNG visually match the canvas styling.

Re-verifiable by running `apps/jet_print_playground`; no longer a release blocker.
