# 0006 — P2 runs against a stand-in consumer

**Status:** Accepted — 2026-09-21 — phase P2

## Context

P2 exists because of [`0001`](0001-publish-0-1-0-as-a-preview.md). That record
published `0.1.0` as a preview for one reason above the others — to get the
public surface in front of a consumer while changing it is still free:

> **It produces a real install path.** Everything the package currently proves
> about itself it proves to itself.

and

> A bug report against `0.1.0` can be fixed by changing the API. The same report
> against `1.0.0` cannot.

[`../roadmap.md`](../roadmap.md), *Current plan*, turned that into a phase and
gave it an exit criterion phrased from outside the project: one real Monepro
report rendered and exported from the published package, plus a written friction
list — "with no path dependency and no reaching into `lib/src/`". The embed has
been a named target far longer than the phase has existed. The June assessment
quoted at the head of the roadmap was reached against three intended consumers
at once, "a published pub.dev package, a module embedded in our own app, and a
standalone designer product", and of those three the embed is the only one with
no epic attached to it: E1 to E8 cover release hygiene, scale, platforms, the
1.0 freeze and the designer product, and none of them covers embedding the
library in the application it was written for. P2 is the first and only place
that work was ever scheduled.

Two of the three things the criterion names are no longer available to this
phase.

**The product repository stays out of scope.** The decision is the maintainer's:
no change lands in Monepro's repository during the run to 1.0. An embed pilot is
by construction a change to the host product, so the phase as written cannot be
started at all, let alone finished.

**The package is not published.** *Where this stands*, in
[`../release-checklist.md`](../release-checklist.md), records the state
precisely: every file change on the P1 list has been written on the branch
`docs/p0-decisions`, and **none of it has been compiled, analysed, formatted or
tested**, because no Dart or Flutter toolchain was reachable from the sessions
that wrote it. `packages/jet_print/pubspec.yaml` still reads `version: 0.1.0`,
and that version is not on pub.dev. There is no
archive for a consumer to resolve, so the only dependency form available to a
pilot today is a path.

A pilot is still worth running. The method already works at small scale: nine
concrete items in [`../api-friction.md`](../api-friction.md) came out of
building `packages/jet_print/example/` against the barrel alone, including a
README Quickstart that did not compile. Waiting for the embed means waiting on
two conditions this phase does not control, and arriving at the 1.0 freeze with
the surface exercised only by the tests that were written to pass.

## Decision

P2 runs against a **stand-in consumer built inside this repository**:
`apps/ledger_pilot/`, a Turkish trial balance over a synthetic chart of
accounts, consuming `jet_print` by path through the barrel
`package:jet_print/jet_print.dart`, with no imports from `lib/src/`. The
Monepro embed is not attempted in this phase.

The written friction list stays the deliverable that outlives the phase, and
entries from the pilot are marked with the consumer they came from, so a later
reader can weigh a stand-in's report differently from a product's.

The roadmap's P2 exit criterion is **amended** to what the stand-in can
satisfy, with the original criterion kept visible on the page as the thing that
was amended. A phase that quietly rewrites its own success condition is the
failure this directory exists to prevent, and it is not made acceptable by the
rewrite being reasonable.

## Consequences

**The substitution buys a consumer now.** It is not gated on the publish, and it
is not gated on the product repository opening. Whatever it does find about the
public API, it finds while the API can still change, which is the whole reason
0001 chose a preview.

**A path dependency does not exercise the published archive.** This is the
first cost and it is exact. `pub publish` ships what the archive contains, and
`packages/jet_print/.pubignore` — added on this branch and never once run
through a publish — decides that: it excludes `test/`, `tool/` and
`example/pubspec.lock`, and, because a `.pubignore` *replaces* rather than
extends the `.gitignore` beside it, anything it fails to list ships and anything
it over-lists disappears. A path-dependent consumer sees neither failure. Nor
can it catch an export that resolves only because the whole repository is on
disk, a `lib/` file that the archive drops, or a dependency constraint that is
satisfied by the workspace lockfile and by nothing a stranger would resolve.
**Recoverable**, and cheaply: `flutter pub publish --dry-run`, pana, and P1's
own exit criterion — `flutter pub add jet_print` working for a stranger — retire
these the day a toolchain is reachable. P2 simply does not retire them, and must
not be read as having done so.

**A consumer written inside the repository by someone who has just read the
source is not a stranger.** A real proportion of API friction is not knowing
where to look: which of the barrel's hundred-odd public names is the entry
point, what the README does not say, which dartdoc is wrong. The pilot's author
has the source, the wiki and the tests in front of them, so that signal cannot
be produced here at all. **Lost for good** for this consumer. A first encounter
with a surface happens once and cannot be re-run by the same person later; only
a different consumer recovers it. The partial mitigation is procedural — work
from the barrel, the README and the dartdoc, and record every occasion where
the author had to open `lib/src/` to proceed — and it is a proxy, not the
thing.

**Synthetic data is chosen by the person writing the report.** A trial balance
invented for this pilot will tend to have the shape the engine already handles:
the columns that bind cleanly, the grouping the band model already expresses,
the numbers that format without an argument. Real data does not negotiate — it
arrives with the wrong types, the missing periods and the account codes that do
not sort. **Recoverable in substance, not in this phase's evidence.** Real data
can be put through the engine later and will produce its findings then; what
cannot be recovered is confidence in *this* friction list's completeness, since
the selection bias is invisible from inside the phase that has it. Treat the
list as a floor on the friction, never as a measure of it.

**The report is not driven by a product's constraints.** No tenant model, no
existing data layer whose shape the report must accept, no deadline, and nobody
who will complain when the output is wrong. Those constraints are most of what
makes an embed informative: they are what turns "the API could do this" into
"the API had to do this, by Thursday, against data it did not choose".
**Lost for this phase**, and recoverable only by the embed itself — no amount of
further work on a stand-in reproduces a caller who cannot be argued with.

**The friction list's provenance becomes heterogeneous**, and the file already
says otherwise: `api-friction.md` states that the Monepro embed "will carry more
weight, because it is a real product rather than a demonstration". That sentence
describes a source this phase will not have. Correcting it belongs to whoever
owns that file in P3; this record is the reason it needs correcting.

**P4 inherits a weaker input than the plan assumed.** The freeze review was to
be fed by a real product's use of the surface. It will instead be fed by an
example and a stand-in, and the honest move at the freeze is to say so on the
page rather than let "P2 complete" stand in for "the API met the world".

## What this does not decide

- **Not the cancellation of the first-party embed.** It is deferred, not
  dropped, and it re-opens on any of three events: `0.1.0` reaching pub.dev and
  P1's exit criterion being met, which removes the publish half of the
  obstruction; the product repository coming back into scope, which removes the
  other half; or P4 reaching the freeze with the embed still unattempted, at
  which point the choice between gating the freeze on a real consumer and
  narrowing what 1.0 claims is a decision to be taken in the open, as
  [`0003`](0003-mobile-in-1-0-scope.md) takes the equivalent one for the mobile
  claim.
- **Not P1's exit criterion.** It stands exactly as written. A path-dependent
  pilot is not a stranger running `flutter pub add`, and nothing here lets P2's
  completion count towards P1's.
- **Not a licence to amend other criteria.** This amendment is recorded, linked
  and keeps the original text visible. Any other phase whose criterion stops
  matching reality gets the same treatment or none.
- **Not what P3 must act on.** The pilot's friction list is evidence; which
  entries become changes before the freeze remains P3's call, and a stand-in's
  entry does not automatically earn one.
- **Not the pilot's fate after P2.** Whether `apps/ledger_pilot/` stays in the
  tree, is folded into `packages/jet_print/example/`, or is deleted once its
  findings are written down, is left open.
