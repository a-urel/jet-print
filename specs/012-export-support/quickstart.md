# Quickstart: Export Support (012)

Everything below uses **only** `package:jet_print/jet_print.dart` (Constitution I). It
extends the 011 rendered-invoice example — the report is rendered **once** and the same
`RenderedReport` feeds the preview, the PDF, the images, and the printer (FR-001).

## You already have this (011)

```dart
final RenderedReport report = const JetReportEngine().render(
  invoiceSampleTemplate(),
  invoiceDataSource(),
  options: const RenderOptions(locale: Locale('en')),
);
// Widget: JetReportPreview(report: report)
```

## Export a PDF — the whole document as bytes (US1)

```dart
final Uint8List pdf = await const JetReportExporter().toPdf(report);
// The library is headless: YOU own the bytes. Save, attach, share:
await File(path).writeAsBytes(pdf);   // host code, e.g. via file_selector
```

Real, selectable text; fonts embedded; pages match the preview page-for-page; identical
inputs produce byte-identical files.

## Export page images — PNG at a chosen scale (US2)

```dart
final Uint8List thumb = await const JetReportExporter().pageToPng(report, 0);
final Uint8List crisp = await const JetReportExporter().pageToPng(report, 0, scale: 2);
// All pages, in order:
for (var i = 0; i < report.pageCount; i++) {
  pages.add(await const JetReportExporter().pageToPng(report, i));
}
```

A `scale: 2` image has exactly twice the page's pixel dimensions. An out-of-range page
index throws a `RangeError` — no silent empty image.

## Print — the system dialog in one call (US3)

```dart
final bool sent = await const JetReportPrinter().printReport(report);
// sent == false ⇒ the user cancelled the dialog (not an error).
// PrintUnavailableException ⇒ this platform cannot print (structured, no crash).
```

The one sanctioned exception to headlessness: the library presents the OS print dialog
itself, at the template's true page size.

## Preview with built-in export/print actions (US4)

```dart
JetReportPreview(
  report: report,
  onExportPdf: () async => host.savePdf(await const JetReportExporter().toPdf(report)),
  onPrint: () => const JetReportPrinter().printReport(report),
)
```

Supply a callback and its toolbar action appears (localized en/de/tr, keyboard-operable);
omit it and the preview is exactly the 011 widget. The playground's
`rendered_invoice_example.dart` wires both end-to-end (save via `file_selector`, print via
`JetReportPrinter`) — run `flutter run` in `apps/jet_print_playground` and use the preview
toolbar.

**Line budget check (SC-001)**: producing a saveable PDF beyond the 011 example is the two
`JetReportExporter` lines above — well under 10.
