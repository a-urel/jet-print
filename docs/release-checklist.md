# Release checklist — P1, publishing `0.1.0`

The work that stands between the current tree and `jet_print` being installable
by a stranger. It exists because [`decisions/0001`](decisions/0001-publish-0-1-0-as-a-preview.md)
chose to publish a preview now rather than hold the name until the 1.0 freeze.
[`roadmap.md`](roadmap.md) places this phase in the wider plan.

Tick items here as they land; the phase is finished when `flutter pub add
jet_print` works for someone who has never seen this repository.

## Status of the evidence

The audit behind this list was run on 2026-09-21 against commit `a8aa9cb` by
**static inspection only**. No Dart or Flutter toolchain was available to the
machine that produced it, so **no pana score and no `pub publish --dry-run`
output exist yet**. Every score figure below is an estimate; every file-level
fact was read directly and is reliable.

Get the real numbers first, on a machine with a toolchain:

```bash
dart pub global activate pana
dart pub global run pana --json --no-warning packages/jet_print > pana.json
cd packages/jet_print && flutter pub publish --dry-run 2>&1 | tee ../../dry-run.txt
```

Use `flutter pub publish`, not `dart pub publish` — this is a Flutter package in
a pub workspace, and the Dart CLI will not resolve `sdk: flutter` dependencies.
Replace the estimates below with what those two commands actually say, and
correct anything this file gets wrong.

Estimated total: **130-150 of 160**, midpoint 140. Conventions 30/30, platform
support 20/20, documentation 10/20, static analysis 40-50 (unverifiable),
dependency currency 30-40 (unverifiable).

## Where this stands

Everything on this list that is a file change has been written, on the branch
`docs/p0-decisions`. **None of it has been compiled, analysed, formatted or
tested** — no Dart or Flutter toolchain is reachable from the session that wrote
it, and pub.dev is unreachable too. Treat the ticks below as "written", not as
"verified", until `verify-p1.sh` has run clean on a machine with a toolchain.
The two most likely failures are `dart format` disagreeing with hand-wrapped
lines, and the analyser reporting real diagnostics in `lib/` — which is the
point of the first item, since nothing has ever analysed this package from
inside its own directory.

Three things were found along the way and are worth reading before the
remaining items: the README Quickstart did not compile (`TextElement` requires
`text`, and the sample omitted it — fixed); `JetReportPreview` needs a
`shadcn_ui` ancestor and says so nowhere; and the example surfaced nine pieces
of API friction, now collected in [`api-friction.md`](api-friction.md) as the
seed of the P4 freeze review.

## Blocking — do these in order

- [x] **Add `packages/jet_print/analysis_options.yaml`.** The strict config CI
      enforces lives at the *repository root*, so it is not in the published
      archive and pana never sees it. The root file also excludes the generated
      localizations, and that exclusion disappears on publish, putting roughly
      127 KB of committed, never-linted `gen-l10n` output into pana's analysis.
      Include `package:flutter_lints/flutter.yaml`, restate the
      `**/l10n/jet_print_localizations*.dart` exclude, then run `flutter
      analyze` from inside the package directory to see what the root config has
      been masking. Do this first: until it is done, the 50-point analysis
      section is a black box and every other estimate rests on it. *~30 min plus
      whatever it uncovers.*
- [x] **Add `packages/jet_print/example/`.** The only confirmed deduction in the
      audit, and the only item on this list that certainly adds points (+10).
      `apps/jet_print_playground` is already a working consumer; trim it to one
      screen. It must keep compiling — pana analyses it. *2-4 h.*
- [x] **Pin `intl`.** `intl: any` is the sole expected `--dry-run` warning and
      the only theoretical threat to the 20-point lower-bound check. Use
      `^0.20.3`, which is what the lockfile already resolves. *5 min.*
- [ ] **Run `flutter pub outdated` and bump what has moved.** The last
      unquantified 10 points. `shadcn_ui ^0.54.0` is pre-1.0 and the likeliest
      mover. *15 min to 2 h.*
- [x] **Reconcile the changelog.** `## 0.1.0` at line 848 describes an "Initial
      scaffold release" advertising `JetPrintPlaceholder`, a widget that no
      longer exists, while every real feature sits under `## Unreleased` at line
      7. Publishing as-is ships a release note for a package that was never
      shipped. Either rename `## Unreleased` to a dated `## 0.1.0` and fold the
      stub in, or bump to `0.2.0` and date that. Costs no points; misleads every
      reader. *15 min.*
- [ ] **Run `pana` and `--dry-run` and act on the real output.** Then update the
      figures at the top of this file.

## Worth doing, cheap

- [x] **Add `packages/jet_print/.pubignore`** for `test/` and `tool/`. The
      archive is 6.8 MB, of which 4.0 MB is of no use to a consumer. *15 min.*
- [x] **Trim the package description.** 217 characters against pana's preferred
      60-180; expect a hint. Cutting the trailing clause is enough. *10 min.*
- [x] **Give the four `crosstab/*` barrel exports explicit `show` clauses.** Four
      of the 65 exports re-export everything public in their file, so any new
      public symbol there joins the API silently. This matters more once
      [`decisions/0002`](decisions/0002-extension-seam-closed-for-1-0.md) makes
      the surface a deliberate boundary. *30 min.*
- [ ] **Refresh `pubspec.lock`.** It still records `intl` as transitive after it
      became a direct dependency. *5 min.*
- [ ] **Confirm the dry-run accepts `resolution: workspace`** in a published
      package. Believed fine, unverified. *verify only.*

## Not worth doing for the score

These were assumed to be gaps and are real absences, but pana awards them
nothing. They buy presentation, not points, and they are not P1 work.

- `screenshots:` in the pubspec — affects the listing page only.
- `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` — not scored anywhere. P4 adds them
  for their own sake.
- Documenting the thirteen undocumented public declarations (twelve `Ctrl*`
  extensions plus `BoolProperty`). Coverage is already 108 of 121 = 89.3%
  against a 20% threshold. Worth doing for readers, worth nothing for the score.

## Assumptions this audit refuted

Three things believed to be release blockers are not.

- **dartdoc coverage is not a problem.** The June figure of 18 of 54 exports is
  stale by a wide margin; it is now 89.3% of public top-level declarations.
- **The changelog check passes.** A `## 0.1.0` heading exists and matches the
  pubspec version. The problem is its content, not its absence.
- **`screenshots:`, `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` are worth zero
  points.** Release-prep time spent on them is presentation work.

The package is in better shape than the June planning assumed. Scope the phase
accordingly: roughly one focused day of real work, of which the first and third
blocking items take under an hour combined and remove most of the remaining
uncertainty.
