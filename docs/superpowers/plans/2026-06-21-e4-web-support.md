# Epic E4 — Web Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify and harden `jet_print` under Flutter web (CanvasKit) — the library compiles to web, renders, exports PDF/PNG, and prints via the browser — proven locally in Chrome.

**Architecture:** Single-phase, fully local (Chrome installed; no GitHub Actions dependency). De-risk first (`flutter build web`), then make the playground web-buildable, gate VM-only tests off the Chrome leg, add automated Chrome render/export tests, wire the print seam's web semantics, add a CI web job, and record a smoke findings note. No engine/domain change; goldens stay byte-identical; the macOS full suite stays green.

**Tech Stack:** Flutter `3.44.0` (pinned), Dart, CanvasKit web renderer, `cross_file` `XFile.saveTo` (web download), `flutter_test` `@TestOn('vm')` platform selector + the existing `@Tags(['golden'])` gate, GitHub Actions.

## Global Constraints

- Suite green via the documented CI command from repo root: `flutter test packages/jet_print apps/jet_print_playground`.
- Run `flutter`/`dart` from `packages/jet_print` (or `apps/jet_print_playground` for app-specific commands); run `git` from the repo root.
- **Goldens byte-identical** — no `*.png` and no `test/goldens/invoice.pdf` changes at any task.
- **The macOS full suite stays green** — the `@TestOn('vm')` and `--exclude-tags golden` gates only affect the *Chrome* leg, never the default (VM) run.
- **No engine/domain change; no public-API change** beyond any additive, web-only seam. Hardening must be a localized conditional/fallback.
- Arch tests scan source via `findWorkspaceRoot()` (`test/support/workspace.dart`).
- The expression layer must not import the fill layer (arch-test-enforced).
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Do not push** (Actions is billing-locked; E4 acceptance is the local Chrome verification).
- Default web renderer is **CanvasKit** (Flutter 3.44 dropped the HTML renderer).

## Branch setup (before Task 1)

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git checkout main
git checkout -b e4-web-support
```

## File structure

| File | Responsibility | Task |
|------|----------------|------|
| `apps/jet_print_playground/web/**` (new, generated) | Web runner (index.html, manifest, bootstrap) | 1 |
| `apps/jet_print_playground/lib/main.dart` | Drop `dart:io`: guard → `kIsWeb`/`defaultTargetPlatform`; saves → `kIsWeb`-branched `XFile.saveTo` helper | 1 |
| (≈11 test files) | `@TestOn('vm')` on tests that import `dart:io` directly or transitively | 2 |
| `packages/jet_print/test/web/web_render_export_test.dart` (new) | `--platform chrome` render + PNG/PDF export assertions (CanvasKit soft spots) | 3 |
| `packages/jet_print/lib/src/print/jet_report_printer.dart` | Document web print semantics (browser print; best-effort cancel) | 4 |
| `.github/workflows/ci.yml` | Add a web job (`flutter build web` + chrome test) | 5 |
| `docs/superpowers/specs/2026-06-21-e4-findings.md` (new) | Record the Chrome smoke + automated web results | 6 |

---

### Task 1: Web-buildable playground + de-risk gate

**Why combined:** the playground's only web blockers are `Platform` (the guard) and one `File().writeAsString` (the `_save` flow); both removable with web-safe APIs (no conditional-import files needed). Making the playground compile to web *is* the de-risk gate — `flutter build web` then proves the library + a real consumer compile to web. If a hidden transitive blocker exists, it surfaces here.

**Files:**
- Generate: `apps/jet_print_playground/web/**`
- Modify: `apps/jet_print_playground/lib/main.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `flutter build web` of the playground succeeds; the playground launches on web (guard permits it); saves use the cross-platform `XFile.saveTo`.

- [ ] **Step 1: Generate the web runner dir**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print/apps/jet_print_playground
flutter create --platforms=web .
```
Expected: new files under `web/`.

- [ ] **Step 2: Remove `flutter create` side-effects (E3 Task 6 lesson)**

`flutter create` may also emit `analysis_options.yaml` and `test/widget_test.dart` (a boilerplate `MyApp` test that breaks the suite). Remove them so the playground stays under the strict root analyzer config and the suite stays green:

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git status --porcelain apps/jet_print_playground
rm -f apps/jet_print_playground/analysis_options.yaml
rm -f apps/jet_print_playground/test/widget_test.dart
```
(If `git status` shows neither was created, skip the `rm`s. A `.metadata` update is acceptable.)

- [ ] **Step 3: Make `main.dart` web-compile-clean — replace the imports + guard**

In `apps/jet_print_playground/lib/main.dart`, replace the first import line:

```dart
import 'dart:io' show File, Platform;
```
with:

```dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
```

Then replace the guard block in `main()`:

```dart
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    throw UnsupportedError(
      'jet_print_playground targets desktop (macOS, Windows, Linux).',
    );
  }
```
with (web-safe — no `dart:io`):

```dart
  final bool supported = kIsWeb ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (!supported) {
    throw UnsupportedError(
      'jet_print_playground targets desktop (macOS, Windows, Linux) and web.',
    );
  }
```

- [ ] **Step 4: Route saves through a cross-platform helper (drops the last `dart:io`)**

Add `import 'dart:convert' show utf8;` and `import 'dart:typed_data';` if not present (check the existing imports — `dart:typed_data` is already imported as `Uint8List` is used). Add this method to `_DesignerTabState` (near `_save`):

```dart
  /// Cross-platform save: on web, download via the browser (file picking is
  /// unsupported there) — on desktop, pick a location then write. Both go
  /// through `cross_file`'s `XFile.saveTo`, which downloads on web and writes
  /// a file on desktop, so no `dart:io` is needed.
  Future<void> _saveBytes(
    Uint8List bytes, {
    required String suggestedName,
    required List<XTypeGroup> acceptedTypeGroups,
    String? mimeType,
  }) async {
    if (kIsWeb) {
      await XFile.fromData(bytes, name: suggestedName, mimeType: mimeType)
          .saveTo(suggestedName);
      return;
    }
    final FileSaveLocation? location = await getSaveLocation(
      acceptedTypeGroups: acceptedTypeGroups,
      suggestedName: suggestedName,
    );
    if (location == null) return; // user cancelled
    await XFile.fromData(bytes, mimeType: mimeType).saveTo(location.path);
  }
```

Replace the body of `_save` (the `getSaveLocation` + `File(...).writeAsString` block) with:

```dart
  Future<void> _save(ReportDefinition definition) async {
    final Uint8List bytes = Uint8List.fromList(
        utf8.encode(JetReportFormat.encodeDefinitionJson(definition)));
    await _saveBytes(
      bytes,
      suggestedName: 'report.jetreport',
      acceptedTypeGroups: const <XTypeGroup>[_reportType],
    );
  }
```

Replace the body of `_exportPdf` (the `getSaveLocation` + `XFile.fromData(...).saveTo` block) with:

```dart
  Future<void> _exportPdf(RenderedReport report) async {
    final Uint8List pdf = await const JetReportExporter().toPdf(report);
    await _saveBytes(
      pdf,
      suggestedName: 'invoice.pdf',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'PDF document', extensions: <String>['pdf']),
      ],
      mimeType: 'application/pdf',
    );
  }
```

(The `_open` flow already uses `XFile.readAsString` — web-safe — leave it unchanged.)

- [ ] **Step 5: Confirm no `dart:io` remains and it builds for web**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
grep -n "dart:io\|File(\|Platform\." apps/jet_print_playground/lib/main.dart || echo "no dart:io residue (good)"
cd apps/jet_print_playground
flutter build web
```
Expected: no `dart:io`/`File(`/`Platform.` matches; `✓ Built build/web`. **This is the de-risk gate — if the build fails on a library symbol, STOP and report the blocker.**

- [ ] **Step 6: macOS suite still green + goldens unchanged + analyze clean**

```bash
cd packages/jet_print && flutter analyze
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print apps/jet_print_playground
git status --porcelain | grep -E '\.(png|pdf)$' || echo "no golden changes (good)"
```
Expected: `No issues found!`; `All tests passed!`; no golden diffs.

- [ ] **Step 7: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add apps/jet_print_playground/web apps/jet_print_playground/lib/main.dart apps/jet_print_playground/.metadata
git commit -m "$(cat <<'EOF'
feat(e4): make the playground web-buildable (de-risk gate)

Generate the web/ runner dir; drop dart:io from main.dart — guard via
foundation kIsWeb/defaultTargetPlatform, saves via a kIsWeb-branched
XFile.saveTo helper (downloads on web). `flutter build web` succeeds, proving
the library + a real consumer compile to web. macOS suite green; goldens
unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: VM-only test audit — `@TestOn('vm')`

`flutter test --platform chrome` runs tests in the browser, so any test importing `dart:io` (directly, or transitively via `support/workspace.dart`'s `findWorkspaceRoot` or `support/pdf_inspector.dart`) cannot compile there. Tag exactly those `@TestOn('vm')` so the Chrome leg skips them; everything else must run green in Chrome (decision a, maximal).

**Files:**
- Modify: every test file that imports `dart:io` directly or transitively (audited empirically — start list: the 11 files importing `dart:io`, plus any test importing `support/workspace.dart`).

**Interfaces:**
- Consumes: nothing.
- Produces: `flutter test --platform chrome --exclude-tags golden packages/jet_print apps/jet_print_playground` compiles and runs green.

- [ ] **Step 1: Seed the audit list**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
echo "--- direct dart:io test files ---"
grep -rln "import 'dart:io'" packages/jet_print/test apps/jet_print_playground/test
echo "--- transitive via workspace.dart (findWorkspaceRoot) ---"
grep -rln "support/workspace.dart\|findWorkspaceRoot" packages/jet_print/test
```

- [ ] **Step 2: Add the platform selector to each audited TEST file**

For each TEST file (not the `support/*.dart` helpers — those have no `main()` and need no annotation), insert at the very top, before the first `import` (after any leading `//` comment), followed by a blank line:

```dart
@TestOn('vm')
library;
```

`@TestOn` is a built-in platform selector from the test framework; it resolves through the existing `package:flutter_test/flutter_test.dart` import (same path as `@Tags`, confirmed in E3) and analyzes clean. Apply to at least these (verify against Step 1 output): `architecture/barcode_dependency_isolation_test.dart`, `architecture/layer_boundaries_test.dart`, `domain/serialization/migration_v1_to_v2_test.dart`, `encapsulation_test.dart`, `rendering/export/pdf_determinism_test.dart`, `rendering/migrated_equals_native_test.dart`, `rendering/native_engine_semantics_test.dart`, `rendering/paint/canvas_painter_variant_test.dart`, `rendering/resilience/stress_dirty_dataset_test.dart`, `rendering/text/metrics_text_measurer_test.dart`, `rendering/text/ttf_metrics_test.dart`, plus any test that imports `support/workspace.dart`.

Note on `pdf_determinism_test.dart`: it is ALSO `@Tags(['golden'])`-relevant via its pinned-PDF case (E3). A file can carry both `@TestOn('vm')` and a test-level `tags: 'golden'`; the `@TestOn('vm')` goes at the library level. The Chrome leg excludes it via `@TestOn('vm')` (whole file is VM-only anyway).

- [ ] **Step 3: Empirically close the audit (the robust method)**

Run the Chrome leg; any remaining compile failure naming `dart:io` (or an unsupported library) identifies a still-untagged transitive case — tag that file `@TestOn('vm')` and re-run until the leg compiles and passes:

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test --platform chrome --exclude-tags golden packages/jet_print apps/jet_print_playground 2>&1 | tail -25
```
Expected (iterate to): `All tests passed!` with the VM-only files reported as skipped/not-run on chrome. If a file fails to compile with a `dart:io`/`Unsupported operation` message, add `@TestOn('vm')` to it and re-run.

- [ ] **Step 4: Confirm the default (VM) run is unaffected**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print apps/jet_print_playground
cd packages/jet_print && flutter analyze
```
Expected: `All tests passed!` (the tagged tests STILL run on the VM — `@TestOn('vm')` only excludes them on chrome); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test
git commit -m "$(cat <<'EOF'
test(e4): tag dart:io-bound tests @TestOn('vm') for the Chrome leg

So `flutter test --platform chrome` skips browser-incompatible tests (arch
scans, PDF file pins, the stress test, etc.) while the rest run green in
Chrome. The default VM run is unchanged — these tests still run there.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Automated Chrome render + export tests (CanvasKit soft spots)

Prove the three CanvasKit runtime soft spots — render, PNG export (`toByteData(png)`), PDF export (`toPdf`) — work in a real browser, with assertions on valid bytes/dimensions. Harden anything that breaks (localized; no engine change).

**Files:**
- Create: `packages/jet_print/test/web/web_render_export_test.dart`
- (Harden under `packages/jet_print/lib/src/rendering/...` only if a soft spot fails.)

**Interfaces:**
- Consumes: the public render/export API (`JetReportEngine`, `JetReportExporter`).
- Produces: a browser-run regression net for web rendering/export.

- [ ] **Step 1: Write the Chrome render/export test**

`packages/jet_print/test/web/web_render_export_test.dart`:

```dart
// Web (CanvasKit) render + export smoke — runs ONLY in the browser so it
// exercises the real web rendering engine, not the VM. Asserts the three
// CanvasKit soft spots (E4 §5): canvas render, PNG export via toByteData,
// PDF export. No dart:io (must compile on web).
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _definition() => const ReportDefinition(
      name: 'Web smoke',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        title: Band(
          id: 'body/title',
          type: BandType.title,
          height: 48,
          elements: <ReportElement>[
            TextElement(
              id: 'h',
              bounds: JetRect(x: 0, y: 0, width: 300, height: 24),
              text: 'WEB RENDER',
              style: JetTextStyle(fontSize: 18, weight: JetFontWeight.bold),
            ),
          ],
        ),
        root: DetailScope(id: 'root', children: <ScopeNode>[]),
      ),
    );

RenderedReport _render() => const JetReportEngine().renderDefinition(
      _definition(),
      JetInMemoryDataSource(const <Map<String, Object?>>[<String, Object?>{}]),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF export produces valid bytes in the browser', () async {
    final Uint8List pdf = await const JetReportExporter().toPdf(_render());
    expect(pdf.length, greaterThan(100));
    // %PDF- magic header.
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  test('PNG export (toByteData on CanvasKit) produces a valid image',
      () async {
    final Uint8List png =
        await const JetReportExporter().pageToPng(_render(), 0);
    expect(png.length, greaterThan(100));
    // PNG 8-byte signature.
    expect(png.sublist(0, 8),
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  });
}
```

- [ ] **Step 2: Run it in Chrome (RED→GREEN; if a soft spot fails, harden then)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test --platform chrome packages/jet_print/test/web/web_render_export_test.dart 2>&1 | tail -15
```
Expected: `All tests passed!`. If PNG export fails (CanvasKit `toByteData` quirk), harden the localized export path (a CanvasKit-aware fallback in `page_rasterizer.dart`) — NOT an engine change — then re-run. Report any harden as a concern.

- [ ] **Step 3: Confirm it's browser-only (does not run/break on the VM leg)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print/test/web/web_render_export_test.dart 2>&1 | tail -4
```
Expected: `No tests ran.` (the `@TestOn('browser')` selector excludes it from the VM run) — so the default suite is unaffected.

- [ ] **Step 4: Full VM suite still green + analyze**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print apps/jet_print_playground
cd packages/jet_print && flutter analyze
git status --porcelain | grep -E '\.(png|pdf)$' || echo "no golden changes (good)"
```
Expected: `All tests passed!`; `No issues found!`; no golden diffs.

- [ ] **Step 5: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/web packages/jet_print/lib
git commit -m "$(cat <<'EOF'
test(e4): browser-run render + PNG/PDF export assertions (CanvasKit)

A @TestOn('browser') test that renders and exports in real Chrome, asserting
the PDF %PDF- header and the PNG signature — exercising toByteData/toPdf on
CanvasKit. Excluded from the VM run; macOS suite unchanged; goldens intact.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Print seam — document the web semantics

The seam already calls `Printing.info()` + `Printing.layoutPdf`, which on web opens the browser print dialog. No code change is needed for it to *function* on web; the deliverable is **honest documentation** of the web semantics (no OS dialog; user-cancel may report as success), so the `true`/`false` contract is understood as best-effort on web.

**Files:**
- Modify: `packages/jet_print/lib/src/print/jet_report_printer.dart` (doc comments only)

**Interfaces:**
- Consumes: nothing.
- Produces: documented web behavior; no behavior change.

- [ ] **Step 1: Add a web-semantics note to the seam's printReport doc**

In `jet_report_printer.dart`, extend the doc comment of the method that calls `Printing.layoutPdf` (around line 98–104) with a web note. Append to its existing doc comment:

```dart
  /// On web, `printing` renders the PDF with pdf.js and opens the browser's
  /// print dialog; there is no OS print dialog and user-cancel is not reliably
  /// reported, so the `true`/`false` ("handed to the OS" / "cancelled") result
  /// is best-effort on web. `Printing.info().canPrint` still gates genuinely
  /// unsupported environments (which throw [PrintUnavailableException]).
```

- [ ] **Step 2: Analyze + full suite green (doc-only is inert)**

```bash
cd packages/jet_print && flutter analyze
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test packages/jet_print apps/jet_print_playground
```
Expected: `No issues found!`; `All tests passed!`.

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/lib/src/print/jet_report_printer.dart
git commit -m "$(cat <<'EOF'
docs(e4): document the print seam's web (browser-print) semantics

On web, Printing.layoutPdf opens the browser print dialog via pdf.js; cancel
is not reliably reported, so the true/false contract is best-effort there.
Doc-only; no behavior change.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: CI web job

Add a web job to the matrix workflow: build web + the Chrome non-golden leg. It runs once the Actions billing lock clears; E4's acceptance remains the local verification.

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the web-buildable playground (Task 1), the VM-only gating (Task 2).
- Produces: a durable web regression guard in CI.

- [ ] **Step 1: Add the web job**

Append this job under `jobs:` in `.github/workflows/ci.yml` (a standalone job, not part of the desktop matrix):

```yaml
  web:
    name: web (chrome)
    runs-on: ubuntu-latest
    steps:
      - name: Check out the repository
        uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.44.0
          channel: stable
          cache: true

      - name: Resolve workspace dependencies
        run: flutter pub get

      - name: Build the playground for web
        working-directory: apps/jet_print_playground
        run: flutter build web

      - name: Run the Chrome test leg (goldens + VM-only tests excluded)
        run: flutter test --platform chrome --exclude-tags golden packages/jet_print apps/jet_print_playground
```

- [ ] **Step 2: Validate the workflow against GitHub's schema**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
actionlint .github/workflows/ci.yml && echo "actionlint CLEAN"
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('valid YAML')"
```
Expected: `actionlint CLEAN`; `valid YAML`.

- [ ] **Step 3: Re-confirm the local web leg matches what CI will run**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print/apps/jet_print_playground && flutter build web
cd /Users/ahmeturel/Projects/oss/jet-print
flutter test --platform chrome --exclude-tags golden packages/jet_print apps/jet_print_playground 2>&1 | tail -4
```
Expected: `✓ Built build/web`; `All tests passed!`.

- [ ] **Step 4: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
ci(e4): add a web job (flutter build web + chrome test leg)

ubuntu-latest: build the playground for web, then run
`flutter test --platform chrome --exclude-tags golden`. Runs once the Actions
billing lock clears; E4 acceptance is the local Chrome verification.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Chrome smoke + E4 findings record

Capture the web verification results (automated + the manual `flutter run -d chrome` walk) in a findings doc, mirroring E2/E3's records.

**Files:**
- Create: `docs/superpowers/specs/2026-06-21-e4-findings.md`

**Interfaces:**
- Consumes: the results of Tasks 1–5.
- Produces: the durable E4 acceptance record.

- [ ] **Step 1: Run the manual Chrome smoke (controller/user step)**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print/apps/jet_print_playground
flutter run -d chrome
```
Confirm in the browser: the designer renders; a sample previews; PDF export downloads; print opens the browser dialog. (This visual confirmation is a human GUI walk, like E1's T037; the automated Task-3 tests are the regression net.)

- [ ] **Step 2: Write the findings doc**

`docs/superpowers/specs/2026-06-21-e4-findings.md` — record: the `flutter build web` result; the Chrome test-leg pass count; the three CanvasKit soft spots' outcomes (and any hardening applied); the print-on-web behavior observed; and a one-line statement of whether SC-E4-001..005 are met. Note the CI web job is pending the billing lock.

- [ ] **Step 3: Commit**

```bash
cd /Users/ahmeturel/Projects/oss/jet-print
git add docs/superpowers/specs/2026-06-21-e4-findings.md
git commit -m "$(cat <<'EOF'
docs(e4): web-support findings + Chrome smoke record

Records flutter build web, the chrome test-leg result, the CanvasKit soft-spot
outcomes, and the print-on-web behavior. SC-E4 acceptance via local Chrome.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**1. Spec coverage** (FR/SC → task):
- FR-E4-001 (`flutter build web` compiles — de-risk) → Task 1 Step 5. ✓
- FR-E4-002 (canvas renders under CanvasKit) → Task 3 (render) + Task 6 (smoke). ✓
- FR-E4-003 (PNG + PDF export valid) → Task 3 Steps 1–2. ✓
- FR-E4-004 (browser print + documented semantics) → Task 4. ✓
- FR-E4-005 (playground web-buildable; `dart:io` split; guard relaxed; `web/` dir) → Task 1. ✓
- FR-E4-006 (VM-only tests `@TestOn('vm')`; chrome leg green) → Task 2. ✓
- FR-E4-007 (macOS suite green; goldens byte-identical) → golden/suite checks every task. ✓
- FR-E4-008 (CI web job) → Task 5. ✓
- SC-E4-001..005 → Tasks 1/3/2/1/3 + the Task 6 record. ✓

**Refinement vs spec §7:** the spec suggested conditional-import `_io`/`_web` files; the plan achieves the same web-buildable result more simply with `kIsWeb` branching + `cross_file` `XFile.saveTo` (which already downloads on web) — no new files, no `package:web` dep. Same intent, less surface.

**2. Placeholder scan:** no TBD/TODO; every code step shows exact contents; every command has an expected result. (Task 6's findings doc is descriptive by nature — its content is enumerated, not a placeholder.)

**3. Type/identifier consistency:** `_saveBytes(Uint8List, {suggestedName, acceptedTypeGroups, mimeType})` is defined in Task 1 and used by `_save`/`_exportPdf` in the same task; `@TestOn('vm')` (Task 2) vs `@TestOn('browser')` (Task 3) are distinct and correct for their direction; `_reportType` (existing `XTypeGroup`) is reused; the tag string `golden` and selector `vm`/`browser` are used consistently with `--exclude-tags golden` and `--platform chrome`.
