# 0004 — What 1.0 must settle

**Status:** Accepted — 2026-10-10 (P3)

## Context

P3's exit criterion in [`../roadmap.md`](../roadmap.md) is "no open question
that would force a breaking change after 1.0". [`../api-friction.md`](../api-friction.md)
is the list of open questions: twenty-one places where the published surface
made a consumer's job harder, of which two (8 and 9) are fixed. Its own last
section says the P4 freeze review decides, for each entry, whether to fix it
before 1.0, accept and document it, or record it as a known cost. It does not
say which entries *must* be decided before the freeze and which can wait,
because nothing in the repository defines what counts as breaking.

That definition is not obvious for this library. The usual semver reading
covers the Dart surface: an export removed, a type or a signature changed, a
required parameter added. But what a host builds on `jet_print` is a printed
document. A report that rendered one way under `1.0.0` and another way under
`1.1.0`, with no code change on the host's side, has broken that host, even
though every call still compiles. Several entries on the list are exactly that
kind of fix:

- entry 7: `UPPER` and `LOWER` call Dart's locale-blind `toUpperCase` and
  `toLowerCase` (`src/expression/functions/string_functions.dart` → `_upper`,
  `_lower`), so a Turkish report prints "KISA VADELI". The fix changes the
  output of every existing report that uppercases an `i`;
- entry 11: `validate` is exported but no render path calls it
  (`JetReportEngine.render` never does). Making render validate changes what
  an existing host sees;
- entry 12: `RenderOptions.knownFields` defaults to null, and its dartdoc
  promises that leaving it null "renders such a binding empty, exactly as
  before". Turning `#ERROR` on by default changes output;
- entry 1: `JetNumber` wraps a `double`, so a column that should foot to zero
  prints `-0,00`. Any fix changes totals.

## Decision

**After `1.0.0`, three kinds of change need a major version:**

1. **A change to the Dart surface.** An export removed or renamed, a type or
   signature changed, a parameter made required: what semver already means.
2. **A change to the output of an existing report.** The text, layout or pixels
   of a page, what a PDF or PNG shows, and the diagnostics a render reports,
   for the same definition, data, fonts and platform. Fixing output that is
   plainly wrong is still a change to output.
3. **A change to a default.** What happens when a host does not pass a
   parameter is part of the contract, because most hosts never pass it.

Adding is not breaking: a new export, an optional parameter, a function, a
variable, or accepting something validation used to reject.

**So an `api-friction.md` entry whose fix would fall under any of the three is
decided before `1.0.0`**: fixed, or accepted permanently and documented as the
behaviour. As of this record that is eight entries:

| Entry | Why it cannot wait |
|---|---|
| 1 — money is a `double` | totals change (output) |
| 2 — `PageFurniture.columnHeader`, `.columnFooter`, `.background` draw nothing | removing them changes the surface; implementing them changes the output of reports that set them |
| 7 — `UPPER` / `LOWER` ignore the locale | output |
| 11 — render never calls `validate` | a default |
| 12 — an unknown field renders empty unless `knownFields` is passed | a default |
| 14 — `GroupLevel` has an `id` and a `name`, and `name` is also a key | merging or renaming them changes the surface and the schema |
| 19 — `JetReportPreview.onExportPdf` is a `VoidCallback` | its type |
| 20 — `RenderedReport.fonts` is public, its type `FontRegistry` is not exported | hiding or exporting it changes the surface |

Each gets its own issue, and P3 is met when all eight are closed, by a fix or
by a recorded acceptance. That replaces "no open question" with a list somebody
outside the project can check.

The other open entries are triaged in `api-friction.md` itself, one verdict
line each: **after 1.0, additive** (3, 4, 5 as a sort feature, 10, 13, 15, 16,
17), or **P3, a documentation or defect fix** (5 as documentation, 6, 18, 21).
Neither kind blocks the freeze.

## Consequences

The output of a report becomes part of the contract, which is what a host
printing invoices needs from a reporting library: an upgrade of `jet_print`
within `1.x` will not move a total, a line break or a capital letter. A Flutter
upgrade or a different operating system still can, since text shaping and
rasterization are not this package's to freeze.

The cost is that a wrong output cannot be quietly corrected after `1.0.0`.
"KISA VADELI" is a spelling error in the report's own language, and under this
rule it is fixed now or carried until `2.0.0`. That is the reason the eight
entries are worth doing before the freeze rather than after it, and it makes P3
larger than "documentation plus defect closure", which is how the roadmap
described it.

It also binds future fixes. A rendering bug found after `1.0.0` that changes
output has to ship behind an opt-in, such as a `RenderOptions` flag, or wait
for a major version. That is the price of the guarantee, stated here so it is
not discovered later.

Entries 3 and 4, a per-page carried subtotal and a group header carrying its
own group's total, are *not* on the list. Both add something that cannot be
expressed today, so neither blocks the freeze, however much an accounting
consumer wants them.

## What this does not decide

- **How any of the eight is fixed.** Entry 2 can be implemented or removed,
  entry 14 can merge the fields or document `name` as a unique key. Each issue
  decides its own entry.
- **The design of entries 1 to 4.** They need their own brainstorming; this
  record only says that 1 and 2 must be settled before the freeze and 3 and 4
  need not be.
- **Whether a stand-in consumer may satisfy P2.** That is still open, and
  belongs in a record of its own.
- **Pre-1.0 releases.** Until `1.0.0`, `0.x` minor versions may still break,
  as [`0001`](0001-publish-0-1-0-as-a-preview.md) says; the changelog lists
  each break.
