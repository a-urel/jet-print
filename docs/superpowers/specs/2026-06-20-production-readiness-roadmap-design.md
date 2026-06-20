# jet_print — Production Readiness Roadmap

- **Date:** 2026-06-20
- **Status:** Approved (umbrella roadmap; each epic gets its own spec → plan → implement cycle)
- **Type:** Assessment + decomposition (not directly implementable — it indexes the epics that are)

## Purpose

Answer the question "can `jet_print` be considered production-ready, or what must
be completed first?" against three intended consumers at once — a published
pub.dev package, a module embedded in our own app, and a standalone designer
product — and decompose the remaining work into independently shippable epics.

## What jet_print is today (grounding)

A layered, theme-aware Flutter widget library for building WYSIWYG report
designers, plus a macOS playground app that consumes it as an external consumer
would. Current measured state (2026-06-20):

- **~35k LOC** of library source across **220 files** under `packages/jet_print/lib/src`.
- **~40k LOC** of tests across **300 files**; **1847 tests passing**, exit 0.
- A single public entry point (`lib/jet_print.dart`) with **54 curated exports**.
- Quality gate enforced in CI: `dart format` + `flutter analyze` (zero warnings) + tests.
- Feature breadth: reified band/scope tree (`ReportDefinition`), groups, nested &
  recursive aggregates, fx expression editor, 10 barcode/QR symbologies,
  multi-column labels, images, shapes, PDF + PNG export, system print, full
  interactive designer (select/resize/move/undo-redo/zoom/rulers/grid-snap/
  clipboard), versioned serialization migrations, i18n (en/de/tr), and a real
  data-source abstraction (in-memory/JSON/object) feeding 7 realistic playground
  samples (invoice, label, barcode, menu, nested list, packing slip, payroll).

## Verdict

**The engineering core is production-grade. What is missing is the release,
platform, and packaging layer around it.** The gaps are not "the reporting engine
is fragile" — they are "this has not yet been turned into a shippable/publishable
artifact, and has only ever run on one platform."

Two structural strengths drive that verdict:

1. **Invariants are enforced, not documented.** `encapsulation_test.dart` (no
   consumer reaches into `lib/src/`) and `architecture/layer_boundaries_test.dart`
   (inward-only dependencies) make the layering a build failure if violated, so it
   cannot silently rot. WYSIWYG fidelity is golden-locked.
2. **The public surface is deliberate.** One entry point, 54 explicit exports,
   privacy enforced — the contract is real, not incidental.

## Evidence scorecard

🔴 = hard blocker · 🟡 = risk / soft blocker · — = not a concern for that target

| Dimension | State | pub.dev | embed | ship designer |
|---|---|:--:|:--:|:--:|
| Functional breadth | Strong | — | — | — |
| Test coverage & gates (1847 green) | Strong | — | — | — |
| Architecture / API encapsulation (test-enforced) | Strong | — | — | — |
| WYSIWYG render fidelity (golden-locked) | Strong | — | — | — |
| LICENSE file | Missing | 🔴 | 🟡 | 🟡 |
| Versioning (still `0.1.0`, all "Unreleased") | Immature | 🔴 | — | — |
| pub.dev metadata (`repository`/`homepage`/`topics`, `example/`) | Missing | 🔴 | — | — |
| Docs (README still says "scaffold/placeholder"; no integration guide) | Stale | 🔴 | 🟡 | 🟡 |
| Cross-platform (only `macos/` runner; CI macOS-only) | Unverified | 🔴 | 🟡 | 🟡 |
| Scale / performance (lazy pagination, but no large-dataset benchmark) | Unproven | 🟡 | 🟡 | 🟡 |
| Acceptance closure (manual GUI walks T037/T052… pending; spec 033 postponed) | Partial | 🟡 | 🟡 | 🟡 |
| Designer-as-product UX (no file open/save, data-connection UI, packaging) | Absent | — | — | 🔴 |

## Target platforms (in scope for production)

Desktop (macOS / Windows / Linux), **Web**, and **Mobile (iOS / Android)**. Today
only macOS is exercised; the library is written to be platform-agnostic but this
is unverified everywhere else.

## Epic decomposition

Each epic is independently specifiable and shippable. Sizes are rough order of
magnitude (S/M/L/XL).

### E1 — Release hygiene & truth — Tier 0 — S — Low risk
Add a `LICENSE`; rewrite the stale README (it still describes the spec-001
scaffold and a "placeholder"); remove the vestigial `JetPrintPlaceholder` export;
add pub metadata stubs; close the pending manual-GUI acceptances (T037, T052, …);
explicitly resolve spec 033's postponed status. Removes false signals; unblocks
everything else. No engine risk.

### E2 — Scale & resilience — Tier 1 — M — Medium risk
Large-dataset (≈10k-row) render / paginate / export benchmark tests; memory
profile of the lazy pagination path; harden malformed-/missing-data error paths
(the `Diagnostic` system exists — confirm it covers the bad-input cases). This is
a **go/no-go gate**: prove the engine is embed-safe at real volume *before*
investing in platform breadth. May surface real engine work.

### E3 — Desktop matrix — Tier 1 — M — Medium risk
Windows + Linux playground runners; expand CI to a desktop matrix; fix
platform-specific issues. Spec 038 already needed macOS-specific cursor handling —
Windows/Linux will have their own font, printing, and cursor differences.

### E4 — Web support — Tier 1/2 — L — High risk
Verify `pdf` / `printing` / `image` + canvas rendering + font loading under
Flutter web. The `printing` plugin's web behavior is the chief unknown; font
embedding and raster decode are secondary risks.

### E5 — Mobile / touch — Tier 1/2 — XL — Highest risk
The designer is mouse-oriented: drag handles, hover cursors, right-click menus,
small hit targets. Touch needs gesture rework, larger targets, and likely layout
changes. This is **closer to an interaction redesign than a port** and deserves
its own brainstorming session; its cost may decide whether mobile is in the 1.0.

### E6 — pub.dev 1.0 release — Tier 2 — M — Low risk (capstone)
API-stability review and freeze; `1.0.0`; cut a real CHANGELOG release entry;
`example/`; dartdoc + docs; CONTRIBUTING / CODE_OF_CONDUCT; multi-platform CI
green. **Must come after E4 and E5** (see sequencing).

### E7 — Designer-as-product — Tier 3 — L — Medium risk
File open/save UX, a data-source connection UI, and per-platform packaging /
signing / distribution. A separate product surface layered on the library.

### E8 — Spec 033: multi-level inline aggregates — pre-1.0 feature — M — Medium risk
Promoted from "postponed" into the pre-1.0 scope by decision (2026-06-20).
`{SUM([leaf])}` folds at every footer level (flat fold). **Already has
`spec.md` + `plan-designer.md` + `plan-engine.md`** at
`specs/033-multilevel-inline-aggregates/` — so it skips brainstorming and goes
straight to plan-execution. Runs as a sibling to E1; must land before the E6
1.0 freeze (it touches authoring + resolution, i.e. the public surface).

## Sequencing & gating constraints

```
E1 ─▶ E2 ─▶ E3 ─┐
                ├─▶ E4 ─┐
                └─▶ E5 ─┤
E8 (spec 033) ──────────┴─▶ E6 (1.0 freeze) ─▶ E7
```

- **E1 first** — cheap, no risk, removes false signals everything else assumes.
- **E2 before platform breadth** — answer "is the core embed-safe at real volume?"
  before porting it to four more platforms. A memory/perf finding here is a
  core-engine concern you want early.
- **E6 (1.0 API freeze) must follow E4 and E5.** Declaring `1.0.0` is a semver
  promise not to break the 54 public exports. Web and especially touch/mobile are
  exactly the work that forces breaking changes to the interaction and designer
  APIs. Freeze the surface *through* the platform work, then commit to it — never
  before.
- **E5 may dominate the program.** Everything else is "wrap working software for
  release"; E5 is a paradigm change. Its outcome may reshape whether mobile is in
  the 1.0 scope at all.

## Per-target readiness summary

- **Embed in our own app:** closest to ready. Gated by E2 (scale/resilience) and
  by E3/E4/E5 only for whichever platforms we actually ship on.
- **Publish on pub.dev:** furthest. Needs E1 + E6 at minimum, plus the platform
  epics for any "supports X" claim to be honest.
- **Ship the designer as a product:** needs E7 on top of the platform epics for
  its target platforms.

## Next step

**E1 — Release hygiene & truth** is brainstormed and specced:
[e1-release-hygiene-design.md](./2026-06-20-e1-release-hygiene-design.md) — ready
for `writing-plans`. **E8 (spec 033)** follows immediately as a sibling (it already
has spec + plans → plan-execution). The remaining epics are brainstormed in later
sessions, in roughly the sequence above.
