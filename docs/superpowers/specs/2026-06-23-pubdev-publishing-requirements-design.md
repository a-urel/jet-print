# Publishing `jet_print` to pub.dev — Requirements & Best-Practice

**Date:** 2026-06-23
**Status:** Requirements reference (no implementation in scope)
**Package:** `packages/jet_print` (the only publishable member; `jet_print_google_fonts` and the workspace root are `publish_to: none`)

## Purpose

A single authoritative checklist of what pub.dev *requires* to accept a publish,
what its scoring panel *rewards* (best-practice), and which of those are
currently **gaps for `jet_print`**. This document lists requirements only — it
does not implement them. A later plan/epic (the existing E6 "1.0 freeze") can
execute against it.

## Current state (measured 2026-06-23)

- `dart pub publish --dry-run` → **1 warning**: `intl: any` has no version
  constraint. Everything else passes.
- Archive size: **~1 MB** (limit is 100 MB).
- Present: `LICENSE` (Apache-2.0), `CHANGELOG.md`, `README.md`, pubspec
  `repository`/`homepage`/`issue_tracker`/`topics`.
- Absent: `example/` directory.
- Public API barrel (`lib/jet_print.dart`): **57 exports, ~18 doc comments** —
  dartdoc coverage on the full re-exported surface is unverified and likely
  under the 20 % scored threshold.
- `pana` (the exact scorer pub.dev runs) is **not installed** locally.
- Git remote `https://github.com/a-urel/jet-print.git` matches the pubspec, but
  the repository is **private** (per project memory), so the repository link
  cannot be verified.

## 1. Hard requirements (publish is rejected without these)

| Requirement | Status |
|---|---|
| Valid pubspec: `name`, `version`, `description` (60–180 chars), `environment` SDK constraint | ✓ have |
| OSI-approved `LICENSE` file at package root | ✓ Apache-2.0 |
| All dependencies hosted on pub.dev with version constraints; **no** `path:`/`git:` deps | ✗ `intl: any` (warning, not yet hard-rejected, but fix it) |
| Archive < 100 MB | ✓ ~1 MB |
| Package not marked `publish_to: none` | ✓ (`jet_print` publishes; root + gfonts excluded) |
| Authenticated pub.dev account with publish rights | action: confirm login (`dart pub login`) |

Note: `resolution: workspace` in the member pubspec does **not** block publishing
— `dart pub publish` resolves it; the dry-run already confirms this.

## 2. pub.dev score panel (best-practice — the public /160 + likes badge)

pub.dev runs `pana` and grants points across these axes. Maximize all:

1. **Follow Dart file conventions** — valid pubspec, `LICENSE`, `CHANGELOG.md`,
   and a non-empty `example/`.
2. **Provide documentation** — at least **20 % of public API members carry
   dartdoc** *and* an `example/` exists.
3. **Platform support** — points scale with the number of supported platforms.
   `jet_print` targets web + macOS + iOS + Android + Windows + Linux; declare and
   keep them all green.
4. **Pass static analysis** — `dart analyze` reports **zero** errors, warnings,
   or lints (under `flutter_lints`).
5. **Support up-to-date dependencies** — every dependency resolves to its latest
   published version against a current SDK.
6. **WASM compatibility** — a newer scored axis; passes if no
   `dart:html`/non-WASM-safe imports leak. (Web support already hardened in E4.)

## 3. `jet_print`-specific gaps (the actual work list)

1. **`intl` constraint.** Replace `intl: any` with a real range (e.g.
   `intl: ^0.20.2`) to clear the sole dry-run warning. *(Deferred to E6 in
   memory; this is the trigger to do it.)*
2. **Add `example/`.** A runnable, minimal `example/lib/main.dart` (trim the
   playground to one screen). Required for both the *conventions* and
   *documentation* score axes.
3. **dartdoc coverage audit.** Document the 57-export public surface until
   ≥ 20 % of members have `///` comments. Verify with `dart doc` and `pana`'s
   per-member report. Prioritize the top-level entry types a consumer touches
   first.
4. **Make the repository public.** Enables pub.dev repository-link verification
   (the "verified repository" affordance) and unblocks the CI badge story.
   Optional for *accepting* a publish, expected for *credibility*.
5. **CHANGELOG release entry.** Convert the `## Unreleased` section to a dated,
   versioned entry (`## 0.1.0 - 2026-…`) matching the pubspec `version` at the
   moment of publish.
6. **`screenshots:` in pubspec.** `jet_print` is a *visual* WYSIWYG designer —
   screenshots render directly on the listing page and are a high-value,
   low-cost win. Add 1–3 PNGs via the pubspec `screenshots:` field.
7. **Version decision.** Choose deliberately:
   - `0.1.0` preview — claims the name, signals "API may break", room to iterate.
   - `1.0.0` — only after the E6 API freeze; semver then forbids breaking
     changes without a `2.0.0`.
   Document the choice; do not drift into 1.0 by accident.

## 4. Best-practice process gate (run, in order, before every publish)

1. `dart pub global activate pana` then `pana` (or `flutter pub global run pana`)
   in `packages/jet_print` → **target ≥ 140 / 160**; read every deduction.
2. `dart pub publish --dry-run` → **0 warnings** (not just "1 warning").
3. `dart analyze` → clean.
4. `dart format --output=none --set-exit-if-changed .` → clean. *(Memory notes
   ~12 format-dirty files on `main`; resolve first.)*
5. Optional `.pubignore` — exclude the bulky test fixtures (`fixture_font_data.dart`
   ~141 KB, golden PNGs) from the published archive to shrink the consumer
   download. Tests are published by default; they are not needed by consumers.
6. Tag the release in git and cut a GitHub release matching the pubspec version.
7. Optional: register a **verified publisher** (domain-verified) for the listing
   badge.
8. `dart pub publish` (only after 1–4 are green).

## Out of scope

- Implementing any of the above (this is a requirements reference).
- Publishing `jet_print_google_fonts` (intentionally `publish_to: none`).
- The E6 1.0 API-freeze work itself (separate epic); this doc only flags where it
  intersects publishing (items 3.1, 3.7).

## Open questions

- Final version at first publish: `0.1.0` preview vs gate on E6 `1.0.0`?
- Make the repo public before or after first publish?
- Ship `example/` as a trimmed single screen, or point at the full playground?
