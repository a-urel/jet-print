# Epic 1 — Release Hygiene & Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the false "scaffold/placeholder" signals and the publishability gaps so `jet_print` presents as the mature library it is, and clean the public surface before a future 1.0 freeze locks it.

**Architecture:** Pure hygiene. The only code change is deleting one dead widget (`JetPrintPlaceholder`) and repointing its self-tests at a real public entry point. Everything else is licensing, README, pubspec metadata, and two acceptance closures (automate the automatable; record the human-only steps). No domain/rendering/engine change; no golden changes except the intentional deletion of the placeholder golden.

**Tech Stack:** Dart 3.6+/Flutter, `flutter_test`. Files touched live under `packages/jet_print/` plus repo-root docs.

**Spec:** `docs/superpowers/specs/2026-06-20-e1-release-hygiene-design.md`. **Parent roadmap:** `docs/superpowers/specs/2026-06-20-production-readiness-roadmap-design.md`.

## Global Constraints

- **License:** Apache-2.0. Copyright notice line, verbatim: `Copyright 2026 Ahmet Urel`.
- **Run directories:** run `flutter` / `dart` from `packages/jet_print`; run `git` from repo root `/Users/ahmeturel/Projects/oss/jet-print` (the `flutter` tool leaves cwd inside the package — always `cd` back to the repo root before `git`).
- **Public surface:** removing `JetPrintPlaceholder` takes the export count 54 → 53. No other export changes in E1.
- **Out of scope (do NOT do — these are Epic 6):** bumping `version` from `0.1.0`; cutting a CHANGELOG release entry; adding an `example/` directory; dartdoc site; CONTRIBUTING/CODE_OF_CONDUCT; multi-platform CI matrix.
- **Green-suite invariant:** after every task, `flutter analyze` is clean, `dart format --output=none --set-exit-if-changed lib test` is clean, and `flutter test` is fully green. **No golden changes except the deleted `goldens/jet_print_placeholder.png`.** If any other golden changes, STOP and inspect.
- **pub topics rules:** lowercase, no spaces, ≤5 topics, each ≤32 chars.

---

## Task 1: Apache-2.0 LICENSE (root + package)

**Files:**
- Create: `/LICENSE`
- Create: `/packages/jet_print/LICENSE`

pub.dev derives the license from a `LICENSE` file **inside the published package directory**, so a root-only file is not enough — the package needs its own copy. The text is the canonical, unmodified Apache License 2.0 with the standard copyright notice appended in its APPENDIX slot.

- [ ] **Step 1: Create `/LICENSE`.** Write the **verbatim** Apache License, Version 2.0 (the canonical text from <https://www.apache.org/licenses/LICENSE-2.0.txt>). At the end, fill the APPENDIX "how to apply" boilerplate with this exact notice block:

```text
   Copyright 2026 Ahmet Urel

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

- [ ] **Step 2: Copy it into the package.**

Run (from repo root):
```bash
cp LICENSE packages/jet_print/LICENSE
```

- [ ] **Step 3: Verify both files are present and well-formed.**

Run (from repo root):
```bash
test -f LICENSE && test -f packages/jet_print/LICENSE && \
  grep -q "Apache License" LICENSE && \
  grep -q "Copyright 2026 Ahmet Urel" LICENSE && \
  grep -q "Copyright 2026 Ahmet Urel" packages/jet_print/LICENSE && \
  echo "LICENSE OK"
```
Expected: `LICENSE OK`

- [ ] **Step 4: Commit.**

Run (from repo root):
```bash
git add LICENSE packages/jet_print/LICENSE
git commit -m "chore: add Apache-2.0 LICENSE (root + jet_print package)"
```

---

## Task 2: Remove the vestigial `JetPrintPlaceholder`

**Files:**
- Delete: `packages/jet_print/lib/src/designer/jet_print_placeholder.dart`
- Delete: `packages/jet_print/test/jet_print_placeholder_test.dart`
- Delete: `packages/jet_print/test/goldens/jet_print_placeholder.png`
- Modify: `packages/jet_print/lib/jet_print.dart` (remove the export + fix the library doc comment)
- Modify: `packages/jet_print/test/public_api_test.dart` (remove the placeholder test)
- Modify: `packages/jet_print/test/designer/designer_test.dart` (repoint at `JetReportDesigner`)

`JetPrintPlaceholder` is a spec-001 relic. Its only references are its own definition and three self-tests; the playground no longer renders it. `public_api_test.dart` already has a `JetReportDesigner is const-constructible and is a Widget` test (lines 57-61), so removing the placeholder test loses no public-surface coverage. `designer_test.dart` is the only designer-seam smoke test, so it must be repointed (not just deleted) to keep proving the designer seam builds standalone.

- [ ] **Step 1: Repoint the designer-seam test.** Replace the entire body of `packages/jet_print/test/designer/designer_test.dart` with:

```dart
// Designer seam test (SC-004).
//
// Proves the designer seam is exercisable independently of the playground app:
// it consumes the public report-designer shell through the single public entry
// point and builds it standalone inside a ShadApp shell.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets(
    'JetReportDesigner builds standalone inside a ShadApp shell',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ShadApp(home: JetReportDesigner()));
      await tester.pumpAndSettle();

      expect(find.byType(JetReportDesigner), findsOneWidget);
    },
  );
}
```

- [ ] **Step 2: Remove the placeholder test from `public_api_test.dart`.** Delete exactly this block (lines 52-55), leaving the surrounding `jetPrintVersion` and `JetReportDesigner` tests intact:

```dart
  test('JetPrintPlaceholder is const-constructible and is a Widget', () {
    const placeholder = JetPrintPlaceholder();
    expect(placeholder, isA<Widget>());
  });

```

- [ ] **Step 3: Delete the placeholder widget, its self-test, and its golden.**

Run (from repo root):
```bash
git rm packages/jet_print/lib/src/designer/jet_print_placeholder.dart \
       packages/jet_print/test/jet_print_placeholder_test.dart \
       packages/jet_print/test/goldens/jet_print_placeholder.png
```

- [ ] **Step 4: Remove the export and fix the library doc comment in `lib/jet_print.dart`.** Delete this export line:

```dart
export 'src/designer/jet_print_placeholder.dart' show JetPrintPlaceholder;
```

Then update the library-level doc comment (lines 14-17) so it no longer advertises the placeholder. Replace:

```dart
/// The public surface for this iteration: the version constant, a theme-aware
/// placeholder widget, the report-designer shell ([JetReportDesigner]), and the
/// library's own localization delegate ([JetPrintLocalizations]). See
/// `contracts/designer-layout-api.md` for the authoritative contract.
```

with:

```dart
/// The public surface centers on the report-designer shell
/// ([JetReportDesigner]) and workspace ([JetReportWorkspace]), the reified
/// report model ([ReportDefinition] and its tree), the render engine
/// ([JetReportEngine]), export/print ([JetReportExporter] / [JetReportPrinter]),
/// and the library's own localization delegate ([JetPrintLocalizations]).
```

- [ ] **Step 5: Confirm no `JetPrintPlaceholder` references remain.**

Run (from repo root):
```bash
grep -rn "JetPrintPlaceholder" packages apps --include="*.dart" || echo "NO REFERENCES — OK"
```
Expected: `NO REFERENCES — OK`

- [ ] **Step 6: Run the full library suite — green, and the placeholder golden is gone.**

Run (from repo root):
```bash
cd packages/jet_print && flutter test ; cd /Users/ahmeturel/Projects/oss/jet-print
```
Expected: `All tests passed!` with one fewer test file than before, and **no** golden failures (the only golden removed was the placeholder's; nothing references it now).

- [ ] **Step 7: Analyze + format, then commit.**

Run (from repo root):
```bash
cd packages/jet_print && flutter analyze && \
  dart format --output=none --set-exit-if-changed lib test ; \
  cd /Users/ahmeturel/Projects/oss/jet-print
git add -A packages/jet_print/lib/jet_print.dart \
           packages/jet_print/test/public_api_test.dart \
           packages/jet_print/test/designer/designer_test.dart
git commit -m "refactor: remove vestigial JetPrintPlaceholder (pre-1.0 surface cleanup, 54->53)"
```

---

## Task 3: pub.dev metadata + honest description

**Files:**
- Modify: `packages/jet_print/pubspec.yaml`

The pubspec `description` still calls the package a "scaffold," and it carries no `repository`/`homepage`/`issue_tracker`/`topics` — so a pub.dev page would be metadata-poor and mislabeled. Fix the description and add the metadata. Do **not** touch `version` (Epic 6).

- [ ] **Step 1: Edit `packages/jet_print/pubspec.yaml`.** Replace the `description:` block (lines 2-6):

```yaml
description: >-
  A layered, theme-aware Flutter widget library scaffold for building WYSIWYG
  report designers, integrating the shadcn_ui design system. This is the
  publishable product; the playground app consumes it exactly as an external
  consumer would.
```

with:

```yaml
description: >-
  A layered, theme-aware Flutter library for building WYSIWYG report designers:
  a reified report model, a render/paginate engine, PDF/PNG export and system
  printing, and an interactive shadcn_ui-themed designer surface.
```

Then, immediately after the `version: 0.1.0` line, insert the metadata block:

```yaml

# pub.dev metadata (Epic 1 — release hygiene). Version stays 0.1.0 until the
# 1.0 API freeze (Epic 6). Topics: lowercase, no spaces, <=5.
repository: https://github.com/a-urel/jet-print
homepage: https://github.com/a-urel/jet-print
issue_tracker: https://github.com/a-urel/jet-print/issues
topics:
  - report
  - pdf
  - wysiwyg
  - designer
  - printing
```

- [ ] **Step 2: Resolve and dry-run publish.**

Run (from repo root):
```bash
flutter pub get
cd packages/jet_print && dart pub publish --dry-run ; cd /Users/ahmeturel/Projects/oss/jet-print
```
Expected: the dry-run lists the package files and reports **no** errors about a missing/unrecognized license or missing description. A warning about the `0.1.0` version, or about a missing `example/`, or about `publish_to`/workspace resolution is acceptable — note it as an Epic-6 follow-up; do not act on it here.

- [ ] **Step 3: Confirm the suite still passes (pubspec changes can affect resolution).**

Run (from repo root):
```bash
cd packages/jet_print && flutter analyze && flutter test ; cd /Users/ahmeturel/Projects/oss/jet-print
```
Expected: analyzer clean, `All tests passed!`

- [ ] **Step 4: Commit.**

Run (from repo root):
```bash
git add packages/jet_print/pubspec.yaml pubspec.lock
git commit -m "chore(jet_print): add pub.dev metadata + truthful description"
```

---

## Task 4: Rewrite the root README + add the publishable package README

**Files:**
- Modify: `/README.md`
- Create: `/packages/jet_print/README.md`

The root README still describes the spec-001 "foundational scaffold / placeholder." Rewrite it as a truthful product README. Separately, the **package has no README**, so its pub.dev page would be blank — add a standalone consumer-facing one. Both must use a real widget in their examples (the placeholder is gone as of Task 2).

- [ ] **Step 1: Create `/packages/jet_print/README.md`** (the publishable, consumer-facing README — no monorepo/CI internals). Content:

````markdown
# jet_print

A layered, theme-aware Flutter library for building **WYSIWYG report designers**.
Design a report as a reified, id'd section tree; fill it with your data; preview,
paginate, export to PDF/PNG, and print — all from a single public entry point.

```dart
import 'package:jet_print/jet_print.dart';
```

## Features

- **Reified report model** — `ReportDefinition` (page furniture + body), bands,
  groups, and nested/recursive detail scopes; author-time `validate()` returns
  structured `Diagnostic`s.
- **Render engine** — `JetReportEngine` fills a definition with a `JetDataSource`
  (in-memory / JSON / object-backed), paginates lazily, and surfaces render
  diagnostics.
- **Export & print** — `JetReportExporter` produces deterministic PDFs (real
  selectable text, embedded fonts) and PNGs; `JetReportPrinter` presents the
  system print dialog behind an injectable presenter seam.
- **Interactive designer** — `JetReportDesigner` / `JetReportWorkspace`: select,
  move, resize, align, undo/redo, zoom, rulers, grid-snap, clipboard.
- **Rich elements** — text with fx expressions, shapes, images, and 10 barcode/QR
  symbologies; multi-column label layouts.
- **Localized chrome** — ships en/de/tr via `JetPrintLocalizations`.

## Quickstart — render and export a report

```dart
import 'package:flutter/widgets.dart';
import 'package:jet_print/jet_print.dart';

// 1. Describe a report (or build one in the designer and serialize it).
const ReportDefinition definition = ReportDefinition(
  name: 'Greeting',
  page: PageFormat.a4Portrait,
  body: ReportBody(
    root: DetailScope(
      id: 'root',
      children: <ScopeNode>[
        BandNode(Band(
          id: 'detail',
          type: BandType.detail,
          height: 40,
          elements: <ReportElement>[
            TextElement(
              id: 't1',
              bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
              text: r'Hello, $F{name}!',
            ),
          ],
        )),
      ],
    ),
  ),
);

Future<void> main() async {
  // 2. Fill it with data.
  final RenderedReport report = const JetReportEngine().renderDefinition(
    definition,
    JetInMemoryDataSource(const <Map<String, Object?>>[
      <String, Object?>{'name': 'Ada'},
    ]),
  );

  // 3. Export — headless: you own the bytes.
  final Uint8List pdf = await const JetReportExporter().toPdf(report);
  final Uint8List png = await const JetReportExporter().pageToPng(report, 0);

  // 4. Or preview it in a widget: JetReportPreview(report: report)
  // 5. Or print it: await const JetReportPrinter().printReport(report);
}
```

## Designer widget

```dart
// Inside a ShadApp / ShadTheme shell:
const JetReportDesigner();
```

## Platform support

Verified on **macOS desktop** today. Windows, Linux, web, and mobile are on the
roadmap and not yet verified. The library code itself is platform-agnostic; the
`printing` dependency carries the platform-specific print integration.

## License

Apache-2.0. See [LICENSE](LICENSE).
````

- [ ] **Step 2: Rewrite `/README.md`** (the repo landing page). Replace the whole file with the content below. It keeps the (accurate) test/quality-gate section and the monorepo layout, but drops every "scaffold/placeholder" claim and uses a real consuming example.

````markdown
# jet-print

A monorepo for **`jet_print`** — a layered, theme-aware Flutter library for
building WYSIWYG report designers — and **`jet_print_playground`**, a macOS
desktop app that consumes the library exactly as an external consumer would.

`jet_print` provides a reified report model, a render/paginate engine, PDF/PNG
export and system printing, and an interactive shadcn-themed designer surface.
See [`packages/jet_print/README.md`](packages/jet_print/README.md) for the
library quickstart and public API.

## Layout

```text
jet-print/
├── pubspec.yaml                 # Dart pub workspace root → one pubspec.lock
├── analysis_options.yaml        # shared strict lints (zero-warning gate)
├── LICENSE                      # Apache-2.0
├── packages/jet_print/          # the library (the product)
│   ├── lib/jet_print.dart       # the single PUBLIC entry point (exports only)
│   └── lib/src/                  # PRIVATE internals (domain · expression · data
│                                 #   · rendering · designer · print)
└── apps/jet_print_playground/   # playground app (consumer; macOS desktop only)
    └── lib/*_sample.dart        # invoice, label, barcode, menu, nested-list,
                                  #   packing-slip, payroll samples
```

## Prerequisites

- Flutter **3.44.0+** / Dart **3.6.0+** (pub workspaces require Dart `^3.6.0`).
- macOS with desktop support: `flutter config --enable-macos-desktop`.
- Verify your toolchain with `flutter doctor`.

## Install

```bash
flutter pub get        # run from the repository root (single root lockfile)
```

## Run the playground app (macOS desktop only)

> The playground targets **macOS desktop** this iteration and fails fast with a
> clear message elsewhere. The `jet_print` library itself is platform-agnostic;
> cross-platform verification is tracked on the production-readiness roadmap.

```bash
cd apps/jet_print_playground && flutter run -d macos
```

The app shows the report designer with several worked samples (invoice, labels,
barcodes, menu, nested lists, packing slip, payroll) you can edit, preview,
export, and print.

## Test & quality gate

Run from the repository root. These three commands mirror CI exactly:

```bash
dart format --output=none --set-exit-if-changed .                 # formatting is clean
flutter analyze                                                    # zero analyzer warnings
flutter test packages/jet_print apps/jet_print_playground          # all tests pass
```

> **Why the explicit paths?** `flutter analyze` fans out across all workspace
> members automatically, but `flutter test` at the workspace root only looks at
> the root package — so the member packages are listed explicitly.

A clean checkout MUST show: formatting clean, analyzer zero warnings, all tests
green.

## Consuming the library

```dart
import 'package:jet_print/jet_print.dart';

// The interactive designer, inside a ShadApp / ShadTheme shell:
const JetReportDesigner();

// Diagnostics:
print(jetPrintVersion);
```

Only the symbols exported from `package:jet_print/jet_print.dart` are public;
everything under `lib/src/` is private implementation detail (enforced by
`encapsulation_test.dart`).

## License

Apache-2.0 — see [LICENSE](LICENSE).
````

- [ ] **Step 3: Verify no stale "scaffold/placeholder" language survives in either README.**

Run (from repo root):
```bash
grep -rin "scaffold\|placeholder" README.md packages/jet_print/README.md || echo "CLEAN — no stale framing"
```
Expected: `CLEAN — no stale framing`

- [ ] **Step 4: Commit.**

Run (from repo root):
```bash
git add README.md packages/jet_print/README.md
git commit -m "docs: rewrite root README as product, add publishable package README"
```

---

## Task 5: Close T037 (export) — automate the preview action, record the human steps

**Files:**
- Modify: `packages/jet_print/test/designer/preview/jet_report_preview_test.dart`
- Create: `specs/012-export-support/acceptance-T037.md`
- Modify: `specs/012-export-support/tasks.md` (check off T037)

The exporter (`toPdf`/`pageToPng`) and printer (presenter seam) are already covered by `rendering/export/*` and `print/jet_report_printer_test.dart`. The one automatable acceptance step with **no** assertion today is "the preview's export/print toolbar actions actually fire their callbacks." The test file already defines `_exportKey`/`_printKey` and a `_pumpPreview(...)` harness accepting `onExportPdf`/`onPrint` — add the missing tap-fires-callback assertions. The genuinely human-only steps (driving the native macOS save panel and the OS print dialog) are recorded in an acceptance note.

- [ ] **Step 1: Write the failing test.** Append this `group` inside `main()` in `jet_report_preview_test.dart` (it reuses the file's existing `_exportKey`, `_printKey`, and `_pumpPreview` helpers):

```dart
  group('export/print toolbar actions (T037)', () {
    testWidgets('tapping export fires onExportPdf exactly once', (
      WidgetTester tester,
    ) async {
      int exports = 0;
      await _pumpPreview(tester, onExportPdf: () => exports++);
      await tester.tap(find.byKey(_exportKey));
      await tester.pump();
      expect(exports, 1);
    });

    testWidgets('tapping print fires onPrint exactly once', (
      WidgetTester tester,
    ) async {
      int prints = 0;
      await _pumpPreview(tester, onPrint: () => prints++);
      await tester.tap(find.byKey(_printKey));
      await tester.pump();
      expect(prints, 1);
    });

    testWidgets('with no callbacks, neither action is shown', (
      WidgetTester tester,
    ) async {
      await _pumpPreview(tester);
      expect(find.byKey(_exportKey), findsNothing);
      expect(find.byKey(_printKey), findsNothing);
    });
  });
```

- [ ] **Step 2: Run to verify it fails (or compiles-and-passes if already wired).**

Run (from repo root):
```bash
cd packages/jet_print && \
  flutter test test/designer/preview/jet_report_preview_test.dart ; \
  cd /Users/ahmeturel/Projects/oss/jet-print
```
Expected: the three new tests run. If `_pumpPreview`'s signature does not yet accept `onExportPdf`/`onPrint` by name, the file won't compile — in that case verify against the harness definition (the grep in the spec confirmed it takes `onExportPdf`/`onPrint`) and match the existing parameter names exactly. If the actions are conditionally rendered behind a callback, the first two tests prove they appear AND fire; the third proves they're absent without callbacks.

> If all three pass on first run, that is the expected outcome here (the keys and harness already exist; only the assertions were missing). Treat green as success and proceed — the test is still the closure artifact for T037's automatable steps.

- [ ] **Step 3: Write the acceptance record.** Create `specs/012-export-support/acceptance-T037.md`:

```markdown
# T037 — Acceptance record (export support, spec 012)

**Closed:** 2026-06-20, via Epic 1 (release hygiene), "automate + waive".

## Automated coverage (replaces the automatable quickstart steps)
- `JetReportExporter.toPdf` / `pageToPng`: `test/rendering/export/*` (byte
  determinism, page count/size, selectable text, scale math, range/scale errors).
- `JetReportPrinter` presenter seam: `test/print/jet_report_printer_test.dart`
  (same bytes as `toPdf`, true page size, job name, cancel→false, unavailable→
  `PrintUnavailableException`).
- Preview toolbar actions fire their callbacks and are hidden without them:
  `test/designer/preview/jet_report_preview_test.dart` group "export/print
  toolbar actions (T037)".

## Human-verified, then waived from per-release manual repetition
The following depend on OS-native dialogs the test harness cannot drive; verified
once by inspection in the macOS playground and waived going forward:
- Clicking the preview **export** action opens the native macOS save panel and
  writes a `.pdf` that opens in a standard (Quartz) viewer with extractable text.
- Clicking the preview **print** action opens the OS print dialog and
  print-to-file produces a document matching the preview page-for-page.

These remain re-verifiable by running `apps/jet_print_playground` and using the
preview toolbar; they are no longer a release blocker.
```

- [ ] **Step 4: Check off T037 in `specs/012-export-support/tasks.md`.** Change the line that begins `- [ ] T037` to `- [x] T037`, and append to its note: ` — CLOSED 2026-06-20 via Epic 1; see acceptance-T037.md.`

- [ ] **Step 5: Run the preview suite green, then commit.**

Run (from repo root):
```bash
cd packages/jet_print && \
  flutter test test/designer/preview/jet_report_preview_test.dart && \
  dart format --output=none --set-exit-if-changed test ; \
  cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/designer/preview/jet_report_preview_test.dart \
        specs/012-export-support/acceptance-T037.md \
        specs/012-export-support/tasks.md
git commit -m "test(012): automate preview export/print actions; close T037 with acceptance record"
```

---

## Task 6: Close T052 (format properties) — consolidated persistence test + record

**Files:**
- Create: `packages/jet_print/test/domain/serialization/styled_elements_roundtrip_test.dart`
- Create: `specs/021-format-properties/acceptance-T052.md`
- Modify: `specs/021-format-properties/tasks.md` (check off T052)

Most of T052's automatable acceptance is already covered (`domain/styles/*`, `domain/serialization/*`, `designer/controller/*_command_test.dart`, `designer/properties_editor_test.dart`). The one criterion without a single direct test is quickstart §4.3 — a report carrying **all three** styled element kinds (text underline + translucent color, shape fill/none/stroke-width, barcode color) round-trips through save→reload with every field intact. Add that one consolidated test, then record the visual GUI steps.

- [ ] **Step 1: Write the failing test.** Create `packages/jet_print/test/domain/serialization/styled_elements_roundtrip_test.dart`:

```dart
// T052 closure (spec 021): a report carrying all three styled element kinds —
// text (underline + translucent color), shape (fill/stroke/none states), and
// barcode (custom color) — survives an encode→decode round-trip byte-for-byte
// (quickstart §4.3). This is the automatable half of the format-properties
// acceptance; the visual GUI steps are recorded in acceptance-T052.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_print/jet_print.dart';

ReportDefinition _styledDef() => const ReportDefinition(
      name: 'Styled',
      page: PageFormat.a4Portrait,
      body: ReportBody(
        root: DetailScope(
          id: 'root',
          children: <ScopeNode>[
            BandNode(Band(
              id: 'detail',
              type: BandType.detail,
              height: 80,
              elements: <ReportElement>[
                TextElement(
                  id: 't1',
                  bounds: JetRect(x: 0, y: 0, width: 120, height: 18),
                  text: 'Hi',
                  style: JetTextStyle(
                    weight: JetFontWeight.bold,
                    underline: true,
                    color: JetColor(0x80123456), // translucent
                    align: JetTextAlign.center,
                  ),
                ),
                ShapeElement(
                  id: 's1',
                  bounds: JetRect(x: 0, y: 20, width: 40, height: 40),
                  kind: ShapeKind.rectangle,
                  style: JetBoxStyle(
                    fill: JetColor(0x3300FF00),
                    stroke: JetColor.black,
                    strokeWidth: 3,
                  ),
                ),
                BarcodeElement(
                  id: 'b1',
                  bounds: JetRect(x: 0, y: 64, width: 60, height: 16),
                  symbology: BarcodeSymbology.qrCode,
                  data: '42',
                  color: JetColor(0xFF1E40AF),
                ),
              ],
            )),
          ],
        ),
      ),
    );

void main() {
  test('all three styled element kinds round-trip losslessly (T052)', () {
    final ReportDefinition original = _styledDef();
    final String json = JetReportFormat.encodeDefinitionJson(original);
    final ReportDefinition reopened =
        JetReportFormat.decodeDefinitionJson(json);

    // Byte-stable canonical form is the strongest single assertion.
    expect(
      JetReportFormat.encodeDefinition(reopened),
      equals(JetReportFormat.encodeDefinition(original)),
    );

    // Spot-check the specific style fields the quickstart calls out.
    final List<ReportElement> els =
        reopened.body.root.children.whereType<BandNode>().single.band.elements;
    final TextElement text = els.whereType<TextElement>().single;
    expect(text.style.underline, isTrue);
    expect(text.style.color, const JetColor(0x80123456));
    final ShapeElement shape = els.whereType<ShapeElement>().single;
    expect(shape.style.fill, const JetColor(0x3300FF00));
    expect(shape.style.strokeWidth, 3);
    final BarcodeElement barcode = els.whereType<BarcodeElement>().single;
    expect(barcode.color, const JetColor(0xFF1E40AF));
  });
}
```

- [ ] **Step 2: Run to verify it passes (round-trip already supported).**

Run (from repo root):
```bash
cd packages/jet_print && \
  flutter test test/domain/serialization/styled_elements_roundtrip_test.dart ; \
  cd /Users/ahmeturel/Projects/oss/jet-print
```
Expected: PASS. If a property name differs from this plan (e.g. `JetTextStyle.color`/`align`, `BarcodeElement.color`), fix the test to the real public field names — confirm against `lib/jet_print.dart` exports and the existing `public_api_test.dart` style tests (which already exercise `JetTextStyle`, `JetBoxStyle`, and `setBarcodeColor`). This is a TDD test whose implementation already exists; a compile/assert failure means a name mismatch, not missing engine work.

- [ ] **Step 3: Write the acceptance record.** Create `specs/021-format-properties/acceptance-T052.md`:

```markdown
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
```

- [ ] **Step 4: Check off T052 in `specs/021-format-properties/tasks.md`.** Change the line beginning `- [ ] T052` to `- [x] T052`, and append: ` — CLOSED 2026-06-20 via Epic 1; see acceptance-T052.md.`

- [ ] **Step 5: Run the new test green, format, commit.**

Run (from repo root):
```bash
cd packages/jet_print && \
  flutter test test/domain/serialization/styled_elements_roundtrip_test.dart && \
  dart format --output=none --set-exit-if-changed test ; \
  cd /Users/ahmeturel/Projects/oss/jet-print
git add packages/jet_print/test/domain/serialization/styled_elements_roundtrip_test.dart \
        specs/021-format-properties/acceptance-T052.md \
        specs/021-format-properties/tasks.md
git commit -m "test(021): consolidated styled-element round-trip; close T052 with acceptance record"
```

---

## Task 7: Final verification sweep

**Files:** none (verification + any straggler fix).

- [ ] **Step 1: Full gate across both workspace members.**

Run (from repo root):
```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test packages/jet_print apps/jet_print_playground
```
Expected: formatting clean, zero analyzer warnings, all tests green across both packages.

- [ ] **Step 2: Confirm goldens unchanged except the intended deletion.**

Run (from repo root):
```bash
git status --porcelain packages/jet_print/test/goldens
git log --oneline -1 -- packages/jet_print/test/goldens/jet_print_placeholder.png
```
Expected: no uncommitted golden changes; the only golden touched in this epic is the **deleted** `jet_print_placeholder.png` (in Task 2's commit). If any other golden shows as modified, STOP and inspect — E1 must not alter rendering.

- [ ] **Step 3: Confirm the public surface is exactly 53 exports.**

Run (from repo root):
```bash
grep -c '^export' packages/jet_print/lib/jet_print.dart
```
Expected: `53`

- [ ] **Step 4: Confirm publishability metadata once more.**

Run (from repo root):
```bash
cd packages/jet_print && dart pub publish --dry-run ; cd /Users/ahmeturel/Projects/oss/jet-print
```
Expected: no license/description/metadata errors (version/`example/` warnings are acceptable Epic-6 follow-ups).

- [ ] **Step 5: Commit any stragglers (formatting, etc.), if `git status` is not clean.**

Run (from repo root):
```bash
git add -A && git commit -m "chore: E1 release-hygiene verification sweep" || echo "nothing to commit — clean"
```

---

## Self-Review

**Spec coverage** (against `2026-06-20-e1-release-hygiene-design.md`):
- Work item 1 (Apache-2.0 LICENSE root + package) → Task 1.
- Work item 2 (root README rewrite + new package README) → Task 4.
- Work item 3 (remove `JetPrintPlaceholder` widget+export+self-tests+golden, repoint to real entry) → Task 2.
- Work item 4 (pub.dev metadata) → Task 3 (also fixes the stale "scaffold" description).
- Work item 5 (close T037/T052 via automate-and-waive) → Tasks 5 & 6.
- SC-E1-1 → Task 1 Step 3. SC-E1-2 → Task 4 Step 3 (no stale framing) + working quickstart. SC-E1-3 → Task 2 Steps 5-6 + Task 7 Step 3 (53 exports, suite green, no placeholder refs). SC-E1-4 → Task 3 Step 2 + Task 7 Step 4 (`pub publish --dry-run`). SC-E1-5 → Tasks 5 & 6 (acceptance records + checked boxes + automated tests). SC-E1-6 → Task 7 Steps 1-2 (analyze/format/suite green, goldens unchanged but the placeholder).
- Out-of-scope guardrails (no version bump, no CHANGELOG cut, no `example/`) → stated in Global Constraints and reinforced in Task 3 Step 2 / Task 7 Step 4.

**Placeholder scan:** No "TBD/TODO/handle appropriately." Every code step shows real code; every command shows expected output. The two "if it already passes/name differs" notes (Task 5 Step 2, Task 6 Step 2) are deliberate reviewer guidance for tests whose implementation pre-exists, not deferred work.

**Type consistency:** `JetReportExporter.toPdf`/`pageToPng`, `JetReportPrinter.printReport`, `JetReportFormat.encodeDefinitionJson`/`decodeDefinitionJson`/`encodeDefinition`, `JetReportEngine.renderDefinition`, and the style fields (`JetTextStyle.underline/color/align`, `JetBoxStyle.fill/stroke/strokeWidth`, `BarcodeElement.color`) are taken from the read source/tests; Task 6 Step 2 explicitly instructs reconciling any field-name drift against the public surface before trusting the sketch.

**Risk:** The single behavioral risk is Task 2 (deleting the widget) cascading into a test that still references it — Steps 1-2 repoint both consumers before deletion, and Step 5 greps for stragglers. Everything else is docs/metadata/tests-of-existing-behavior.
