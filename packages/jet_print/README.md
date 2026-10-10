# jet_print

Build **WYSIWYG report designers** in Flutter. Describe a report as a tree of
bands and elements, fill it with your data, then preview, export to PDF/PNG or
print it. Or give your users the visual designer and let them build the report
themselves.

![The jet_print designer: toolbox, canvas, data fields and property inspector](https://raw.githubusercontent.com/a-urel/jet-print/main/packages/jet_print/doc/screenshots/designer.png)

> **Status: 0.x.** The API may still change between minor versions until 1.0.
> Breaking changes are listed in the [changelog](CHANGELOG.md).

## Features

- **Visual designer.** `JetReportWorkspace` gives you a toolbox, canvas,
  outline, data-field panel, property inspector and live preview in one widget,
  with undo/redo, zoom, rulers, grid snap, alignment and clipboard.
- **What you design is what prints.** The canvas, the preview, page thumbnails,
  PDF and PNG are all drawn from the same recorded page, so they cannot
  disagree.
- **Bands and groups.** Title, page header and footer, detail, group
  header/footer and summary bands; nested master–detail lists; multi-column
  label sheets.
- **Expressions and totals.** `$F{field}`, `$P{parameter}` and
  `$V{PAGE_NUMBER}` references, functions, and `SUM`/`AVG`/`COUNT`/`MIN`/`MAX`
  per group or for the whole report, with ICU number and date formats.
- **Elements.** Text, shapes, images, bar, line and pie charts, crosstab
  (pivot) tables, watermarks, and 20+ barcode and QR symbologies.
- **Data from anywhere.** In-memory rows, JSON, your own Dart objects, or a
  paged source.
- **Real output.** PDFs with selectable text and embedded fonts, PNG pages, and
  the system print dialog.
- **Saved as JSON.** Reports serialize to versioned JSON that newer and older
  builds both read without losing anything.
- **Themed and localized.** Follows your shadcn_ui theme, light or dark;
  English, German and Turkish built in.

## Screenshots

| Preview with page thumbnails | Charts |
| --- | --- |
| ![Invoice preview](https://raw.githubusercontent.com/a-urel/jet-print/main/packages/jet_print/doc/screenshots/preview_invoice.png) | ![Sales chart preview](https://raw.githubusercontent.com/a-urel/jet-print/main/packages/jet_print/doc/screenshots/preview_chart.png) |
| **Barcodes and QR codes** | **Dark theme** |
| ![Barcode gallery in the designer](https://raw.githubusercontent.com/a-urel/jet-print/main/packages/jet_print/doc/screenshots/designer_barcodes.png) | ![The designer in dark mode](https://raw.githubusercontent.com/a-urel/jet-print/main/packages/jet_print/doc/screenshots/designer_dark.png) |

All screenshots are from the
[playground app](https://github.com/a-urel/jet-print/tree/main/apps/jet_print_playground),
which has a dozen ready-made reports to try.

## Install

```sh
flutter pub add jet_print
```

Requires Flutter 3.44 or later. Runs on Android, iOS, web, macOS, Windows and
Linux.

## Quickstart

Describe a report. A title band prints once; the detail band prints once per
row, and its expression reads the row's `name` field:

```dart
const ReportDefinition greetingsReport = ReportDefinition(
  name: 'Greetings',
  page: PageFormat.a4Portrait,
  body: ReportBody(
    title: Band(
      id: 'title',
      type: BandType.title,
      height: 40,
      elements: <ReportElement>[
        TextElement(
          id: 'heading',
          bounds: JetRect(x: 0, y: 0, width: 300, height: 28),
          text: 'Greetings',
          style: JetTextStyle(fontSize: 20, weight: JetFontWeight.bold),
        ),
      ],
    ),
    root: DetailScope(
      id: 'root',
      children: <ScopeNode>[
        BandNode(Band(
          id: 'detail',
          type: BandType.detail,
          height: 24,
          elements: <ReportElement>[
            TextElement(
              id: 'greeting',
              bounds: JetRect(x: 0, y: 0, width: 300, height: 20),
              text: '', // replaced per row by the expression
              expression: r'"Hello, " + $F{name} + "!"',
            ),
          ],
        )),
      ],
    ),
  ),
);
```

Fill it with data, then export, print or preview the result:

```dart
/// 2. Fill it with data. Pages are laid out lazily, as they are read.
RenderedReport renderGreetings(List<String> names) =>
    const JetReportEngine().renderDefinition(
      greetingsReport,
      JetInMemoryDataSource(<Map<String, Object?>>[
        for (final String name in names) <String, Object?>{'name': name},
      ]),
    );

/// 3a. Export it headlessly: you own the bytes.
Future<Uint8List> exportGreetingsPdf(List<String> names) =>
    const JetReportExporter().toPdf(renderGreetings(names));

/// 3b. Or hand it to the system print dialog (false when the user cancels).
Future<bool> printGreetings(List<String> names) =>
    const JetReportPrinter().printReport(renderGreetings(names));
```

`JetReportPreview(report: report)` shows the result on screen, with page
navigation, zoom, thumbnails, PDF export and print buttons. It is built from
[shadcn_ui](https://pub.dev/packages/shadcn_ui) widgets, so it needs a
shadcn_ui theme above it, and the library's localizations. Add `shadcn_ui` to
your app's dependencies and wrap the preview in a `ShadApp`, or in a
`ShadTheme` if your app is a `MaterialApp`. Under a `MaterialApp` alone it
throws on its first build:

```dart
/// 3c. Or preview it. JetReportPreview is built from shadcn_ui widgets, so it
/// needs a shadcn_ui theme above it — a ShadApp, as here, or a ShadTheme inside
/// a MaterialApp — and the library's localizations. Without them it throws on
/// its first build.
class GreetingsApp extends StatelessWidget {
  /// Creates an app that previews [report].
  const GreetingsApp({super.key, required this.report});

  /// The filled report to preview.
  final RenderedReport report;

  @override
  Widget build(BuildContext context) => ShadApp(
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          JetPrintLocalizations.delegate,
        ],
        supportedLocales: JetPrintLocalizations.supportedLocales,
        home: JetReportPreview(report: report),
      );
}
```

## Host the designer

The designer needs a shadcn_ui theme and the library's localizations above it:

```dart
Widget build(BuildContext context) => ShadApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        JetPrintLocalizations.delegate,
      ],
      supportedLocales: JetPrintLocalizations.supportedLocales,
      home: const ReportDesignerPage(),
    );
```

`JetReportWorkspace` is the whole designer. The controller holds the design and
its undo history. `dataSchema` lists the fields users can drag onto the page,
and `renderReport` fills the design for the Preview tab:

```dart
class _ReportDesignerPageState extends State<ReportDesignerPage> {
  // The controller holds the design and its undo history.
  final JetReportDesignerController _controller = JetReportDesignerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => JetReportWorkspace(
        controller: _controller,
        dataSchema: customerSchema,
        renderReport: (ReportDefinition definition) =>
            const JetReportEngine().renderDefinition(definition, customerRows),
      );
}
```

The workspace also takes `onSaveRequested`, `onOpenRequested`, `onExportPdf`
and `onPrint` callbacks, which add the matching toolbar buttons, plus `fonts`
for your own font families.

## Save and reopen designs

A design is plain, versioned JSON. Store it wherever you like:

```dart
/// Saves the current design as versioned JSON.
String saveReport(JetReportDesignerController controller) =>
    JetReportFormat.encodeDefinitionJson(controller.definition);

/// Opens a saved design in the designer.
void openReport(JetReportDesignerController controller, String json) =>
    controller.open(JetReportFormat.decodeDefinitionJson(json));
```

Each document records the schema version that wrote it, and
`JetReportFormat.schemaVersion` is the version this build writes. Older
documents are migrated as they load; a newer one throws
`ReportFormatException`.

## Bind your data

Rows can come from JSON:

```dart
final JetDataSource ordersFromJson = JetJsonDataSource.parse(
  '''
  [
    {"region": "North", "customer": "Ada", "amount": 120.5},
    {"region": "North", "customer": "Grace", "amount": 80},
    {"region": "South", "customer": "Linus", "amount": 42.25}
  ]
  ''',
  fields: salesSchema.fields,
);
```

or from your own classes, mapped to rows as the report reads them:

```dart
final JetDataSource ordersFromObjects = JetObjectDataSource<Order>(
  const <Order>[
    Order('North', 'Ada', 120.5),
    Order('North', 'Grace', 80),
    Order('South', 'Linus', 42.25),
  ],
  fields: salesSchema.fields,
  row: (Order o) => <String, Object?>{
    'region': o.region,
    'customer': o.customer,
    'amount': o.amount,
  },
);
```

A group breaks whenever its key changes, so sort the rows by it. Each group
gets a header and a footer band; `SUM` in the footer totals the group, and the
same expression in the summary band totals the report:

```dart
GroupLevel(
  id: 'region',
  name: 'Region',
  key: r'$F{region}',
  header: Band(
    id: 'regionHeader',
    type: BandType.groupHeader,
    height: 24,
    elements: <ReportElement>[
      TextElement(
        id: 'regionName',
        bounds: JetRect(x: 0, y: 0, width: 200, height: 20),
        text: '',
        expression: r'$F{region}',
        style: JetTextStyle(weight: JetFontWeight.bold),
      ),
    ],
  ),
  footer: Band(
    id: 'regionFooter',
    type: BandType.groupFooter,
    height: 24,
    elements: <ReportElement>[
      TextElement(
        id: 'subtotal',
        bounds: JetRect(x: 300, y: 0, width: 100, height: 20),
        text: '',
        expression: r'SUM($F{amount})',
        format: '#,##0.00',
      ),
    ],
  ),
),
```

Page numbers come from `$V{PAGE_NUMBER}` and `$V{PAGE_COUNT}` in a page footer.
`validate(definition, schema: schema)` checks every binding before you render.

## What you can extend

Four seams are open to your app:

- **Data.** Implement `JetDataSource`, whose `open` returns a `DataSet`
  cursor, to read rows from a database, an API or anything else, and pass it
  to `renderDefinition`.
- **Fonts.** `RenderOptions.fonts` adds your own font families. The preview,
  PDF and print all draw with the same font files.
- **Elements as they print.** `RenderOptions.onElementPrint` is called for each
  element just before it is painted, with the row it came from, and can change
  or hide it.
- **The print dialog.** `JetReportPrinter(presenter: ...)` takes a
  `PrintDialogPresenter` that replaces the system print dialog.

Element types and expression functions are not on that list. Both are a fixed
set that ships with the library: there is no API for registering your own, and
adding one means changing the
[jet_print repository](https://github.com/a-urel/jet-print) itself. That keeps
the saved-JSON format limited to types this library defines, which is how a
report saved by one version still opens in another.

## Platform notes

Reports look the same on every platform, but are not byte-identical: text
rasterization (PNG pixels) and PDF font subsetting vary by operating system. Do
not compare exported files across platforms byte for byte.

Printing goes through the [`printing`](https://pub.dev/packages/printing)
package: a print dialog on macOS, Windows and Linux, the share sheet on iOS and
Android, and the browser's print dialog on the web. `printReport` returns
`false` when the user cancels, but on mobile and the web that is best-effort:
a dismissed dialog may still report success.

## Learn more

- [`example/`](example/): the code on this page, as complete files.
- [The playground app](https://github.com/a-urel/jet-print/tree/main/apps/jet_print_playground):
  a dozen full reports (invoice, labels, payroll, ledger, charts, pivot) in the
  designer.
- [How it works](https://github.com/a-urel/jet-print/tree/main/docs): the
  report model, data binding, pagination, painting and the designer, one page
  each.

## License

Apache-2.0. See [LICENSE](LICENSE).
