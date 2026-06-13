---
description: "Task list for spec 022 — Host & System Fonts in Font Pickers"
---

# Tasks: Host & System Fonts in Font Pickers

**Input**: Design documents from `/specs/022-host-fonts/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/host-fonts-api.md, quickstart.md

**Tests**: MANDATORY per Constitution Principle III (Test-First, NON-NEGOTIABLE) and Principle IV (golden tests for rendered output). Every phase below writes failing tests **before** implementation, organized by the C1–C12 contracts.

**Organization**: Tasks are grouped by user story (US1 = P1 host registration; US2 = P2 unavailable-font portability) so each story can be implemented and tested independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: `[US1]` / `[US2]` for user-story tasks; Setup/Foundational/Polish have no story label
- All paths are relative to the repo root `/Users/ahmeturel/Projects/oss/jet-print/`
- Run tests with `flutter test packages/jet_print` from the repo root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Test-support fixtures the new font tests need (real TTF bytes to parse, plus a deliberately-bad sample).

- [X] T001 [P] Add a test font-byte support helper at `packages/jet_print/test/support/test_fonts.dart` exposing: a valid regular TTF, a valid bold TTF, and a valid italic TTF (reuse the bundled JetSans/JetSerif/JetMono asset bytes already loaded by the default registry where possible), plus an empty `Uint8List` and a malformed (non-TTF) byte sample for rejection tests. This is shared by the foundational and US1 tests.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The public font value types, the re-exported exception, and the internal registry ingest — the font primitives **both** user stories build on.

**⚠️ CRITICAL**: No user-story work can begin until this phase is complete.

### Tests (write first — MUST FAIL before implementation) ⚠️

- [X] T002 [P] Write `packages/jet_print/test/rendering/text/jet_font_test.dart` covering contracts C1–C3: `JetFontFace(bytes)` defaults `weight: JetFontWeight.normal`, `italic: false`; value equality over `(bytes identity, weight, italic)`; `JetFontFamily` accepts a regular-only family and a full 4-face family (faces preserved in order); rejects empty `name` with `ArgumentError`, rejects no-regular-face with `FontFormatException` whose message names the family, rejects empty/malformed face bytes with `FontFormatException` naming the family + offending weight/italic, rejects duplicate `(weight, italic)` with `ArgumentError`; assert all throws are synchronous at construction.
- [X] T003 [P] Write `packages/jet_print/test/rendering/text/font_registry_host_test.dart` covering contracts C4–C6: `FontRegistry()..registerDefault()..registerHostFonts([famA])` resolves famA's bytes/metrics; same-name (or same family twice) → last-wins per face with exactly one `families` entry; after ingest `hasDefault` is true, all three built-in names present, an unregistered family falls back to default, shadowing a built-in replaces only its faces and never removes the default; `families` order is `[JetSans, JetSerif, JetMono, …host in supplied order]` and is stable across repeated reads; a regular-only host family asked for bold/italic returns the **same regular byte instance** and equal metrics without throwing.

### Implementation (make the tests green)

- [X] T004 [P] Create `packages/jet_print/lib/src/rendering/text/jet_font.dart` defining public `JetFontFace {Uint8List bytes; JetFontWeight weight = JetFontWeight.normal; bool italic = false}` (const-friendly, `==`/`hashCode` over bytes-identity+weight+italic) and public `JetFontFamily {String name; List<JetFontFace> faces}` with eager synchronous constructor validation: non-empty name (else `ArgumentError`), ≥1 regular face (else `FontFormatException` naming the family), each face's bytes parse via `parseTtfMetrics` (re-throw `FontFormatException` with family name + weight/italic on failure), no duplicate `(weight, italic)` (else `ArgumentError`).
- [X] T005 Add `void registerHostFonts(List<JetFontFamily> families)` to `packages/jet_print/lib/src/rendering/text/font_registry.dart` — iterate families in list order, iterate each family's faces, calling the existing `register(family.name, face.bytes, weight: face.weight, italic: face.italic)`; always intended to run after `registerDefault()` so host faces overwrite per `family|weight|italic` (last-wins, additive). `FontRegistry` stays internal; the `families` getter is unchanged. (Depends on T004 for the `JetFontFamily` type.)
- [X] T006 Export `JetFontFace`, `JetFontFamily`, and the previously-internal `FontFormatException` from the barrel `packages/jet_print/lib/jet_print.dart` (do **not** export `FontRegistry`). (Depends on T004.)

**Checkpoint**: Font value types validate eagerly, the registry ingests host families last-wins, and the new symbols are exported. Both user stories can now begin.

---

## Phase 3: User Story 1 - Host application contributes its own fonts (Priority: P1) 🎯 MVP

**Goal**: A host registers brand fonts once at startup; they appear in every designer font picker previewed in their own typeface, and render byte-for-byte identically across canvas, preview, PDF, and PNG — driven by the single registry the render chain carries.

**Independent Test**: Register one font family with the designer (`fonts:`) and the engine (`RenderOptions.fonts`), open the designer, confirm the family appears in the family picker previewed in its own typeface, apply it to a text element, and confirm the rendered glyphs are identical across canvas, preview, and a PDF/PNG export.

### Tests for User Story 1 (write first — MUST FAIL before implementation) ⚠️

- [X] T007 [P] [US1] Write/extend `packages/jet_print/test/rendering/engine/render_options_test.dart` and create `packages/jet_print/test/rendering/engine/rendered_report_fonts_test.dart` for contract C7: `RenderOptions()` has `fonts == const []`; `JetReportEngine().render(t, src, options: RenderOptions(fonts: [famA]))` returns a `RenderedReport` whose carried registry resolves famA; with `fonts` empty the carried registry is default-only; assert the carried registry is the **same** instance used for layout measurement (no second default-only build).
- [X] T008 [P] [US1] Extend `packages/jet_print/test/rendering/export/pdf_painter_parity_test.dart` for contracts C8 & C12: a report rendered with a host family exports a PDF that uses that family (not the default) and embeds the host face **once** per document (byte-keyed cache), with the text remaining real/selectable (present in the PDF font resources); a default-only report is unchanged.
- [X] T009 [P] [US1] Create `packages/jet_print/test/rendering/host_font_parity_golden_test.dart` for contract C9: a page whose text uses a host family is byte-identical across canvas, preview, PNG, and PDF text geometry; assert existing default-only goldens remain byte-identical (SC-005).
- [X] T010 [P] [US1] Extend `packages/jet_print/test/designer/properties_editor_test.dart` for contract C10 (extends 021 C3): with `JetReportDesigner(fonts: [famA])` the family picker lists famA **after** the built-ins, previewed in its own typeface; applying it commits `fontFamily: "Acme Brand"` as one undoable change and the canvas re-renders in that font.

### Implementation for User Story 1 (make the tests green)

- [X] T011 [US1] Add `List<JetFontFamily> fonts = const <JetFontFamily>[]` to `packages/jet_print/lib/src/rendering/engine/render_options.dart` with dartdoc (register-before-render; threaded to `RenderedReport`).
- [X] T012 [US1] Add an **internal** `final FontRegistry fonts;` to `packages/jet_print/lib/src/rendering/engine/rendered_report.dart` (constructor param internal, not exported).
- [X] T013 [US1] In `packages/jet_print/lib/src/rendering/engine/jet_report_engine.dart` `render`, build the registry once (`FontRegistry()..registerDefault()..registerHostFonts(options.fonts)`), pass it to `ReportLayouter` for measurement **and** attach the same instance to the returned `RenderedReport`. (Depends on T005, T011, T012.)
- [X] T014 [US1] Change `packages/jet_print/lib/src/designer/preview/jet_report_preview.dart` to paint using `widget.report.fonts` (the carried registry) instead of constructing `FontRegistry()..registerDefault()`. No new public parameter. (Depends on T012.)
- [X] T015 [US1] Change `packages/jet_print/lib/src/rendering/export/jet_report_exporter.dart` so `toPdf` and `pageToPng` use `report.fonts` (the carried registry) instead of building a default-only one. No new public parameter; printer inherits via the exporter. (Depends on T012.)
- [X] T016 [US1] Add `List<JetFontFamily> fonts = const <JetFontFamily>[]` to `packages/jet_print/lib/src/designer/jet_report_designer.dart` and build the hoisted registry as `FontRegistry()..registerDefault()..registerHostFonts(widget.fonts)` (the existing `preloadUiFontFamilies` picks up host families for free). Dartdoc the register-before-build contract. (Depends on T005.)
- [X] T017 [US1] Add `List<JetFontFamily> fonts = const <JetFontFamily>[]` to `packages/jet_print/lib/src/designer/jet_report_workspace.dart` and forward it to the nested `JetReportDesigner`. (Depends on T016.)
- [X] T018 [US1] Update `packages/jet_print/test/public_api_test.dart` to record all additions: `JetFontFace`, `JetFontFamily`, `FontFormatException` exported; `RenderOptions.fonts`; `JetReportDesigner.fonts` and `JetReportWorkspace.fonts` params; and assert `FontRegistry` is still NOT exported. (Depends on T006, T011, T016, T017.)
- [X] T019 [US1] Add dartdoc to every new public symbol (the two value types, the re-exported `FontFormatException`, `RenderOptions.fonts`, the designer/workspace `fonts` params) covering: bytes-are-the-input, register-before-build, last-wins, and the "pass the same `List<JetFontFamily>` to both the designer and `RenderOptions`" guidance. (Touches jet_font.dart, render_options.dart, jet_report_designer.dart, jet_report_workspace.dart.)
- [X] T020 [P] [US1] Add one custom `.ttf` asset under `apps/jet_print_playground/assets/fonts/` and declare it in `apps/jet_print_playground/pubspec.yaml` (the playground's own asset, keeping the library self-contained).
- [X] T021 [US1] In `apps/jet_print_playground/lib/main.dart`, load the asset bytes into a `List<JetFontFamily>` and pass the **same list** to both `JetReportWorkspace.fonts` and the `renderReport` callback's `RenderOptions.fonts`, demonstrating FR-012 / SC-001 end-to-end. (Depends on T011, T017, T020.)

**Checkpoint**: A host font appears in the picker previewed in its own typeface, applies on the canvas, and renders byte-identically across preview/PDF/PNG; the playground proves it end-to-end. User Story 1 is independently shippable (MVP).

---

## Phase 4: User Story 2 - Reports stay readable when a font is not registered (Priority: P2)

**Goal**: A report naming a host font that is **not** registered in the current session opens with zero errors, renders in a fallback font, shows the name marked unavailable in the picker, preserves the name on save, and still exports — extending the existing 021 unavailable-family behavior to host-contributed names.

**Independent Test**: Author a report using a host font, then load it in a session where that font is not registered; confirm it opens without error, the stored family name is shown as unavailable in the picker, the value is preserved on save, and the text renders (and exports) in a fallback font.

### Tests for User Story 2 (write first — MUST FAIL or confirm coverage before implementation) ⚠️

- [X] T022 [P] [US2] Extend `packages/jet_print/test/designer/properties_editor_test.dart` for contract C11 (designer side): a text element whose stored `fontFamily` is **not** in the current registry shows the name marked unavailable in the family picker, and the stored name is preserved across an unrelated edit and on save (never silently swapped).
- [X] T023 [P] [US2] Create `packages/jet_print/test/rendering/host_font_unavailable_test.dart` for contract C11 (codec/export side): a report naming an unregistered host family round-trips byte-identically through the codecs (name preserved, `kReportSchemaVersion` unchanged), renders via the fallback font, and `JetReportExporter.toPdf`/`.pageToPng` succeed using the fallback without blocking on the missing font.

### Implementation for User Story 2

- [X] T024 [US2] Confirm the existing 021 unavailable-family path fully covers host-contributed names through the registry the render chain now carries (designer picker, preview, and export). Per data-model §8 this requires **no new code**; if any path hard-fails on an unregistered name (e.g. export throwing instead of falling back), apply the minimal fallback fix in the offending file (`jet_report_exporter.dart` / `jet_report_preview.dart` / the picker) so T022–T023 pass.

**Checkpoint**: A host-font report degrades gracefully and portably when the font is absent; both user stories work independently.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, formatting, and full-suite validation.

- [X] T025 [P] Add a `CHANGELOG.md` entry under `packages/jet_print/CHANGELOG.md` describing the additive host-font API (value types, exported exception, `RenderOptions.fonts`, designer/workspace `fonts` param; no schema change).
- [X] T026 [P] Run `flutter analyze` (zero warnings) and `dart format --output none --set-exit-if-changed packages/jet_print`; fix any analyzer/format issues introduced.
- [X] T027 Run the full suite `flutter test packages/jet_print` (C1–C12 green, default-only goldens byte-identical). Explicitly confirm `layer_boundaries_test` still passes (the new public value types in the **rendering** layer must keep dependencies pointing inward — Principle II) and `public_api_test` reflects the exact additions with `FontRegistry` unexported (Principle I). Then walk the `quickstart.md` scenario in the playground to confirm the font appears in the picker and renders identically across canvas/preview/PDF/PNG, and degrades gracefully when unregistered. — DONE (automated): full suite **1360 green, 0 skipped**; `flutter analyze` clean (library + playground); `dart format` clean. `layer_boundaries_test` updated to admit the engine→`text/` inward dependency (the engine now owns the per-render registry build) and passes; `public_api_test` records the additions with `FontRegistry` still unexported. **PENDING (manual):** the macOS-desktop `quickstart.md` GUI walkthrough in the playground.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — **BLOCKS both user stories** (value types, exception export, registry ingest).
- **User Story 1 (Phase 3)**: Depends on Foundational. The MVP.
- **User Story 2 (Phase 4)**: Depends on Foundational. Independently testable; in practice exercised against the registry US1 wires through, but its acceptance (graceful absence) does not require US1's playground/golden work.
- **Polish (Phase 5)**: Depends on all desired user stories being complete.

### Key Task-Level Dependencies

- T005 (registerHostFonts) → needs T004 (value types).
- T006 (barrel export) → needs T004.
- T013 (engine builds + carries registry) → needs T005, T011, T012.
- T014 (preview) and T015 (exporter) → need T012.
- T017 (workspace) → needs T016 (designer).
- T018 (public_api_test) → needs T006, T011, T016, T017.
- T021 (playground main) → needs T011, T017, T020.
- T024 (US2 verification) → relies on the carried registry from T013–T015.
- Within each story: tests (T002–T003, T007–T010, T022–T023) are written and failing **before** their implementation tasks.

### Parallel Opportunities

- **Foundational tests**: T002 and T003 in parallel (different files).
- **Foundational impl**: T004 then T005/T006 (T005 and T006 both depend only on T004 and touch different files → parallel after T004).
- **US1 tests**: T007, T008, T009, T010 all in parallel (different files).
- **US1 impl**: T011 and T012 in parallel; T020 (playground asset) in parallel with the library changes.
- **US2 tests**: T022 and T023 in parallel (different files).
- **Polish**: T025 and T026 in parallel.

---

## Parallel Example: User Story 1 tests

```bash
# Launch all US1 contract tests together (each a different file), all expected to FAIL first:
Task: "render_options/rendered_report_fonts tests (C7) in test/rendering/engine/"
Task: "PDF embedding/parity tests (C8/C12) in test/rendering/export/pdf_painter_parity_test.dart"
Task: "Cross-path parity golden (C9) in test/rendering/host_font_parity_golden_test.dart"
Task: "Picker lists/applies host family (C10) in test/designer/properties_editor_test.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup (test fixtures).
2. Phase 2: Foundational (value types + registry ingest) — CRITICAL, blocks everything.
3. Phase 3: User Story 1 — register → picker → identical across canvas/preview/PDF/PNG; playground demo.
4. **STOP and VALIDATE**: run the US1 independent test; the picker shows the host font and all four render paths match.
5. Ship the MVP.

### Incremental Delivery

1. Setup + Foundational → font primitives ready.
2. Add US1 → test independently → MVP (host fonts render everywhere, by construction WYSIWYG-safe).
3. Add US2 → test independently → portability (graceful absence), no schema change.
4. Polish → docs, format, full-suite + quickstart validation.

---

## Notes

- **TDD is non-negotiable** (Constitution III): verify each test FAILS before writing implementation; never merge with failing/skipped tests.
- **WYSIWYG by construction** (Constitution IV): the engine builds **one** registry and `RenderedReport` carries it; preview/export/print read it off the report (T014/T015) — never build a parallel default-only registry. T009's parity golden and T008/T012's PDF embedding are the guardrails.
- **No schema change** (Constitution V): `kReportSchemaVersion` is unchanged; reports store only the family name. T023 asserts byte-identical round-trips.
- `[P]` tasks touch different files with no incomplete dependencies. T010 (US1) and T022 (US2) both extend `properties_editor_test.dart` in different phases — do them sequentially, not in parallel with each other.
- Commit after each task or logical group.
