# ledger_pilot — the P2 embed pilot

A Turkish trial balance ("mizan") over a Tek Düzen Hesap Planı chart of
accounts, rendered and exported through `package:jet_print/jet_print.dart` and
nothing else. It is the pilot [`docs/roadmap.md`](../../docs/roadmap.md)'s P2
calls for, and its real output is not the report — it is the friction list in
[`docs/api-friction.md`](../../docs/api-friction.md).

## It is a stand-in, and that matters

P2 asks for one real report from a real product, embedded in that product. This
is not that. The product's own repository stays untouched, so the pilot lives
here, in the library's own workspace, and imitates the position an embedding
host would be in: its own package, its own `pubspec.yaml`, the public entry
point only, no test helpers, no `src/` imports, no privileged knowledge.

What that buys and what it does not:

- **It does find real API friction.** Every awkwardness recorded while building
  this is an awkwardness the public surface actually has. A missing export is
  missing whoever notices it; a total the engine cannot fold is one a host must
  fold whoever the host is. Those findings transfer whole.
- **It does not find friction that comes from a real codebase.** A first-party
  embed collides with things a stand-in never meets: an existing data layer
  whose types have to be adapted to `JetDataSource`, a dependency graph that
  already pins `intl` or a UI kit, an existing theme the preview has to sit
  inside, a build that has to stay green, a designer surfaced to end users. The
  pilot's data layer was written to suit the library, which is exactly the
  freedom a real embed does not have.
- **It does not weigh the findings.** A real embed tells you which friction is
  expensive, because the cost shows up as work somebody did not want to do.
  Here the author chose the report, so nothing pushes back. Treat the list as
  complete in kind and unweighted in severity.

So: the entries are evidence, and the absence of an entry is not. Read the
findings as a lower bound.

## Why a trial balance

Because it is the hardest thing the engine claims to do, in one page of
authoring.

A mizan groups a flat ledger by a hierarchical account code — TDHP codes nest
as `1` → `10` → `100` → `100.01` — subtotals at every level, and carries four
money columns (opening balance, period debit, period credit, closing balance)
that must foot both **across** (closing = opening + debit − credit, per row and
per subtotal) and **down** (the rows sum to the subtotal, the subtotals to the
class total, the class totals to the grand total). It runs to several pages, so
the column headings have to repeat, groups have to survive a page break, and a
subtotal has to land in the right place when its group straddles one.

If multi-level grouping, aggregates or pagination have weak spots, a report
shaped like this finds them. It also has an unusually strong correctness test:
the grand total of the opening and closing columns must read `0,00` and the
period debit and credit columns must be equal. A reader can check the engine's
arithmetic from the printed page.

## What is in here

| File | What it holds |
|---|---|
| `lib/chart_of_accounts.dart` | 68 posting accounts across 6 TDHP classes and 39 main accounts, with real codes and Turkish names |
| `lib/ledger_data.dart` | the schema in its three required shapes, and a deterministic generator that posts ~350 balanced journal entries over the chart |
| `lib/trial_balance_report.dart` | the `ReportDefinition`: page furniture, two group levels, detail band, summary |
| `lib/main.dart` | the app shell — one `JetReportPreview` in a `ShadApp`, with a PDF export action |

The data is synthetic but internally consistent, and the invariants are stated
at the top of `ledger_data.dart` rather than assumed: every movement is a
balanced journal entry, opening balances net to zero with retained earnings as
the balancing figure, income-statement accounts open at zero, and the closing
balance is derived rather than stored. The same seed always produces the same
figures, so a rendered page can be compared across runs and platforms.

Amounts are held internally in quarter-lira and divided by four. That is not an
accounting convention — it is a concession to the engine, which folds in
`double`. See the note at the top of `ledger_data.dart`.

## Running it

The pilot is a workspace member, so the repository's usual commands cover it:

```bash
flutter pub get                       # at the repository root
flutter analyze                       # covers apps/ledger_pilot/lib
```

It has no platform runner directories — no `macos/`, `windows/`, `linux/`,
`web/`, `ios/` or `android/`. Generate the one you want before running:

```bash
cd apps/ledger_pilot
flutter create --platforms=macos .
flutter run -d macos
```

`flutter create` rewrites `pubspec.yaml` on an existing project, so check that
`resolution: workspace` and the dependency block survived before committing
anything it produced.

## What this pilot does not prove

- **Not the published install path.** P2's brief wants the pilot to consume
  what P1 publishes. P1 has not published yet, so `pubspec.yaml` declares a
  bare `jet_print:` and resolves the workspace member against the root
  lockfile. That is a different question from `flutter pub add jet_print`
  resolving against published constraints, and this pilot answers neither it
  nor the `intl` constraint that goes with it.
- **Not anything about the designer.** The pilot renders and exports; it never
  opens `JetReportDesigner`. A host that lets its users author reports has a
  second, larger surface to evaluate.
- **Not performance.** 68 rows is nothing. E2's stress work already covers
  volume.
- **Not the numbers themselves.** The chart and the movements are invented.
  They are plausible and they balance; they are not anybody's books.
