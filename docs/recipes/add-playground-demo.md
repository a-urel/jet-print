# Add a playground demo

Two files, one registration in two parallel lists, and the one assertion that catches a report which renders and is still wrong.

The playground is a strict consumer: `AGENTS.md`'s public-API rule governs every
line you write here, and names the test that enforces it. What a demo is
demonstrating is the spine, starting at [page 01](../01-smallest-report.md). This
page is the sequence.

## The sequence

1. **`apps/jet_print_playground/lib/<name>_sample.dart`** — the
   `ReportDefinition` and the `JetDataSchema` describing the shape it binds
   against. One import, `package:jet_print/jet_print.dart`. If something you need
   is not exported, that is a finding about the public API, not a licence to
   reach into `src/`.
2. **`lib/rendered_<name>_example.dart`** — the sample rows as a `const` list, a
   `JetDataSource` over them, and a function that renders the definition through
   `JetReportEngine.renderDefinition`. Give the render function optional
   `definition`, `source` and `fonts` parameters defaulting to the bundled
   sample, as the existing examples do: that is what lets the designer tab
   preview a *live* edit rather than the committed definition. Keep the rows in
   one `const` so the demo and its tests read the same numbers.
3. **Register it in `lib/main.dart`** — and in two places. The `_demoBodies`
   record list built in `initState` carries the stable key, the icon and the
   body; the `labels` list built in `build` carries the caption. They are zipped
   **by index**, and nothing links them, so an entry added to one and not the
   other silently renames every demo after it. The caption may be a literal, or
   a key in the app's own ARB set under `lib/l10n/` — the playground has its own
   `l10n.yaml`, so that is the same procedure as
   [`add-localized-string.md`](add-localized-string.md) with `flutter gen-l10n`
   run from `apps/jet_print_playground` instead. Both patterns are in use.
4. **Assert `validate()` is empty.** In
   `test/<name>_definition_test.dart`, beside its neighbours:

   ```dart
   expect(validate(<name>Definition()), isEmpty);
   ```

   Do not skip this because the demo looks right. `JetReportEngine` never calls
   `validate`; the designer surfaces it as diagnostics, but a sample authored in
   Dart and rendered headlessly passes nowhere near that. A definition can be
   structurally wrong, render without complaint, and be wrong on paper — a
   heading band sitting in a per-row slot reprinted itself once per row here,
   through a rendering path that reported nothing, and in one demo the fixture
   had a single master row so even the output looked correct.

5. **Add a rendered-example test** — `test/rendered_<name>_example_test.dart` —
   asserting on page count and on text the definition should have produced.
   Choose the sample values with [`../testing.md`](../testing.md)'s note on
   fixtures that force divergence in front of you.
6. **`CHANGELOG.md`** if the demo ships with a library change. A demo alone is
   not user-visible library behaviour.

## Where the enforcement actually lives

The test that catches an `src/` import in your new sample scans the app's `lib/`
but *lives in the library package*. So `flutter test apps/jet_print_playground`
will not catch it, and neither will analyzing the app. Run both packages, which
is what the gate in `AGENTS.md` does.

## Verify

```bash
flutter test apps/jet_print_playground
flutter test packages/jet_print/test/encapsulation_test.dart
```

Then the full gate from the repository root. A new demo adds no golden of its
own, but registering one changes the nav list — if a designer golden moves, that
is why, and [`update-goldens.md`](update-goldens.md) is the procedure.

## Next

[`add-element-type.md`](add-element-type.md) if the demo wants something the
library cannot draw yet. [Page 02](../02-binding-data.md) for the master/detail
shapes a schema can describe, and where an aggregate folds.
