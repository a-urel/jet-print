# Epic E3 — Desktop Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove `jet_print` builds, tests, and renders correctly on macOS, Windows, and Linux by expanding CI to a 3-OS matrix and hardening the platform-conditional surfaces — with the golden tests gated to a single canonical host.

**Architecture:** Two phases. **Phase A** (Tasks 1–7) is locally verifiable on the macOS dev host: normalize formatting so the canonical job's format gate is green, gate the golden surface behind a `golden` test tag, generate the playground's Windows/Linux runner directories, relax the playground's macOS-only guard, add cross-platform `.gitattributes` hygiene, and rewrite the CI workflow into a 3-OS matrix. **Phase B** is a CI feedback loop — push the branch, read the real Windows/Linux/macOS Actions results, and absorb whatever fixes make all three green (scope decision a). Phase B is *not* a fixed task list; it is driven against Actions.

**Tech Stack:** Flutter `3.44.0` (pinned), Dart, GitHub Actions (`subosito/flutter-action@v2`), `flutter_test` tags (`@Tags` / `tags:`), CMake desktop runners.

## Global Constraints

- Suite green via the documented CI command from repo root: `flutter test packages/jet_print apps/jet_print_playground`.
- Run `flutter`/`dart` from `packages/jet_print` for local checks; run all `git` from the repo root (the `flutter` tool leaves cwd inside the package).
- **Goldens must not change** — every committed `*.png` and `test/goldens/invoice.pdf` stays byte-identical (`git status` shows no golden diffs at every task).
- **No engine/domain/rendering behavior change; no public-API change.** E3 touches only: formatting whitespace, test-file tag annotations, the playground guard, generated runner dirs, `.gitattributes`, `dart_test.yaml`, and `.github/workflows/ci.yml`.
- Arch tests scan source via `findWorkspaceRoot()` (`test/support/workspace.dart`) — never bare relative dirs.
- The expression layer must not import the fill layer (arch-test-enforced; unaffected by E3 but must stay true).
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Do not push** until Phase A (Tasks 1–7) is complete and the user is ready to start Phase B.
- Canonical OS = **macOS**: it alone runs the full suite (including the golden surface) and the `dart format` gate. Ubuntu and Windows run `flutter test --exclude-tags golden …`.

## Branch setup (before Task 1)

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git checkout main
git checkout -b e3-desktop-matrix
```

All Task commits land on `e3-desktop-matrix`.

## File structure

| File | Responsibility | Task |
|------|----------------|------|
| (33 `*.dart` files, whitespace only) | Bring the repo to `dart format` cleanliness so the canonical format gate passes | 1 |
| `.gitattributes` (new, repo root) | LF for `*.dart`; binary for `*.png` / `*.pdf` | 2 |
| `packages/jet_print/dart_test.yaml` (new) | Declare the `golden` tag (no unknown-tag warning under `--exclude-tags`) | 2 |
| 11 pure-golden test files | File-level `@Tags(['golden'])` | 3 |
| 3 mixed test files | Test/group-level `tags: 'golden'` on only the golden case(s) | 4 |
| `apps/jet_print_playground/lib/main.dart` | Relax the desktop guard to macOS ∪ Windows ∪ Linux | 5 |
| `apps/jet_print_playground/windows/`, `…/linux/` (new, generated) | CMake desktop runners so the app builds on Win/Linux | 6 |
| `.github/workflows/ci.yml` | 3-OS build+test matrix | 7 |

---

### Task 1: Normalize repository formatting (unblock the canonical format gate)

**Why this is in scope:** the canonical macOS job keeps the `dart format --output=none --set-exit-if-changed .` step (mirrored from today's `ci.yml:29`). On `main` that command currently **exits 1** — 33 files (`lib/src/rendering/elements/placeholder.dart` + 32 test files) are not in `dart format` canonical form under the pinned `3.44.0` formatter. Until this is fixed, the macOS leg can never be green, so SC-E3-001 fails. This is the "one-commit format pass" deferred out of E1; E3 is where it lands. `dart format` changes whitespace only — no behavior, no golden bytes.

**Files:**
- Modify: 33 `*.dart` files (whitespace only; exact set is whatever the pinned formatter rewrites).

**Interfaces:**
- Consumes: nothing.
- Produces: a repo where `dart format --output=none --set-exit-if-changed .` exits 0 — every later task and the canonical CI job depend on this.

- [ ] **Step 1: Confirm the gate fails first (the failing "test")**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
dart format --output=none --set-exit-if-changed . ; echo "exit=$?"
```
Expected: a list of `Changed …` lines and `exit=1`.

- [ ] **Step 2: Apply formatting**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
dart format .
```
Expected: `Formatted N files (33 changed …)` (count may differ slightly if the tree moved).

- [ ] **Step 3: Confirm the gate now passes**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
dart format --output=none --set-exit-if-changed . ; echo "exit=$?"
```
Expected: `exit=0` (no `Changed` lines).

- [ ] **Step 4: Confirm no golden changed and behavior is intact**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git status --porcelain | grep -E '\.(png|pdf)$' || echo "no golden/pdf changes (good)"
flutter test packages/jet_print apps/jet_print_playground
```
Run the suite from repo root. Expected: no `.png`/`.pdf` in the diff; `All tests passed!` (same count as pre-E3, ~1964+ green).

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add -A
git commit -m "$(cat <<'EOF'
style(e3): dart format normalize so the canonical CI format gate passes

Pre-existing: `dart format --set-exit-if-changed .` exited 1 on main (33
files under the pinned 3.44.0 formatter — placeholder.dart + 32 test files).
The E3 macOS canonical job keeps this gate, so normalize now. Whitespace
only; no behavior change; goldens byte-identical.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Golden-tag declaration + `.gitattributes`

**Files:**
- Create: `.gitattributes` (repo root)
- Create: `packages/jet_print/dart_test.yaml`

**Interfaces:**
- Consumes: nothing.
- Produces: the `golden` tag is a *declared* tag (Tasks 3/4 attach it; the CI matrix excludes it off-canonical). `.gitattributes` guarantees LF Dart + binary goldens on every platform's checkout.

- [ ] **Step 1: Create `.gitattributes`**

`.gitattributes` (repo root), exact contents:

```gitattributes
# Cross-platform hygiene (E3). LF-normalize Dart so the `dart format` gate
# cannot fail on a Windows CRLF checkout; mark golden artifacts binary so EOL
# conversion can never corrupt a baseline.
*.dart text eol=lf
*.png  binary
*.pdf  binary
```

- [ ] **Step 2: Verify attributes resolve and nothing renormalizes**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git check-attr eol -- packages/jet_print/lib/src/rendering/elements/placeholder.dart
git check-attr binary -- packages/jet_print/test/goldens/invoice.pdf
git status --porcelain | grep -vE '^\?\? \.gitattributes$' | grep -E '\.(dart|png|pdf)' || echo "no dart/png/pdf renormalization (good)"
```
Expected: `eol: lf` for the dart file; `binary: set` for the pdf; and **no** `*.dart`/`*.png`/`*.pdf` files show as modified (the repo is already LF on macOS, so adding `.gitattributes` causes no churn — do **not** run `git add --renormalize`).

- [ ] **Step 3: Create the tag declaration**

`packages/jet_print/dart_test.yaml`, exact contents:

```yaml
# Declares the `golden` tag used to gate visual/byte-pinned goldens to the
# canonical (macOS) CI host. Off-canonical jobs run `flutter test
# --exclude-tags golden`; macOS runs the full suite. See
# docs/superpowers/specs/2026-06-20-e3-desktop-matrix-design.md §5.
tags:
  golden:
    description: >-
      Visual PNG goldens and the byte-pinned invoice.pdf comparison. Host
      font rasterization / PDF font-subsetting differs across OSes, so these
      run only on the macOS canonical host.
```

- [ ] **Step 4: Verify the tag is recognized (no unknown-tag warning)**

```bash
cd packages/jet_print
flutter test --exclude-tags golden test/rendering/export/pdf_determinism_test.dart 2>&1 | tail -6
```
Expected: all 4 tests still run and pass (no tags attached yet), and **no** "Unknown tag 'golden'" warning appears.

- [ ] **Step 5: Full suite green + commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print apps/jet_print_playground
git add .gitattributes packages/jet_print/dart_test.yaml
git commit -m "$(cat <<'EOF'
build(e3): declare the `golden` test tag + add cross-platform .gitattributes

dart_test.yaml declares the `golden` tag the matrix excludes off-canonical;
.gitattributes pins LF for *.dart and binary for *.png/*.pdf. No tags
attached yet (Tasks 3/4). Suite unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```
Expected: `All tests passed!`

---

### Task 3: Tag the 11 pure-golden test files

Each of these files' every test case is a golden, so a file-level `@Tags(['golden'])` is correct. The annotation resolves through the `package:flutter_test/flutter_test.dart` import every one already has (empirically verified analyze-clean).

**Files (all under `packages/jet_print/test/`):**
- Modify: `designer/canvas/bound_token_render_test.dart`
- Modify: `designer/goldens/design_surface_grid_test.dart`
- Modify: `designer/goldens/shape_forms_test.dart`
- Modify: `designer/goldens/data_aware_invoice_test.dart`
- Modify: `designer/goldens/jet_report_designer_light_dark_test.dart`
- Modify: `designer/goldens/design_surface_test.dart`
- Modify: `designer/goldens/barcode_symbologies_golden_test.dart`
- Modify: `rendering/paint/canvas_painter_golden_test.dart`
- Modify: `goldens/rendered_invoice_test.dart`
- Modify: `goldens/label_sheet_test.dart`
- Modify: `goldens/formatted_value_test.dart`

**Interfaces:**
- Consumes: the `golden` tag declared in Task 2.
- Produces: these 11 files are entirely excluded by `--exclude-tags golden`.

- [ ] **Step 1: Add the file-level annotation to each file**

For **each** of the 11 files, insert these two lines immediately **before the first `import` statement** (after any leading `//` comment block), followed by one blank line:

```dart
@Tags(['golden'])
library;
```

Example — `rendering/paint/canvas_painter_golden_test.dart` starts directly with `import 'dart:typed_data';`, so the top becomes:

```dart
@Tags(['golden'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;
```

Example — `goldens/rendered_invoice_test.dart` starts with a `//` comment block; insert after it, before `import 'package:flutter/material.dart'`:

```dart
// … existing leading comment block (unchanged) …
// Public API only; regenerate with `--update-goldens`.
@Tags(['golden'])
library;

import 'package:flutter/material.dart' show ThemeMode;
```

- [ ] **Step 2: Verify each tagged file is fully excluded**

```bash
cd packages/jet_print
for f in \
  test/designer/canvas/bound_token_render_test.dart \
  test/designer/goldens/design_surface_grid_test.dart \
  test/designer/goldens/shape_forms_test.dart \
  test/designer/goldens/data_aware_invoice_test.dart \
  test/designer/goldens/jet_report_designer_light_dark_test.dart \
  test/designer/goldens/design_surface_test.dart \
  test/designer/goldens/barcode_symbologies_golden_test.dart \
  test/rendering/paint/canvas_painter_golden_test.dart \
  test/goldens/rendered_invoice_test.dart \
  test/goldens/label_sheet_test.dart \
  test/goldens/formatted_value_test.dart ; do
  echo "== $f =="
  flutter test --exclude-tags golden "$f" 2>&1 | tail -2
done
```
Expected: each prints `No tests ran.` + `No tests match the requested tag selectors: … exclude: "golden"`.

- [ ] **Step 3: Verify analyze clean and the full suite still runs them on macOS**

```bash
cd packages/jet_print
flutter analyze
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print apps/jet_print_playground
git status --porcelain | grep -E '\.(png|pdf)$' || echo "no golden changes (good)"
```
Expected: `No issues found!`; `All tests passed!` (full run is unfiltered, so goldens still execute on macOS); no golden diffs.

- [ ] **Step 4: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test
git commit -m "$(cat <<'EOF'
test(e3): tag the 11 pure-golden test files @Tags(['golden'])

File-level golden tag so off-canonical CI jobs exclude them. Annotation
resolves via the existing flutter_test import; macOS still runs them in the
full suite. Goldens byte-identical.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Tag the golden case(s) in the 3 mixed files (+ local matrix proxy)

These files mix goldens with platform-independent cases (pixel dimensions, byte self-consistency, exceptions). Tag **only** the golden case(s) at test/group level so the platform-independent cases keep running on all three OSes.

**Files (all under `packages/jet_print/test/`):**
- Modify: `designer/goldens/page_letter_landscape_test.dart` (2 of 3 cases are golden)
- Modify: `rendering/export/png_export_test.dart` (1 of 8 cases is golden)
- Modify: `rendering/export/pdf_determinism_test.dart` (1 of 4 cases is the byte-pinned PDF)

**Interfaces:**
- Consumes: the `golden` tag (Task 2).
- Produces: the **local proxy** for the Linux/Windows test job — `flutter test --exclude-tags golden packages/jet_print apps/jet_print_playground` — runs green with the entire golden surface skipped.

- [ ] **Step 1: `page_letter_landscape_test.dart` — tag the two `testWidgets` goldens**

The first `test(...)` (export size check, lines ~78–86) is platform-independent — **leave it untagged**. Tag the two `testWidgets` cases. Change the first `testWidgets`'s closing line:

```dart
      matchesGoldenFile('page_letter_landscape_canvas_light.png'),
    );
  });
```
to:
```dart
      matchesGoldenFile('page_letter_landscape_canvas_light.png'),
    );
  }, tags: 'golden');
```

And the second `testWidgets`'s closing line:

```dart
      matchesGoldenFile('page_letter_landscape_export.png'),
    );
  });
```
to:
```dart
      matchesGoldenFile('page_letter_landscape_export.png'),
    );
  }, tags: 'golden');
```

- [ ] **Step 2: `png_export_test.dart` — tag the golden-pin group**

Change the final group's closing (the `group('golden pin (T020) — decoded-pixel comparison', () { … })` at lines ~100–108):

```dart
      await expectLater(
          image, matchesGoldenFile('../../goldens/invoice_page1_2x.png'));
    });
  });
}
```
to:
```dart
      await expectLater(
          image, matchesGoldenFile('../../goldens/invoice_page1_2x.png'));
    });
  }, tags: 'golden');
}
```
(Only the group's closing `});` → `}, tags: 'golden');`. The three other groups — dimensions, page-order, determinism, errors — stay untagged.)

- [ ] **Step 3: `pdf_determinism_test.dart` — tag only the pinned-PDF case**

The three self-consistency cases (export-twice-identical, re-export, partially-viewed) are valuable cross-platform determinism checks — **leave them untagged**. Tag only the 4th case. Change its closing:

```dart
    expect(bytes, golden.readAsBytesSync(),
        reason: 'the exported invoice changed. If deliberate (SDK/dart_pdf '
            'upgrade or a real visual change), regenerate with '
            '--update-goldens and review; otherwise determinism broke');
  });
}
```
to:
```dart
    expect(bytes, golden.readAsBytesSync(),
        reason: 'the exported invoice changed. If deliberate (SDK/dart_pdf '
            'upgrade or a real visual change), regenerate with '
            '--update-goldens and review; otherwise determinism broke');
  }, tags: 'golden');
}
```

- [ ] **Step 4: Verify the per-file partition is exact**

```bash
cd packages/jet_print
echo "== page_letter_landscape: 3 full / 1 excluded =="
flutter test test/designer/goldens/page_letter_landscape_test.dart 2>&1 | tail -1
flutter test --exclude-tags golden test/designer/goldens/page_letter_landscape_test.dart 2>&1 | tail -1
echo "== png_export: 8 full / 7 excluded =="
flutter test test/rendering/export/png_export_test.dart 2>&1 | tail -1
flutter test --exclude-tags golden test/rendering/export/png_export_test.dart 2>&1 | tail -1
echo "== pdf_determinism: 4 full / 3 excluded =="
flutter test test/rendering/export/pdf_determinism_test.dart 2>&1 | tail -1
flutter test --exclude-tags golden test/rendering/export/pdf_determinism_test.dart 2>&1 | tail -1
```
Expected `+N` final counts: page_letter_landscape `+3` full / `+1` excluded; png_export `+8` / `+7`; pdf_determinism `+4` / `+3`. (All passing.)

- [ ] **Step 5: Run the local matrix proxy (the Linux/Windows test leg, on macOS)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
flutter analyze 2>/dev/null || (cd packages/jet_print && flutter analyze)
flutter test --exclude-tags golden packages/jet_print apps/jet_print_playground
echo "--- and the canonical (full) leg ---"
flutter test packages/jet_print apps/jet_print_playground
git status --porcelain | grep -E '\.(png|pdf)$' || echo "no golden changes (good)"
```
Expected: analyze `No issues found!`; the `--exclude-tags golden` run is **green** with the golden surface skipped (this is exactly what ubuntu/windows will run); the full run is green (macOS canonical); no golden diffs.

- [ ] **Step 6: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test
git commit -m "$(cat <<'EOF'
test(e3): tag only the golden case(s) in the 3 mixed test files

page_letter_landscape (2 testWidgets goldens), png_export (golden-pin group),
pdf_determinism (the byte-pinned invoice.pdf case). Platform-independent
cases — pixel dimensions, byte self-consistency, exceptions, PDF determinism
— stay running on all OSes. `--exclude-tags golden` full-suite proxy green.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Relax the playground desktop guard

**Files:**
- Modify: `apps/jet_print_playground/lib/main.dart` (the `if (!Platform.isMacOS)` guard at ~line 34)

**Interfaces:**
- Consumes: nothing.
- Produces: the playground `main()` launches on macOS, Windows, and Linux; still throws on other targets (web/mobile — E4/E5).

**Note on testing:** this guard lives inside `main()` (which calls `runApp`), so it has no clean unit test without mocking `Platform` — a contrived mock here would assert nothing real. The deliverable is validated by `flutter analyze`, the unchanged suite, and (decisively) the Phase B Windows/Linux app builds. Do not add a Platform-mock test.

- [ ] **Step 1: Edit the guard**

Replace:

```dart
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'jet_print_playground targets macOS desktop this iteration.',
    );
  }
```
with:

```dart
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    throw UnsupportedError(
      'jet_print_playground targets desktop (macOS, Windows, Linux).',
    );
  }
```

- [ ] **Step 2: Analyze + suite green**

```bash
cd packages/jet_print && flutter analyze
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print apps/jet_print_playground
```
Expected: `No issues found!`; `All tests passed!`.

- [ ] **Step 3: Confirm the macOS app still builds (guard didn't break launch path)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print/apps/jet_print_playground
flutter build macos --debug
```
Expected: `✓ Built build/macos/Build/Products/Debug/…app`.

- [ ] **Step 4: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/lib/main.dart
git commit -m "$(cat <<'EOF'
feat(e3): allow the playground to launch on all three desktop OSes

Relax the macOS-only guard to macOS | Windows | Linux; keep a clear
UnsupportedError for not-yet-supported targets (web/mobile — E4/E5).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Generate the Windows + Linux playground runner directories

**Files:**
- Create (generated): `apps/jet_print_playground/windows/**`, `apps/jet_print_playground/linux/**`

**Interfaces:**
- Consumes: nothing.
- Produces: `flutter build windows` / `flutter build linux` have runner scaffolding to target. `lib/`, `macos/`, and `pubspec.yaml` are untouched.

- [ ] **Step 1: Generate the runner dirs (scaffolding only — safe on macOS)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print/apps/jet_print_playground
flutter create --platforms=windows,linux .
```
Expected: output listing newly created `windows/` and `linux/` files; it does **not** modify `lib/`, `macos/`, or `pubspec.yaml`.

- [ ] **Step 2: Confirm the generated scope and that nothing else changed**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git status --porcelain | sed -n '1,40p'
echo "--- assert lib/main.dart and macos/ are NOT in the diff ---"
git status --porcelain | grep -E 'jet_print_playground/(lib|macos)/' && echo "UNEXPECTED: core files changed" || echo "lib/ and macos/ untouched (good)"
git status --porcelain | grep -E '\.(png|pdf)$' || echo "no golden changes (good)"
```
Expected: only `apps/jet_print_playground/windows/` and `.../linux/` appear as new; lib/macos untouched; no golden diffs.

- [ ] **Step 3: Analyze + suite + macOS build still green**

```bash
cd packages/jet_print && flutter analyze
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print apps/jet_print_playground
cd apps/jet_print_playground && flutter build macos --debug
```
Expected: `No issues found!`; `All tests passed!`; macOS app builds (the new runner dirs don't disturb the macOS target).

- [ ] **Step 4: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/windows apps/jet_print_playground/linux
git commit -m "$(cat <<'EOF'
build(e3): generate Windows + Linux playground runner directories

`flutter create --platforms=windows,linux .` — CMake desktop runners so the
playground builds natively on Win/Linux. lib/, macos/, pubspec untouched.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Rewrite `ci.yml` into the 3-OS matrix

**Files:**
- Modify: `.github/workflows/ci.yml` (replace the single `macos-latest` job with a matrix)

**Interfaces:**
- Consumes: the golden tags (Tasks 3/4), the runner dirs (Task 6), the relaxed guard (Task 5), `.gitattributes` (Task 2), and the format cleanliness (Task 1).
- Produces: the Phase A → Phase B bridge — the workflow that, on push, runs all three OS legs.

- [ ] **Step 1: Replace `.github/workflows/ci.yml` with the matrix**

Exact contents:

```yaml
name: CI

# Mirrors the local quality gate (README "Test & quality gate") across the
# three desktop platforms (E3). macOS is canonical: it alone runs the full
# suite (including goldens) and the dart format gate; Ubuntu and Windows run
# the suite with the golden surface excluded. Every leg builds the playground
# app to prove the native plugin toolchain links per-OS.
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-and-test:
    name: ${{ matrix.os }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: macos-latest
            build_target: macos
            test_filter: ""
            canonical: true
          - os: ubuntu-latest
            build_target: linux
            test_filter: "--exclude-tags golden"
            canonical: false
          - os: windows-latest
            build_target: windows
            test_filter: "--exclude-tags golden"
            canonical: false
    steps:
      - name: Check out the repository
        uses: actions/checkout@v4

      - name: Install Linux desktop build dependencies
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libcups2-dev

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.0
          channel: stable
          cache: true

      - name: Resolve workspace dependencies
        run: flutter pub get

      - name: Verify formatting
        if: matrix.canonical
        run: dart format --output=none --set-exit-if-changed .

      - name: Analyze (zero warnings)
        run: flutter analyze

      - name: Build the playground app
        working-directory: apps/jet_print_playground
        run: flutter build ${{ matrix.build_target }} --debug

      - name: Run tests
        # `flutter test` at a workspace root does not fan out to members, so the
        # member packages are listed explicitly. Off-canonical jobs exclude the
        # golden surface (host rasterization / PDF subsetting differs per OS).
        run: flutter test ${{ matrix.test_filter }} packages/jet_print apps/jet_print_playground
```

- [ ] **Step 2: Validate the workflow YAML parses**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml: valid YAML')"
```
Expected: `ci.yml: valid YAML`. (If `actionlint` is installed, also run `actionlint .github/workflows/ci.yml` — optional.)

- [ ] **Step 3: Re-run the macOS leg's commands locally (full canonical proxy)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
flutter pub get
dart format --output=none --set-exit-if-changed . ; echo "format exit=$?"
cd packages/jet_print && flutter analyze
cd /Users/ahmeturel/Projects/oss/jet-print/apps/jet_print_playground && flutter build macos --debug
cd /Users/ahmeturel/Projects/oss/jet-print && flutter test packages/jet_print apps/jet_print_playground
```
Expected: pub get ok; `format exit=0`; `No issues found!`; macOS app built; `All tests passed!`. This proves the entire canonical leg is green before any push.

- [ ] **Step 4: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
ci(e3): expand CI to a macOS/Ubuntu/Windows build+test matrix

Each OS: pub get -> analyze -> build the playground (debug) -> test. macOS is
canonical (full suite incl. goldens + dart format gate); Ubuntu/Windows run
--exclude-tags golden. Linux installs GTK/clang/cmake/ninja/CUPS deps.
fail-fast: false so all three legs report.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

**End of Phase A.** At this point the canonical (macOS) leg is fully green locally and the off-canonical test leg is proven via the `--exclude-tags golden` proxy. Stop and confirm with the user before pushing (Global Constraints).

---

## Phase B — matrix-to-green (CI feedback loop, NOT pre-planned tasks)

Phase B begins only after the user approves the push. It is an iteration loop, not a fixed task list — the Windows/Linux failures are unknowable until Actions runs them.

**Loop:**
1. Push `e3-desktop-matrix` and open a PR (or push to a branch CI watches): `git push -u origin e3-desktop-matrix`.
2. Read the three legs in Actions (`gh run watch` / `gh run view --log-failed`).
3. For each red leg, make the minimal fix on the branch, commit (Co-Authored-By line), push, re-read.
4. Repeat until macOS + Ubuntu + Windows are all green. Then hand off via `superpowers:finishing-a-development-branch`.

**Anticipated fixes (playbook — apply only if the matrix surfaces them):**
- **Linux build:** if `flutter build linux` reports desktop disabled, add `flutter config --enable-linux-desktop` before the build; if a native link fails, extend the apt list (the spec already includes `libcups2-dev` for `printing`).
- **Windows build:** if desktop disabled, `flutter config --enable-windows-desktop`; watch for long-path or pwsh-quoting issues in the run steps.
- **macOS build signing:** if `flutter build macos --debug` fails on code signing in CI, add `env: { CODE_SIGNING_ALLOWED: "NO" }` (or `CODE_SIGNING_REQUIRED: "NO"`) to that step.
- **A test with a macOS assumption:** fix the test to be platform-neutral (use `findWorkspaceRoot()`, `p.join`, no hardcoded separators). The library uses bundled fonts + no hardcoded paths in `lib/`, so this risk is low.
- **The FFI cursor `_io` file:** it compiles on Win/Linux and no-ops (guarded by `Platform.isMacOS` before any Objective-C lookup) — expected to need no change; confirm via the green Linux/Windows analyze+test.
- **Format gate diverging on CI:** it only runs on macOS (same OS + pinned Flutter as local), so it should match Task 1's result exactly; if not, re-run `dart format .` and commit.

Each Phase B fix is committed on the branch and absorbed into E3 (scope decision a).

---

## Self-Review

**1. Spec coverage** (every FR/SC → a task):
- FR-E3-001 (matrix, triggers, pinned Flutter) → Task 7. ✓
- FR-E3-002 (per-OS spine pub get→analyze→build→test) → Task 7. ✓
- FR-E3-003 (macOS canonical: full suite + format gate) → Task 7 (`canonical` flag) + Task 1 (format passes). ✓
- FR-E3-004 (ubuntu/windows `--exclude-tags golden`) → Task 7 + Tasks 3/4 (tags exist). ✓
- FR-E3-005 (golden surface = PNG goldens + pinned PDF; pure file-level, mixed test-level) → Tasks 3 + 4. ✓
- FR-E3-006 (`dart_test.yaml` declares the tag) → Task 2. ✓
- FR-E3-007 (windows/ + linux/ runner dirs; lib/macos/pubspec untouched) → Task 6. ✓
- FR-E3-008 (relaxed guard) → Task 5. ✓
- FR-E3-009 (`.gitattributes`) → Task 2. ✓
- FR-E3-010 (ubuntu apt deps) → Task 7. ✓
- FR-E3-011 (absorb fixes inline until green) → Phase B. ✓
- SC-E3-001 (macOS green) → Task 7 Step 3 local proxy + Phase B. ✓
- SC-E3-002 / SC-E3-003 (ubuntu/windows green) → Phase B. ✓
- SC-E3-004 (no golden off-canonical) → Task 4 Step 5 proxy. ✓
- SC-E3-005 (zero re-baselining; goldens byte-identical) → golden-diff check in every task. ✓
- SC-E3-006 (only guard + runner dirs change in lib/app; no engine/API change) → Tasks 5/6 scope; format (Task 1) is whitespace-only. ✓

**Coverage gap found & resolved:** the spec assumed the macOS format gate was already green; it is not (33 files dirty). Added **Task 1** (format normalization) — without it SC-E3-001 cannot pass. In scope per decision (a).

**2. Placeholder scan:** no TBD/TODO; every code/edit step shows exact contents or exact before/after; every command has an expected result.

**3. Type/identifier consistency:** the tag string is `'golden'` everywhere (`@Tags(['golden'])`, `tags: 'golden'`, `--exclude-tags golden`, `dart_test.yaml` key `golden`); the matrix field names (`build_target`, `test_filter`, `canonical`) are used consistently in Task 7; build targets (`macos`/`linux`/`windows`) match the per-OS rows.
