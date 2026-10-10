# `jet_print` — pub.dev readiness baseline

**Status: NO PANA SCORE WAS PRODUCED.** The Dart/Flutter toolchain could not be installed in this
container because every host that serves it is denied by this session's egress policy. What follows
is a manual checklist audit against pub.dev's published scoring criteria, with every claim tied to a
file I read at a named commit. **The totals below are my estimates, not pana output.** Treat them as
a prioritised work list, not as a number to quote.

| | |
|---|---|
| Package | `packages/jet_print` (`jet_print` 0.1.0) |
| Repo | `https://github.com/a-urel/jet-print` (public) |
| Commit audited | `a8aa9cb6eca9fe3665b9d05de9b614bee0a11f43` (2026-09-18, "Merge pull request #55") |
| Audit run | 2026-09-21T09:06Z |
| Audit method | static inspection + Python 3.11.15 parsing scripts (no Dart executed) |

---

## 1. Toolchain: what I tried and what blocked it

**Versions used: none.** There is no Dart and no Flutter in this container, and I could not install
either.

`which flutter dart` returned nothing. I then worked through every acquisition route:

| Attempt | Host | Result |
|---|---|---|
| Official stable tarball `flutter_linux_*-stable.tar.xz` | `storage.googleapis.com` | `curl: (56) CONNECT tunnel failed, response 403` |
| Flutter China mirror (`FLUTTER_STORAGE_BASE_URL`) | `storage.flutter-io.cn` | CONNECT rejected |
| Dart SDK archive | `dl.google.com`, `download.dartlang.org` | CONNECT rejected |
| `git clone flutter/flutter` + bootstrap | `github.com` reachable, but bootstrap pulls the bundled Dart SDK and engine artifacts from `storage.googleapis.com` | blocked at the same wall |
| GitHub release assets | `api.github.com/repos/flutter/flutter/releases/latest`, `.../dart-lang/sdk/...` | `assets: []` — neither project publishes SDK binaries on GitHub |
| Distro packages | `archive.ubuntu.com` (reachable) | Ubuntu 24.04 has no Dart/Flutter package; `apt-cache search dart` returns only the DART robotics library |
| Snap | `snapcraft.io` | CONNECT rejected |
| Package registry (needed even with an SDK) | `pub.dev`, `pub.dartlang.org`, `pub.flutter-io.cn` | all CONNECT rejected |

Proxy status endpoint (`$HTTPS_PROXY/__agentproxy/status`) recorded the denials verbatim:

```
storage.googleapis.com:443 connect_rejected
pub.dev:443              connect_rejected
dl.google.com:443        connect_rejected
storage.flutter-io.cn:443 connect_rejected
download.dartlang.org:443 connect_rejected
pub.dartlang.org:443     connect_rejected
pub.flutter-io.cn:443    connect_rejected
```

`/root/.ccr/README.md` is explicit: *"403 / 407 from the proxy — the destination host is not allowed
by your organization's egress policy for this session. Do not retry or route around it — report the
blocked host."* So I stopped.

**This was not a disk-space problem.** 30 GB were free throughout; the trimming fallback in the brief
was never needed.

`pub.dev` being blocked is the decisive one. Even a working SDK could not have run
`dart pub global activate pana`, `flutter pub get`, or the `pub downgrade` that pana's lower-bound
check depends on. Nothing about this is fixable from inside the container.

**To get a real number**, run this on a machine with normal egress:

```bash
git clone https://github.com/a-urel/jet-print.git && cd jet-print
flutter --version                      # record this in the report
dart pub global activate pana
dart pub global run pana --json --no-warning packages/jet_print > pana.json
cd packages/jet_print && flutter pub publish --dry-run 2>&1 | tee ../../dry-run.txt
```

Note `flutter pub publish`, not `dart pub publish` — this is a Flutter package in a pub workspace, and
the Dart CLI will not resolve `sdk: flutter` dependencies.

---

## 2. `dart pub publish --dry-run` output

**Not available.** I could not run it, and I will not invent it. Section 4 lists the warnings I expect
it to emit, each with the file and line that would cause it, so the real output can be diffed against
a prediction rather than against nothing.

---

## 3. Estimated score by section

pub.dev's current model is **160 points** across five sections. My estimate:

| Section | Max | Estimate | Confidence | Basis |
|---|---|---|---|---|
| Follow Dart file conventions | 30 | **30** | High | All four sub-checks verified by hand |
| Provide documentation | 20 | **10** | **Certain** | Example missing (−10); dartdoc far above threshold |
| Platform support | 20 | **20** | Medium | Conditional imports correct; depends on `printing`'s tags |
| Pass static analysis | 50 | **40–50** | Low | Cannot run the analyzer; structural risk in §4.4 |
| Support up-to-date dependencies | 40 | **30–40** | Low | Cannot query pub.dev for latest versions |
| **Total** | **160** | **≈130–150, midpoint 140** | — | — |

The only **confirmed** deduction in the whole audit is the missing example (−10). Everything else
is either verified-passing or unverifiable-from-here. The honest headline is: *this package is in
much better shape than the brief's premise assumed, and the release-prep work should be scoped
accordingly.*

### 3.1 Follow Dart file conventions — 30/30 estimated

| Check | Pts | Verdict | Evidence |
|---|---|---|---|
| Valid `pubspec.yaml` | 10 | Pass (one hint) | `packages/jet_print/pubspec.yaml` — name, version 0.1.0, `repository`, `homepage`, `issue_tracker`, 5 `topics`, SDK constraints all present. Description is 217 chars vs pana's preferred 60–180 → expect a hint, probably not a deduction. |
| Valid `README.md` | 5 | Pass | `packages/jet_print/README.md`, 111 lines, sections: Features, Quickstart, Designer widget, Platform support, License. Real runnable code sample. |
| Valid `CHANGELOG.md` | 5 | Pass | `packages/jet_print/CHANGELOG.md` has `## 0.1.0` at line 848, matching the pubspec version. **This refutes the assumption in the brief** — pana's check is "does a heading match the published version", and one does. See §4.5 for why it still needs work. |
| OSI-approved license | 10 | Pass | `packages/jet_print/LICENSE` — Apache License 2.0, full 169-line text, correctly placed inside the package directory. |

### 3.2 Provide documentation — 10/20 estimated

| Check | Pts | Verdict | Evidence |
|---|---|---|---|
| Package has an example | 10 | **FAIL** | No `packages/jet_print/example/` at all. pana accepts `example/lib/main.dart`, `example/main.dart`, `example/README.md` or `example/example.md`; none exist. `git ls-files packages/jet_print` shows only `lib/ test/ tool/` plus the four metadata files. README code blocks do not satisfy this check. |
| ≥20% of public API has dartdoc | 10 | **Pass, comfortably** | I parsed the barrel and all 79 files reachable through it: **108 of 121** public top-level declarations carry `///` comments — **89.3%**, against a 20% threshold. |

**The "18 of 54 exports" figure from June is refuted at this commit.** The barrel
(`packages/jet_print/lib/jet_print.dart`) now has **65 `export` directives** exposing **106
explicitly-shown symbols**, and documentation has clearly been done since. The 13 undocumented
top-level declarations are the twelve `Ctrl*` controller extensions
(`packages/jet_print/lib/src/designer/controller/api/*.dart`, e.g. `CtrlSelection` at
`selection.dart:8`) plus `BoolProperty` at `packages/jet_print/lib/src/domain/bool_property.dart:11`
— and `BoolProperty` is a false negative, since the file carries a `library`-level doc comment
describing it. Documenting these is polish, not points.

### 3.3 Platform support — 20/20 estimated

The package declares no platform restriction and its platform-specific code is correctly guarded:

```dart
// packages/jet_print/lib/src/designer/canvas/native_resize_cursor.dart:14
import 'native_resize_cursor_stub.dart'
    if (dart.library.io) 'native_resize_cursor_io.dart' as platform;
```

`dart:ffi` and `dart:io` appear **only** inside `native_resize_cursor_io.dart`, reached only when
`dart.library.io` is available. Web and WASM get the stub. Everything else in `lib/` is Flutter or
pure Dart (21 files touch `dart:ui`; none touch `dart:html`, `dart:js` or `package:web`).

Residual risk: pana derives platform tags transitively, so `printing ^5.14.3` and `shadcn_ui ^0.54.0`
can narrow the result. `README.md:86–108` claims CI covers all six targets, which is consistent with
6/6, but only a real pana run settles it — including whether the WASM tag is awarded.

### 3.4 Pass static analysis — 40–50 estimated, unverifiable

I cannot run the analyzer, so this is the softest number in the report. Two observations:

**Pointing up.** The workspace enforces a stricter-than-default gate: `/analysis_options.yaml` sets
`strict-casts`, `strict-inference` and `strict-raw-types`, promotes `unused_import`,
`unused_local_variable`, `unused_element`, `unused_field` and `dead_code` to **errors**, and adds
`prefer_relative_imports` and `directives_ordering` on top of `flutter_lints`. The file's own comment
states the goal is "ZERO analyzer warnings — not merely zero errors", and CI enforces it. A codebase
that clears that bar will almost certainly clear pana's.

**Pointing down — and this is a real structural finding.** `analysis_options.yaml` lives at the
**repository root**, not in `packages/jet_print/`. I confirmed there is no
`packages/jet_print/analysis_options.yaml`. The published tarball contains only the package
directory, so **the config that CI validates against is not the config pana sees**. Two consequences:

- pana analyzes with its own defaults, not `flutter_lints` — usually *looser*, so not itself a threat.
- The root file's exclusion of generated localizations
  (`- "**/l10n/jet_print_localizations*.dart"`) is lost. The generated files **are** committed —
  `packages/jet_print/lib/src/designer/l10n/jet_print_localizations.dart` (62 KB) and the `_en`/`_de`/`_tr`
  siblings — so pana will analyze roughly 127 KB of machine-generated code that CI has never linted.
  Generated `gen-l10n` output is normally clean, but nobody has checked.

This gap is the difference between "we know analysis is clean" and "we hope it is", and it is cheap
to close.

### 3.5 Support up-to-date dependencies — 30–40 estimated, unverifiable

| Check | Pts | Verdict | Notes |
|---|---|---|---|
| All dependencies supported in latest version | 10 | Unknown | Needs `pub.dev`, which is blocked. Declared: `intl: any`, `shadcn_ui: ^0.54.0`, `pdf: ^3.12.0`, `printing: ^5.14.3`, `image: ^4.3.0`, `barcode: ^2.2.9`, `vector_math: ^2.2.0`. `shadcn_ui` is pre-1.0 and moves fast — the likeliest single point of failure here. |
| Supports latest stable Dart and Flutter SDKs | 10 | Likely pass | `sdk: ^3.6.0`, `flutter: ">=3.44.0"`, both open at the top. `/pubspec.lock` records `dart: ">=3.12.0 <4.0.0"`, `flutter: ">=3.44.0"`. |
| Compatible with dependency constraint lower bounds | 20 | Likely pass | This is what `intl: any` threatens — `any` nominally admits intl 0.0.x. In practice `flutter_localizations` from the SDK pins intl tightly, and `/pubspec.lock` resolves it to **0.20.3**, so `pub downgrade` is probably boxed in. Probably, not certainly: this check is exactly the one I cannot run. |

**On `intl: any`:** confirmed present at `packages/jet_print/pubspec.yaml`. But my read is that it is a
**`pub publish` warning, not a pana deduction** — and the fix costs thirty seconds, so the distinction
is academic. Pin it.

**Unrelated lock finding:** `/pubspec.lock:296–302` records intl as `dependency: transitive`, while
`packages/jet_print/pubspec.yaml` declares it as a direct dependency. The lockfile is stale relative to
the pubspec. Harmless, but it means the committed lock does not reflect the current manifest.

---

## 4. Deductions and other findings

Sorted by points at risk. "Score impact" distinguishes confirmed point losses from risks and from
items that cost nothing at all.

| # | Finding | Section | Score impact | Remedy | Effort |
|---|---|---|---|---|---|
| 1 | **No `example/` directory** — confirmed absent | Documentation | **−10, certain** | Add `packages/jet_print/example/` with its own `pubspec.yaml` and `lib/main.dart`. `apps/jet_print_playground` is a working consumer already — trim it to one screen. Must stay compiling; pana analyzes it. | 2–4 h |
| 2 | **No package-local `analysis_options.yaml`** — root config is not published | Analysis | **up to −50 at risk** | Add `packages/jet_print/analysis_options.yaml` including `package:flutter_lints/flutter.yaml` and re-stating the `**/l10n/jet_print_localizations*.dart` exclude, then re-run `flutter analyze` from inside the package dir to see what CI has been hiding. | 30 min + fixes |
| 3 | **Dependency currency unverified** — `pub.dev` unreachable from here | Dependencies | **up to −10 at risk** | `flutter pub outdated` on a connected machine. Expect `shadcn_ui ^0.54.0` to be the one that has moved. | 15 min + bumps |
| 4 | **`intl: any`** — unbounded constraint | Dependencies / dry-run | 0 pts expected; **dry-run warning, confirmed** | `intl: ^0.20.3`, matching what `/pubspec.lock` already resolves. | 5 min |
| 5 | **`## 0.1.0` changelog entry describes the wrong release** | Conventions | 0 pts (check passes) | The 0.1.0 entry says "Initial scaffold release … `JetPrintPlaceholder`". Every real feature sits under `## Unreleased` at line 7. Publishing as-is ships a changelog that describes a placeholder widget. Rename `## Unreleased` to `## 0.1.0` with a date and fold the old stub in — or bump to 0.2.0 and date that. | 15 min |
| 6 | **Description is 217 chars** (pana prefers 60–180) | Conventions | 0–10, likely hint only | Trim to ~150 chars. The current text runs "…, and an interactive shadcn_ui-themed designer surface." — cut the last clause. | 10 min |
| 7 | **4 barrel exports have no `show` clause** | API hygiene | 0 pts | `src/domain/crosstab/{crosstab,crosstab_group,crosstab_measure,crosstab_style}.dart` re-export everything public, so any new public symbol in those files silently joins the API. Add explicit `show` lists. | 30 min |
| 8 | **13 undocumented public top-level declarations** | Documentation | 0 pts (89.3% ≫ 20%) | Twelve `Ctrl*` extensions under `lib/src/designer/controller/api/` plus `BoolProperty`. Worth doing for readers, worth nothing for the score. | 1 h |
| 9 | **`test/` (3.9 MB) and `tool/` (128 KB) ship in the archive** | — | 0 pts | Package is 6.8 MB, of which 4.0 MB is never useful to a consumer. Add `packages/jet_print/.pubignore` listing `test/` and `tool/`. | 15 min |
| 10 | **Stale `pubspec.lock`** — intl marked transitive | — | 0 pts | `flutter pub get` at the workspace root, commit the result. | 5 min |
| 11 | **No `screenshots:` in pubspec** | — | **0 pts** | Screenshots affect the listing page, not the score. Optional. | 1–2 h |
| 12 | **No `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md`** | — | **0 pts** | Neither is scored by pana, anywhere. Optional. | 30 min |
| 13 | **`resolution: workspace` in a published package** | — | Unknown | Worth confirming the dry-run accepts it. I believe pub tolerates it and consumers ignore it, but I could not verify without the toolchain. | verify |

Items 11 and 12 were on the brief's list of suspected gaps. They are real absences, and they are
**not worth any pub.dev points**. Spending release-prep time on them buys presentation, not score.

---

## 5. Smallest set of changes to clear 140 points

My central estimate already puts the package around 140. The work below is what makes clearing it
*robust* rather than *probable*, in dependency order:

1. **Add `packages/jet_print/analysis_options.yaml`** (30 min). Do this **first** — until the
   published package is analyzed under its own config, the 50-point analysis section is a black box
   and every other estimate is built on sand. Run `flutter analyze` from inside the package
   directory and fix whatever the root config was masking.
2. **Add `packages/jet_print/example/`** (2–4 h). The only confirmed deduction. Worth a guaranteed
   +10 and nothing else on this list is.
3. **Pin `intl: ^0.20.3`** (5 min). Clears the sole expected dry-run warning and removes the only
   theoretical threat to the 20-point lower-bound check.
4. **Run `flutter pub outdated` and bump what has moved** (15 min–2 h depending on `shadcn_ui`).
   The last unquantified 10 points.

That is roughly one focused day. Steps 1 and 3 are under an hour combined and eliminate most of the
uncertainty in this report; step 2 is the only item that definitely adds points.

Fix the changelog (item 5) before publishing regardless — it costs no points and misleads every
reader.

---

## 6. The brief's assumptions, checked

| Assumption | Verdict |
|---|---|
| `intl: any` is unpinned | **Confirmed** — `packages/jet_print/pubspec.yaml`. Likely a dry-run warning, not a deduction. |
| No `example/` directory | **Confirmed** — the one certain deduction, −10. |
| dartdoc was 18/54; barrel now ~65 exports | **Barrel size confirmed** (65 `export` directives, 106 shown symbols). **Coverage figure refuted** — now 108/121 = 89.3% of public top-level declarations, vastly above the 20% threshold. Not a deduction. |
| `CHANGELOG.md` has no dated release entry | **Partly refuted** — `## 0.1.0` exists at line 848 and matches the pubspec version, so pana's check passes. But its content describes a scaffold release while all real content sits under `## Unreleased`. A content problem, not a scoring one. |
| No `screenshots:` in pubspec | **Confirmed absent** — worth **0 points**. |
| No `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md` | **Confirmed absent** — worth **0 points**. |
| Repo is public, so verified-repository should pass | **Repo is public** (cloned anonymously). Verified-repository is a pub.dev **badge**, not a pana point; `repository:` is set correctly. The monorepo layout is the thing to watch when it is first published. |

### Findings the brief did not anticipate

- **The root `analysis_options.yaml` is not published with the package** (§3.4, item 2). The largest
  single block of unverified score.
- **Generated localizations are committed but excluded from CI linting**, and that exclusion
  disappears on publish — ~127 KB of never-linted code enters pana's analysis.
- **4 of 65 barrel exports have no `show` clause**, leaving part of the public API implicit.
- **`test/` and `tool/` are 4.0 MB of the 6.8 MB archive** with no `.pubignore` to stop them.
- **`/pubspec.lock` is stale** — it still records intl as transitive after it became a direct dependency.

---

## 7. Files inspected

```
/pubspec.yaml                                              workspace root, members list
/analysis_options.yaml                                     strict lints — NOT published with the package
/pubspec.lock                                              intl 0.20.3 (transitive); dart >=3.12.0; flutter >=3.44.0
/.gitignore                                                per-package lockfiles excluded
/apps/jet_print_playground/pubspec.yaml                    example-source candidate
/packages/jet_print_google_fonts/pubspec.yaml              sibling package, publish_to: none
/packages/jet_print/pubspec.yaml                           intl: any; 217-char description; no screenshots
/packages/jet_print/README.md                              111 lines, 5 sections
/packages/jet_print/CHANGELOG.md                           ## Unreleased (L7), ## 0.1.0 (L848)
/packages/jet_print/LICENSE                                Apache-2.0, 169 lines
/packages/jet_print/l10n.yaml                              gen-l10n config
/packages/jet_print/lib/jet_print.dart                     barrel: 65 exports, 106 shown symbols
/packages/jet_print/lib/src/**                             295 .dart files; 79 reachable from the barrel
/packages/jet_print/lib/src/designer/canvas/native_resize_cursor*.dart   conditional dart:io/dart:ffi
/packages/jet_print/lib/src/designer/l10n/                 generated localizations, committed, CI-excluded
/packages/jet_print/test/**                                408 .dart files, 3.9 MB
/packages/jet_print/tool/                                  font-generation script + 4 TTF subsets, 128 KB
(absent) /packages/jet_print/example/
(absent) /packages/jet_print/analysis_options.yaml
(absent) CONTRIBUTING.md, CODE_OF_CONDUCT.md  (package and repo root)
```
