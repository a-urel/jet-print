# The roadmap

What stands between `jet_print` as it is and `jet_print` as a released product,
and how far along each part of it is. This is the single tracked home for
release planning. It replaces the git-ignored
`docs/superpowers/specs/2026-06-20-production-readiness-roadmap-design.md`,
which was the only copy of the epic decomposition and therefore existed only in
git history — the failure mode [`workflow.md`](workflow.md) describes, arriving
at a document nobody could read without `git show`.

Two things live here. The **epic decomposition** is a restoration: E1 to E8 as
the 2026-06-20 assessment stated them, with a status column added and the
engineering judgement left alone. The **current plan** is what actually governs
work now — five phases that supersede the bare epic sequence, each with one
exit criterion somebody outside the project could check.

## The original assessment, in one line

> The engineering core is production-grade. What is missing is the release,
> platform, and packaging layer around it.

That verdict was reached against three intended consumers at once — a published
pub.dev package, a module embedded in our own app, and a standalone designer
product — and it held: none of the eight epics turned out to be "the reporting
engine is fragile". The target platforms named as in scope were desktop (macOS,
Windows, Linux), web, and mobile (iOS, Android). At the time only macOS was
exercised.

## Epic status

Status as of 2026-09-21. The size and tier columns are the original sizings,
not re-estimates.

| Epic | Tier | Size | Status | Evidence |
|---|---|---|---|---|
| E1 Release hygiene & truth | 0 | S | Done | `LICENSE` (Apache-2.0), rewritten `README.md`, pub metadata and `topics:` in `packages/jet_print/pubspec.yaml` |
| E2 Scale & resilience | 1 | M | Done | `test/rendering/resilience/stress_dirty_dataset_test.dart` at 50,000 rows; E2b deferred by decision |
| E3 Desktop matrix | 1 | M | Done | `.github/workflows/ci.yml` matrix: macOS, Ubuntu, Windows |
| E4 Web support | 1/2 | L | Done | `web (chrome)` CI job; one real `double.toString` divergence found and fixed |
| E5 Mobile / touch | 1/2 | XL | Done | `android (apk)` and `ios (no codesign)` CI jobs; touch handles, long-press menu, phone-width layout |
| E6 1.0 API freeze + pub.dev | 2 | M | In progress | `version: 0.1.0`, unpublished; P1 has written the release prep but nothing is verified |
| E7 Designer-as-product | 3 | L | Not started | no data-connection UI, no packaging or signing; file I/O exists only as playground host code |
| E8 Spec 033 multi-level aggregates | pre-1.0 | M | Done | PR #22, merged 2026-06-18 |

## The epics as written

Each epic was independently specifiable and shippable. Sizes are rough order of
magnitude (S/M/L/XL).

### E1 — Release hygiene & truth — Tier 0 — S — Low risk

Add a `LICENSE`; rewrite the stale README (it still describes the spec-001
scaffold and a "placeholder"); remove the vestigial `JetPrintPlaceholder`
export; add pub metadata stubs; close the pending manual-GUI acceptances (T037,
T052, …); explicitly resolve spec 033's postponed status. Removes false
signals; unblocks everything else. No engine risk.

**Done.** The package root carries an Apache-2.0 `LICENSE`, the README no
longer mentions a scaffold or a placeholder, `JetPrintPlaceholder` is gone from
`lib/`, and the pubspec declares `repository`, `homepage`, `issue_tracker` and
five topics. Spec 033 was resolved by promotion into E8 rather than by
cancellation.

### E2 — Scale & resilience — Tier 1 — M — Medium risk

Large-dataset (≈10k-row) render / paginate / export benchmark tests; memory
profile of the lazy pagination path; harden malformed-/missing-data error paths
(the `Diagnostic` system exists — confirm it covers the bad-input cases). This
is a **go/no-go gate**: prove the engine is embed-safe at real volume *before*
investing in platform breadth. May surface real engine work.

**Done, and the gate opened.** The committed stress test runs 50,000 rows with
every hundredth row carrying a wrong-type value, and asserts that the engine
does not crash, that diagnostics stay bounded, and that the clean rows still
sum correctly. Escalating-N exploration went well past the committed figure and
found no breaking point up to a million rows: growth was strictly linear at
roughly 1.24 MB and 6.4 microseconds per thousand rows, with no cliff. On that
evidence **E2b (streaming fill, streaming PDF export) was deferred by decision**
rather than scheduled, and E3 to E5 were allowed to start.

The findings table is no longer in the tree — it was written to the git-ignored
`docs/superpowers/` — but it survives at commit `f44cbc9d`, and two of its rows
now matter more than they did in June: 500,000 rows cost 631 MB of process RSS
and 1,000,000 cost 1.24 GB. The original finding named exactly that as the
evidence that would reopen E2b *if the library were ever aimed at a constrained
device*. [`decisions/0003`](decisions/0003-mobile-in-1-0-scope.md) has since
aimed it at one. Nothing in the deferral is wrong for the report sizes real
users author — tens of thousands of rows stay comfortable — but the condition
the deferral was written against is no longer hypothetical, and P4 should
re-read that table before the 1.0 platform claim is final.

The two standing proportionality guards are described in
[`testing.md`](testing.md); note that they count rather than time, and are not
the stress test.

### E3 — Desktop matrix — Tier 1 — M — Medium risk

Windows + Linux playground runners; expand CI to a desktop matrix; fix
platform-specific issues. Spec 038 already needed macOS-specific cursor
handling — Windows/Linux will have their own font, printing, and cursor
differences.

**Done.** `ci.yml` runs a three-way matrix. macOS is canonical: it alone runs
the full suite including goldens, and the `dart format` gate. Ubuntu and
Windows run the suite with the golden surface excluded, because host
rasterization and PDF subsetting differ per OS. Every leg builds the playground
to prove the native plugin toolchain links on that OS.

### E4 — Web support — Tier 1/2 — L — High risk

Verify `pdf` / `printing` / `image` + canvas rendering + font loading under
Flutter web. The `printing` plugin's web behavior is the chief unknown; font
embedding and raster decode are secondary risks.

**Done, and the risk was real but not where it was expected.** The plugin
surface held. What did not was arithmetic: JavaScript has one number type, so
`Number.toString()` drops the trailing `.0` an integer-valued Dart `double`
keeps on the VM, and the same expression rendered `5` on web where it rendered
`5.0` on desktop. `jetStringify` now normalizes it, and
`test/web/jet_stringify_web_test.dart` pins the behaviour on the Chrome leg.
The trap is recorded in [`../AGENTS.md`](../AGENTS.md).

### E5 — Mobile / touch — Tier 1/2 — XL — Highest risk

The designer is mouse-oriented: drag handles, hover cursors, right-click menus,
small hit targets. Touch needs gesture rework, larger targets, and likely
layout changes. This is **closer to an interaction redesign than a port** and
deserves its own brainstorming session; its cost may decide whether mobile is
in the 1.0.

**Done, and it did not dominate the program.** The canvas tracks
`PointerDeviceKind` and adapts: touch gets larger handle hit targets and a
thicker scroll bar, a long press takes the place of the right-click menu, and
the layout collapses to a phone width. CI builds an Android APK and an
unsigned iOS binary. Mobile is therefore in scope for the 1.0 platform
declaration rather than a question hanging over it.

### E6 — pub.dev 1.0 release — Tier 2 — M — Low risk (capstone)

API-stability review and freeze; `1.0.0`; cut a real CHANGELOG release entry;
`example/`; dartdoc + docs; CONTRIBUTING / CODE_OF_CONDUCT; multi-platform CI
green. **Must come after E4 and E5** (see sequencing).

**In progress, unverified.** The version is still `0.1.0` and the package is
not on pub.dev, but P1 has done the release prep: the changelog now carries a
dated `## 0.1.0 - 2026-09-21` entry with the scaffold stub retired, `example/`
exists, `intl` is pinned, and the analyser config ships with the package. None
of it has been compiled, analysed or tested — see
[`release-checklist.md`](release-checklist.md) for what the ticks there do and
do not mean. The detailed requirements — what pub.dev
rejects a publish for, what its score panel rewards, and the specific gaps —
were worked out separately on 2026-06-23 and are folded into P1 and P4 below.

### E7 — Designer-as-product — Tier 3 — L — Medium risk

File open/save UX, a data-source connection UI, and per-platform packaging /
signing / distribution. A separate product surface layered on the library.

**Not started**, and deliberately so — see P5. The playground does open, save
and export through `file_selector`, and can attach a `*.jetreport.datasource`
file, but that is host-owned I/O written to exercise the public API, not a
product surface the library offers. There is no data-connection UI, and no
packaging, signing or distribution of any kind.

### E8 — Spec 033: multi-level inline aggregates — pre-1.0 feature — M — Medium risk

Promoted from "postponed" into the pre-1.0 scope by decision (2026-06-20).
`{SUM([leaf])}` folds at every footer level (flat fold). Runs as a sibling to
E1; must land before the E6 1.0 freeze (it touches authoring + resolution, i.e.
the public surface).

**Done.** Merged as PR #22 on 2026-06-18, ahead of its own promotion into the
roadmap — engine folds, designer affordances, fx status for descendant
operands, en/de/tr strings, and the nested-list demo migrated onto it.

## The original sequencing

```
E1 ─▶ E2 ─▶ E3 ─┐
                ├─▶ E4 ─┐
                └─▶ E5 ─┤
E8 (spec 033) ──────────┴─▶ E6 (1.0 freeze) ─▶ E7
```

- **E1 first** — cheap, no risk, removes false signals everything else assumes.
- **E2 before platform breadth** — answer "is the core embed-safe at real
  volume?" before porting it to four more platforms. A memory/perf finding here
  is a core-engine concern you want early.
- **E6 (1.0 API freeze) must follow E4 and E5.** Declaring `1.0.0` is a semver
  promise not to break the public exports. Web and especially touch/mobile are
  exactly the work that forces breaking changes to the interaction and designer
  APIs. Freeze the surface *through* the platform work, then commit to it —
  never before.
- **E5 may dominate the program.** Everything else is "wrap working software
  for release"; E5 is a paradigm change. Its outcome may reshape whether mobile
  is in the 1.0 scope at all.

The gating held. The one judgement the outcome revised is the last: E5 landed
without reshaping the scope, so mobile is in the 1.0 platform declaration.

## Work delivered outside the roadmap

Two substantial programmes ran that the epic decomposition does not account
for. Both are recorded here so the gap between "E5 done, E6 next" and the
calendar is not mistaken for idle time.

**The crosstab / pivot engine and designer (30 August – 1 September 2026).** A
new feature axis rather than release work: single-pass prefix folding into a
matrix, crosstab bands spliced during the row walk, then the authoring side —
outline, canvas block, Properties inspector, six style slots, per-measure cell
overrides, en/de/tr strings, a pivot playground sample and its goldens. It
predates this roadmap's scope and lands inside the public surface, which makes
it E6's business: the crosstab API is part of what a 1.0 freezes. The planner
has no wiki page; [`README.md`](README.md) says where the written guidance for
it is.

**The September documentation and test-guard programme.** The ten-page wiki and
its five recipes were written, reviewed in successive rounds, and then held in
place by architecture tests: documented figures are pinned to the code that
produces them, table completeness is checked, the fx palette is pinned against
the evaluator's registry, and rule bodies copied into per-agent files are held
to the canonical one. The point of that work is that a documented claim now
fails loudly when it stops being true, rather than drifting.
[`testing.md`](testing.md) lists the guards.

## Current plan

The epic sequence answers "what is left". It does not answer "what do we do
next", because with E1 to E5 and E8 done, the remaining epics are one large
capstone and one product that may never be wanted. These five phases replace
the bare sequence. Each has exactly one exit criterion, and each criterion is
checkable by somebody who does not work on the project.

| Phase | Duration | Exit criterion |
|---|---|---|
| P0 Decisions | 3 days | the blocking decisions recorded under `decisions/` (six records; none on `main` yet) |
| P1 Publish 0.1.0 | 1 week | `flutter pub add jet_print` works for a stranger |
| P2 Stand-in consumer pilot | 2 weeks, parallel with P1 | one report authored in `apps/ledger_pilot/`, rendered and exported through the package's public API, plus a written friction list — amended, see below |
| P3 Extensibility boundary and defect closure | 3 weeks | no open question that would force a breaking change after 1.0 |
| P4 1.0 freeze | 3 weeks | `1.0.0` on pub.dev with all six platforms declared and green |
| P5 Designer-as-product | deferred | starts only on demonstrated demand |

**P0 — Decisions.** The three questions that everything downstream depends on:
what the first published version is, who the package is for, and where the
extensibility boundary sits. **These decisions have been taken**; the records
are in [`decisions/`](decisions/), and the rest of this plan is written against
their outcomes.

**P1 — Publish 0.1.0.** Ship the preview under its real name rather than
continuing to build against a package nobody can install. The exit criterion is
deliberately phrased from outside: not "the publish command succeeded" but that
an unconnected person can add the dependency and get a working package. That
forces the `intl` constraint, the `example/` and the dated changelog entry to be
real rather than nearly done. The itemised work, with what a 2026-09-21 audit
confirmed and what it refuted, is in
[`release-checklist.md`](release-checklist.md) — note that the dartdoc floor is
already cleared by a wide margin, and that the largest unknown was not any of
the items June expected but the package's missing local `analysis_options.yaml`,
which now exists and has still never been run.

**P2 — Stand-in consumer pilot.** Was *Monepro embed pilot*, and the criterion
it was given is amended rather than met. The original, kept here because a plan
that silently rewrites its own success conditions is worth less than no plan:

> One real Monepro report rendered and exported from the published package,
> plus a written friction list. Runs in parallel with P1 and consumes what P1
> publishes: one real report from a real product, rendered and exported through
> the published package with no path dependency and no reaching into
> `lib/src/`.

Two of its three parts are unavailable to this phase. The product repository
stays out of scope, so there is no embed to build; and `0.1.0` is not on
pub.dev, so there is no archive to consume. What runs instead is
`apps/ledger_pilot/`, a Turkish trial balance over a synthetic chart of
accounts, built inside this repository and consuming `jet_print` by path
through `package:jet_print/jet_print.dart`, still with no reaching into
`lib/src/`. The friction list remains the deliverable that outlives the phase.

[`decisions/0006`](decisions/0006-p2-runs-against-a-stand-in-consumer.md) rules
on the substitution and is the place to read what it costs: a path dependency
proves nothing about the published archive, and a consumer written by someone
who has just read the source cannot report the friction of not knowing where to
look. The first-party embed is deferred, not cancelled; 0006 says what re-opens
it. P2 completing is not evidence that the API has met the world.

**P3 — Extensibility boundary and defect closure.** The extensibility question
resolved to **closed by design** — the library does not take third-party
element types or renderers across its public surface, and that is the answer
rather than a gap to fill. P3 is therefore documentation plus defect closure,
not engine work: write down where the boundary is and why, close what P2's
friction list surfaced, and clear the defects that would otherwise be
discovered after the semver promise. The exit criterion is the absence of an
open question, which is why it cannot be met by shipping code alone.

**P4 — 1.0 freeze.** E6, renamed for what it actually is. All six platforms —
macOS, Linux, Windows, web, iOS, Android — declared in the pubspec and green in
CI, because a platform claim that CI does not exercise is the same class of
false signal E1 existed to remove.

**P5 — Designer-as-product.** E7, deferred rather than scheduled. It is a
second product, not the completion of this one, and nothing yet shows the
demand that would justify it. It starts when somebody asks for it and not
before.

## How this document is maintained

A status changes when a phase exit is met, not when the work feels close, and
the row that changes cites what an outside reader can check — a merged PR, a
green CI job, a file in the tree. The epic sections above are a restoration and
stay as they were written in June 2026; what moves is the status column and the
paragraph under each epic.

Planning documents belong here, in tracked `docs/`, and not in
`docs/superpowers/`. That directory is git-ignored scaffolding for work in
progress — see [`workflow.md`](workflow.md) — and a roadmap put there is
knowledge that outlives its branch filed somewhere that does not. This page
exists because that is exactly what happened to the first one.
