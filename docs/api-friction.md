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

Entries so far come from building `packages/jet_print/example/`. P2's Monépro
embed is the next source and will carry more weight, because it is a real
product rather than a demonstration.

## Correctness

1. **The README Quickstart did not compile.** `TextElement` declares `required
   this.text`, and the sample omitted it — a hard compile error in the first
   code a stranger reads. Fixed on this branch; recorded because it survived
   every documentation pass this repository has run, which suggests the samples
   are not compiled by anything.

2. **`JetReportPreview` requires a `shadcn_ui` ancestor and does not say so.**
   `jet_report_preview.dart` calls `ShadTheme.of(context)`, so a host that
   wraps it in `MaterialApp` fails at runtime, not at compile time. The widget's
   own dartdoc is silent; the README mentions the `ShadApp` shell for
   `JetReportDesigner` only. A consumer must take a direct dependency on a
   pre-1.0 third-party package to show a preview. Either a `JetPrintTheme`
   wrapper or a line of dartdoc would close it.

3. **`validate()` is opt-in, and the render path never calls it.** A host that
   builds a definition in code ships a mis-slotted band silently. There is no
   exported `hasErrors` convenience or severity filter, so the example spends an
   `assert` plus its own predicate doing what the designer gets for free.

4. **`knownFields` does not connect to a data source.** `JetInMemoryDataSource`
   infers a schema and exposes `fields` as `List<FieldDef>`; `RenderOptions`
   wants a `Set<String>`. Without wiring them by hand a mistyped field name
   renders empty rather than `#ERROR` — the silent option is the default one.

## Ergonomics

5. **`text` is required even when `expression` is non-null.** Every bound
   element carries a placeholder the render discards. The house idiom is to
   repeat the field name, which reads as duplication to anyone who has not been
   told why.

6. **The smallest report is five nested constructors.** `ReportDefinition` →
   `ReportBody` → `DetailScope` → `BandNode` → `Band`, by hand, before a single
   element. `test/support/report_builders.dart` has exactly the helper a
   consumer wants — `oneBandReport` — and it is not public. A
   `ReportDefinition.singleBand(...)` factory would roughly halve the example's
   definition. [`01-smallest-report.md`](01-smallest-report.md) already names
   this cost from the inside; it lands harder from outside.

7. **`$V{PAGE_NUMBER}` and `$V{PAGE_COUNT}` are magic strings.** Documented in
   prose, with no exported constants and no helper for the "Page N of M" footer
   that nearly every report wants. They are also legal only in page and column
   header/footer bands — a rule enforced at fill time, by a diagnostic, rather
   than by any type.

8. **`JetReportPreview.onExportPdf` is a bare `VoidCallback` while `toPdf` is
   async.** The host passes a `Future<void> Function()` into a `void Function()`
   slot: no way to show progress, and a failure becomes an unhandled async
   error. `JetReportWorkspace.onExportPdf` at least receives the report;
   the preview's receives nothing, so the callback must close over it.

9. **`RenderedReport.fonts` is public but its type is not exported.**
   `FontRegistry` describes itself as internal, so a consumer cannot name the
   type of a field on a public class.

## How to use this list

Bring it to P4. For each entry the freeze review decides one of three things:
fix it before 1.0, accept it and document it, or record it as a known cost with
the version that would address it. An entry that is neither fixed nor
deliberately accepted is the thing 1.0 is supposed to stop happening.
