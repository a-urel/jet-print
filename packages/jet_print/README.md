# jet_print

A layered, theme-aware Flutter library for building **WYSIWYG report designers**.
Design a report as a reified, id'd section tree; fill it with your data; preview,
paginate, export to PDF/PNG, and print — all from a single public entry point.

```dart
import 'package:jet_print/jet_print.dart';
```

## Features

- **Reified report model** — `ReportDefinition` (page furniture + body), bands,
  groups, and nested/recursive detail scopes; author-time `validate()` returns
  structured `Diagnostic`s.
- **Render engine** — `JetReportEngine` fills a definition with a `JetDataSource`
  (in-memory / JSON / object-backed), paginates lazily, and surfaces render
  diagnostics.
- **Export & print** — `JetReportExporter` produces deterministic PDFs (real
  selectable text, embedded fonts) and PNGs; `JetReportPrinter` presents the
  system print dialog behind an injectable presenter seam.
- **Interactive designer** — `JetReportDesigner` / `JetReportWorkspace`: select,
  move, resize, align, undo/redo, zoom, rulers, grid-snap, clipboard.
- **Rich elements** — text with fx expressions, shapes, images, and 10 barcode/QR
  symbologies; multi-column label layouts.
- **Localized chrome** — ships en/de/tr via `JetPrintLocalizations`.

## Quickstart — render and export a report

```dart
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:jet_print/jet_print.dart';

// 1. Describe a report (or build one in the designer and serialize it).
const ReportDefinition definition = ReportDefinition(
  name: 'Greeting',
  page: PageFormat.a4Portrait,
  body: ReportBody(
    root: DetailScope(
      id: 'root',
      children: <ScopeNode>[
        BandNode(Band(
          id: 'detail',
          type: BandType.detail,
          height: 40,
          elements: <ReportElement>[
            TextElement(
              id: 't1',
              bounds: JetRect(x: 0, y: 0, width: 200, height: 24),
              expression: r'"Hello, " + $F{name} + "!"',
            ),
          ],
        )),
      ],
    ),
  ),
);

Future<void> main() async {
  // 2. Fill it with data.
  final RenderedReport report = const JetReportEngine().renderDefinition(
    definition,
    JetInMemoryDataSource(const <Map<String, Object?>>[
      <String, Object?>{'name': 'Ada'},
    ]),
  );

  // 3. Export — headless: you own the bytes.
  final Uint8List pdf = await const JetReportExporter().toPdf(report);
  final Uint8List png = await const JetReportExporter().pageToPng(report, 0);

  // 4. Or preview it in a widget: JetReportPreview(report: report)
  // 5. Or print it: await const JetReportPrinter().printReport(report);
}
```

## Designer widget

```dart
// Inside a ShadApp / ShadTheme shell:
const JetReportDesigner();
```

## Platform support

The core is pure Dart — the domain, data, expression, render, and export layers
carry no `dart:ui` or platform dependency — so `jet_print` runs everywhere
Flutter runs. CI exercises every target on each push to `main`:

| Platform        | CI coverage                                               |
| --------------- | -------------------------------------------------------- |
| macOS desktop   | full test suite **incl. golden / WYSIWYG** + format gate |
| Linux desktop   | full test suite (goldens excluded¹) + app build          |
| Windows desktop | full test suite (goldens excluded¹) + app build          |
| Web (Chrome)    | web build + Chrome test leg (goldens + VM-only excluded)  |
| iOS             | app build (no codesign)                                  |
| Android         | APK build                                                |

¹ Goldens run only on the macOS runner — host text rasterization and PDF font
subsetting differ per OS, so pixel-level fidelity is pinned on one canonical
platform rather than asserted everywhere.

System printing is provided by the `printing` dependency, which carries its own
per-platform integration: a desktop print dialog on macOS/Windows/Linux, and the
OS share sheet on iOS/Android (a user dismissal there may report as success).

## License

Apache-2.0. See [LICENSE](LICENSE).
