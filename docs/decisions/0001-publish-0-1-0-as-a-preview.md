# 0001 — Publish `0.1.0` to pub.dev as a preview

**Status:** Accepted — 2026-09-21

## Context

`packages/jet_print/pubspec.yaml` has carried `version: 0.1.0` since the package
was named, under a comment that states the plan: "Version stays 0.1.0 until the
1.0 API freeze (Epic 6)." `lib/src/version.dart` → `jetPrintVersion` mirrors it.
Nothing has been published.

The roadmap that comment points at sequenced the epics
`E1 → E2 → E3 → E4/E5 → E6 (1.0 freeze) → E7` and gated the freeze explicitly:
it "must follow E4 and E5", because "Declaring `1.0.0` is a semver promise not
to break the 54 public exports. Web and especially touch/mobile are exactly the
work that forces breaking changes to the interaction and designer APIs." That
document lived under `docs/superpowers/`, which [`../workflow.md`](../workflow.md)
designates working-document space, and is no longer in the tree; the quotations
above are from commit `d9b2458d` (2026-06-20), which is where it survives.

E5 finished on 2026-06-21 — its last commit is `f94cf7a4`, recording the third
round of simulator smoke. The gate has been open since. Three months later the
version is still `0.1.0`, and the roadmap's only stated exit condition is an API
freeze.

That exit condition is the problem, because it structurally rewards waiting.
A freeze is a promise about a surface, so every addition to the surface is a
fresh reason to postpone the promise — the work that would be frozen keeps
arriving, and each arrival is an argument for one more month. The figures say
this is not hypothetical. On 2026-06-22 (`c40540d6`) `lib/jet_print.dart` carried
54 `export` directives naming 84 public symbols — the 54 the roadmap counted.
Today it carries 65 directives naming 118 symbols by `show`, plus the five types
reached through the four whole-file `src/domain/crosstab/…` exports: 123 public
names. In the window the freeze was nominally waiting out, the surface grew by
11 directives and 39 names.

Crosstab, which landed between 2026-08-30 and 2026-09-01, accounts for four of
those directives and eight of those names — `Crosstab`, `CrosstabSort`,
`CrosstabGroup`, `CrosstabMeasure`, `CrosstabStyle`, `CrosstabNode`,
`CtrlCrosstab`, and `UnknownScopeNode`, the last being, as the CHANGELOG puts
it, "the crosstab's own forward-migration seam". It is a good feature. It is
also exactly the kind of feature that will exist again next quarter, and the
freeze-first plan has no answer to that other than waiting longer.

The release channel that does have an answer is the one already in the version
number. Below `1.0.0`, pub.dev and the semver spec both treat a minor bump as
potentially breaking, so a `0.x` release carries no stability promise at all.
Publishing does not freeze anything.

## Decision

Publish `0.1.0` to pub.dev now, as a preview, rather than holding the package
name until the surface is frozen.

The release is gated on the P1 checklist, not on an API freeze:

- pin `intl` — `pubspec.yaml` currently declares `intl: any`, which is not a
  constraint;
- add an `example/` directory (the package has none; `apps/jet_print_playground`
  is a workspace member and does not appear on a pub.dev page);
- dartdoc coverage on the public surface;
- screenshots declared in `pubspec.yaml` (no `screenshots:` key today);
- a dated `## 0.1.0` entry in `packages/jet_print/CHANGELOG.md` — which means
  reconciling two sections, not adding one. The file already carries an undated
  `## 0.1.0` headed "Initial scaffold release", written when the package was
  scaffolded and now describing software that no longer exists (it announces
  `JetPrintPlaceholder`, removed in `fe79c076`), while `## Unreleased` holds
  every change since. Publishing `0.1.0` against that file would ship a release
  note for the scaffold; the two sections fold into one dated entry;
- a `.pubignore` (none exists; `build/` and `tool/fonts/` are the obvious
  candidates);
- pana score at or above 140;
- a clean `dart pub publish --dry-run`.

## Consequences

**It claims the name.** Publishing is what reserves `jet_print`; holding the
version back reserves nothing. The cost of losing the name is not a rename in
one file — it is a rename that reaches every import in every consumer, the
barrel, the docs, `pubspec.yaml`'s `repository`/`homepage`/`issue_tracker` URLs
and the CI jobs.

**It produces a real install path.** Everything the package currently proves
about itself it proves to itself: `apps/jet_print_playground` consumes the
library only through its public API, which is what keeps the API honest, but it
consumes it as a workspace member with a root `pubspec.lock`. A `pub add
jet_print` resolves against published constraints instead, which is a different
question — and `intl: any` is the kind of answer that only goes wrong there.

**It produces outside feedback while feedback is still cheap to act on.** A bug
report against `0.1.0` can be fixed by changing the API. The same report against
`1.0.0` cannot.

**It costs the quiet.** A published `0.x` invites issues against an API that is
still going to move, and there is one maintainer to field them. This is the real
price and it is not small: the package acquires users whose expectations are set
by the pub.dev page rather than by the version number, and every one of them is
a correspondent. Some of those issues will be about behaviour that is about to
change anyway, and answering them is still work. The judgement here is that the
feedback is worth more than the quiet, not that the quiet costs nothing.

**It puts a stale artifact in the world.** Once published, `0.1.0` is
permanent — pub.dev does not allow a version to be replaced — so whatever ships
is what a reader finds for as long as it is the newest release.

## What this does not decide

- **Not a 1.0 date, and not a freeze.** `0.1.0` makes no semver promise;
  breaking changes remain free, by minor bump, until `1.0.0` is cut.
- **Not the scope of 1.0.** What `1.0.0` claims is decided in
  [`0002`](0002-extension-seam-closed-for-1-0.md) and
  [`0003`](0003-mobile-in-1-0-scope.md), not here.
- **Not a support policy.** Whether issues get triaged on a schedule, and what
  response is promised, is an open question this record deliberately leaves open.
- **Not the fate of `jet_print_google_fonts`.** The optional font catalog
  add-on is a separate package with its own release question.
