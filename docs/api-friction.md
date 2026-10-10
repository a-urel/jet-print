# Public API friction

Places where the published surface made a consumer's job harder than it needed
to be. Each entry is a concrete thing someone had to work around while building
against `package:jet_print/jet_print.dart` alone — no `src/` imports, no
internal test helpers.

This list exists because [`decisions/0001`](decisions/0001-publish-0-1-0-as-a-preview.md)
chose to publish a preview precisely so the API would be used from outside
before it is frozen. It is the main input to the P4 freeze review in
[`roadmap.md`](roadmap.md): an export that survives 1.0 only because nobody has
tried to use it is not a considered decision. Nothing here is a commitment to
change anything.

## Where these came from

Two consumers, both written on 2026-09-21 inside this repository against the
barrel alone, and neither merged — both survive on the branch
`docs/p0-decisions` at `ca73f81`:

- a minimal example app over five lines of literal data. `main` has since
  gained its own, different `example/` in `e901735`;
- a stand-in pilot: a Turkish trial balance over 68 accounts and 352 balanced
  journal entries, running to four or five pages. It was never compiled.

Neither is a stranger to the codebase, and neither is a real product. A
consumer written by someone who has just read the source cannot report the
friction of not knowing where to look, and synthetic data takes the shape the
engine already handles. This list is a floor on the friction a real embed would
find, not a measure of it.

Worth stating before the complaints, because it is the more surprising result:
**the pilot precomputes no total in Dart.** Multi-level grouping, two levels of
aggregate, group keys derived with `SUBSTRING` off the account code,
`keepTogether`, header reprinting and lazy pagination all carried the hardest
report available to give them. The findings below are at the edges. The core
held.

## Blocking for an accounting consumer

1. **Money is a `double`, so a trial balance does not foot to zero.**
   `JetNumber` wraps a `double` and every accumulator folds in double
   arithmetic. A balance whose columns ought to sum to exactly zero comes out
   around `-6e-8`, and `#,##0.00` renders that as `-0,00` in the grand total —
   the first cell any accountant looks at. The pilot only avoids it by holding
   every amount as a whole number of quarter-lira, because quarters are exact
   in binary; real books cannot choose their own amounts. A decimal-backed
   value, or at minimum a documented rounding policy on aggregates, removes it.
   *`src/expression/value.dart` → `JetNumber`;
   `src/expression/aggregate/variable_accumulator.dart`.*

   **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *before 1.0*,
   [#95](https://github.com/a-urel/jet-print/issues/95). Any fix changes totals,
   so it is output. The design needs its own brainstorm.

2. **`PageFurniture.columnHeader` is public, exported, and draws nothing.**
   Repeating column captions on every page is the defining requirement of a
   tabular multi-page report. The slot exists, `BandType.columnHeader` and
   `columnFooter` exist, both are exported — and the layouter does not lay them
   out; each one present records an *info* diagnostic.
   [`03-pagination.md`](03-pagination.md) says so in one clause. The only
   working route is `pageHeader`, which is record-blind, so the captions can
   never be data-driven. A consumer discovers this at render time by going
   looking for a diagnostic, rather than from a compile error or a dartdoc.
   *`src/domain/report_definition.dart` → `PageFurniture.columnHeader`,
   `.columnFooter`, `.background`; `src/rendering/layout/report_layouter.dart`.*

   **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *before 1.0*,
   [#96](https://github.com/a-urel/jet-print/issues/96). Removing the slots
   changes the surface; implementing them changes the output of reports that set
   them.

3. **A per-page subtotal cannot be expressed.** A Turkish mizan running to
   several pages carries *nakli yekûn* — carried forward at the foot of each
   page, brought forward at the head of the next. Page chrome is evaluated
   against a context whose field resolution always returns null and whose
   variables are only `PAGE_NUMBER` and `PAGE_COUNT`; report variables are not
   visible to chrome; and `columnFooter` is the slot that would carry it (see
   entry 2). The pilot dropped the requirement rather than fake it.
   *`src/rendering/layout/page_eval_context.dart`;
   `src/rendering/fill/page_variables.dart` → `kPageScopedVariables`.*

   **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *after 1.0,
   additive*. A carried total is something chrome cannot express today. How it
   is carried depends on how entry 2 is settled.

4. **A group header cannot carry its own group's total.** Validation makes a
   top-level aggregate in a group header an error, and aggregate expansion
   rewrites only the summary band and root group footers. So the most common
   trial-balance layout — the main-account line showing its four totals with
   sub-accounts indented beneath — is not expressible; totals must follow the
   detail, not head it.
   *`src/domain/report_validation.dart` → `aggregateBand(g.header, supported:
   false)`; `src/expression/aggregate/aggregate_synthesizer.dart` →
   `expandAggregates`.*

   **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *after 1.0,
   additive*. Validation rejects an aggregate in a group header today, and
   0004's output promise covers only definitions `validate` accepts, so allowing
   it later changes no covered output.

## Wrong output rather than an error

5. **There is no sort, and an unsorted source fails silently.** A group level
   breaks when its key differs from the previous row's, so a ledger not already
   ordered by account code prints the same class heading five times, with no
   diagnostic anywhere. Nothing in `ReportDefinition` can express an ordering.
   "Group by X implies already sorted by X" is a defensible design for a report
   engine; it is undocumented in the public dartdoc, and its failure mode is a
   plausible-looking wrong report.
   *`src/domain/group_level.dart` → `GroupLevel.key`;
   `src/rendering/fill/report_filler.dart`.*

   **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *P3,
   documentation*: the `GroupLevel` dartdoc should say that the source must
   already be ordered by the key. A sort is *after 1.0, additive*. A diagnostic
   for a repeated key would change what a render reports, so if one is wanted it
   lands in P3 too.

6. **`validate()` warns about the natural way to write a derived total.**
   `SUM($F{borc}) - SUM($F{alacak})` in a summary band draws two
   record-blind-field warnings. They are wrong: those are aggregate operands,
   and the synthesizer folds them correctly. The exemption fires only when the
   aggregate is the *whole* expression, while the synthesizer explicitly
   supports an aggregate nested inside surrounding arithmetic — two parts of the
   library disagree about the same string. The workaround is non-obvious
   (rewrite as one aggregate over a compound operand). A host that follows
   entry 11 and asserts on `validate()` must filter or special-case these.
   The pilot keeps the natural form in one cell so the evidence survives.
   *`src/domain/report_validation.dart` → `_recordFieldRefs`;
   `src/expression/aggregate/aggregate_synthesizer.dart` →
   `_expandInlineAggregates`.*

   **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *P3, defect
   fix*. It removes a false warning from `validate`; no render changes. If entry
   11 is settled by making render validate, this has to be fixed first: the
   warnings would then be render diagnostics, and removing them after 1.0 would
   change output.

7. **`UPPER` and `LOWER` were locale-blind, and wrong in Turkish.** *Fixed*
   in [#97](https://github.com/a-urel/jet-print/issues/97), by following the
   render locale. They used Dart's `toUpperCase`/`toLowerCase`, which map
   `i`→`I` and `I`→`i`; Turkish needs `i`→`İ` and `I`→`ı`. `UPPER` on "Kısa
   Vadeli Yabancı Kaynaklar" yielded "KISA VADELI" — a spelling error in the
   report's own language. The engine already took a per-render locale that
   number formatting honoured; the case functions never saw it. They now case
   by `Intl.getCurrentLocale()`, which the engine scopes to
   `RenderOptions.locale` exactly as it does for `FORMAT`, so under `tr` or `az`
   the dotted and dotless `i` keep their dots and every other locale is
   unchanged. Settled before 1.0, as
   [`0004`](decisions/0004-what-1-0-must-settle.md) required, because it
   changes the output of every Turkish report that uppercases an `i`.
   `test/expression/functions/string_functions_test.dart` and
   `test/rendering/engine/render_locale_test.dart` pin it.
   *`src/expression/functions/string_functions.dart` → `_upper`, `_lower`.*

## Correctness of the published contract

8. **The README Quickstart did not compile.** *Fixed.* `TextElement` declares
   `required this.text` and the sample omitted it — a hard compile error in the
   first code a stranger reads. `e901735` fixed the sample, and
   `test/readme_snippets_test.dart` now requires every Dart block in the package
   README to be an excerpt of a file under `example/`, which the analyser
   compiles and the example tests run.

9. **`JetReportPreview` requires a `shadcn_ui` ancestor and says so nowhere.**
   *Fixed* in `158eefa`, by documentation. It calls `ShadTheme.of(context)`, so
   a host wrapping it in `MaterialApp` fails at runtime rather than at compile
   time. Both consumers had to take a direct dependency on a pre-1.0
   third-party UI package for the sole purpose of showing a read-only page
   viewer. The widget's dartdoc now has a *Host requirements* paragraph, and
   the README Quickstart shows the `ShadApp` wrapper from
   `example/jet_print_example.dart` and says that a `ShadTheme` inside a
   `MaterialApp` also works. `test/designer/preview/jet_report_preview_test.dart`,
   *host requirements*, pins both halves of that claim. The requirement itself
   stands: a host still depends on `shadcn_ui` to show the preview. Whether to
   lift it with a theme wrapper is a question for P4.

10. **A stored report cannot be operated over a database, though it can be
    saved and loaded.** `JetReportFormat` is exported and does the round trip;
    the playground uses it through the barrel and reaches into no internals. But
    the schema version constant was not exported (since `c4a7f8d` it is, as
    `JetReportFormat.schemaVersion`), and every decode failure
    arrives as one exception type carrying one English string — so a consumer
    cannot tell "written by a newer build" from "corrupt row" except by
    substring-matching a sentence. (Malformed documents raising `TypeError` or
    `FormatException` instead of that type was a third gap; `7535890` closed it,
    for #60.) [`serialization-gap.md`](serialization-gap.md) has the full
    analysis and judges it a P3 item rather than a freeze blocker.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *after 1.0,
    additive*. Distinguishable failures can be subtypes of
    `ReportFormatException`, which existing `catch` clauses still catch.

11. **`validate()` is opt-in, and the render path never calls it.** A host that
    builds a definition in code ships a mis-slotted band silently. There is also
    a `hasErrors` helper on the render-time diagnostics carrier and none on the
    author-time one, so both consumers hand-rolled the same severity predicate
    for the author-time half of an identical question.
    *`src/rendering/fill/report_diagnostics.dart` → `ReportDiagnostics.hasErrors`;
    `src/domain/report_validation.dart` → `validate`.*

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *before 1.0*,
    [#98](https://github.com/a-urel/jet-print/issues/98). Whether render
    validates is a default. A `hasErrors` on the author-time diagnostics is
    additive.

12. **One schema, three incompatible spellings.** A consumer needs
    `List<FieldDef>` for the in-memory data source, a `JetDataSchema` for
    `validate`, and a `Set<String>` for `RenderOptions.knownFields`. The data
    source exposes the first; there is no conversion to either of the others, so
    the host writes both. The minimal consumer needed two of the three; the
    pilot needed all three at once. Without the wiring, a mistyped field name
    renders empty instead of `#ERROR` — the silent option is the default.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *before 1.0*,
    [#99](https://github.com/a-urel/jet-print/issues/99). Whether an unknown
    field renders `#ERROR` without `knownFields` is a default. Conversions
    between the three spellings are additive.

## Ergonomics

13. **A group key has no label reachable from an expression.** `GroupLevel.name`
    is display-only and no expression can read it; a header or footer can only
    read fields off a row. To print "3 — Kısa Vadeli Yabancı Kaynaklar" the host
    must denormalise the class and account names onto all 68 rows, where they
    repeat a 6-entry and a 39-entry lookup.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *after 1.0,
    additive*. A new variable or function.

14. **`GroupLevel` has both an `id` and a `name`, and which one is the reference
    depends where you stand.** The dartdoc says `name` is "display label only (no
    longer the reference key)", but the filler keys header and footer bands by
    name, the aggregate synthesizer writes names into the variables it
    synthesises, and a private translation step bridges the two. It works. The
    consequence — group names must be unique, and `name` is not decorative — is
    nowhere in the public documentation. Both consumers set `id == name` to stay
    out of it, which is also what the playground's own sample does. Since
    `7b989f0`, `validate` rejects a `resetGroup` that matches one group's id and
    another's name — the ambiguity is now caught, but still not explained.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *before 1.0*,
    [#100](https://github.com/a-urel/jet-print/issues/100). Merging or renaming
    the fields changes the surface and the schema; the alternative is to
    document `name` as a unique key and accept it.

15. **`text` is required even when `expression` is non-null.** Thirty of the
    pilot's thirty-six text elements carry both; every placeholder is discarded
    by every render. The house idiom is to repeat the field name, which reads as
    duplication to anyone who has not been told why.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *after 1.0,
    additive*. Dropping `required` from a parameter that gains a default breaks
    no caller.

16. **The smallest report is five nested constructors.** `ReportDefinition` →
    `ReportBody` → `DetailScope` → `BandNode` → `Band`, by hand, before a single
    element. `test/support/report_builders.dart` has exactly the helper a
    consumer wants and it is not public.
    [`01-smallest-report.md`](01-smallest-report.md) names this cost from the
    inside; it lands harder from outside.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *after 1.0,
    additive*. A public builder is a new export.

17. **`$V{PAGE_NUMBER}` and `$V{PAGE_COUNT}` are magic strings.** Documented in
    prose, no exported constants, no helper for the "Page N of M" footer nearly
    every report wants — both consumers spelled the concatenation by hand. They
    are also legal only in page and column header/footer bands, a rule enforced
    at fill time by a diagnostic rather than by any type.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *after 1.0,
    additive*. Constants and a page-footer helper are new exports; the band rule
    stays as it is.

18. **A format pattern and the locale that interprets it live in different
    files, with no cross-reference.** `TextElement.format` says "an ICU
    number/date pattern" and does not say the grouping and decimal symbols come
    from `RenderOptions.locale`. `#,##0.00` reads as comma-thousands and renders
    as dot-thousands under `tr` — correct, and surprising. No exported money
    pattern, so the string is repeated as a private constant in every consumer.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *P3,
    documentation*.

19. **`onExportPdf` is a `VoidCallback` while `toPdf` is async.** The assignment
    compiles silently because `void` is a top type, so there is no diagnostic at
    all: no progress state to drive, nowhere for the widget to catch a failure.
    The workspace variant at least receives the report; the preview's receives
    nothing, so the callback must close over it.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *before 1.0*,
    [#101](https://github.com/a-urel/jet-print/issues/101). Changing the
    callback's type changes the surface.

20. **`RenderedReport.fonts` was public but its type is not exported.**
    *Fixed* in [#102](https://github.com/a-urel/jet-print/issues/102), by
    hiding it. `FontRegistry` describes itself as internal, so a consumer could
    not name the type of a field on a public class, yet could call every member
    of it through the field. The field is now private and the constructor no
    longer takes a registry; the engine, preview, exporter and printer reach it
    through `fontsOf` and `renderedReportWithFonts`, which the barrel does not
    export. `test/public_api_test.dart` pins the field's absence, and
    `test/architecture/exported_member_type_test.dart` stops any public member
    of an exported type from exposing an unexported one without a written
    reason — which is how entry 22 was found.
    *`src/rendering/engine/rendered_report.dart` → `fontsOf`.*

## Documentation

21. **Nothing public says where an aggregate may go.** The five recipes in
    [`README.md`](README.md) cover neither grouping nor subtotals nor
    aggregates; the only guidance is one section of
    [`02-binding-data.md`](02-binding-data.md), written from inside the engine
    and naming private files. The two facts the pilot actually needed — that an
    aggregate nested inside arithmetic still lifts, and that an aggregate over a
    compound operand is a legal single-argument aggregate — are stated nowhere a
    consumer can reach. Both had to be read out of the synthesizer.

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *P3,
    documentation*.

## Found since

Entries found after the two consumers, by a test rather than by building
against the barrel.

22. **`RenderedPage.frame` and `JetReportDesignerController.activeGuides`
    expose unexported types.** The guard added for entry 20 found both on its
    first run. `frame` is a `PageFrame`, the display list every painter and
    exporter reads; neither it nor its primitives are exported, yet
    `pageAt(i).frame.primitives` is walkable today, and the playground's
    rendered-example tests walk it, with a `src/` import for the primitive
    types. `activeGuides` is a `List<SnapGuide>`, the snap guides the canvas
    overlay draws mid-drag. Both are allowlisted in the guard until this is
    decided.
    *`src/rendering/engine/rendered_report.dart` → `RenderedPage.frame`;
    `src/designer/controller/jet_report_designer_controller.dart` →
    `activeGuides`.*

    **Triage** ([`0004`](decisions/0004-what-1-0-must-settle.md)): *before 1.0*,
    [#105](https://github.com/a-urel/jet-print/issues/105). Exporting the types
    commits to their API, and hiding the members changes the surface, so it is
    entry 20's question again.

## How to use this list

Bring it to P4. For each entry the freeze review decides one of three things:
fix it before 1.0, accept it and document it, or record it as a known cost with
the version that would address it. An entry that is neither fixed nor
deliberately accepted is the thing 1.0 is supposed to stop happening.

Entries 1 to 4 deserve deciding earlier than that. They are not ergonomics —
they are an accounting library that cannot foot a column to zero, two public
slots that draw nothing, and a layout every trial balance in the country uses.
None of them is a small change, and all of them are cheaper before a semver
promise than after.

Since [`decisions/0004`](decisions/0004-what-1-0-must-settle.md), each open
entry carries a **Triage** line saying when it has to be decided. *Before 1.0*
means a fix after the freeze would change the Dart surface, the output of an
existing report, or a default, and so would need a major version; P3 is met
when every such entry is fixed or deliberately accepted. *After 1.0, additive*
means the fix only adds something. *P3, documentation* or *defect fix* means it
is small enough to close now and blocks nothing. Of entries 1 to 4, only 1 and
2 block the freeze: 3 and 4 add what cannot be expressed today, however soon an
accounting consumer wants them.
