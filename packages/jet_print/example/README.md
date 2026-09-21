# jet_print example

The smallest useful consumer of [`jet_print`](../README.md): one screen, built
entirely against the package's single public entry point,
`package:jet_print/jet_print.dart`.

`lib/main.dart` does four things, in that order:

1. **Builds a `ReportDefinition` in code** — a `title` band with the heading and
   column captions, one `detail` band repeated per row, a `summary` band
   carrying the grand total, and a page-number band in
   `PageFurniture.pageFooter`. Roles are structural: a band is a page footer
   because of the slot it sits in, not because of its `type`.
2. **Binds a handful of literal rows** through `JetInMemoryDataSource`. The
   bound elements carry `$F{...}` expressions; the total is a `ReportVariable`
   folded with `JetCalculation.sum` and read back as `$V{grandTotal}`.
3. **Renders and previews** — `JetReportEngine().renderDefinition(...)` returns
   a `RenderedReport`, which `JetReportPreview` displays page by page.
4. **Exports a PDF** — the preview's export action calls
   `JetReportExporter().toPdf(report)`, which returns bytes. The library never
   touches the filesystem; this example passes the bytes to the platform's
   share/save sheet.

Two things the example is deliberate about. It calls `validate()` on its own
definition in an `assert`, because nothing on the render path validates a
definition built in code. And it wraps everything in a `ShadApp` with
`JetPrintLocalizations.delegate` wired in, because jet_print's widgets are
shadcn_ui-themed and localize their own chrome.

## Running it

From a checkout of the repository, the workspace root resolves the example
along with everything else:

```bash
flutter pub get                      # at the repository root
cd packages/jet_print/example
flutter create .                     # once: adds the platform runner you need
flutter run -d macos                 # or windows, linux, chrome, ...
```

The example ships no platform runner directories — `flutter create .` generates
the one your target needs and leaves `lib/` and `pubspec.yaml` alone.

Working from the published archive rather than a checkout? Delete the
`resolution: workspace` line from `pubspec.yaml` first — it is there so the
repository's single root `pub get` resolves the example, and it means nothing
outside that workspace. `flutter pub get` here then resolves `jet_print`
through `path: ../`.
